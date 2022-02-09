##
using AeroMDAO
using LinearAlgebra
using StaticArrays
using DataFrames
using NLsolve
using TimerOutputs
using SparseArrays

# Case
#==========================================================================================#

## Aerodynamic variables

# Define wing
wing = Wing(foils     = fill(naca4((2,4,1,2)), 2),
            chords    = [1.0, 0.6],
            twists    = [0.0, 0.0],
            spans     = [5.0],
            dihedrals = [5.],
            sweeps      = [15.]);

# Horizontal tail
htail = Wing(foils     = fill(naca4((0,0,1,2)), 2),
             chords    = [0.7, 0.42],
             twists    = [0.0, 0.0],
             spans     = [1.25],
             dihedrals = [0.],
             sweeps      = [6.39],
             position  = [4., 0., 0.],
             angle     = 0.,
             axis      = [0., 1., 0.])

# Vertical tail
vtail = HalfWing(foils     = fill(naca4((0,0,0,9)), 2),
                 chords    = [0.7, 0.42],
                 twists    = [0.0, 0.0],
                 spans     = [1.0],
                 dihedrals = [0.],
                 sweeps      = [7.97],
                 position  = [4., 0, 0],
                 angle     = 90.,
                 axis      = [1., 0., 0.]);

## Meshing and assembly
wing_mesh  = WingMesh(wing,  [8], 6)
htail_mesh = WingMesh(htail, [6], 6)
vtail_mesh = WingMesh(vtail, [6], 6)

# Aircraft assembly
aircraft = ComponentArray(
                          wing    = make_horseshoes(wing_mesh),
                          htail   = make_horseshoes(htail_mesh),
                          vtail   = make_horseshoes(vtail_mesh),
                        );

## Aerodynamic case

# Reference values
ac_name  = "My Aircraft"
wing_mac = mean_aerodynamic_center(wing);
S, b, c  = projected_area(wing), span(wing), mean_aerodynamic_chord(wing);
ρ        = 0.98
ref      = [wing_mac[1], 0., 0.]
V, α, β  = 25.0, 5.0, 5.0
Ω        = zeros(3)
fs       = Freestream(V, α, β, Ω)
refs     = References(S, b, c, ρ, ref)

## Solve aerodynamic case for initial vector
@time system =
    solve_case(aircraft, fs, refs;
               print_components = true,      # Prints the results for each component
              );

## Data collection
CFs, CMs = surface_coefficients(system)
forces, moments   = surface_dynamics(system)
hs_acs   = bound_leg_center.(system.vortices)


## Wing FEM setup
wing_beam_ratio = 0.40
wing_fem_mesh   = make_beam_mesh(wing_mesh.chord_mesh, wing_beam_ratio)

aluminum = Material(       # Aluminum properties
                    85e9,  # Elastic modulus, N/m²
                    25e9,  # Shear modulus, N/m²,
                    350e6, # Yield stress with factor of safety 2.5, N/m²,
                    1.6e3, # Density, kg/m³
                    )

Ls_wing = norm.(diff(wing_fem_mesh))                              # Beam lengths, m
rs_wing = range(2e-2, stop = 1e-2, length = length(Ls_wing) ÷ 2)  # Outer radius, m
ts_wing = range(1e-2, stop = 6e-3, length = length(Ls_wing) ÷ 2)  # Thickness, m
r_wing  = [ reverse(rs_wing); rs_wing ]
t_wing  = [ reverse(ts_wing); ts_wing ]

tubes_wing     = Tube.(Ref(aluminum), Ls_wing, r_wing, t_wing)
Ks_wing        = build_big_stiffy(tubes_wing, wing_fem_mesh, wing_mesh.chord_mesh)
cons_wing      = [length(wing_fem_mesh) ÷ 2]
stiffy_wing    = build_stiffness_matrix(Ks_wing, cons_wing)
fem_loads_wing = compute_loads(hs_acs.wing, forces.wing, wing_fem_mesh)

dx_wing = solve_cantilever_beam(Ks_wing, fem_loads_wing, cons_wing)
Δx_wing = [ zeros(6); dx_wing[:] ]

## Horizontal tail FEM setup
htail_beam_ratio = 0.35
htail_fem_mesh   = make_beam_mesh(htail_mesh.chord_mesh, htail_beam_ratio)

