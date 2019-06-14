%   This file is part of redbKIT.
%   Copyright (c) 2016, Ecole Polytechnique Federale de Lausanne (EPFL)
%   Author: Federico Negri <federico.negri@epfl.ch>

clear all
clc

[~,~,~] = mkdir('Results');

dim      =  3;

%% Load F mesh
[vertices, boundaries, elements] = msh_to_Mmesh('../mesh/FluidVeryCoarse', dim);

%% Solve Fluid
[U0_Fluid, MESH, DATA] = NSt_Solver(dim, elements, vertices, boundaries, {'P1','P1'}, 'datafile_CFD', [], 'Results/AneurysmC0094_');
