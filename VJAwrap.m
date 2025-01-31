function [u] = VJAwrap(IN_MAT)
% Make single input, single output version of Vertex Jumping Algorithm
% for use in Simulink via the MATLAB Fcn block
% IN_MAT = [B     d
%           umin' 0
%           umax' 0
%           INDX  0]
% 20140524  KAB Modified to include INDX, which is used to specify active
%               effectors
global NumU
% Get sizes
[k2,m1]=size(IN_MAT);
k=k2-3;
m=m1-1;
% If matrices too small, set contols to zero and return
if k<1 || m<1 || norm(IN_MAT)<1e-16
    u=zeros(NumU,1);
    return
end
% Partition input matrix into component matrices
B=IN_MAT(1:k,1:m);
y=IN_MAT(1:k,end);
umin=IN_MAT(k+1,1:m)';
umax=IN_MAT(k+2,1:m)';
INDX=IN_MAT(k+3,1:m)';

% get active effectors
B=B(:,INDX>0.5); 
umin=umin(INDX>0.5);
umax=umax(INDX>0.5);

[u1] = vja (B, umax, umin, y);

u2=u1;
u=zeros(NumU,1);
u(INDX>0.5,1)=u2;

end

function [u] = vja (B, umax, umin, y)
% Multiple output version can also be implemented:
% function [v, fi, iter, degen] = vja (B, umax, umin, y)
% outputs
% v is surface command units? size?
% fi is status on facets (Boolean) 1x?
% iter is iteration counter 1x1
% degen is degenerate ? 1x1
% inputs
% B is the B matrix (nondimensional?) or per degree? , 3xm   -> m == #effectors
% umax is the maximum limit for surfaces (dimensions) / mx1 
% umin is the minimum limit for surfaces (dimensions) / mx1
% y is the moment command (dimensionless?) size (3x1)?
	degen = 0;
	iter = 0;

	% First, find a vertex in direction of y

	[v1, y1] = findvertex (B, umax, umin, y);


	% Next, find a vertex in direction perpendicular to y1, 
	% and in the plane of y and y1

	d = y-(y'*y1)/(y1'*y1)*y1;
	[v2, y2] = findvertex (B, umax, umin, d);


	% Now, find a vertex in a direction perpendicular to 
	% the plane of y1 and y2, on the same side of the plane
	% y is on.

	d = cross (y1, y2);
	if d'*y < 0
		v4 = v1; y4 = y1;
		v1 = v2; y1 = y2;
		v2 = v4; y2 = y4;
		[v3, y3] = findvertex (B, umax, umin, -d);
	else
		[v3, y3] = findvertex (B, umax, umin, d);
	end

	
	% It is possible that y is not found within the solid
	% angle formed from y1,y2,y3.  If so, try to find another
	% point that does the job.

	while 1
		if det([y,y2,y3]) < 0
			v1 = v3; y1 = y3;
			[v3, y3] = findvertex (B, umax, umin, cross(y3,y2));
		elseif 	det([y,y3,y1]) < 0
			v2 = v3; y2 = y3;
			[v3, y3] = findvertex (B, umax, umin, cross(y1,y3));
		else
			break
		end


		% Increment iteration count

		iter = iter + 1; % Comment out MCC ,pause
	end


	% Begin the loop to find three connected nodes

	while ~ node_connected (v1,v2,v3)

		% Find a vertex in a direction perpendicular to the plane 
		% formed by y1,y2,y3, and pointing outward

		d = cross(y2-y1,y3-y1);
		[v4, y4, degenv, dmask] = findvertex (B, umax, umin, d);

		% Check for degeneracy.  For now, just exit in that case.

		if degenv
			if node_mask_equal (v1, dmask)
				degen = 1;
				break
			end
			if node_mask_equal (v2, dmask)
				degen = 1;
				break
			end
			if node_mask_equal (v3, dmask)
				degen = 1;
				break
			end
		end

		% Figure out which point y4 should replace

		if det ([y,y4,y1]) > 0
			if det ([y,y4,y2]) > 0
				v1 = v4;
				y1 = y4;
			else
				v3 = v4;
				y3 = y4;
			end
		else
			if det ([y,y4,y3]) > 0
				v2 = v4;
				y2 = y4;
			else
				v1 = v4;
				y1 = y4;
			end
		end


		% Increment iteration count

		iter = iter + 1;
	end


	% Determine the common facet

	if degen
		v = dmask;
		fi = [];
		for I = 1:length(dmask)
			if dmask(I) == 0
				fi = [fi,I];
			end
		end
	else
		[v, fi] = common_facet (v1,v2,v3);
    end