# Beam properties
Ls_htail = norm.(diff(htail_fem_mesh))                              # Beam lengths, m
rs_htail = range(8e-3, stop = 2e-3, length = length(Ls_htail) ÷ 2)  # Outer radius, m
ts_htail = range(6e-4, stop = 2e-4, length = length(Ls_htail) ÷ 2)  # Thickness, m
r_htail  = [ reverse(rs_htail); rs_htail ]
t_htail  = [ reverse(ts_htail); ts_htail ]

tubes_htail     = Tube.(Ref(aluminum), Ls_htail, r_htail, t_htail)
Ks_htail        = build_big_stiffy(tubes_htail, htail_fem_mesh, htail_mesh.chord_mesh)
cons_htail      = [length(htail_fem_mesh) ÷ 2]
stiffy_htail    = build_stiffness_matrix(Ks_htail, cons_htail)
fem_loads_htail = compute_loads(hs_acs.htail, forces.htail, htail_fem_mesh)

dx_htail = solve_cantilever_beam(Ks_htail, fem_loads_htail, cons_htail)
Δx_htail = [ zeros(6); dx_htail[:] ]

## Vertical tail FEM setup
vtail_beam_ratio = 0.35
vtail_fem_mesh   = make_beam_mesh(vtail_mesh.chord_mesh, vtail_beam_ratio)

# Beam properties
Ls_vtail = norm.(diff(vtail_fem_mesh))                          # Beam lengths, m
rs_vtail = range(8e-3, stop = 2e-3, length = length(Ls_vtail))  # Outer radius, m
ts_vtail = range(6e-4, stop = 2e-4, length = length(Ls_vtail))  # Thickness, m
r_vtail  = rs_vtail
t_vtail  = ts_vtail

tubes_vtail     = Tube.(Ref(aluminum), Ls_vtail, r_vtail, t_vtail)
Ks_vtail        = build_big_stiffy(tubes_vtail, vtail_fem_mesh, vtail_mesh.chord_mesh)
cons_vtail      = [1]
stiffy_vtail    = build_stiffness_matrix(Ks_vtail, cons_vtail)
fem_loads_vtail = compute_loads(hs_acs.vtail, forces.vtail, vtail_fem_mesh)

dx_vtail = solve_cantilever_beam(Ks_vtail, fem_loads_vtail, cons_vtail)
Δx_vtail = [ zeros(6); dx_vtail[:] ]

## Weight variables (FOR FUTURE USE)

# W   = force(ff_t[3], q, S)
# W_y = fill(W / length(CFs) + 1, length(CFs) + 1)
# W   = (collect ∘ Iterators.flatten ∘ zip)(W_y, zeros(length(My)))
# F_W = [ zeros(length(py)); W; zeros(length(px)) ]
weight      = 60 * 9.81
load_factor = 1.3;

##
stiffy = blockdiag(stiffy_wing, stiffy_htail, stiffy_vtail)

## Aerostructural residual
#==========================================================================================#

chord_meshes  = [ wing_mesh.chord_mesh, htail_mesh.chord_mesh, vtail_mesh.chord_mesh ]
camber_meshes  = [ wing_mesh.camber_mesh, htail_mesh.camber_mesh, vtail_mesh.camber_mesh ]
fem_meshes  = [ wing_fem_mesh, htail_fem_mesh, vtail_fem_mesh ]
fem_weights = [ wing_beam_ratio, htail_beam_ratio, vtail_beam_ratio ]
syms        = [ :wing, :htail, :vtail ]

# Initial guess as ComponentArray for the different equations
x0 = ComponentArray(aerodynamics = (
                                    wing  = system.circulations.wing, 
                                    htail = system.circulations.htail, 
                                    vtail = system.circulations.vtail
                                   ),
                    structures   = (
                                    wing  = Δx_wing, 
                                    htail = Δx_htail, 
                                    vtail = Δx_vtail
                                   ),
                    load_factor  = deg2rad(α))

# Set up initial guess and function
solve_aerostructural_residual!(R, x) =
    solve_coupled_residual!(R, x,
                            V, deg2rad(β), ρ, Ω,
                            syms, chord_meshes, camber_meshes, fem_meshes,
                            stiffy, weight, load_factor)

