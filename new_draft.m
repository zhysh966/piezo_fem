clc
clear all
%% PRELIMINARY ANALYSIS AND PARAMETERS
% Beam Theory analysis
a = 0.5;        % X Side length [m]
b = 0.05;       % Y Side length [m]
t = 1e-3;       % Shell Thickness [m]
E = 69e9;       % Elasticity Modulus [Pa]
nu = 0;         % Poisson Coefficient
rho = 2700;     % Density [kg/m3]
A = b*t;        % Area [m2]
I = b*(t^3)/12; % Second moment of Area [m4]
F = 1;
% Expected Frequencies
c = sqrt(E*I/(A*rho*a^4));
lambda = [1.875,4.694,7.885]';
expected_f = (lambda.^2)*c/(2*pi);

%% FEM and MESH
% Elements along the side
dofs_per_node = 5;
dofs_per_ele = 0;
n = 6;
mesh = Factory.ShellMesh('AHMAD8',[2*n,n],[a,b,t]);
material = Material(E,nu,rho);
M = @(element) Physics.M_Shell(element,material,3);
K = @(element) Physics.K_Shell(element,material,3);
physics = Physics.Dynamic(dofs_per_node,dofs_per_ele,K,M);
fem = FemCase(mesh,physics);

%% BC
% Fixed End
tol = 1e-9;
x0_edge = (@(x,y,z) (abs(x) < tol));
base = mesh.find_nodes(x0_edge);
fem.bc.node_vals.set_val(base,true);

%% LOADS
% Load the other side
f_border = (@(x,y,z) (abs(x-a) < tol));
border = find(mesh.find_nodes(f_border));
q = [0 0 F 0 0]';
load_fun = @(element,sc,sv) Physics.apply_surface_load( ...
    element,2,q,sc,sv);
L = mesh.integral_along_surface(dofs_per_node,dofs_per_ele, ...
    border,load_fun);
fem.loads.node_vals.dof_list_in(L);

%% Assembly
F = ~fem.bc.all_dofs;
S = fem.S;
M = fem.M;

%% EigenValues
n_dofs = mesh.n_dofs(dofs_per_node,dofs_per_ele);
[V,D] = eigs(S(F,F),M(F,F),3,'SM');
M2 = diag(V'*M(F,F)*V);
for i = 1:size(V,2)
    V(:,i) = V(:,i) / (norm(V(:,i))*sqrt(M2(i)));
end

%% Modal Decomposition
dt = 5e-3;
R = fem.loads.all_dofs;
C = sparse(eye(n_dofs)/10000);
S2 = diag(V'*S(F,F)*V);
C2 = diag(V'*C(F,F)*V)/(2*dt);
R2 = V'*R(F);

%% Time integration
steps = 300;
Z = zeros(size(V,2),steps+1);
K2T = S2 - 2/(dt^2);
MC1 = 1./(dt^-2 + C2);
MC2 = dt^-2 - C2;

%% Control

ele_dofs = mesh.master_ele_dofs(dofs_per_node,dofs_per_ele, ...
                                            1:mesh.n_ele,dofs_per_ele);
Kuphi = S(F(ele_dofs),F(ele_dofs));
P = V'*Kuphi;

A = [   zeros(size(S2)) eye(size(C2))
        -S2             -C2         ]
B = [ zeros(size(P));   P]

%% Time integration
for n = 2:steps
    Z(:,n+1) = MC1.*(R2 - K2T.*Z(:,n) - MC2.*Z(:,n-1));
end
%% Rebuild D, final value
D = fem.compound_function(0);
aux = D.all_dofs;
aux(F) = V*(Z(:,end));
D.dof_list_in(aux);
dz = max(D.node_vals.vals(:,3));
%% Static Solution
fem.solve();
max_dz = max(fem.dis.node_vals.vals(:,3));
%% Compare
error = abs((dz - max_dz)/max_dz);