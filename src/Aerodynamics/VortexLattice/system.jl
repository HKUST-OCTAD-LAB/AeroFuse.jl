mutable struct VLMState{T <: Real}
	speed     :: T
    alpha     :: T
    beta      :: T
    velocity  :: SVector{3,T}
    omega     :: SVector{3,T}
	r_ref 	  :: SVector{3,T}
	rho_ref   :: T
	area_ref  :: T
	chord_ref :: T
	span_ref  :: T
	name 	  :: String
    VLMState(U, α, β, Ω :: AbstractVector{T} = zeros(3); r_ref = zeros(3), rho_ref = 1.225, area_ref = 1, chord_ref = 1, span_ref = 1, name = "Aircraft") where T <: Real = new{T}(U, α, β, freestream_to_cartesian(-U, α, β), SVector(Ω...), SVector(r_ref...), rho_ref, area_ref, chord_ref, span_ref, name)
end

rate_coefficient(state :: VLMState) = rate_coefficient(state.omega, state.speed, state.span_ref, state.chord_ref)
update_velocity!(state :: VLMState) = 
    state.velocity = freestream_to_cartesian(-state.speed, state.alpha, state.beta)

name(state :: VLMState) = state.name

struct StabilityFrame{T <: Real}
    alpha :: T
end

struct WindFrame{T <: Real}
    alpha :: T
    beta  :: T
end

mutable struct VLMSurface{T <: Real}
    horseshoes      :: Matrix{Horseshoe{T}}
    normals         :: Matrix{SVector{3,T}}
    surface_forces  :: Matrix{SVector{3,T}}
    surface_moments :: Matrix{SVector{3,T}}
    circulations    :: Matrix{T}
    wake_vectors    :: Vector{SVector{3,T}}
    wake_AIC        :: Matrix{T}
    farfield_forces :: SVector{3,T}
    name            :: String
end

function VLMSurface(panels :: Matrix{Panel3D{T}}, normals :: Matrix{SVector{3,T}}, name = "Wing") where T <: Real
    # Initialize
    m               = size(panels)
    wake_AIC        = Matrix{T}(undef, m)
    Γs              = Matrix{T}(undef, m)
    surface_forces  = Matrix{SVector{3,T}}(undef, m)
    surface_moments = Matrix{SVector{3,T}}(undef, m)
    wake_vectors    = Vector{SVector{3,T}}(undef, m[1])
    farfield_forces = SVector{3,T}(0., 0., 0.)

    VLMSurface{T}(horseshoe_line.(panels), normals, surface_forces, surface_moments, Γs, wake_vectors, wake_AIC, farfield_forces, name)
end

horseshoes(surf :: VLMSurface)      = surf.horseshoes
normals(surf :: VLMSurface)         = surf.normals
surface_forces(surf :: VLMSurface)  = surf.surface_forces
surface_moments(surf :: VLMSurface) = surf.surface_moments
circulations(surf :: VLMSurface)    = surf.circulations
name(surf :: VLMSurface)            = surf.name

collocation_points(surf :: VLMSurface) = collocation_point.(horseshoes(surf))

function compute_wake_properties!(surface :: VLMSurface, α, β)
    # Reference velocity for broadcasting
    U_ref = (Ref ∘ SVector)(1, 0, 0)

    # Transform to wind axes
    wake_lines  = @. body_to_wind_axes(bound_leg(surface.horseshoes[end,:][:]), α, β)
    centers     = center.(wake_lines)
    wake_points = points(wake_lines)

    # Project trailing edge horseshoes' bound legs into Trefftz plane along wind axes
    surface.wake_vectors = @. project_vector(vector(wake_lines), U_ref)

    # Compute normal vectors
    wake_normals = @. normal(surface.wake_vectors, U_ref)

    surface.wake_AIC = trefftz_influence_matrix(centers, wake_normals, wake_points)
end

mutable struct VLMSystem{T <: Real}
    horseshoes   :: Vector{Horseshoe{T}}
    normals      :: Vector{SVector{3,T}}
    AIC          :: Matrix{T}
    RHS          :: Vector{T}
    circulations :: Vector{T}
end

