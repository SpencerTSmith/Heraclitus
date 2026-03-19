package main

import "core:log"
import "base:runtime"

import gl "vendor:OpenGL"

MAX_IMMEDIATE_VERTEX_COUNT :: 4096 * 32

Immediate_Vertex :: struct
{
  position: vec3,
  uv:       vec2,
  color:    vec4,
}

// NOTE: When an immediate_* function takes in a vec2 for position it means its in screen coords
// When taking in a vec3 for position its in world space

Immediate_Primitive :: enum
{
  TRIANGLES,
  LINES,
}

Immediate_Space :: enum
{
  SCREEN,
  WORLD,
}

// NOTE: This is not integrated with the general asset system and deals with actual textures and such...
// TODO: Finish up render pass system and integrate with batching system...
// batches would probably include a renderpass, the immediate space, and the primitive
Immediate_State :: struct
{
  vertex_buffer: GPU_Buffer,
  vertex_count:  int, // ALL vertices for current frame

  shader:        Shader_Program,
  white_texture: Texture_Handle,

  batches:    [256]Immediate_Batch,
  curr_batch: int,
}

// Just a view into the main vertex buffer
// TODO: Maybe each batch should store vertices itself so that we can check if there is a batch
// that matches state but is not the current batch?
Immediate_Batch :: struct
{
  vertex_base:  int, // First vertex in batch
  vertex_count: int, // How many vertices in batch

  primitive: Immediate_Primitive,
  texture:   Texture_Handle,
  space:     Immediate_Space,
  depth:     Depth_Test_Mode,
}

// Internal state
@(private="file")
immediate: Immediate_State

init_immediate_renderer :: proc(allocator: runtime.Allocator) -> (ok: bool)
{
  assert(state.gl_initialized)

  immediate.vertex_buffer = make_vertex_buffer(Immediate_Vertex, MAX_IMMEDIATE_VERTEX_COUNT,
                                               flags = {.PERSISTENT, .FRAME_BUFFERED})
  bind_gpu_buffer_base(immediate.vertex_buffer, .IMM_VERTICES)

  immediate.shader, ok = make_shader_program("immediate.vert", "immediate.frag", state.perm_alloc)

  immediate.white_texture = load_texture("white.png")

  return ok
}

immediate_frame_reset :: proc()
{
  immediate.vertex_count = 0
  immediate.curr_batch = 0
}

// Starts a new batch if necessary
immediate_begin :: proc(wish_primitive: Immediate_Primitive, wish_texture: Texture_Handle, wish_space: Immediate_Space, wish_depth: Depth_Test_Mode)
{
  current := immediate.batches[immediate.curr_batch]
  if  current.primitive != wish_primitive ||
      current.space     != wish_space     ||
      current.texture   != wish_texture   ||
      current.depth     != wish_depth
  {
    if immediate.curr_batch + 1 < len(immediate.batches)
    {
      immediate.curr_batch += 1
      immediate.batches[immediate.curr_batch] =
      {
        vertex_base = immediate.vertex_count,
        primitive   = wish_primitive,
        texture     = wish_texture,
        space       = wish_space,
        depth       = wish_depth,
      }
    }
    else
    {
      log.errorf("Too many immediate draw batches.")
    }
  }
}

// NOTE: Does not check batch info. Trusts the caller to make sure that all batch info is right
immediate_vertex :: proc(position: vec3, color: vec4 = WHITE, uv: vec2 = {0.0, 0.0})
{
  if immediate.vertex_count + 1 < MAX_IMMEDIATE_VERTEX_COUNT
  {
    vertex: Immediate_Vertex =
    {
      position = position,
      uv       = uv,
      color    = color,
    }

    vertex_ptr := cast([^]Immediate_Vertex)gpu_buffer_frame_base_ptr(immediate.vertex_buffer)

    current := &immediate.batches[immediate.curr_batch]

    // Write into the current batch.
    offset := current.vertex_base + current.vertex_count

    // To the gpu buffer!
    vertex_ptr[offset] = vertex
    immediate.vertex_count += 1

    // And remember to add to the current batches count.
    current.vertex_count += 1
  }
  else
  {
    // log.errorf("Too many immediate vertices", immediate.vertex_count)
  }
}