## Solve nonlinear system
reset_timer!()
@timeit "Solving Residuals" res_aerostruct =
    nlsolve(solve_aerostructural_residual!, x0,
            method         = :newton,
            show_trace     = true,
            # extended_trace = true,
            autodiff       = :forward,
           );
print_timer()

## Get zero
x_opt = res_aerostruct.zero
Γ_opt = x_opt.aerodynamics
δ_opt = x_opt.structures
α_opt = x_opt.load_factor

## Compute displacements
Δs    = map((key, n) -> reshape(δ_opt[key][7:end], 6, n), valkeys(δ_opt), length.(fem_meshes))
dxs   = mesh_translation.(Δs)
Ts    = mesh_rotation.(Δs)

## New VLM variables
new_mesh.chord_meshes = transfer_displacements.(dxs, Ts, chord_meshes, fem_meshes)
new_panels     = make_panels.(new_mesh.chord_meshes)

new_mesh.camber_meshes = transfer_displacements.(dxs, Ts, camber_meshes, fem_meshes)
new_cam_panels = make_panels.(new_mesh.camber_meshes)

new_horsies = new_horseshoes.(dxs, Ts, chord_meshes, camber_meshes, fem_meshes)
all_horsies = reduce(vcat, vec.(new_horsies));

## Aerodynamic forces and center locations
U_opt      = freestream_to_cartesian(-V, α_opt, deg2rad(β))
new_acs    = new_horsies .|> horsies -> bound_leg_center.(horsies)
all_forces = surface_forces(Γ_opt, all_horsies, Γ_opt, all_horsies, U_opt, Ω, ρ)

new_Γs     = getindex.(Ref(Γ_opt), syms)
new_forces = surface_forces.(new_Γs, new_horsies, Ref(Γs), Ref(all_horsies), Ref(U_opt), Ref(Ω), Ref(ρ));

## New beams and loads
new_fem_meshes = make_beam_mesh.(new_mesh.chord_meshes, fem_weights)
fem_loads      = compute_loads.(new_acs, new_forces, new_fem_meshes);

## Compute stresses
δxs = Δs .|> dx -> eachcol(diff(dx[1:3,:], dims = 2)) # Need to transform these to principal axes
δθs = Δs .|> dx -> eachcol(diff(dx[4:6,:], dims = 2)) # Need to transform these to principal axes
σs  = map((tubes, δx, δθ) -> reduce(hcat, von_mises_stress.(tubes, δx, δθ)), [ tubes_wing, tubes_htail, tubes_vtail ], δxs, δθs)

## Check numbers
lift     = sum(all_forces)[3]
load_fac = lift * cos(α_opt) / weight

println("Load factor: $load_fac")
println("Weight: $weight N")
println("Lift: $lift N")
println("Speed: $V m/s")
println("Angle of attack: $(rad2deg(α_opt))ᵒ")

## Generate DataFrame
dfs = DataFrame.((permutedims ∘ vcat).(fem_loads, Δs), :auto)
rename!.(dfs, Ref([:Fx, :Fy, :Fz, :Mx, :My, :Mz, :dx, :dy, :dz, :θx, :θy, :θz]))

## Plotting
#==========================================================================================#

# Beam loads and stresses
fem_plot     = @. reduce(hcat, chop_coordinates(fem_meshes, 1))
new_fem_plot = @. reduce(hcat, chop_coordinates(new_fem_meshes, 1))
loads_plot   = fem_loads
σs_max       = map(σ -> maximum.(eachcol(σ)), σs)
σs_norm      = [ σ_max ./ maximum(σ_max) for σ_max in σs_max ]
σ_norms      = [ [ σ_norm; σ_norm[end] ] for σ_norm in σs_norm ]

## Panels
wing_panel_plot  = plot_panels(wing_panels)
htail_panel_plot = plot_panels(htail_panels)
vtail_panel_plot = plot_panels(vtail_panels)

# Aerodynamic centers and forces
ac_plots    = @. reduce(hcat, new_acs)
force_plots = @. reduce(hcat, new_forces)

# Cambers
cam_panels   = @. make_panels(camber_meshes)
cam_plot     = plot_panels(reduce(vcat, vec.(cam_panels)))
new_cam_plot = plot_panels(reduce(vcat, vec.(new_cam_panels)))