horseshoes(system :: VLMSystem)   = system.horseshoes
normals(system :: VLMSystem)      = system.normals
AIC(system :: VLMSystem)          = system.AIC
RHS(system :: VLMSystem)          = system.RHS
circulations(system :: VLMSystem) = system.circulations

collocation_points(system :: VLMSystem) = collocation_point.(horseshoes(system))

# Initialization
function VLMSystem{T}(horseshoes :: Vector{Horseshoe{T}}, normals :: Vector{SVector{3,T}}) where T <: Real
    m   = length(horseshoes)
    AIC = Matrix{T}(undef, m, m)
    RHS = Vector{T}(undef, m)
    Γs  = Vector{T}(undef, m)
    VLMSystem{T}(horseshoes, normals, AIC, RHS, Γs)
end

function VLMSystem(surface :: VLMSurface{T}) where T <: Real
    horsies = horseshoes.(surface)[:]
    normies = normals.(surface)[:]
    VLMSystem{T}(horsies, normies)
end

function VLMSystem(surfaces :: AbstractVector{VLMSurface{T}}) where T <: Real
    # Flattening for system
    horsies = reduce(vcat, (vec ∘ horseshoes).(surfaces))
    normies = reduce(vcat, (vec ∘ normals).(surfaces))
    VLMSystem{T}(horsies, normies)
end

function build_system(aircraft :: Dict{String, Tuple{Matrix{Panel3D{T}}, Matrix{SVector{3,T}}}}) where T <: Real
    # Get panels and normals
    names  = keys(aircraft)
    vals   = values(aircraft)

    # Build surfaces and systems
    surfs  = @. VLMSurface(getindex.(vals, 1), getindex.(vals, 2), names)
    system = VLMSystem(surfs)

    system, surfs  # NEED TO THINK ABOUT WHETHER TO RETURN DICTIONARY OF SURFACES
end

compute_horseshoes!(system :: VLMSystem, horseshoe_panels) = 
    system.horseshoes = horseshoe_line.(horseshoe_panels)

compute_influence_matrix!(system, V) = 
    system.AIC = influence_matrix(horseshoes(system), collocation_points(system), normals(system), -normalize(V))

compute_boundary_condition!(system :: VLMSystem, V, Ω) = 
    system.RHS = boundary_condition(map(r -> V + Ω × r, collocation_points(system)), normals(system))

generate_system!(system :: VLMSystem, V, Ω) =
    matrix_assembly!(AIC(system), RHS(system), horseshoes(system), collocation_points(system), normals(system), V, Ω)

solve_system!(system :: VLMSystem) = 
    system.circulations = AIC(system) \ RHS(system)

function update_circulations!(Γ, surfs) 
    # Get sizes and indices for reshaping (UGLY AF)
    sizes = @. (size ∘ horseshoes)(surfs)
    inds  = [ 0; cumsum(prod.(sizes)) ]
    Γs    = reshape_array(Γ, inds, sizes)

    # Allocate surface circulations
    for (surf, Γ_vec) in zip(surfs, Γs)
        surf.circulations = Γ_vec
    end
end

## Dynamics evaluations
compute_surface_forces!(surf :: VLMSurface, system :: VLMSystem, U, Ω, ρ) = 
    surf.surface_forces = nearfield_forces(circulations(surf), horseshoes(surf), circulations(system), horseshoes(system), U, Ω, ρ)

compute_surface_moments!(surf :: VLMSurface, r_ref) =
    surf.surface_moments = moments(horseshoes(surf), surface_forces(surf), r_ref)
    
function compute_farfield_forces!(surface :: VLMSurface, U, α, β, ρ);
    # Set up wake AIC and evaluate doublet normal derivatives
    Δφs = vec(sum(circulations(surface), dims = 1))
    compute_wake_properties!(surface, α, β)
    ∂φ_∂n = surface.wake_AIC * Δφs

    Δs = @. norm(surface.wake_vectors)
    θs = @. dihedral(surface.wake_vectors)

    surface.farfield_forces = trefftz_compute(Δφs, Δs, ∂φ_∂n, θs, U, ρ) 
end

