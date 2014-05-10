classdef Element
    properties
        coords
        normals
    end
    properties (Dependent)
        n_nodes
        thickness_at_node
        mu_matrix
    end
    methods
        function obj = Element(coords,normals)
            require(size(coords,1)==4, ...
                'ArgumentError: only 4 nodes');
            require(size(coords)==size(normals), ...
                'ArgumentError: coords and normals should have same size');
            obj.coords = coords;
            obj.normals = normals;
        end
        function jac_out = jacobian(element,xi,eta,mu)
            % jac_out = jacobian(element,xi,eta,mu)
            % jac_out [3x3][Float]: Jacobian Matrix
            % xi, eta, mu [Float] between [-1,1]
            % Computes the Jacobian for the ShellQ4 element
            % as defined in Cook pg 360 12.5-4
            dNdxi = Element.dNdxi_Q4(xi,eta);
            dNdeta = Element.dNeta_Q4(xi,eta);
            N = Element.N_Q4(xi,eta);
            % This ASSUMES element.normals has a certain shape
            jac_out = [dNdxi;dNdeta;zeros(1,4)]*element.coords ...
                + [mu*dNdxi;mu*dNdeta;N]*element.normals/2;
        end
        function thickness_out = get.thickness_at_node(element)
            % thickness_out = get.thickness_at_node(element)
            % thickness_out [4x1][Float] original thickness of the shell at
            % each node. Cook pg 358 12.5-1 as t_i
            % Computed from the normals vector
            V3 = element.normals';
            node_num = 4;
            thickness_out = zeros(node_num,1);
            for node = 1:node_num
                thickness_out(node) = norm(V3(:,node));
            end
        end
        function mu_out = get.mu_matrix(element)
            % mu_out = get.mu_matrix(element)
            % mu_out [3x2x4] Cook pg 359 12.5-3
            % Computes the matrix for each element and stores it in a 3D
            % array
            node_num = 4;
            V1 = zeros(3,node_num);
            node = 1;
            for i = [-1,1]
                for j = [-1,1]
                    V1(:,node) = Element.dNeta_Q4(i,j)*element.coords;
                    node = node + 1;
                end
            end
            V3 = element.normals';
            mu_out = zeros(3,2,node_num);
            for node = 1:node_num
                mu_out(:,2,node) = V1(:,node)/norm(V1(:,node));
                V2 = cross(V3(:,node),mu_out(:,2,node));
                mu_out(:,1,node) = -V2/norm(V2);
            end
        end
        function out = get.n_nodes(element)
            % out = get.n_nodes(element)
            % Number of nodes in the element
            out = size(element.coords,1);
        end
    end
    methods (Static)
        function T = T(jac)
            % sistema de coordenadas local 123 en [ksi eta zeta]
            dir1 = jac(1,:);
            dir3 = cross(dir1,jac(2,:));
            dir2 = cross(dir3,dir1);

            % Transformation of Strain, Cook pg 212: 
            % Cook [7.3-5]
            M1 = [ dir1/norm(dir1); dir2/norm(dir2); dir3/norm(dir3) ];
            M2 = M1(:,[2 3 1]);
            M3 = M1([2 3 1],:);
            M4 = M2([2 3 1],:);
            T = [ M1.^2     M1.*M2;
                  2*M1.*M3  M1.*M4 + M3.*M2 ];
            % Since sigma_zz is ignored, we eliminate the appropriate row.
            T(3,:) = [];
        end
        function B = B(eleType,dofs_per_node,nodalCoords,tEle,v,ksi,eta,zeta)
            % Prepare values
            v3 = squeeze(v(:,3,:));         % v3 of iele's coords
            nodes_per_ele = size(nodalCoords,1);
            N  = Element.shapefuns([ksi,eta],eleType);
            jac = Element.shelljac(eleType,nodalCoords,tEle,v3,ksi,eta,zeta);
            invJac = jac \ eye(3);
            dN = invJac(:,1:2)*Element.shapefunsder([ksi,eta],eleType);

            B  = zeros(6,nodes_per_ele*dofs_per_node);
            % B matrix has the same structure for each node and comes from
            % putting all the B_coords next to each other.
            % Loop through the mesh.connect coords and get each B_node, then add it
            % to its columns in the B matrix
            for inod = 1:nodes_per_ele
                v1 = v(:,1,inod);
                v2 = v(:,2,inod);
                dZN = dN(:,inod)*zeta + N(inod)*invJac(:,3);
                aux1 = [ dN(1,inod)         0          0
                                 0  dN(2,inod)         0
                                 0          0  dN(3,inod)
                         dN(2,inod) dN(1,inod)         0
                                 0  dN(3,inod) dN(2,inod)
                         dN(3,inod)         0  dN(1,inod) ];

                aux2 = [ -v2.*dZN                        v1.*dZN
                         -v2(1)*dZN(2) - v2(2)*dZN(1)    v1(1)*dZN(2) + v1(2)*dZN(1)
                         -v2(2)*dZN(3) - v2(3)*dZN(2)    v1(2)*dZN(3) + v1(3)*dZN(2)
                         -v2(1)*dZN(3) - v2(3)*dZN(1)    v1(1)*dZN(3) + v1(3)*dZN(1) ]*0.5*tEle(inod);
                ini = 1 + (inod - 1)*dofs_per_node;
                fin = ini + dofs_per_node - 1;
                B(:,ini:fin) = [aux1 aux2];
            end
        end
        function jac = shelljac(eleType,xyz,t,v3,ksi,eta,zeta)
            % Computes the jacobian for Shell Elements
            % Cook [6.7-2] gives Isoparametric Jacobian
            % Cook [12.5-4] & [12.5-2] gives Shells Derivatives.
            N  = Element.shapefuns([ksi,eta],eleType);
            dN = Element.shapefunsder([ksi,eta],eleType);
            tt = [t; t; t];
            v3t = (v3.*tt)';
            jac = [ dN*(xyz + zeta*v3t/2);
                N*(v3t)/2 ];
        end
        function dN = shapefunsder(pointArray,eleType)
            ngauss = size(pointArray,1);
            switch eleType
                case {'Q9', 'AHMAD9'}
                    dN = zeros(2,9,ngauss);
                    for igauss = 1:ngauss
                        ksi = pointArray(igauss,1);
                        eta = pointArray(igauss,2);
                        
                        dN(:,:,igauss) = [ % derivadas respecto de ksi
                            0.25*eta*(-1+eta)*(2*ksi-1),      0.25*eta*(-1+eta)*(2*ksi+1),       0.25*eta*(1+eta)*(2*ksi+1),...
                            0.25*eta*( 1+eta)*(2*ksi-1),                -ksi*eta*(-1+eta),  -1/2*(-1+eta)*(1+eta)*(2*ksi+1),...
                            -ksi*eta*(1+eta),  -1/2*(-1+eta)*(1+eta)*(2*ksi-1),           2*ksi*(-1+eta)*(1+eta)
                            % derivadas respecto de eta
                            0.25*ksi*(-1+2*eta)*(ksi-1),      0.25*ksi*(-1+2*eta)*(1+ksi),       0.25*ksi*(2*eta+1)*(1+ksi),...
                            0.25*ksi*(2*eta+1)*(ksi-1),  -0.5*(ksi-1)*(1+ksi)*(-1+2*eta),                 -ksi*eta*(1+ksi),...
                            -0.5*(ksi-1)*(1+ksi)*(2*eta+1),                 -ksi*eta*(ksi-1),           2*(ksi-1)*(1+ksi)*eta ];
                    end
                    
                case {'Q8', 'AHMAD8'}
                    dN = zeros(2,8,ngauss);
                    for igauss = 1:ngauss
                        ksi = pointArray(igauss,1);
                        eta = pointArray(igauss,2);
                        dN(:,:,igauss) = [  % derivadas respecto de ksi
                            -0.25*(-1+eta)*(eta+2*ksi),  -0.25*(-1+eta)*(-eta+2*ksi),    0.25*(1+eta)*(eta+2*ksi),   0.25*(1+eta)*(-eta+2*ksi),...
                            ksi*(-1+eta),        -0.5*(-1+eta)*(1+eta),                -ksi*(1+eta),        0.5*(-1+eta)*(1+eta)
                            % derivadas respecto de eta
                            -0.25*(-1+ksi)*(ksi+2*eta),   -0.25*(1+ksi)*(ksi-2*eta),    0.25*(1+ksi)*(ksi+2*eta),   0.25*(-1+ksi)*(ksi-2*eta),...
                            0.5*(-1+ksi)*(1+ksi),                -(1+ksi)*eta,       -0.5*(-1+ksi)*(1+ksi),               (-1+ksi)*eta ];
                    end
                case {'Q4', 'AHMAD4'}
                    dN = zeros(2,4,ngauss);
                    for igauss = 1:ngauss
                        ksi = pointArray(igauss,1);
                        eta = pointArray(igauss,2);
                        dN(:,:,igauss) = [  % derivadas respecto de ksi
                            -0.25*(1 - eta),  0.25*(1 - eta), 0.25*(1 + eta), -0.25*(1 + eta)
                            % derivadas respecto de eta
                            -0.25*(1 - ksi), -0.25*(1 + ksi), 0.25*(1 + ksi),  0.25*(1 - ksi) ];
                    end
                    
            end
        end
        
        function [Ni,N] = shapefuns(pointArray,eleType)
            ngauss = size(pointArray,1);
            
            switch eleType
                
                case 'Q9'
                    N  = zeros(2,18,ngauss);
                    Ni = zeros(1, 9,ngauss);
                    for igauss = 1:ngauss
                        ksi = pointArray(igauss,1);
                        eta = pointArray(igauss,2);
                        
                        N9 =      (1 - ksi^2)*(1 - eta^2);
                        N8 = 0.50*(1 - ksi  )*(1 - eta^2) - 0.5*N9;
                        N7 = 0.50*(1 - ksi^2)*(1 + eta  ) - 0.5*N9;
                        N6 = 0.50*(1 + ksi  )*(1 - eta^2) - 0.5*N9;
                        N5 = 0.50*(1 - ksi^2)*(1 - eta  ) - 0.5*N9;
                        N4 = 0.25*(1 - ksi  )*(1 + eta  ) - 0.5*(N7 + N8 + 0.5*N9);
                        N3 = 0.25*(1 + ksi  )*(1 + eta  ) - 0.5*(N6 + N7 + 0.5*N9);
                        N2 = 0.25*(1 + ksi  )*(1 - eta  ) - 0.5*(N5 + N6 + 0.5*N9);
                        N1 = 0.25*(1 - ksi  )*(1 - eta  ) - 0.5*(N5 + N8 + 0.5*N9);
                        
                        Ni(1,:     ,igauss) = [N1 N2 N3 N4 N5 N6 N7 N8 N9];
                        N (1,1:2:17,igauss) = [N1 N2 N3 N4 N5 N6 N7 N8 N9];
                        N (2,2:2:18,igauss) = [N1 N2 N3 N4 N5 N6 N7 N8 N9];
                    end
                    
                case 'AHMAD9'
                    N  = zeros(3,3*9,ngauss);
                    Ni = zeros(1,  9,ngauss);
                    Id = eye(3);
                    for igauss = 1:ngauss
                        ksi = pointArray(igauss,1);
                        eta = pointArray(igauss,2);
                        
                        N9 =      (1 - ksi^2)*(1 - eta^2);
                        N8 = 0.50*(1 - ksi  )*(1 - eta^2) - 0.5*N9;
                        N7 = 0.50*(1 - ksi^2)*(1 + eta  ) - 0.5*N9;
                        N6 = 0.50*(1 + ksi  )*(1 - eta^2) - 0.5*N9;
                        N5 = 0.50*(1 - ksi^2)*(1 - eta  ) - 0.5*N9;
                        N4 = 0.25*(1 - ksi  )*(1 + eta  ) - 0.5*(N7 + N8 + 0.5*N9);
                        N3 = 0.25*(1 + ksi  )*(1 + eta  ) - 0.5*(N6 + N7 + 0.5*N9);
                        N2 = 0.25*(1 + ksi  )*(1 - eta  ) - 0.5*(N5 + N6 + 0.5*N9);
                        N1 = 0.25*(1 - ksi  )*(1 - eta  ) - 0.5*(N5 + N8 + 0.5*N9);
                        
                        Ni(1,:,igauss) = [N1 N2 N3 N4 N5 N6 N7 N8 N9];
                        N (:,:,igauss) = [  N1*Id, N2*Id, N3*Id, ...
                            N4*Id, N5*Id, N6*Id, ...
                            N7*Id, N8*Id, N9*Id ];
                    end
                    
                case 'Q8'
                    N  = zeros(2,16,ngauss);
                    Ni = zeros(1, 8,ngauss);
                    for igauss = 1:ngauss
                        ksi = pointArray(igauss,1);
                        eta = pointArray(igauss,2);
                        
                        N8 = 0.50*(1 - ksi  )*(1 - eta^2);
                        N7 = 0.50*(1 - ksi^2)*(1 + eta  );
                        N6 = 0.50*(1 + ksi  )*(1 - eta^2);
                        N5 = 0.50*(1 - ksi^2)*(1 - eta  );
                        N4 = 0.25*(1 - ksi  )*(1 + eta  ) - 0.5*(N7 + N8);
                        N3 = 0.25*(1 + ksi  )*(1 + eta  ) - 0.5*(N6 + N7);
                        N2 = 0.25*(1 + ksi  )*(1 - eta  ) - 0.5*(N5 + N6);
                        N1 = 0.25*(1 - ksi  )*(1 - eta  ) - 0.5*(N5 + N8);
                        
                        Ni(1,:     ,igauss) = [N1 N2 N3 N4 N5 N6 N7 N8];
                        N (1,1:2:15,igauss) = [N1 N2 N3 N4 N5 N6 N7 N8];
                        N (2,2:2:16,igauss) = [N1 N2 N3 N4 N5 N6 N7 N8];
                    end
                    
                case 'AHMAD8'
                    N  = zeros(3,3*8,ngauss);
                    Ni = zeros(1,  8,ngauss);
                    Id = eye(3);
                    for igauss = 1:ngauss
                        ksi = pointArray(igauss,1);
                        eta = pointArray(igauss,2);
                        
                        N8 = 0.50*(1 - ksi  )*(1 - eta^2);
                        N7 = 0.50*(1 - ksi^2)*(1 + eta  );
                        N6 = 0.50*(1 + ksi  )*(1 - eta^2);
                        N5 = 0.50*(1 - ksi^2)*(1 - eta  );
                        N4 = 0.25*(1 - ksi  )*(1 + eta  ) - 0.5*(N7 + N8);
                        N3 = 0.25*(1 + ksi  )*(1 + eta  ) - 0.5*(N6 + N7);
                        N2 = 0.25*(1 + ksi  )*(1 - eta  ) - 0.5*(N5 + N6);
                        N1 = 0.25*(1 - ksi  )*(1 - eta  ) - 0.5*(N5 + N8);
                        
                        Ni(1,:,igauss) = [N1 N2 N3 N4 N5 N6 N7 N8];
                        N (:,:,igauss) = [ N1*Id, N2*Id, N3*Id, ...
                            N4*Id, N5*Id, N6*Id, ...
                            N7*Id, N8*Id ];
                    end
                    
                case 'Q4'
                    N  = zeros(2,8,ngauss);
                    Ni = zeros(1,4,ngauss);
                    for igauss = 1:ngauss
                        ksi = pointArray(igauss,1);
                        eta = pointArray(igauss,2);
                        
                        N4 = 0.25*(1 - ksi)*(1 + eta);
                        N3 = 0.25*(1 + ksi)*(1 + eta);
                        N2 = 0.25*(1 + ksi)*(1 - eta);
                        N1 = 0.25*(1 - ksi)*(1 - eta);
                        
                        Ni(1,:    ,igauss) = [N1 N2 N3 N4];
                        N (1,1:2:7,igauss) = [N1 N2 N3 N4];
                        N (2,2:2:8,igauss) = [N1 N2 N3 N4];
                    end
                    
                case 'AHMAD4'
                    N  = zeros(3,3*4,ngauss);
                    Ni = zeros(1,  4,ngauss);
                    Id = eye(3);
                    for igauss = 1:ngauss
                        ksi = pointArray(igauss,1);
                        eta = pointArray(igauss,2);
                        
                        N4 = 0.25*(1 - ksi)*(1 + eta);
                        N3 = 0.25*(1 + ksi)*(1 + eta);
                        N2 = 0.25*(1 + ksi)*(1 - eta);
                        N1 = 0.25*(1 - ksi)*(1 - eta);
                        
                        Ni(1,:,igauss) = [N1 N2 N3 N4];
                        N (:,:,igauss) = [ N1*Id, N2*Id, N3*Id, N4*Id ];
                    end
                    
            end
        end
        function N_out = N_ShellQ4(element,xi,eta,mu)
            % Not really used!!!
            require(isnumeric(mu), ...
                'ArgumentError: xi, eta, and mu should be numeric')
            require(-1<=mu && mu<=1, ...
                'ArgumentError: mu should is not -1<=mu<=1')
            % Need to check the way it works with Jacobian
            N_out = Element.N_Q4(xi,eta)*mu*element.normals;
        end
        function N_out = N_Q4(xi,eta)
            %  Notes:
            %     1st node at (-1,-1), 3rd node at (-1,1)
            %     4th node at (1,1), 2nd node at (1,-1)
            require(isnumeric([xi eta]), ...
                'ArgumentError: Both xi and eta should be numeric')
            require(-1<=xi && xi<=1, ...
                'ArgumetnError: xi should be -1<=xi<=1')
            require(-1<=eta && eta<=1, ...
                'ArgumetnError: eta should be -1<=eta<=1')
            N_out = zeros(1,4);
            N_out(1) = 0.25*(1-xi)*(1-eta);
            N_out(3) = 0.25*(1+xi)*(1-eta);
            N_out(2) = 0.25*(1-xi)*(1+eta);
            N_out(4) = 0.25*(1+xi)*(1+eta);
        end
        function dNdxiQ4_out = dNdxi_Q4(xi,eta)
            % derivatives
            require(isnumeric([xi eta]), ...
                'ArgumentError: Both xi and eta should be numeric')
            require(-1<=xi && xi<=1, ...
                'ArgumetnError: xi should be -1<=xi<=1')
            require(-1<=eta && eta<=1, ...
                'ArgumetnError: eta should be -1<=eta<=1')
            dNdxiQ4_out = zeros(1,4);
            dNdxiQ4_out(1) = -0.25*(1-eta);
            dNdxiQ4_out(2) = 0.25*(1-eta);
            dNdxiQ4_out(3) = -0.25*(1+eta);
            dNdxiQ4_out(4) = 0.25*(1+eta);
        end
        function dNdetaQ4_out = dNeta_Q4(xi,eta)
            % derivatives
            require(isnumeric([xi eta]), ...
                'ArgumentError: Both xi and eta should be numeric')
            require(-1<=xi && xi<=1, ...
                'ArgumetnError: xi should be -1<=xi<=1')
            require(-1<=eta && eta<=1, ...
                'ArgumetnError: eta should be -1<=eta<=1')
            dNdetaQ4_out = zeros(1,4);
            dNdetaQ4_out(1) = -0.25*(1-xi);
            dNdetaQ4_out(2) = -0.25*(1+xi);
            dNdetaQ4_out(3) = 0.25*(1-xi);
            dNdetaQ4_out(4) = 0.25*(1+xi);
        end
    end
end
