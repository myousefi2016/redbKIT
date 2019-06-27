%   This file is not part of redbKIT.
%   Copyright (c) 2019, Clemson University
%   Author: Mehrdad Yousefi <yousefi@clemson.edu>

% Inlet inward normal
N1  = [-0.22769944801055877 0.9698369277334794 0.08700169527183198];


% Source term
data.force{1} = @(x, y, z, t, param)(0.*x.*y);
data.force{2} = @(x, y, z, t, param)(0.*x.*y);
data.force{3} = @(x, y, z, t, param)(0.*x.*y);

data.bcDir_t = @(t) Velocity(t);

% Dirichlet
data.bcDir{1,155} = @(x, y, z, t, param)( data.bcDir_t(t)  * N1(1) * 1 + 0.*x.*y); 
data.bcDir{2,155} = @(x, y, z, t, param)( data.bcDir_t(t)  * N1(2) * 1 + 0.*x.*y); 
data.bcDir{3,155} = @(x, y, z, t, param)( data.bcDir_t(t)  * N1(3) * 1 + 0.*x.*y); 

data.bcDir{1,80} = @(x, y, z, t, param)(0.*x.*y); 
data.bcDir{2,80} = @(x, y, z, t, param)(0.*x.*y); 
data.bcDir{3,80} = @(x, y, z, t, param)(0.*x.*y);

data.bcDir{1,755} = @(x, y, z, t, param)(0.*x.*y);
data.bcDir{2,755} = @(x, y, z, t, param)(0.*x.*y);
data.bcDir{3,755} = @(x, y, z, t, param)(0.*x.*y);

% initial condition
data.u0{1}    = @(x, y, z, t, param)(0.*x.*y);
data.u0{2}    = @(x, y, z, t, param)(0.*x.*y);
data.u0{3}    = @(x, y, z, t, param)(0.*x.*y);

% flags
data.flag_dirichlet{1} = [80 155 755];

data.flag_dirichlet{2} = [80 155 755];

data.flag_dirichlet{3} = [80 155 755];

data.flag_neumann{1}   = [230 305 380 455 530 605 680];
data.flag_neumann{2}   = [230 305 380 455 530 605 680];
data.flag_neumann{3}   = [230 305 380 455 530 605 680];

% Neumann
data.bcNeu{1} = @(x, y, z, t, param)(0.*x.*y);
data.bcNeu{2} = @(x, y, z, t, param)(0.*x.*y);
data.bcNeu{3} = @(x, y, z, t, param)(0.*x.*y);

% Model parameters
data.dynamic_viscosity   = 0.04;
data.density             = 1.00;

% Nonlinear solver
data.NonlinearSolver.tol         = 1e-6; 
data.NonlinearSolver.maxit       = 30;

% Stabilization
data.Stabilization = 'SUPG';

% Linear solver
data.LinearSolver.type           = 'MUMPS'; % MUMPS, backslash, gmres
data.LinearSolver.mumps_reordering  = 7;

% Preconditioner
data.Preconditioner.type         = 'None'; % AdditiveSchwarz, None, ILU

% time 
data.time.BDF_order  = 2;
data.time.t0         = 0;
data.time.dt         = 0.01;
data.time.tf         = 3.0;
data.time.nonlinearity  = 'implicit';
