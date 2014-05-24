clear all
clc

%% PRELIMINARY ANALYSIS AND PARAMETERS
% Beam Theory analysis
a = 1;      % X Side length [m]
b = 1;      % Y Side length [m]
t = 0.2;      % Shell Thickness [m]
E = 2e7;	% Elasticity Modulus [Pa]
nu = 0;     % Poisson Coefficient
rho = 1;	% Density [kg/m3]

% Expected Mass
m = a*b*t*rho;   % [kg]

%% FEM and MESH
% Elements along the side
dofs_per_node = 5;
dofs_per_ele = 0;
n = 1;
m = 1;
mesh = Factory.ShellMesh('AHMAD4',[m,n],[a,b,t]);
material = Material(E,nu,rho);
M = @(element) Physics.M_Shell(element,material,3);
K = @(element) Physics.K_Shell(element,material,3);
physics = Physics.Dynamic(5,0,K,M);
fem = FemCase(mesh,physics);

%% Obtained Mass

M = fem.M;
got_m = zeros(3,1);
for i = 1:3
    x_dis = zeros(size(M,1),1);
    % Valid only for dofs_per_ele = 0
    x_dis(i:dofs_per_node:end) = 1;
    got_m(i) = sum(M*x_dis);    % Looking good
end
got_m

%% BC
% Fixed End
tol = 1e-5;
x0_edge = (@(x,y,z) (abs(x) < tol));
base = mesh.find_nodes(x0_edge);
fem.bc.node_vals.set_val(base,true);

% [V D] = (fem.eigen_values)