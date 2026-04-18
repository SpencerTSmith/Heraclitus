package main

draw_quad :: proc {
  draw_quad_screen,
  draw_quad_world,
}

draw_quad_screen :: proc(top_left_position: vec2, w, h: f32, color: vec4 = WHITE,
                         top_left_uv: vec2 = {0.0, 1.0}, bottom_right_uv: vec2 = {1.0, 0.0},
                         texture: Texture_Handle = WHITE_TEXTURE)
{
  immediate_begin(.TRIANGLES, texture, .SCREEN, .ALWAYS)

  top_left: Immediate_Vertex =
  {
    position = {top_left_position.x, top_left_position.y, 0},
    uv       = top_left_uv,
    color    = color,
  }
  top_right: Immediate_Vertex =
  {
    position = {top_left_position.x + w, top_left_position.y, 0},
    uv       = {bottom_right_uv.x, top_left_uv.y},
    color    = color,
  }
  bottom_left: Immediate_Vertex =
  {
    position = {top_left_position.x, top_left_position.y + h, 0},
    uv       = {top_left_uv.x, bottom_right_uv.y},
    color    = color,
  }
  bottom_right: Immediate_Vertex =
  {
    position = {top_left_position.x + w, top_left_position.y + h, 0},
    uv       = bottom_right_uv,
    color    = color,
  }

  immediate_vertex(top_left.position, top_left.color, top_left.uv)
  immediate_vertex(top_right.position, top_right.color, top_right.uv)
  immediate_vertex(bottom_left.position, bottom_left.color, bottom_left.uv)

  immediate_vertex(top_right.position, top_right.color, top_right.uv)
  immediate_vertex(bottom_right.position, bottom_right.color, bottom_right.uv)
  immediate_vertex(bottom_left.position, bottom_left.color, bottom_left.uv)
}

draw_quad_world :: proc(center, normal: vec3, w, h: f32, color := WHITE,
                        uv0: vec2 = {0.0, 1.0}, uv1: vec2 = {1.0, 0.0},
                        texture: Texture_Handle = WHITE_TEXTURE, depth_test: Depth_Test_Mode = .LESS)
{
  immediate_begin(.TRIANGLES, texture, .WORLD, depth_test)

  norm := normalize(normal) // Just in case
  right, up := orthonormal_axes(norm)

  half_w := w / 2
  half_h := h / 2

  top_left: Immediate_Vertex =
  {
    position = center - (right * half_w) + (up * half_h),
    uv       = uv0,
    color    = color,
  }
  top_right: Immediate_Vertex =
  {
    position = center + (right * half_w) + (up * half_h),
    uv       = {uv1.x, uv0.y},
    color    = color,
  }
  bottom_left: Immediate_Vertex =
  {
    position = center - (right * half_w) - (up * half_h),
    uv       = {uv0.x, uv1.y},
    color    = color,
  }
  bottom_right: Immediate_Vertex =
  {
    position = center + (right * half_w) - (up * half_h),
    uv       = uv1,
    color    = color,
  }

  immediate_vertex(top_left.position, top_left.color, top_left.uv)
  immediate_vertex(top_right.position, top_right.color, top_right.uv)
  immediate_vertex(bottom_left.position, bottom_left.color, bottom_left.uv)

  immediate_vertex(bottom_left.position, bottom_left.color, bottom_left.uv)
  immediate_vertex(top_right.position, top_right.color, top_right.uv)
  immediate_vertex(bottom_right.position, bottom_right.color, bottom_right.uv)
}

// TODO: These should not be immediate... should be draw_line
draw_line :: proc
{
  draw_line_screen,
  draw_line_world,
}

// NOTE: A 2d line so takes in screen coordinates!
draw_line_screen :: proc(xy0, xy1: vec2, rgba := WHITE)
{
  immediate_begin(.LINES, WHITE_TEXTURE, .SCREEN, .ALWAYS)

  immediate_vertex({xy0.x, xy0.y, 0}, color=rgba)
  immediate_vertex({xy1.x, xy1.y, 0}, color=rgba)
}

