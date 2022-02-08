## TOTALLY not a ripoff of MIT's Dawn Solar HALE aircraft
using AeroMDAO
using TimerOutputs
using BenchmarkTools

# Aerostructural analysis case
#==========================================================================================#

## Aerodynamic variables

# Define wing
@time wing = Wing(
                foils     = fill(naca4((2,4,1,2)), 3),
                chords    = [1.0, 1.0, 0.6],
                twists    = [0.0, 0.0, 0.0],
                spans     = [4.0, 3.0],
                dihedrals = [0., 0.],
                sweeps    = [0., 5.]
            );

print_info(wing, "Lawn Polar Wing")

# Horizontal tail
@time htail = Wing(
                foils     = fill(naca4((0,0,1,2)), 2),
                chords    = [0.7, 0.42],
                twists    = [0.0, 0.0],
                spans     = [1.25],
                dihedrals = [0.],
                sweeps    = [6.39],
                position  = [4., 0., 0.],
                angle     = 0.,
                axis      = [0., 1., 0.]
            )

# Vertical tail
@time vtail_u = HalfWing(
                    foils     = fill(naca4((0,0,0,9)), 2),
                    chords    = [0.7, 0.25],
                    twists    = [0.0, 0.0],
                    spans     = [1.0],
                    dihedrals = [0.],
                    sweeps    = [7.97],
                    position  = [4.7, 0, 0],
                    angle     = 90.,
                    axis      = [1., 0., 0.]
                );

@time vtail_d = HalfWing(
                    foils     = fill(naca4((0,0,0,9)), 2),
                    chords    = [0.7, 0.42],
                    twists    = [0.0, 0.0],
                    spans     = [0.4],
                    dihedrals = [0.],
                    sweeps    = [7.97],
                    position  = [4.7, 0, 0],
                    angle     = 90.,
                    axis      = [1., 0., 0.]
                );

@time vtail = Wing(vtail_d, vtail_u)

# Tailerons
@time atail_l = Wing(
                    foils     = fill(naca4((0,0,0,9)), 2),
                    chords    = [0.4, 0.2],
                    twists    = [0.0, 0.0],
                    spans     = [0.5],
                    dihedrals = [0.],
                    sweeps    = [8.],
                    position  = [2., 2.5, 0.],
                    angle     = 0.,
                    axis      = [0., 1., 0.]
                );

@time atail_r = Wing(
                    foils     = fill(naca4((0,0,0,9)), 2),
                    chords    = [0.4, 0.2],
                    twists    = [0.0, 0.0],
                    spans     = [0.5],
                    dihedrals = [0.],
                    sweeps    = [8.],
                    position  = [2., -2.5, 0.],
                    angle     = 0.,
                    axis      = [0., 1., 0.]
                );

## Meshing
@time wing_mesh    = WingMesh(wing, [6,6], 6);
@time htail_mesh   = WingMesh(htail, [6], 4);
@time vtail_mesh   = WingMesh(vtail, [6], 4);
@time atail_l_mesh = WingMesh(atail_l, [4], 2);
@time atail_r_mesh = WingMesh(atail_r, [4], 2);

## Aircraft assembly
@time aircraft = ComponentArray(
                          wing    = make_horseshoes(wing_mesh),
                          htail   = make_horseshoes(htail_mesh),
                          vtail   = make_horseshoes(vtail_mesh),
                          atail_l = make_horseshoes(atail_l_mesh),
                          atail_r = make_horseshoes(atail_r_mesh),
                         );

## Aerodynamic analsis
#==========================================================================================#

# Reference values
ac_name  = "Lawn Polar"
wing_mac = mean_aerodynamic_center(wing);
S, b, c  = projected_area(wing), span(wing), mean_aerodynamic_chord(wing);
ρ        = 0.98
ref      = [wing_mac[1], 0., 0.]
V, α, β  = 25.0, 0.0, 0.0
Ω        = zeros(3)
@time fs       = Freestream(α, β, Ω);
@time refs     = References(speed = V, area = S, span = b, chord = c, density = ρ, location = ref);

## Solve aerodynamic case for initial vector
@time system = solve_case(aircraft, fs, refs;
                        #   print_components = true,
                         );

## Data collection
@time CFs, CMs = surface_coefficients(system);

##
@time Fs = surface_forces(system);

##
