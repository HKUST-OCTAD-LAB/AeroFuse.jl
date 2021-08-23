## Coordinates
#==========================================================================================#

wing_bounds(lead, trail) = permutedims([ lead trail ]) 

chop_leading_edge(obj  :: HalfWing, span_num; y_flip = false) = chop_coordinates(leading_edge(obj, y_flip),  span_num)
chop_trailing_edge(obj :: HalfWing, span_num; y_flip = false) = chop_coordinates(trailing_edge(obj, y_flip), span_num)

chop_leading_edge(obj :: Wing, span_num :: Integer)  = chop_coordinates([ leading_edge(left(obj), true)[1:end-1]; leading_edge(right(obj)) ], span_num)
chop_trailing_edge(obj :: Wing, span_num :: Integer) = chop_coordinates([ trailing_edge(left(obj), true)[1:end-1]; trailing_edge(right(obj)) ], span_num)

coordinates(wing :: HalfWing, y_flip = false) = let (lead, trail) = wing_bounds(wing, y_flip); affine_transformation(wing).(wing_bounds(lead, trail)) end
coordinates(wing :: Wing) = let (lead, trail) = wing_bounds(wing); affine_transformation(wing).(wing_bounds(lead, trail)) end

coordinates(wing :: Union{HalfWing, Wing}, span_num, chord_num; span_spacing = ["cosine"], chord_spacing = ["cosine"]) = chop_wing(coordinates(wing), span_num, chord_num; span_spacing = span_spacing, chord_spacing = chord_spacing)

"""
    chord_coordinates(wing :: HalfWing, n_s :: Integer, n_c :: Integer, flip = false)

Compute the chord coordinates of a `HalfWing` consisting of `Foil`s and relevant geometric quantities, given numbers of spanwise ``n_s`` and chordwise ``n_c`` panels, with an option to flip the signs of the ``y``-coordinates.
"""
chord_coordinates(wing :: HalfWing, span_num :: Vector{<: Integer}, chord_num :: Integer; spacings = ["cosine"], flip = false) = chop_wing(coordinates(wing, flip), span_num, chord_num; span_spacing = spacings, flip = flip)

"""
    surface_coordinates(wing :: HalfWing, n_s :: Integer, n_c :: Integer, flip = false)

Compute the surface coordinates of a `HalfWing` consisting of `Foil`s and relevant geometric quantities, given numbers of spanwise ``n_s`` and chordwise ``n_c`` panels, with an option to flip the signs of the ``y``-coordinates.
"""
function surface_coordinates(wing :: HalfWing, span_num :: Vector{<: Integer}, chord_num :: Integer; spacings = ["cosine"], flip = false)
    leading_xyz  = leading_edge(wing, flip)
    scaled_foils = @. wing.chords * (extend_yz ∘ cosine_foil)(wing.foils, chord_num)
    affine_transformation(wing).(chop_spanwise_sections(scaled_foils, twists(wing), leading_xyz, span_num, spacings, flip))
end

"""
    camber_coordinates(wing :: HalfWing, n_s :: Integer, n_c :: Integer, flip = false)

Compute the camber coordinates of a `HalfWing` consisting of camber distributions of `Foil`s and relevant geometric quantities, given numbers of spanwise ``n_s`` and chordwise ``n_c`` panels, with an option to flip the signs of the ``y``-coordinates.
"""
function camber_coordinates(wing :: HalfWing, span_num :: Vector{<: Integer}, chord_num :: Integer; spacings = ["cosine"], flip = false)
    leading_xyz  = leading_edge(wing, flip)
    scaled_foils = @. wing.chords * (camber_coordinates ∘ camber_thickness)(wing.foils, chord_num)
    affine_transformation(wing).(chop_spanwise_sections(scaled_foils, twists(wing), leading_xyz, span_num, spacings, flip))
end

## Wing variants
#==========================================================================================#