// NOTE: 3d line
draw_line_world :: proc(xyz0, xyz1: vec3, color := WHITE,
                        depth_test: Depth_Test_Mode = .LESS)
{
  immediate_begin(.LINES, WHITE_TEXTURE, .WORLD, depth_test)

  immediate_vertex(xyz0, color=color)
  immediate_vertex(xyz1, color=color)
}

draw_fill_box :: proc(xyz_min, xyz_max: vec3, color := WHITE,
                      depth_test: Depth_Test_Mode = .LESS)
{
  corners := box_corners(xyz_min, xyz_max)

  immediate_begin(.TRIANGLES, WHITE_TEXTURE, .WORLD, depth_test)

  immediate_vertex(corners[0], color)
  immediate_vertex(corners[1], color)
  immediate_vertex(corners[2], color)

  immediate_vertex(corners[3], color)
  immediate_vertex(corners[2], color)
  immediate_vertex(corners[0], color)

  immediate_vertex(corners[0], color)
  immediate_vertex(corners[3], color)
  immediate_vertex(corners[4], color)

  immediate_vertex(corners[5], color)
  immediate_vertex(corners[0], color)
  immediate_vertex(corners[4], color)

  immediate_vertex(corners[3], color)
  immediate_vertex(corners[2], color)
  immediate_vertex(corners[7], color)

  immediate_vertex(corners[4], color)
  immediate_vertex(corners[3], color)
  immediate_vertex(corners[7], color)

  immediate_vertex(corners[0], color)
  immediate_vertex(corners[5], color)
  immediate_vertex(corners[6], color)

  immediate_vertex(corners[1], color)
  immediate_vertex(corners[0], color)
  immediate_vertex(corners[6], color)

  immediate_vertex(corners[1], color)
  immediate_vertex(corners[6], color)
  immediate_vertex(corners[7], color)

  immediate_vertex(corners[2], color)
  immediate_vertex(corners[1], color)
  immediate_vertex(corners[7], color)

  immediate_vertex(corners[5], color)
  immediate_vertex(corners[4], color)
  immediate_vertex(corners[7], color)

  immediate_vertex(corners[6], color)
  immediate_vertex(corners[5], color)
  immediate_vertex(corners[7], color)
}

draw_box :: proc(corners: [8]vec3, color := WHITE,
                 depth_test: Depth_Test_Mode = .LESS)
{
  immediate_begin(.LINES, WHITE_TEXTURE, .WORLD, depth_test)

  // Back
  draw_line(corners[0], corners[1], color)
  draw_line(corners[1], corners[2], color)
  draw_line(corners[2], corners[3], color)
  draw_line(corners[3], corners[0], color)

  // Front
  draw_line(corners[4], corners[5], color)
  draw_line(corners[5], corners[6], color)
  draw_line(corners[6], corners[7], color)
  draw_line(corners[7], corners[4], color)

  // Left
  draw_line(corners[4], corners[3], color)
  draw_line(corners[5], corners[0], color)

  // Right
  draw_line(corners[7], corners[2], color)
  draw_line(corners[6], corners[1], color)
}

draw_pyramid :: proc(tip, base0, base1, base2, base3: vec3, color := WHITE,
                     depth_test: Depth_Test_Mode = .LESS)
{
  immediate_begin(.TRIANGLES, WHITE_TEXTURE, .WORLD, depth_test)

  // Triangle sides
  immediate_vertex(tip, color)
  immediate_vertex(base0, color)
  immediate_vertex(base1, color)

  immediate_vertex(tip, color)
  immediate_vertex(base1, color)
  immediate_vertex(base2, color)

  immediate_vertex(tip, color)
  immediate_vertex(base2, color)
  immediate_vertex(base3, color)

  immediate_vertex(tip, color)
  immediate_vertex(base3, color)
  immediate_vertex(base0, color)

  // Base
  immediate_vertex(base0, color)
  immediate_vertex(base3, color)
  immediate_vertex(base1, color)

  immediate_vertex(base2, color)
  immediate_vertex(base0, color)
  immediate_vertex(base3, color)
}

