
# Matrix versions
ac_fem   = reshape(permutedims(reduce(hcat, ac_mine)), (size(ac_mine)..., 3))
fem_arr  = (1 - fem_w) * mesh[1,:,:] + fem_w * mesh[end,:,:]

# Moments
M_in  = [ let xs = (ac_fem[i,:,:] - fem_arr[1:end-1,:]); 
              @. SVector(xs[:,1], xs[:,2], xs[:,3]) × forces[i,:] / 2 end
              for i in eachindex(ac_fem[:,1,1]) ]
M_out = [ let xs = (ac_fem[i,:,:] - fem_arr[2:end,:]); 
              @. SVector(xs[:,1], xs[:,2], xs[:,3]) × forces[i,:] / 2 end
              for i in eachindex(ac_fem[:,1,1]) ]

M_ins  = sum(M_in)
M_outs = sum(M_out)

# Load setups
fem_loads  = zeros(6, length(pt_forces))
fem_forces = reduce(hcat, half_forces)
fem_loads[1:3,1:end-1] = fem_forces
fem_loads[1:3,2:end]  += fem_forces

fem_M_ins  = reduce(hcat, M_ins)
fem_M_outs = reduce(hcat, M_outs)
fem_loads[4:end,1:end-1] = fem_M_ins
fem_loads[4:end,2:end]  += fem_M_outs

# Constrain the plane of symmetry and print
fem_loads[:,span_num+1] .= 0.
fem_loads
 
# Transform loads to principal axes
fem_force_trans  = [ dircos[1] * fem_loads[1:3,1:span_num]   dircos[2] * fem_loads[1:3,span_num+1:end]   ]
fem_moment_trans = [ dircos[1] * fem_loads[4:end,1:span_num] dircos[2] * fem_loads[4:end,span_num+1:end] ]
fem_loads_trans  = [ fem_force_trans  ; 
                     fem_moment_trans ]
fem_loads_trans

## Splitting for Wing case (useless now?)
#==========================================================================================#

function middle_index(x :: AbstractArray)
    n = length(x)
    if n % 2 == 0
        Int(n / 2)
    else
        ceil(Int, n / 2)
    end
end

middle(x :: AbstractVector) = @view x[middle_index(x)]

zero_vec = [SVector(0,0,0.)]

## Testing permutations and transformations of stiffness matrices
#==========================================================================================#

# Testing blocks
Ks = [ tube_stiffness_matrix(aluminum, [tube]) for tube in tubes ]
Ks[1]

## Testing simultaneous permutations of rows and columns:
# 1. (Fx1, Fy1, Fz1, Mx1, My1, Mz1, Fx2, Fy2, Fz2, Mx2, My2, Mz2): [9,1,5,11,6,2,10,3,7,12,8,4]
# 2. (Fx1, Fx2, Mx1, Mx2, Fy1, My1, Fy2, My2, Fz1, Mz1, Fz2, Mz2): [9,10,11,12,1,2,3,4,5,6,7,8]
inds = [9,1,5,11,6,2,10,3,7,12,8,4]
perm_Ks = [ K[inds,:][:,inds] for K in Ks ] 
perm_Ks[1]

# Axis transformation of stiffness matrices
axis_trans = [0 1 0; 0 0 -1; -1 0 0]
K_trans = kron(I(4), axis_trans)

K_tran = repeat(K_trans, 1, 1, length(Ls))

perm_K = zeros(12, 12, length(Ls))
for i in 1:length(Ls)
    perm_K[:,:,i] .= perm_Ks[i]
end

# Using Einstein summation convention for multiplication: D = TᵗKT

@einsum D[j,k,i] := K_tran[l,j,i] * perm_K[l,m,i] * K_tran[m,k,i]