function chord_coordinates(wing :: Wing, span_num :: Vector{<: Integer}, chord_num :: Integer; spacings = ["cosine"])
    left_coord  = chord_coordinates(left(wing), reverse(span_num), chord_num; spacings = reverse(spacings), flip = true)
    right_coord = chord_coordinates(right(wing), span_num, chord_num; spacings = spacings)

    [ left_coord[:,1:end-1] right_coord ]
end

function camber_coordinates(wing :: Wing, span_num :: Vector{<: Integer}, chord_num :: Integer; spacings = ["cosine"], flip = false)
    left_coord  = camber_coordinates(left(wing), reverse(span_num), chord_num; spacings = reverse(spacings), flip = true)
    right_coord = camber_coordinates(right(wing), span_num, chord_num; spacings = spacings)

    [ left_coord[:,1:end-1] right_coord ]
end

function surface_coordinates(wing :: Wing, span_num :: Vector{<: Integer}, chord_num :: Integer; spacings = ["cosine"])
    left_coord  = surface_coordinates(left(wing), reverse(span_num), chord_num; spacings = reverse(spacings), flip = true)
    right_coord = surface_coordinates(right(wing), span_num, chord_num; spacings = spacings)

    [ left_coord[:,1:end-1] right_coord ]
end

## Spanwise distribution processing
#==========================================================================================#

# Numbering
number_of_spanwise_panels(wing :: HalfWing, span_num :: Integer) = ceil.(Int, span_num .* spans(wing) / span(wing))
number_of_spanwise_panels(wing :: Wing,     span_num :: Integer) = number_of_spanwise_panels(right(wing), span_num ÷ 2)

function number_of_spanwise_panels(wing :: HalfWing, span_num :: Vector{<: Integer})
    @assert (length ∘ spans)(wing) > 1 "Provide an integer number of spanwise panels for 1 wing section."
    span_num
end

function number_of_spanwise_panels(wing :: Wing, span_num :: Vector{<: Integer})
    @assert (length ∘ spans ∘ right)(wing) > 1 "Provide an integer number of spanwise panels for 1 wing section."
    span_num .÷ 2
end

# Spacing
spanwise_spacing(wing :: HalfWing) = [ "sine"; fill("cosine", (length ∘ spans)(wing)         - 1) ]
spanwise_spacing(wing :: Wing)     = [ "sine"; fill("cosine", (length ∘ spans ∘ right)(wing) - 1) ]

# Coordinates
chord_coordinates(wing :: Wing, span_num :: Integer, chord_num :: Integer; spacings = ["cosine"]) = chord_coordinates(wing, number_of_spanwise_panels(wing, span_num), chord_num; spacings = spacings)
camber_coordinates(wing :: Wing, span_num :: Integer, chord_num :: Integer; spacings = ["cosine"]) = camber_coordinates(wing, number_of_spanwise_panels(wing, span_num), chord_num; spacings = spacings)

## Panelling
#==========================================================================================#

"""
    mesh_horseshoes(wing :: HalfWing, n_s :: Integer, n_c :: Integer; flip = false)

Mesh a `HalfWing` into panels of ``n_s`` spanwise divisions per section and ``n_c`` chordwise divisions meant for lifting-line/vortex lattice analyses using horseshoe elements.
"""
mesh_horseshoes(wing :: HalfWing, span_num :: Vector{<: Integer}, chord_num :: Integer; spacings = ["cosine"], flip = false) = make_panels(chord_coordinates(wing, span_num, chord_num; spacings = spacings, flip = flip))

"""
    mesh_wing(wing :: HalfWing, n_s :: Integer, n_c :: Integer; flip = false)

Mesh a `HalfWing` into panels of ``n_s`` spanwise divisions per section and ``n_c`` chordwise divisions meant for 3D analyses using doublet-source elements or equivalent formulations. TODO: Tip meshing.
"""
mesh_wing(wing :: HalfWing, span_num :: Vector{<: Integer}, chord_num :: Integer; spacings = ["cosine"], flip = false) = make_panels(surface_coordinates(wing, span_num, chord_num, spacings = spacings, flip = flip))