function evaluate_case!(system :: VLMSystem, surfs :: Vector{<: VLMSurface}, state :: VLMState)
    # Update state velocity
    update_velocity!(state)
    
    # Assemble and solve matrix system
    # compute_influence_matrix!(system, state.velocity)
    # compute_boundary_condition!(system, state.velocity, state.omega)
    generate_system!(system, state.velocity, state.omega) # Pre-allocated version for efficiency
    solve_system!(system)
    update_circulations!(circulations(system), surfs)

    # Evaluate forces
    compute_surface_forces!.(surfs, Ref(system), Ref(state.velocity), Ref(state.omega), state.rho_ref)
    compute_surface_moments!.(surfs, Ref(state.r_ref))
    compute_farfield_forces!.(surfs, state.speed, state.alpha, state.beta, state.rho_ref)

    system, surfs, state
end

function solve_aerodynamic_residual!(R, Γ, system :: VLMSystem, surfs :: Vector{<: VLMSurface}, state :: VLMState)
    # Update state velocity
    update_velocity!(state)

    # Assemble matrix system
    generate_system!(system, state.velocity, state.omega) # Pre-allocated version for efficiency

    # Update circulations
    system.circulations = Γ
    update_circulations!(circulations(system), surfs)

    # Compute forces
    compute_surface_forces!.(surfs, Ref(system), Ref(state.velocity), Ref(state.omega), state.rho_ref)
    compute_surface_moments!.(surfs, Ref(state.r_ref))
    compute_farfield_forces!.(surfs, state.speed, state.alpha, state.beta, state.rho_ref)

    # Evaluate residual
    R = evaluate_residual!(R, Γ, system)
end

## Pure methods
surface_force_coefficients(surf :: VLMSurface, U, ρ, S) = 
    force_coefficient.(surf.surface_forces,  dynamic_pressure(ρ, U), S)

surface_moment_coefficients(surf :: VLMSurface, U, ρ, S, b, c) = 
    moment_coefficient.(surf.surface_moments, dynamic_pressure(ρ, U), S, b, c)

function nearfield_coefficients(surf :: VLMSurface, U, α, β, ρ, S, b, c) 
    CF_body = (sum ∘ surface_force_coefficients)(surf, U, ρ, S)
    CM_body = (sum ∘ surface_moment_coefficients)(surf, U, ρ, S, b, c)
    CF_wind = body_to_wind_axes(CF_body, α, β) # Consider axes specification in state
    CM_wind = body_to_wind_axes(stability_flip(CM_body), α, β)

    [ CF_wind; CM_wind ]
end

farfield_coefficients(surf :: VLMSurface, V, ρ, S) = force_coefficient(surf.farfield_forces, dynamic_pressure(ρ, V), S)

aerodynamic_coefficients(surf :: VLMSurface, state :: VLMState) = nearfield_coefficients(surf, state), farfield_coefficients(surf, state)

function aerodynamic_coefficients(surfs, state :: VLMState) 
    coeffs    = aerodynamic_coefficients.(surfs, Ref(state))
    nf_coeffs = reduce(hcat, first.(coeffs))
    ff_coeffs = reduce(hcat, last.(coeffs))
    
    nf = [ sum(nf_coeffs, dims = 2) nf_coeffs ]
    ff = [ sum(ff_coeffs, dims = 2) ff_coeffs ]
    
    OrderedDict( [ name(state); name.(surfs) ] .=> zip(eachcol(nf), eachcol(ff)) )
end

# State versions
surface_force_coefficients(surf :: VLMSurface, state :: VLMState)  = surface_force_coefficients(surf, state.speed, state.rho_ref, state.area_ref)

surface_moment_coefficients(surf :: VLMSurface, state :: VLMState) = surface_moment_coefficients(surf, state.speed, state.rho_ref, state.area_ref, state.span_ref, state.chord_ref)

nearfield_coefficients(surf :: VLMSurface, state :: VLMState) = nearfield_coefficients(surf, state.speed, state.alpha, state.beta, state.rho_ref, state.area_ref, state.span_ref, state.chord_ref)

farfield_coefficients(surf :: VLMSurface, state :: VLMState)  = farfield_coefficients(surf, state.speed, state.rho_ref, state.area_ref)

## Residual setup
#=============================================#

evaluate_residual!(R, Γ, system :: VLMSystem) =
    R .= AIC(system) * Γ - RHS(system)