# Displacements
new_mesh.chord_mesh_plot = @. reduce(hcat, new_mesh.chord_meshes)
new_panel_plot    = plot_panels(reduce(vcat, vec.(make_panels.(new_mesh.chord_meshes))))

# Planforms
wing_plan   = plot_planform(wing)
htail_plan  = plot_planform(htail)
vtail_plan  = plot_planform(vtail)

# New planforms
nwing_plan  = plot_planform(new_mesh.camber_meshes[1])
nhtail_plan = plot_planform(new_mesh.camber_meshes[2])
nvtail_plan = plot_planform(new_mesh.camber_meshes[3])

# Streamlines
seed    = chop_coordinates(new_mesh.camber_meshes[1][end,:], 4)
streams = streamlines(fs, seed, all_horsies, Γ_opt, 5, 100);

## Plot
using Plots
using LaTeXStrings

# gr()
# plotlyjs(dpi = 300, size = (1280, 720))
# pyplot(dpi = 150)
pgfplotsx(size = (900, 600))

aircraft_plot =
    plot(xaxis = "x", yaxis = "y", zaxis = "z",
         camera = (-85, 20),
         xlim = (-b/4, 3b/4),
     #     ylim = (-b/2, b/2),
         zlim = (-b/8, 3b/4),
        #  bg_inside = RGBA(0.96, 0.96, 0.96, 1.0),
         legend = :topright,
         title = "Coupled Aerostructural Analysis"
        )

# Panels
# [ plot!(pans, color = :lightgray, label = ifelse(i == 1, "Original Panels", :none), linestyle = :solid) for (i, pans) in enumerate(cam_plot) ]
# [ plot!(pans, color = :lightblue, label = ifelse(i == 1, "Deflected Panels", :none), linestyle = :solid) for (i, pans) in enumerate(new_cam_plot) ]

# Planforms
plot!(wing_plan, color = :gray, label = "Original Wing", linestyle = :solid)
plot!(nwing_plan, color = :blue, label = "Deflected Wing")
plot!(htail_plan, color = :gray, label = "Horizontal Tail")
plot!(nhtail_plan, color = :blue, label = "Deflected Horizontal Tail")
plot!(vtail_plan, color = :gray, label = "Vertical Tail")
plot!(nvtail_plan, color = :blue, label = "Deflected Vertical Tail")

# Beams
thickness = 2.5
normer(rs) = [ rs; rs[end] ] / maximum(rs)
r_norms = @. normer([ r_wing, r_htail, r_vtail ]) * thickness
[ plot!(fem[1,:], fem[2,:], fem[3,:], color = :black, label = "Original Beam", linestyle = :solid, linewidth = r_ns) for (fem, r_ns) in zip(fem_plot, r_norms) ]

[ plot!(new_fem[1,:], new_fem[2,:], new_fem[3,:], m = (thickness, 0.8, :heat, Plots.stroke(0)), zcolor = σ_ns, cbar = true, label = "Deflected Beam Stresses", linestyle = :solid, linewidth = r_ns) for (new_fem, σ_ns, r_ns) in zip(new_fem_plot, σ_norms, r_norms) ]

# Streamlines
[ plot!(stream, color = RGBA(0.5, 0.8, 0.5, 1.0), label = ifelse(i == 1, "Streamlines", :none), linestyle = :solid) for (i, stream) in enumerate(streams) ]

# Forces
[ quiver!(ac_plot[1,:], ac_plot[2,:], ac_plot[3,:],
          quiver=(force_plot[1,:], force_plot[2,:], force_plot[3,:]) .* 0.05,
          label = ifelse(i == 1, "Panel Forces", :none), color = :orange) 
          for (i, ac_plot, force_plot) in zip(1:length(ac_plots), ac_plots, force_plots) ]
# [ scatter!(ac_plot[1,:], ac_plot[2,:], ac_plot[3,:], label = ifelse(i == 1, "Aerodynamic Centers", :none)) for ac_plot in ac_plots ]
# [ quiver!(fem_plots[1,:], fem_plots[2,:], fem_plots[3,:],
#         quiver=(loads_plots[1,:], loads_plots[2,:], loads_plots[3,:] ) .* 0.1,
#         label = ifelse(i == 1, "Beam Forces", :none)) for (fem_plots, loads_plots) in zip(fem_plot, loads_plot) ]

savefig(aircraft_plot, "plots/AerostructWingTails.pdf")
plot!()