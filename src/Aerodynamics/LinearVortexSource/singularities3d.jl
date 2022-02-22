"""
    d_ij(i :: Int64, j :: Int64, local_coordinates)

Compute the distance from i-th to j-th point of the panel.
"""
d_ij(i :: Int64, j :: Int64, local_coordinates) = norm(local_coordinates[j] - local_coordinates[i])


"""
    m_ij(i :: Int64, j :: Int64, local_coordinates)

Compute the slope of the line segment consisting i-th and j-th point of the panel.
"""
function m_ij(i :: Int64, j :: Int64, local_coordinates)
    x, y = local_coordinates[j] - local_coordinates[i]
    return y/x
end


"""
    r_k(k :: Int64, local_coordinates, local_point)

Compute the distance from i-th point of the panel to the arbitary point.
"""
r_k(k :: Int64, local_coordinates, local_point) = norm(local_point - local_coordinates[k])


"""
    k :: Int64, local_coordinates, local_point

Compute (x - xk)^2 + z^2.
"""
e_k(k :: Int64, local_coordinates, local_point) = norm([local_point.x - local_coordinates[k].x, local_point.z])


"""
    k :: Int64, local_coordinates, local_point

Compute (x - xk) * (y - yk).
"""
h_k(k :: Int64, local_coordinates, local_point) = (local_point.x - local_coordinates[k].x) * (local_point.y - local_coordinates[k].y)


"""
    constant_quadrilateral_source_velocity(σ, local_panel :: AbstractPanel, local_point)

    Compute the panel velocity (û,v̂,ŵ) in local panel (x̂,ŷ,ẑ) direction of a constant quadrilateral source
"""
function constant_quadrilateral_source_velocity(σ, local_panel :: AbstractPanel3D, local_point)
    # A panel of type `Panel3D` has 4 points of type `SVector{3, Any}` whose coordinates are in the format of
    # [
    #     [x1 y1 0]
    #     [x2 y2 0]
    #     [x3 y3 0]
    #     [x4 y4 0]
    # ]
    local_coordinates = panel_coordinates(local_panel)

    # Check whether the panel is expressed in local coordinates. All z-coordinates must be zeros.
    local_zs = zs(local_panel)
    if norm(local_zs) >= 1e-10
        AssertionError("Panel is not in its local coordinate!")
    end

    x1, x2, x3, x4 = xs(local_panel)
    y1, y2, y3, y4 = ys(local_panel)

    z = local_point[3]

    r1 = r_k(1, local_coordinates, local_point)
    r2 = r_k(2, local_coordinates, local_point)
    r3 = r_k(3, local_coordinates, local_point)
    r4 = r_k(4, local_coordinates, local_point)

    d12 = d_ij(1, 2, local_coordinates)
    d23 = d_ij(2, 3, local_coordinates)
    d34 = d_ij(3, 4, local_coordinates)
    d41 = d_ij(4, 1, local_coordinates)

    m12 = m_ij(1, 2, local_coordinates)
    m23 = m_ij(2, 3, local_coordinates)
    m34 = m_ij(3, 4, local_coordinates)
    m41 = m_ij(4, 1, local_coordinates)

    e1 = e_k(1, local_coordinates, local_point)
    e2 = e_k(2, local_coordinates, local_point)
    e3 = e_k(3, local_coordinates, local_point)
    e4 = e_k(4, local_coordinates, local_point)

    h1 = h_k(1, local_coordinates, local_point)
    h2 = h_k(2, local_coordinates, local_point)
    h3 = h_k(3, local_coordinates, local_point)
    h4 = h_k(4, local_coordinates, local_point)

    # Results from textbook differs from a minus sign
    u = -σ / 4π * (
        (y2 -y1) / d12 * log( (r1 + r2 - d12) / (r1 + r2 + d12) ) +
        (y3 -y2) / d23 * log( (r2 + r3 - d23) / (r2 + r3 + d23) ) +
        (y4 -y3) / d34 * log( (r3 + r4 - d34) / (r3 + r4 + d34) ) +
        (y1 -y4) / d41 * log( (r4 + r1 - d41) / (r4 + r1 + d41) )
    )

    v = -σ / 4π * (
        (x1 -x2) / d12 * log( (r1 + r2 - d12) / (r1 + r2 + d12) ) +
        (x2 -x3) / d23 * log( (r2 + r3 - d23) / (r2 + r3 + d23) ) +
        (x3 -x4) / d34 * log( (r3 + r4 - d34) / (r3 + r4 + d34) ) +
        (x4 -x1) / d41 * log( (r4 + r1 - d41) / (r4 + r1 + d41) )
    )

    w = -σ / 4π * (
        atan( (m12 * e1 - h1) / (z * r1) ) - atan( (m12 * e2 - h2) / (z * r2) ) +
        atan( (m23 * e2 - h2) / (z * r2) ) - atan( (m23 * e3 - h3) / (z * r3) ) +
        atan( (m34 * e3 - h3) / (z * r3) ) - atan( (m34 * e4 - h4) / (z * r4) ) +
        atan( (m41 * e4 - h4) / (z * r4) ) - atan( (m41 * e1 - h1) / (z * r1) )
    )

    @. return SVector(u, v, w)
end


"""
    quadrilateral_panel_area(panel :: AbstractPanel3D)

Compute the area of a quadrilateral panel
"""
function quadrilateral_panel_area(panel :: AbstractPanel3D)
    coord = panel_coordinates(panel)

    d12 = d_ij(1, 2, coord)
    d23 = d_ij(2, 3, coord)
    d34 = d_ij(3, 4, coord)
    d41 = d_ij(4, 1, coord)
    d13 = d_ij(1, 3, coord)

    s1 = 0.5 * (d12 + d23 + d13)
    s2 = 0.5 * (d34 + d41 + d13)

    A1 = sqrt(s1 * (s1 - d12) * (s1 - d23) * (s1 - d13))
    A2 = sqrt(s2 * (s2 - d34) * (s2 - d41) * (s2 - d13))

    return A1 + A2
end


"""
    constant_quadrilateral_source_velocity_farfield(σ, local_panel :: AbstractPanel, local_point)

Compute the panel velocity (û,v̂,ŵ) in local panel (x̂,ŷ,ẑ) direction of a constant quadrilateral source at FARFIELD
"""
function constant_quadrilateral_source_velocity_farfield(σ, local_panel :: AbstractPanel3D, local_point)
    A = quadrilateral_panel_area(local_panel)
    center_point = midpoint(local_panel) # It is better to use centroid

    u = ( σ * A * (local_point.x - center_point.x) ) / ( 4π * norm(local_point - center_point)^3 )
    v = ( σ * A * (local_point.y - center_point.y) ) / ( 4π * norm(local_point - center_point)^3 )
    w = ( σ * A * (local_point.z - center_point.z) ) / ( 4π * norm(local_point - center_point)^3 )

    @. return SVector(u, v, w)
end