%%%%%    taken from vja_20050830.m
	% All below new 20050830 WCD
	
	u = setU_3(v,umin,umax); % Moving to moment space
	
	% u1 with both free controls min
	u1=u;
	u1(fi(1))=umin(fi(1));
	u1(fi(2))=umin(fi(2)); 

	% u2 with first free control max, second min
	u2=u;
	u2(fi(1))=umax(fi(1));
	u2(fi(2))=umin(fi(2));

	% u3 with first free control min, second max
	u3=u;
	u3(fi(1))=umin(fi(1));
	u3(fi(2))=umax(fi(2));
	
	m1=B*u1; m2=B*u2; m3=B*u3; % 3 vertices of facet
	
	% Find intersection of scaled y with facet
	% Scale factor is variable 'a' or ABC(1)
	% Distances along two edges of facet are 'b' and 'c' or ABC(2) and ABC(3)
	% This is solution of ay=m1+b(m2-m1)+c(m3-m1) for a,b,c
	M=[y m1-m2 m1-m3];
	rank1 = rank(M);
	if (rank1 < 3) 
        disp('Bad rank')
        rank1
%         save('data_log.mat','B','u1','u2','u3','u','v','umin','umax','fi','y')
%         stop
        u= zeros(length(umax),1);
        sat = 0;
        v = u;
        fi = 0;
        iter = 0;
        degen = 0;
        return

    end
    ABC=inv(M)*m1; %  If M is singular you have a degenerate problem
	
	% If the solution is correct, a is pos, b and c between 0 and 1
	% This is the place to put a test if problems develop
	% Assuming OK, allocate controls on facet
	u=u1+ABC(2)*(u2-u1)+ABC(3)*(u3-u1);
	% Scale if necessary
	
	if (ABC(1))>0
		sat=1/ABC(1);
        sat=min(1,sat); %KAB mod
	else
		sat=0; % Should happen only if y is zero
	end
	
	u=u*sat;    
    
%%%%%
end

function [v, y, degen, dmask] = findvertex (B, umax, umin, d)

	s = d'*B;

	v = zeros(length(s),1);
	u = zeros(length(s),1);
	degen = 0;
	dmask = zeros(length(s),1);

	epsilon = 1e-6;

	for i = 1:length(s)
		if s(i) > 0
			v(i) = 1;
			u(i) = umax(i);
		else
			v(i) = -1;
			u(i) = umin(i);
		end
		if abs(s(i)) < epsilon
			degen = 1;
		else
			dmask(i) = v(i);
		end
	end
	y = B*u;
end

function c = node_connected (v1, v2, v3)

	d1 = 0;
	d2 = 0;
	d3 = 0;

	for I = 1:length(v1)
		if v1(I) ~= v2(I)
			d3 = d3 + 1;
		end
		if v2(I) ~= v3(I)
			d1 = d1 + 1;
		end
		if v1(I) ~= v3(I)
			d2 = d2 + 1;
		end
	end

	if d1 == 1 & d2 == 1 & d3 == 2
		c = 3;
	elseif d1 == 1 & d2 == 2 & d3 == 1
		c = 2;
	elseif d1 == 2 & d2 == 1 & d3 == 1
		c = 1;
	else
		c = 0;
	end
end

function c = node_mask_equal (v1, mask)

	for I = 1:length(v1)
		if mask(I) & v1(I) ~= mask(I)
			c = 0;
			return
		end
	end

	c = 1;
end

function [v, iz] = common_facet (v1, v2, v3)

	v = zeros(length(v1),1);
	iz = 0;

	for i = 1:length(v1)
		if v1(i) == v2(i) & v2(i) == v3(i)
			v(i) = v1(i);
		else
			if iz == 0
				iz = i;
			else
				iz = [iz, i];
			end
		end
	end
end

function [uOut]=setU_3(uIn,u_Min,u_Max)
[m,n]=size(uIn);
for i=1:m % Column vector
	if (uIn(i)<0)
		uOut(i,1)=u_Min(i);
	elseif (uIn(i)>0)
		uOut(i,1)=u_Max(i);
	else
		uOut(i,1)=0;
	end
end
end



