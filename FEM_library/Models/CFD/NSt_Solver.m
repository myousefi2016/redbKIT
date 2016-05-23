function [u, MESH, DATA] = NSt_Solver(dim, elements, vertices, boundaries, fem, data_file, param, vtk_filename)
%NST_SOLVER unsteady Navier-Stokes Equations solver

%   This file is part of redbKIT.
%   Copyright (c) 2016, Ecole Polytechnique Federale de Lausanne (EPFL)
%   Author: Federico Negri <federico.negri at epfl.ch>

if nargin < 6
    error('Missing input arguments. Please type help NSsteadySolver')
end

if isempty(data_file)
    error('Missing data_file')
end

if nargin < 8
    vtk_filename = [];
end


%% Read problem parameters and BCs from data_file
DATA   = CFD_read_DataFile(data_file, dim);
if nargin < 7
    param      = [];
    DATA.param = [];
else
    DATA.param = param;
end
t      = [];

%% Set quad_order
if dim == 2
    quad_order       = 4;
elseif dim == 3
    quad_order       = 5;
end

%% Create and fill the MESH data structure
[ MESH ] = buildMESH( dim, elements, vertices, boundaries, fem{1}, quad_order, DATA, 'CFD' );

%% Create and fill the FE_SPACE data structure
[ FE_SPACE_v ] = buildFESpace( MESH, fem{1}, dim, quad_order );
[ FE_SPACE_p ] = buildFESpace( MESH, fem{2}, 1, quad_order );

MESH.internal_dof_c{MESH.dim+1} = 1:FE_SPACE_p.numDof;

totSize = FE_SPACE_v.numDof + FE_SPACE_p.numDof;

%% Gather Time Setting
BDF_order = DATA.time.BDF_order;
t0        = DATA.time.t0;
dt        = DATA.time.dt;
tf        = DATA.time.tf;
t         = DATA.time.t0;
k_t       = 0;

BDFhandler = BDF_TimeAdvance( BDF_order);