"""
    solve_case(horseshoe_panels :: Matrix{Panel3D}, normals, freestream :: Freestream, r_ref, ρ = 1.225; symmetry = false)

Evaluate a vortex lattice case given an array of `Panel3D`s with associated normal vectors (not necessarily the same as the panels' normals), a `Freestream`, reference density ``\\rho`` and reference point ``r_\\text{ref}`` for moments.
"""
function evaluate_case(horseshoe_panels :: Array{<: Panel3D}, normals, U, α, β, Ω, rho_ref, r_ref, area_ref, chord_ref, span_ref)
    # Make horseshoes and collocation points
    horseshoes = horseshoe_line.(horseshoe_panels)

    # Solve system
    Γs = reshape(solve_system(horseshoes[:], normals[:], U, Ω), size(horseshoe_panels))

    # Compute forces and moments
    surface_forces, surface_moments, trefftz_force = case_dynamics(Γs, horseshoes, U, α, β, Ω, rho_ref, r_ref)

    # Compute aerodynamic coefficients
    nearfield_coeffs, farfield_coeffs, CFs, CMs = evaluate_coefficients(surface_forces, surface_moments, trefftz_force, U, α, β, Ω, rho_ref, area_ref, chord_ref, span_ref)

    nearfield_coeffs, farfield_coeffs, CFs, CMs, horseshoes, Γs
end

function evaluate_case(components :: Dict{String, Tuple{Matrix{Panel3D{T}}, Matrix{SVector{3,T}}}}, U, α, β, Ω, rho_ref, r_ref, area_ref, chord_ref, span_ref, name) where T <: Real
    # Get panels
    meshes = values(components)
    
    # Flattening for VLM
    horseshoe_panels = first.(meshes)
    normals          = last.(meshes)
    horsies          = reduce(vcat, vec.(horseshoe_panels))
    normies          = reduce(vcat, vec.(normals))

    # Get required vortex lattice variables, i.e. horseshoes, collocation points and normals
    horseshoes = horseshoe_line.(horsies)
    horseshoes_arr = [ horseshoe_line.(horses) for horses in horseshoe_panels ]

    # Solve system
    Γs = solve_system(horseshoes, normies, U, Ω)

    # Reshaping
    panel_sizes = size.(horseshoe_panels)
    panel_inds 	= [ 0; cumsum(prod.(panel_sizes)) ]
    Γs_arr 		= reshape_array(Γs, panel_inds, panel_sizes)

    # Compute forces and moments
    results = case_dynamics.(Γs_arr, horseshoes_arr, Ref(Γs), Ref(horseshoes), Ref(U), α, β, Ref(Ω), rho_ref, Ref(r_ref))
    forces  = getindex.(results, 1)
    moments = getindex.(results, 2) 
    trefftz = getindex.(results, 3)

    # Components' non-dimensional forces and moments
    data = evaluate_coefficients.(forces, moments, trefftz, Ref(U), α, β, Ref(Ω), rho_ref, area_ref, chord_ref, span_ref)

    nf_comp_coeffs = getindex.(data, 1)
    ff_comp_coeffs = getindex.(data, 2)
    CFs            = getindex.(data, 3)
    CMs            = getindex.(data, 4)

    # Aircraft's non-dimensional forces and moments
    nf_coeffs = reduce((x, y) -> x .+ y, nf_comp_coeffs) # Sum nearfield coefficients
    ff_coeffs = reduce((x, y) -> x .+ y, ff_comp_coeffs) # Sum farfield coefficients
    name_CFs  = reduce(vcat, vec.(CFs))                  # Collect surface force coefficients
    name_CMs  = reduce(vcat, vec.(CMs))                  # Collect surface moment coefficients

    # Dictionary assembly
    name_data = (nf_coeffs, ff_coeffs, name_CFs, name_CMs, horsies, normies, horseshoes, Γs)
    comp_data = tuple.(nf_comp_coeffs, ff_comp_coeffs, CFs, CMs, horseshoe_panels, normals, horseshoes_arr, Γs_arr)

    names 	= [ name						 ; # Aircraft name
                (collect ∘ keys)(components) ] # Component names
    data  	= [ name_data ;	# Aircraft data
                comp_data ]	# Component data

    OrderedDict(names .=> data)
end