// NOTE: Can control if flushing world space immediates, screen space immediates, or both
// This is used to draw any world space immediates in the main pass, allowing them to recive MSAA and to sample
// the main scene's depth buffer if they wish
// TODO: Maybe consider just having two different immediate systems, one for things that should be flushed in the main pass
// And others that ought to be flushed in the overlay/ui pass
immediate_flush :: proc(flush_world := false, flush_screen := false)
{
  assert(state.began_drawing, "Tried to flush immediate vertex info before we have begun drawing this frame.")

  if immediate.vertex_count > 0
  {
    bind_shader_program(immediate.shader)

    bind_vertex_buffer(immediate.vertex_buffer)
    defer unbind_vertex_buffer()

    // Transforms
    orthographic := camera_orthographic(state.camera, state.window.w, state.window.h)
    perspective  := camera_perspective(state.camera, window_aspect_ratio(state.window)) * camera_view(state.camera)

    gl.Disable(gl.CULL_FACE)

    frame_base := gpu_buffer_frame_offset(immediate.vertex_buffer) / size_of(Immediate_Vertex)
    for batch in immediate.batches[:immediate.curr_batch + 1]
    {
      if batch.vertex_count > 0
      {
        // TODO: Again make this a more generalizable thing probably
        depth_func_before: i32; gl.GetIntegerv(gl.DEPTH_FUNC, &depth_func_before)
        defer gl.DepthFunc(u32(depth_func_before))

        gl_depth_map: [Depth_Test_Mode]u32 =
        {
          .DISABLED   = gl.ALWAYS,
          .ALWAYS     = gl.ALWAYS,
          .LESS       = gl.LESS,
          .LESS_EQUAL = gl.LEQUAL,
        }

        gl.DepthFunc(gl_depth_map[batch.depth])

        switch batch.space
        {
        case .SCREEN:
          if !flush_screen { continue } // We shouldn't flush screen immediates

          set_shader_uniform("transform", orthographic)
        case .WORLD:
          if !flush_world { continue } // We shouldn't flush world immediates

          set_shader_uniform("transform", perspective)
        }

        bind_texture("tex", get_texture(batch.texture)^)

        first_vertex := i32(frame_base + batch.vertex_base)
        vertex_count := i32(batch.vertex_count)

        gl_primitive_map: [Immediate_Primitive]u32 =
        {
          .TRIANGLES = gl.TRIANGLES,
          .LINES     = gl.LINES,
        }

        gl.DrawArrays(gl_primitive_map[batch.primitive], first_vertex, vertex_count)
      }
    }
  }
}

free_immediate_renderer :: proc()
{
  free_gpu_buffer(&immediate.vertex_buffer)
  free_shader_program(&immediate.shader)
}

draw_quad :: proc {
  draw_quad_screen,
  draw_quad_world,
}

draw_quad_screen :: proc(top_left_position: vec2, w, h: f32, color: vec4 = WHITE,
                         top_left_uv: vec2 = {0.0, 1.0}, bottom_right_uv: vec2 = {1.0, 0.0},
                         texture: Texture_Handle = immediate.white_texture)
{
  immediate_begin(.TRIANGLES, texture, .SCREEN, .ALWAYS)

  top_left: Immediate_Vertex =
  {
    position = {top_left_position.x, top_left_position.y, -state.camera.z_near},
    uv       = top_left_uv,
    color    = color,
  }
  top_right: Immediate_Vertex =
  {
    position = {top_left_position.x + w, top_left_position.y, -state.camera.z_near},
    uv       = {bottom_right_uv.x, top_left_uv.y},
    color    = color,
  }
  bottom_left: Immediate_Vertex =
  {
    position = {top_left_position.x, top_left_position.y + h, -state.camera.z_near},
    uv       = {top_left_uv.x, bottom_right_uv.y},
    color    = color,
  }
  bottom_right: Immediate_Vertex =
  {
    position = {top_left_position.x + w, top_left_position.y + h, -state.camera.z_near},
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
                        texture: Texture_Handle = immediate.white_texture, depth_test: Depth_Test_Mode = .LESS)
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
  immediate_begin(.LINES, immediate.white_texture, .SCREEN, .ALWAYS)

  immediate_vertex({xy0.x, xy0.y, -state.camera.z_near}, color=rgba)
  immediate_vertex({xy1.x, xy1.y, -state.camera.z_near}, color=rgba)
}

// NOTE: 3d line
draw_line_world :: proc(xyz0, xyz1: vec3, color := WHITE,
                        depth_test: Depth_Test_Mode = .LESS)
{
  immediate_begin(.LINES, immediate.white_texture, .WORLD, depth_test)

  immediate_vertex(xyz0, color=color)
  immediate_vertex(xyz1, color=color)
}

draw_fill_box :: proc(xyz_min, xyz_max: vec3, color := WHITE,
                      depth_test: Depth_Test_Mode = .LESS)
{
  corners := box_corners(xyz_min, xyz_max)

  wish_primitive := Immediate_Primitive.TRIANGLES
  wish_space     := Immediate_Space.WORLD
  wish_texture   := immediate.white_texture

  immediate_begin(wish_primitive, wish_texture, wish_space, depth_test)

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
  immediate_begin(.LINES, immediate.white_texture, .WORLD, depth_test)

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
  immediate_begin(.TRIANGLES, immediate.white_texture, .WORLD, depth_test)

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
  immediate_begin(.LINES, immediate.white_texture, .WORLD, depth_test)

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