v0  = [];
for k = 1 : FE_SPACE_v.numComponents
    switch dim
        case 2
            v0  = [v0; DATA.u0{k}(  MESH.nodes(1,:), MESH.nodes(2,:), t0, param )'];
            
        case 3
            v0  = [v0; DATA.u0{k}(  MESH.nodes(1,:), MESH.nodes(2,:), MESH.nodes(3,:), t0, param )'];
    end
end
u = [v0; zeros(FE_SPACE_p.numDof,1)];
CFD_export_solution(MESH.dim, u(1:FE_SPACE_v.numDof), u(1+FE_SPACE_v.numDof:end), MESH.vertices, MESH.elements, MESH.numNodes, vtk_filename, 0);
BDFhandler.Initialize( v0 );

fprintf('\n **** PROBLEM''S SIZE INFO ****\n');
fprintf(' * Number of Vertices  = %d \n',MESH.numVertices);
fprintf(' * Number of Elements  = %d \n',MESH.numElem);
fprintf(' * Number of Nodes     = %d \n',MESH.numNodes);
fprintf(' * Number of Dofs      = %d \n',length(MESH.internal_dof));
fprintf(' * Number of timesteps =  %d\n', (tf-t0)/dt);
fprintf(' * BDF Order           =  %d\n', BDF_order);
fprintf('-------------------------------------------\n');

%% Generate Domain Decomposition (if required)
PreconFactory = PreconditionerFactory( );
Precon        = PreconFactory.CreatePrecon(DATA.Preconditioner.type, DATA);

if isfield(DATA.Preconditioner, 'type') && strcmp( DATA.Preconditioner.type, 'AdditiveSchwarz')
    R      = CFD_overlapping_DD(MESH, FE_SPACE_v, FE_SPACE_p, DATA.Preconditioner.num_subdomains,  DATA.Preconditioner.overlap_level);
    Precon.SetRestrictions( R );
end

%% Assemble Constant Terms
fprintf('\n   -- Assembling Stokes terms... ');
t_assembly = tic;
[A_Stokes] = CFD_Assembler('Stokes', MESH, DATA, FE_SPACE_v, FE_SPACE_p);
t_assembly = toc(t_assembly);
fprintf('done in %3.3f s\n', t_assembly);

fprintf('\n Assembling mass matrix... ');
t_assembly = tic;
Mv = CFD_Assembler('mass_velocity', MESH, DATA, FE_SPACE_v, FE_SPACE_p);
Mp = CFD_Assembler('mass_pressure', MESH, DATA, FE_SPACE_v, FE_SPACE_p);
M  = blkdiag(DATA.density * Mv, 0*Mp);
t_assembly = toc(t_assembly);
fprintf('done in %3.3f s', t_assembly);

%% Initialize Linear Solver
LinSolver = LinearSolver( DATA.LinearSolver );


%% PreProcessing for Drag and Lift Computation
compute_DragLift = 0 ;
if isfield(DATA, 'Output') && isfield(DATA.Output, 'DragLift')
    if DATA.Output.DragLift.computeDragLift == 1
        compute_DragLift = true;
    end
end

if compute_DragLift
    Drag(k_t+1)  = 0;
    Lift(k_t+1)  = 0;
    dofs_drag    = [];
    
    for j = 1 : length(DATA.Output.DragLift.flag)
        Dirichlet_side         = find(MESH.boundaries(MESH.bc_flag_row,:) == DATA.Output.DragLift.flag(j));
        Dirichlet_side         = unique(Dirichlet_side);
        Dirichlet_dof          = MESH.boundaries(1:MESH.numBoundaryDof,Dirichlet_side);
        dofs_drag              = [dofs_drag; Dirichlet_dof];
    end
    dofs_drag = unique(dofs_drag);
    
    fileDragLift = fopen(DATA.Output.DragLift.filename, 'w+');
    fprintf(fileDragLift, 'Time          Drag          Lift');
    fprintf(fileDragLift, '\n%1.4e  %1.4e  %1.4e',  t, Drag(k_t+1),  Lift(k_t+1));
end

%% Time Loop
while ( t < tf )
    
    iter_time = tic;
    
    t       = t   + dt;
    k_t     = k_t + 1;
    
    fprintf('\n=========================================================================')
    fprintf('\n==========  t0 = %2.4f  t = %2.4f  tf = %2.4f\n',t0,t,tf);
    
    v_BDF = BDFhandler.RhsContribute( );
    u_BDF = [v_BDF; zeros(FE_SPACE_p.numDof,1)];
    alpha = BDFhandler.GetCoefficientDerivative();
    
    switch DATA.time.nonlinearity
        
        case 'semi-implicit'
            
            v_extrapolated = BDFhandler.Extrapolate();
            U_k            = zeros(totSize,1);
            
            % Assemble matrix and right-hand side
            fprintf('\n -- Assembling Convective Term... ');
            t_assembly = tic;
            [C1] = CFD_Assembler('convective_Oseen', MESH, DATA, FE_SPACE_v, FE_SPACE_p, v_extrapolated);
            t_assembly = toc(t_assembly);
            fprintf('done in %3.3f s\n', t_assembly);
            
            F_NS = 1/dt * M * u_BDF;
            C_NS = alpha/dt * M + A_Stokes + C1;
            
            % Apply boundary conditions
            fprintf('\n -- Apply boundary conditions ... ');
            t_assembly = tic;
            [A, b, u_D]   =  CFD_ApplyBC(C_NS, F_NS, FE_SPACE_v, FE_SPACE_p, MESH, DATA, t);
            t_assembly = toc(t_assembly);
            fprintf('done in %3.3f s\n', t_assembly);
            
            % Solve
            fprintf('\n -- Solve A x = b ... ');
            Precon.Build( A );
            fprintf('\n      time to build the preconditioner %3.3f s \n', Precon.GetBuildTime());
            LinSolver.SetPreconditioner( Precon );
            U_k(MESH.internal_dof) = LinSolver.Solve( A, b, u );
            fprintf('\n      time to solve the linear system in %3.3f s \n', LinSolver.GetSolveTime());
            U_k(MESH.Dirichlet_dof) = u_D;
            
        case 'implicit'
            
            % Nonlinear Iterations
            tol        = DATA.NonLinearSolver.tol;
            resRelNorm = tol + 1;
            incrNorm   = tol + 1;
            maxIter    = DATA.NonLinearSolver.maxit;
            k          = 1;
            
            [~, ~, u_D]   =  CFD_ApplyBC([], [], FE_SPACE_v, FE_SPACE_p, MESH, DATA, t);
            dU             = zeros(totSize,1);
            U_k            = u;
            U_k(MESH.Dirichlet_dof) = u_D;
            
            % Assemble matrix and right-hand side
            fprintf('\n   -- Assembling Convective terms... ');
            t_assembly = tic;
            [C1, C2] = CFD_Assembler('convective', MESH, DATA, FE_SPACE_v, FE_SPACE_p, U_k);
            t_assembly = toc(t_assembly);
            fprintf('done in %3.3f s\n', t_assembly);
            
            Residual = 1/dt * M * (alpha*U_k - u_BDF) + A_Stokes * U_k + C1 * U_k;
            Jacobian = alpha/dt * M + A_Stokes + C1 + C2;
            
            % Apply boundary conditions
            fprintf('\n -- Apply boundary conditions ... ');
            t_assembly = tic;
            [A, b]   =  CFD_ApplyBC(Jacobian, -Residual, FE_SPACE_v, FE_SPACE_p, MESH, DATA, t, 1);
            t_assembly = toc(t_assembly);
            fprintf('done in %3.3f s\n', t_assembly);
            
            res0Norm = norm(b);
            
            fprintf('\n============ Start Newton Iterations ============\n\n');
            while (k <= maxIter && incrNorm > tol && resRelNorm > tol)
                
                % Solve
                fprintf('\n   -- Solve J x = -R ... ');
                Precon.Build( A );
                fprintf('\n        time to build the preconditioner %3.3f s \n', Precon.GetBuildTime());
                LinSolver.SetPreconditioner( Precon );
                dU(MESH.internal_dof) = LinSolver.Solve( A, b );
                fprintf('\n        time to solve the linear system in %3.3f s \n', LinSolver.GetSolveTime());
                
                U_k        = U_k + dU;
                incrNorm   = norm(dU)/norm(U_k);
                
                % Assemble matrix and right-hand side
                fprintf('\n   -- Assembling Convective terms... ');
                t_assembly = tic;
                [C1, C2] = CFD_Assembler('convective', MESH, DATA, FE_SPACE_v, FE_SPACE_p, U_k);
                t_assembly = toc(t_assembly);
                fprintf('done in %3.3f s\n', t_assembly);
                
                Residual = 1/dt * M * (alpha*U_k - u_BDF) + A_Stokes * U_k + C1 * U_k;
                Jacobian = alpha/dt * M + A_Stokes + C1 + C2;
                
                % Apply boundary conditions
                fprintf('\n   -- Apply boundary conditions ... ');
                t_assembly = tic;
                [A, b]   =  CFD_ApplyBC(Jacobian, -Residual, FE_SPACE_v, FE_SPACE_p, MESH, DATA, t, 1);
                t_assembly = toc(t_assembly);
                fprintf('done in %3.3f s\n', t_assembly);
                
                resRelNorm = norm(b) / res0Norm;
                
                fprintf('\n **** Iteration  k = %d:  norm(dU)/norm(Uk) = %1.2e, Residual Rel Norm = %1.2e \n\n',k, full(incrNorm), full(resRelNorm));
                k = k + 1;
                
            end
            
    end
    u = U_k;
    
    %% Update BDF
    BDFhandler.Append( u(1:FE_SPACE_v.numDof) );
   
    %% Export to VTK
    if ~isempty(vtk_filename)
        CFD_export_solution(MESH.dim, u(1:FE_SPACE_v.numDof), u(1+FE_SPACE_v.numDof:end), MESH.vertices, MESH.elements, MESH.numNodes, vtk_filename, k_t);
    end
       
    %% Compute_DragLift
    if compute_DragLift
        
        if strcmp(DATA.time.nonlinearity,'implicit')
            C_NS = 0*Jacobian;
            F_NS = -Residual;
        end
        Z              = zeros(FE_SPACE_v.numDofScalar,1);
        Z(dofs_drag)   = 1;
        
        W               = zeros(FE_SPACE_v.numDof+FE_SPACE_p.numDof,1);
        W(1:FE_SPACE_v.numDofScalar)        = Z;
        Drag(k_t+1) = DATA.Output.DragLift.factor*(W'*(-C_NS*u + F_NS));
        
        W               = zeros(FE_SPACE_v.numDof+FE_SPACE_p.numDof,1);
        W(FE_SPACE_v.numDofScalar+[1:FE_SPACE_v.numDofScalar])  = Z;
        Lift(k_t+1)  = DATA.Output.DragLift.factor*(W'*(-C_NS*u  + F_NS));
        
        fprintf('\n *** Drag = %f, Lift = %f *** \n',  Drag(k_t+1),  Lift(k_t+1));
        fprintf(fileDragLift, '\n%1.4e  %1.4e  %1.4e',  t, Drag(k_t+1),  Lift(k_t+1));
    end
    
    iter_time = toc(iter_time);
    fprintf('\n-------------- Iteration time: %3.2f s -----------------',iter_time);
    
end

fprintf('\n************************************************************************* \n');

return
