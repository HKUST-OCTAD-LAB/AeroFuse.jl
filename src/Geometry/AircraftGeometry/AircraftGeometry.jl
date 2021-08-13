module AircraftGeometry

using Base.Math
using Base.Iterators
using DelimitedFiles
using StaticArrays
using CoordinateTransformations
using Rotations
using LinearAlgebra

using ..AeroMDAO: uniform_spacing, linear_spacing, sine_spacing, cosine_spacing, cosine_interp, splitat, adj3, slope, columns, fwdsum, fwddiv, fwddiff, weighted_vector, vectarray, Point2D, Panel2D, Panel3D, extend_yz, transform, panel_area, panel_normal, wetted_area

abstract type Aircraft end

export Aircraft

## Foil geometry
#==========================================================================================#

include("foil.jl")

## Fuselage geometry
#==========================================================================================#

include("fuselage.jl")

## Wing geometry
#==========================================================================================#

aspect_ratio(span, area) = span^2 / area
mean_geometric_chord(span, area) = area / span
taper_ratio(root_chord, tip_chord) = tip_chord / root_chord
area(span, chord) = span * chord
mean_aerodynamic_chord(root_chord, taper_ratio) = (2/3) * root_chord * (1 + taper_ratio + taper_ratio^2)/(1 + taper_ratio)
y_mac(y, b, λ) = y + b / 2 * (1 + 2λ) / 3(1 + λ)
quarter_chord(chord) = 0.25 * chord

include("halfwing.jl")
include("wing.jl")
include("mesh_tools.jl")
include("mesh_wing.jl")

aspect_ratio(wing) = aspect_ratio(span(wing), projected_area(wing))

info(wing :: Union{Wing, HalfWing}) = [ span(wing), projected_area(wing), mean_aerodynamic_chord(wing), aspect_ratio(wing) ]

end