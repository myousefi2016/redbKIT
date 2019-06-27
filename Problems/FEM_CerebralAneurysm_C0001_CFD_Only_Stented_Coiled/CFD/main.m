%   This file is not part of redbKIT.
%   Copyright (c) 2019, Clemson University
%   Author: Mehrdad Yousefi <yousefi@clemson.edu>

clear all
clc

[~,~,~] = mkdir('Results');

dim      =  3;

%% Load F mesh
[vertices, boundaries, elements] = msh_to_Mmesh('../mesh/C0001', dim);

%% Solve Fluid
[U0_Fluid, MESH, DATA] = NSt_Solver(dim, elements, vertices, boundaries, {'P1','P1'}, 'datafile_CFD', [], 'Results/AneurysmStentedCoiledC0001_');