draw_sphere :: proc(center: vec3, radius: f32, color := WHITE,
                    latitude_rings := 16,
                    longitude_rings := 16,
                    depth_test: Depth_Test_Mode = .LESS)
{
  immediate_begin(.LINES, WHITE_TEXTURE, .WORLD, depth_test)

  point :: proc(theta, phi, radius: f32, center: vec3) -> vec3
  {
    // Just a rotation matrix basically based on theta and phi, then translating by the center
    return {(cos(phi) * sin(theta) * radius) + center.x,
            (cos(theta) * radius) + center.y,
            (sin(phi) * sin(theta) * radius) + center.z}
  }

  // Draw the horizontal rings
  for r in 1..<latitude_rings
  {
    // Which ring are we on, as an angle
    theta := f32(r) / f32(latitude_rings) * PI

    // The individual line segemnts that make up the ring
    for s in 0..=longitude_rings
    {
      phi_a := f32(s) / f32(longitude_rings) * PI * 2.0
      phi_b := f32(s + 1) / f32(longitude_rings) * PI * 2.0

      draw_line(point(theta, phi_a, radius, center), point(theta, phi_b, radius, center), color)
    }
  }

  // Same for the vertical rings
  for s in 0..<longitude_rings
  {
    // Which ring are we on, as an angle
    phi := f32(s) / f32(longitude_rings) * PI * 2.0

    // The individual line segemnts that make up the ring
    for r in 0..=latitude_rings
    {
      theta_a := f32(r) / f32(latitude_rings) * PI
      theta_b := f32(r + 1) / f32(latitude_rings) * PI

      draw_line(point(theta_a, phi, radius, center), point(theta_b, phi, radius, center), color)
    }
  }
}

draw_torus :: proc(center: vec3)
{

}

draw_grid :: proc(spacing := 100, range := 500, color: vec4 = WHITE)
{
  range_cast := f32(range)

  // Red cube at the origin
  draw_fill_box({-0.1,-0.1,-0.1}, {0.1,0.1,0.1}, RED)

  for z := -range; z <= range; z += spacing
  {
    z_cast := f32(z)
    for x := -range; x <= range; x += spacing
    {
      x_cast := f32(x)
      draw_line(vec3{x_cast, -range_cast, z_cast}, vec3{x_cast, range_cast, z_cast}, color)
    }

    for y := -range; y <= range; y += spacing
    {
      y_cast := f32(y)
      draw_line(vec3{-range_cast, y_cast, z_cast}, vec3{range_cast, y_cast, z_cast}, color)
    }
  }

  for y := -range; y <= range; y += spacing
  {
    y_cast := f32(y)
    for x := -range; x <= range; x += spacing
    {
      x_cast := f32(x)
      draw_line(vec3{x_cast, y_cast, -range_cast}, vec3{x_cast, y_cast, range_cast}, color)
    }

    for z := -range; z <= range; z += spacing
    {
      z_cast := f32(z)
      draw_line(vec3{-range_cast, y_cast, z_cast}, vec3{range_cast, y_cast, z_cast}, color)
    }
  }
}

// TODO: Rewrite immediate line to take in a radius for line, will probably no longer have to have immediate line primitive... just a  line is ugly
draw_vector ::proc(origin, direction: vec3, color: vec4 = WHITE, thickness: f32 = 0.025,
                   depth_test: Depth_Test_Mode = .LESS)
{
  end := origin + direction
  draw_line(origin, end, color, depth_test=depth_test)

  // Need the space relative to the direction of the vector
  // To draw the pyramid tip
  forward := normalize(direction)
  right, up := orthonormal_axes(forward)

  tip   := end

  base0 := end + right * thickness
  base0 += up * thickness
  base0 -= forward * thickness * 4

  base1 := end + right * thickness
  base1 -= up * thickness
  base1 -= forward * thickness * 4

  base2 := end - right * thickness
  base2 += up * thickness
  base2 -= forward * thickness * 4

  base3 := end - right * thickness
  base3 -= up * thickness
  base3 -= forward * thickness * 4

  draw_pyramid(tip, base0, base1, base2, base3, color, depth_test=depth_test)
}

draw_aabb :: proc(aabb: AABB, color: vec4 = GREEN)
{
  corners := box_corners(aabb.min, aabb.max)
  draw_box(corners, color)
}
