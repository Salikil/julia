# Based on "Multi-Threading and One-Sided Communication in Parallel LU Factorization"
# Parry Husbands, Katherine Yelick, 
# http://citeseerx.ist.psu.edu/viewdoc/summary?doi=10.1.1.138.4361&rank=7

function hpl (A::Matrix, b::Vector, blocksize::Number)

global A;
n = length(A);
A = [A b];

B_rows = 0:blocksize:n; 
B_rows(end) = n; 
B_cols = [B_rows n+1];
nB = length(B_rows);
depend = cell(nB, nB);

# Add a ghost row of dependencies to boostrap the computation
for j=1:nB
  depend{1,j} = true; 
end

for i=1:(nB-1)
  # Threads for panel factorizations
  I = (B_rows[i]+1):B_rows[i+1];
  [depend{i+1,i}, panel_p] = spawn(panel_factor, I, depend{i,i});
  
  # Threads for trailing updates
  for j=(i+1):nB
    J = (B_cols[j]+1):B_cols[j+1];    
    depend{i+1,j} = spawn(trailing_update, I, J, panel_p, depend{i+1,i},depend{i,j});
  end
end

# Completion of the last diagonal block signals termination
wait(depend{nB, nB});

# Solve the triangular system
x = triu(A[1:n,1:n]) \ A[:,n+1];

return x

end # hpl()


### Panel factorization ###

function panel_factor(I, col_dep)
# Panel factorization

global A
n = size (A, 1);

# Enforce dependencies
wait(col_dep);

# Factorize a panel
K = I[1]:n;
[A[K,I], panel_p] = lu(A[K,I],'vector','economy'); 

# Panel permutation 
panel_p = K(panel_p);

done = true;

return (done, panel_p)

end # panel_factor()


### Trailing update ###

function trailing_update(I, J, panel_p, row_dep, col_dep)
# Trailing submatrix update

global A
n = size (A, 1);

# Enforce dependencies
wait(row_dep, col_dep);

# Apply permutation from pivoting 
K = (I[end]+1):n;       
A(I[1]:n, J) = A(panel_p, J); 

# Compute blocks of U 
L = tril(A[I,I],-1) + eye(length(I));
A[I, J] = L \ A[I, J];

# Trailing submatrix update
if !isempty(K)
  A[K,J] = A[K,J] - A[K,I]*A[I,J];  
end

done = true;

return done

end # trailing_update()