"""
    mesh_cambers(wing :: HalfWing, n_s :: Integer, n_c :: Integer; flip = false)

Mesh the camber distribution of a `HalfWing` into panels of ``n_s`` spanwise divisions per section and ``n_c`` chordwise divisions meant for vortex lattice analyses.
"""
mesh_cambers(wing :: HalfWing, span_num :: Vector{<: Integer}, chord_num :: Integer; spacings = ["cosine"], flip = false) = make_panels(camber_coordinates(wing, span_num, chord_num; spacings = spacings, flip = flip))


"""
    mesh_horseshoes(wing :: Wing, n_s :: Integer, n_c :: Integer)

Mesh a `Wing` into panels of ``n_s`` spanwise divisions per section and ``n_c`` chordwise divisions meant for lifting-line/vortex lattice analyses using horseshoe elements.
"""
function mesh_horseshoes(wing :: Wing, span_num, chord_num; spacings = ["cosine"])
    left_panels  = mesh_horseshoes(left(wing), reverse(span_num), chord_num; spacings = reverse(spacings), flip = true)
    right_panels = mesh_horseshoes(right(wing), span_num, chord_num; spacings = spacings)

    [ left_panels right_panels ]
end

"""
    mesh_wing(wing :: Wing, n_s :: Integer, n_c :: Integer)

Mesh a `Wing` into panels of ``n_s`` spanwise divisions per section and ``n_c`` chordwise divisions meant for 3D analyses using doublet-source elements or equivalent formulations. TODO: Tip meshing.
"""
function mesh_wing(wing :: Wing, span_num, chord_num; spacings = ["cosine"])
    left_panels  = mesh_wing(left(wing), reverse(span_num), chord_num; spacings = reverse(spacings), flip = true)
    right_panels = mesh_wing(right(wing), span_num, chord_num; spacings = spacings)

    [ left_panels right_panels ]
end

"""
    mesh_cambers(wing :: Wing, n_s :: Integer, n_c :: Integer)

Mesh the camber distribution of a `Wing` into panels of ``n_s`` spanwise divisions per section and ``n_c`` chordwise divisions meant for vortex lattice analyses.
"""
function mesh_cambers(wing :: Wing, span_num, chord_num; spacings = ["cosine"])
    left_panels  = mesh_cambers(left(wing), reverse(span_num), chord_num; spacings = reverse(spacings), flip = true)
    right_panels = mesh_cambers(right(wing), span_num, chord_num; spacings = spacings)

    [ left_panels right_panels ]
end

vlmesh_wing(wing :: Union{HalfWing, Wing}, span_num, chord_num, spacings = ["cosine"]) = mesh_horseshoes(wing, span_num, chord_num; spacings = spacings), mesh_cambers(wing, span_num, chord_num; spacings = spacings)
vlmesh_wing(wing :: Union{HalfWing, Wing}, span_num :: Integer, chord_num, spacings = ["cosine"]) = mesh_horseshoes(wing, [span_num], chord_num; spacings = spacings), mesh_cambers(wing, [span_num], chord_num; spacings = spacings)

function paneller(wing :: Union{HalfWing{T}, Wing{T}}, span_num :: Union{Integer, Vector{<: Integer}}, chord_num :: Integer; spacings = ["cosine"]) where T <: Real
    horseshoes, cambers = vlmesh_wing(wing, span_num, chord_num, spacings)  
    horseshoes, panel_normal.(cambers)
end

panel_wing(comp :: Union{Wing, HalfWing}, span_panels :: Union{Integer, Vector{<: Integer}}, chord_panels :: Integer; spacing = spanwise_spacing(comp)) = paneller(comp, span_panels, chord_panels, spacings = ifelse(typeof(spacing) <: String, [spacing], spacing))