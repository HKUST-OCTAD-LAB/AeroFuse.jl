function plot_panels(panels :: Vector{<: Panel3D})
    coords = panel_coords.(panels)
    tupvector.([coord; [coord[1]]] for coord in coords)
end

# foil_coords = [ [ [coord[1]; 0; coord[2]] .* chord .+ loc for coord in foil.coordinates ] for (chord, foil, loc) in zip(wing.right.chords[end:-1:1], wing.right.foils[end:-1:1], wing_coords) ]
    

function plot_wing(mesh :: Matrix{SVector{3,T}}, rotation, translation) where T <: Real
    affine = Translation(translation) ∘ LinearMap(rotation)
    wing_coords =   [ 
                        mesh[1,1:end-1]; 
                        mesh[1:end-1,end]; 
                        mesh[end,end:-1:2]; 
                        mesh[end:-1:1,1] 
                    ]
                    
    [ tuple(affine(coords)...) for coords in wing_coords ][:]
end

plot_wing(wing :: Union{HalfWing, Wing}, rotation, translation) = plot_wing(coordinates(wing), rotation, translation)

plot_wing(wing; angle :: T = 0., axis = [1., 0., 0.], position = zeros(3)) where T <: Real = plot_wing(wing, AngleAxis{T}(angle, axis...), position)

plot_streams(freestream, points, horseshoes, Γs, length, num_steps) = tupvector.(streamlines(freestream, points, horseshoes, Γs, length, num_steps))

plot_surface(wing :: Union{HalfWing, Wing}, span_num = 5, chord_num = 30; rotation = one(RotMatrix{3, Float64}), translation = SVector(0, 0, 0)) = plot_panels(transform(panel, rotation, translation) for panel in mesh_wing(wing, span_num, chord_num)[:])


## Doublet-source
#==========================================================================================#

## Plotting domain
# x_domain, y_domain = (-1, 2), (-1, 1)
# grid_size = 50
# x_dom, y_dom = linspace(x_domain..., grid_size), linspace(y_domain..., grid_size)
# grid = x_dom × y_dom

# vels, pots = grid_data(dub_src_panels, grid)
# cp = pressure_coefficient.(uniform.magnitude, vels);

# lower_panels, upper_panels = split_panels(dub_src_panels);

# ## Airfoil plot
# plot( (first ∘ collocation_point).(upper_panels), (last ∘ collocation_point).(upper_panels), 
#         label = "Upper", markershape = :circle,
#         xlabel = "x", ylabel = "C_p")
# plot!((first ∘ collocation_point).(lower_panels), (last ∘ collocation_point).(lower_panels),
#         label = "Lower", markershape = :circle,
#         xlabel = "x", ylabel = "C_p")

# ## Pressure coefficient
# plot( (first ∘ collocation_point).(upper_panels), :cp .<< upper_panels, 
#         label = "Upper", markershape = :circle, 
#         xlabel = "x", ylabel = "C_p")
# plot!((first ∘ collocation_point).(upper_panels), :cp .<< lower_panels, 
#         label = "Lower", markershape = :circle, yaxis = :flip)

# ## Control volume
# p1 = contour(x_dom, y_dom, cp, fill = true)
# plot(p1)
# plot!(first.(:start .<< panels), last.(:start .<< panels), 
#       color = "black", label = "Airfoil", aspect_ratio = :equal)