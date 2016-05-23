function [u, FE_SPACE, MESH, DATA] = ADRt_Solver(dim, elements, vertices, boundaries, fem, data_file, param, vtk_filename)
%ADRT_SOLVER time-dependent diffusion-transport-reaction finite element solver
%
%   [U, FE_SPACE, MESH, DATA, ERRORL2, ERRORH1] = ...
%    ADRT_SOLVER(ELEMENTS, VERTICES, BOUNDARIES, FEM, DATA_FILE, PARAM)
%
%   Inputs:
%     ELEMENTS, VERTICES, BOUNDARIES: mesh information
%     FEM: string 'P1' or 'P2'
%     DATA_FILE: name of the file defining the problem data and
%          boundary conditions.
%     PARAM: vector of parameters possibly used in the data_file; 
%         if not provided, the PARAM vector is set to the empty vector.
%
%   Outputs:
%     U: problem solution
%     ERRORL2: L2-error between the numerical solution and the exact one 
%        (provided by the user in the data_file)
%     ERRORH1: H1-error between the numerical solution and the exact one 
%        (provided by the user in the data_file)
%     FE_SPACE: struct containing Finite Element Space information
%     MESH: struct containing mesh information
%     DATA: struct containing problem data

%   This file is part of redbKIT.
%   Copyright (c) 2015, Ecole Polytechnique Federale de Lausanne (EPFL)
%   Author: Federico Negri <federico.negri at epfl.ch> 

if nargin < 6
    error('Missing input arguments. Please type help Elliptic_Solver')
end

if isempty(data_file)
    error('Missing data_file')
end

%% Read problem parameters and BCs from data_file
DATA   = read_DataFile(data_file);
if nargin < 7
    DATA.param = [];
else
    DATA.param = param;
end

if nargin < 8
    vtk_filename = [];
end

%% Set quad_order
if dim == 2
    quad_order       = 4;
elseif dim == 3
    quad_order       = 5;
end

%% Create and fill the MESH data structure
[ MESH ] = buildMESH( dim, elements, vertices, boundaries, fem, quad_order, DATA );

%% Create and fill the FE_SPACE data structure
[ FE_SPACE ] = buildFESpace( MESH, fem, 1, quad_order );

%% Gather Time Setting
BDF_order = DATA.time.BDF_order;
t0        = DATA.time.t0;
dt        = DATA.time.dt;
tf        = DATA.time.tf;
t         = DATA.time.t0;
k_t       = 0;

BDFhandler = BDF_TimeAdvance( BDF_order);

u0         = DATA.u0( MESH.nodes(1,:), MESH.nodes(2,:), t0, param )';
ADR_export_solution(MESH.dim, u0, MESH.vertices, MESH.elements, vtk_filename, 0);
BDFhandler.Initialize( u0 );

fprintf('\n **** PROBLEM''S SIZE INFO ****\n');
fprintf(' * Number of Vertices  = %d \n',MESH.numVertices);
fprintf(' * Number of Elements  = %d \n',MESH.numElem);
fprintf(' * Number of Nodes     = %d \n',MESH.numNodes);
fprintf(' * Number of timesteps =  %d\n', (tf-t0)/dt);
fprintf('-------------------------------------------\n');

%% Generate Domain Decomposition (if required)
PreconFactory = PreconditionerFactory( );
Precon        = PreconFactory.CreatePrecon(DATA.Preconditioner.type, DATA);

if isfield(DATA.Preconditioner, 'type') && strcmp( DATA.Preconditioner.type, 'AdditiveSchwarz')
    R      = ADR_overlapping_DD(MESH, DATA.Preconditioner.num_subdomains,  DATA.Preconditioner.overlap_level);
    Precon.SetRestrictions( R );
end

%% Assemble mass matrix
fprintf('\n Assembling mass matrix... ');
t_assembly = tic;
[~, ~, M]  =  ADR_Assembler(MESH, DATA, FE_SPACE, [], [], [], [], t);
t_assembly = toc(t_assembly);
fprintf('done in %3.3f s', t_assembly);

%% Time Loop
while (t < tf)
    
    iter_time = tic;

    t       = t   + dt;
    k_t     = k_t + 1;
            
    fprintf('\n=========================================================================')
    fprintf('\n==========  t0 = %2.4f  t = %2.4f  tf = %2.4f\n',t0,t,tf);

    u_BDF = BDFhandler.RhsContribute( );
    alpha = BDFhandler.GetCoefficientDerivative();
    
    %% Assemble matrix and right-hand side
    fprintf('\n Assembling ... ');
    t_assembly = tic;
    [A, F]     =  ADR_Assembler(MESH, DATA, FE_SPACE, [], [], [], [], t);
    t_assembly = toc(t_assembly);
    fprintf('done in %3.3f s', t_assembly);
    
    C = alpha/dt * M + A;
    b = 1/dt * M * u_BDF + F;
    
    %% Apply boundary conditions
    fprintf('\n Apply boundary conditions ');
    [C_in, b_in, u_D]   =  ADR_ApplyBC(C, b, FE_SPACE, MESH, DATA, t);
    
    %% Solve
    LinSolver = LinearSolver( DATA.LinearSolver );
    u                         = zeros(MESH.numNodes,1);
    
    fprintf('\n Solve Au = f ... ');
    Precon.Build( C_in );
    fprintf('\n       **  time to build the preconditioner %3.3f s \n', Precon.GetBuildTime());
    LinSolver.SetPreconditioner( Precon );
    u(MESH.internal_dof)  =  LinSolver.Solve( C_in, b_in );
    fprintf('\n       ** time to solve the linear system in %3.3f s \n\n', LinSolver.GetSolveTime());
    
    u(MESH.Dirichlet_dof)     = u_D;
    
    if ~isempty(vtk_filename)
        ADR_export_solution(MESH.dim, u, MESH.vertices, MESH.elements, vtk_filename, k_t);
    end
    
    norm_n  = norm( BDFhandler.M_states{end} - u) / norm(BDFhandler.M_states{end});
    
    BDFhandler.Append( u );

    iter_time = toc(iter_time);
    fprintf('\nnorm(u^(n+1) - u^(n))/norm(u^(n)) = %2.3e -- Iteration time: %3.2f s', norm_n,iter_time);

end

fprintf('\n************************************************************************* \n');

return
