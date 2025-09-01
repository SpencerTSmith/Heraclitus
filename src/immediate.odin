package main

import "core:log"

import gl "vendor:OpenGL"

MAX_IMMEDIATE_VERTEX_COUNT :: 4096 * 4

Immediate_Vertex :: struct {
  position: vec3,
  uv:       vec2,
  color:    vec4,
}

// NOTE: When an immediate_* function takes in a vec2 for position it means its in screen coords
// When taking in a vec3 for position its in world space

Immediate_Primitive :: enum {
  TRIANGLES,
  LINES,
  LINE_STRIPS,
}

Immediate_Space :: enum {
  SCREEN,
  WORLD,
}

// NOTE: This is not integrated with the general asset system and deals with actual textures and such...
// FIXME: We use a pointer and not an index into the batch list for the
// current batch
// TODO: Finish up render pass system and integrate with batching system...
// batches would probably include a renderpass, the immediate space, and the primitive
Immediate_State :: struct {
  vertex_buffer: GPU_Buffer,
  vertex_count:  int, // ALL vertices for current frame

  shader:        Shader_Program,
  white_texture: Texture,

  curr_batch: ^Immediate_Batch, // Eh, pointer could maybe do index instead?
  batches:    [dynamic]Immediate_Batch,
}

// Just a view into the main vertex buffer
// TODO: Maybe each batch should store vertices itself so that we can check if there is a batch
// that matches state but is not the current batch?
Immediate_Batch :: struct {
  vertex_base:  int, // First vertex in batch
  vertex_count: int, // How many vertices in batch

  primitive: Immediate_Primitive,
  texture:   Texture,
  space:     Immediate_Space,
  depth:     Depth_Test_Mode,
}

// Internal state
@(private="file")
immediate: Immediate_State

init_immediate_renderer :: proc(allocator := context.allocator) -> (ok: bool) {
  assert(state.gl_initialized)

  vertex_buffer := make_vertex_buffer(Immediate_Vertex, MAX_IMMEDIATE_VERTEX_COUNT, persistent = true)

  shader := make_shader_program("immediate.vert", "immediate.frag", state.perm_alloc) or_return

  immediate = {
    vertex_buffer = vertex_buffer,
    vertex_count  = 0,
    shader  = shader,
    batches = make([dynamic]Immediate_Batch, allocator),
  }
  MAX_BATCH_COUNT :: 256
  reserve(&immediate.batches, MAX_BATCH_COUNT)

  immediate.white_texture = get_texture_by_name("white.png")^

  return true
}

immediate_frame_reset :: proc() {
  immediate.vertex_count = 0
  clear(&immediate.batches)
  immediate.curr_batch = nil
}

// Returns the pointer to the new batch in the batches dynamic array.
@(private="file")
start_new_batch :: proc(mode: Immediate_Primitive, texture: Texture,
                        space: Immediate_Space,
                        depth: Depth_Test_Mode,
                        ) -> (batch_pointer: ^Immediate_Batch) {
  append(&immediate.batches, Immediate_Batch{
    vertex_base = immediate.vertex_count, // Always on the end.

    primitive = mode,
    texture = texture,
    space = space,
    depth = depth,
  })

  return &immediate.batches[len(immediate.batches) - 1]
}

// Starts a new batch if necessary
immediate_begin :: proc(wish_primitive: Immediate_Primitive, wish_texture: Texture, wish_space: Immediate_Space, wish_depth: Depth_Test_Mode = .LESS) {
  if immediate.curr_batch == nil || // Should short circuit and not do any nil dereferences
     immediate.curr_batch.primitive != wish_primitive ||
     immediate.curr_batch.space     != wish_space     ||
     immediate.curr_batch.texture   != wish_texture   ||
     immediate.curr_batch.depth     != wish_depth {
    immediate.curr_batch = start_new_batch(wish_primitive, wish_texture, wish_space, wish_depth)
  }
}

// Forces the creation of a new batch
immediate_begin_force :: proc() {
  immediate.curr_batch = start_new_batch(immediate.curr_batch.primitive, immediate.curr_batch.texture, immediate.curr_batch.space, immediate.curr_batch.depth)
}

free_immediate_renderer :: proc() {
  free_gpu_buffer(&immediate.vertex_buffer)
  free_shader_program(&immediate.shader)
  delete(immediate.batches)
}

// NOTE: Does not check batch info. Trusts the caller to make sure that all batch info is right
immediate_vertex :: proc(position: vec3, color: vec4 = WHITE, uv: vec2 = {0.0, 0.0}) {
  assert(state.gl_initialized)
  assert(gpu_buffer_is_mapped(immediate.vertex_buffer), "Uninitialized Immediate State")

  if immediate.vertex_count + 1 >= MAX_IMMEDIATE_VERTEX_COUNT {
    log.errorf("Too many (%v) immediate vertices!!!!!!\n", immediate.vertex_count)
    return
  }

  vertex := Immediate_Vertex{
    position = position,
    uv       = uv,
    color    = color,
  }

  vertex_ptr := cast([^]Immediate_Vertex)gpu_buffer_frame_base_ptr(immediate.vertex_buffer)

  // Write into the current batch.
  offset := immediate.curr_batch.vertex_base + immediate.curr_batch.vertex_count

  // To the gpu buffer!
  vertex_ptr[offset] = vertex
  immediate.vertex_count += 1

  // And remember to add to the current batches count.
  immediate.curr_batch.vertex_count += 1
}

immediate_quad :: proc {
  immediate_quad_2D,
  immediate_quad_3D,
}

immediate_quad_2D :: proc(top_left_position: vec2, w, h: f32, color: vec4 = WHITE,
                          top_left_uv: vec2 = {0.0, 1.0}, bottom_right_uv: vec2 = {1.0, 0.0},
                          texture:    Texture = immediate.white_texture,
                          depth_test: Depth_Test_Mode = .ALWAYS) {
  wish_primitive := Immediate_Primitive.TRIANGLES
  wish_space     := Immediate_Space.SCREEN

  immediate_begin(wish_primitive, texture, wish_space, depth_test)

  top_left := Immediate_Vertex{
    position = {top_left_position.x, top_left_position.y, -state.z_near},
    uv       = top_left_uv,
    color    = color,
  }
  top_right := Immediate_Vertex{
    position = {top_left_position.x + w, top_left_position.y, -state.z_near},
    uv       = {bottom_right_uv.x, top_left_uv.y},
    color    = color,
  }
  bottom_left := Immediate_Vertex{
    position = {top_left_position.x, top_left_position.y + h, -state.z_near},
    uv       = {top_left_uv.x, bottom_right_uv.y},
    color    = color,
  }
  bottom_right := Immediate_Vertex{
    position = {top_left_position.x + w, top_left_position.y + h, -state.z_near},
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

immediate_quad_3D :: proc(center, normal: vec3, w, h: f32, color := WHITE,
                          uv0: vec2 = {0.0, 1.0}, uv1: vec2 = {1.0, 0.0},
                          texture:    Texture = immediate.white_texture,
                          depth_test: Depth_Test_Mode = .LESS) {
  wish_primitive := Immediate_Primitive.TRIANGLES
  wish_space     := Immediate_Space.WORLD

  immediate_begin(wish_primitive, texture, wish_space, depth_test)

  norm := normalize(normal) // Just in case
  right, up := orthonormal_axes(norm)

  half_w := w / 2
  half_h := h / 2

  top_left := Immediate_Vertex{
    position = center - (right * half_w) + (up * half_h),
    uv       = uv0,
    color    = color,
  }
  top_right := Immediate_Vertex{
    position = center + (right * half_w) + (up * half_h),
    uv       = {uv1.x, uv0.y},
    color    = color,
  }
  bottom_left := Immediate_Vertex{
    position = center - (right * half_w) - (up * half_h),
    uv       = {uv0.x, uv1.y},
    color    = color,
  }
  bottom_right := Immediate_Vertex{
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

immediate_line :: proc {
  immediate_line_2D,
  immediate_line_3D,
}

// NOTE: A 2d line so takes in screen coordinates!
immediate_line_2D :: proc(xy0, xy1: vec2, rgba := WHITE,
                          depth_test: Depth_Test_Mode = .ALWAYS) {
  wish_primitive := Immediate_Primitive.LINES
  wish_space     := Immediate_Space.SCREEN
  wish_texture   := immediate.white_texture

  immediate_begin(wish_primitive, wish_texture, wish_space, depth_test)

  immediate_vertex({xy0.x, xy0.y, -state.z_near}, color=rgba)
  immediate_vertex({xy1.x, xy1.y, -state.z_near}, color=rgba)
}

// NOTE: 3d line
immediate_line_3D :: proc(xyz0, xyz1: vec3, color := WHITE,
                          depth_test: Depth_Test_Mode = .LESS) {
  wish_primitive := Immediate_Primitive.LINES
  wish_space     := Immediate_Space.WORLD
  wish_texture   := immediate.white_texture

  immediate_begin(wish_primitive, wish_texture, wish_space, depth_test)

  immediate_vertex(xyz0, color=color)
  immediate_vertex(xyz1, color=color)
}

immediate_fill_box :: proc(xyz_min, xyz_max: vec3, color := WHITE,
                           depth_test: Depth_Test_Mode = .LESS) {
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

immediate_box :: proc(xyz_min, xyz_max: vec3, color := WHITE,
                      depth_test: Depth_Test_Mode = .LESS) {
  corners := box_corners(xyz_min, xyz_max)

  wish_primitive := Immediate_Primitive.LINES
  wish_space     := Immediate_Space.WORLD
  wish_texture   := immediate.white_texture
  immediate_begin(wish_primitive, wish_texture, wish_space, depth_test)

  // Back
  immediate_line(corners[0], corners[1], color)
  immediate_line(corners[1], corners[2], color)
  immediate_line(corners[2], corners[3], color)
  immediate_line(corners[3], corners[0], color)

  // Front
  immediate_line(corners[4], corners[5], color)
  immediate_line(corners[5], corners[6], color)
  immediate_line(corners[6], corners[7], color)
  immediate_line(corners[7], corners[4], color)

  // Left
  immediate_line(corners[4], corners[3], color)
  immediate_line(corners[5], corners[0], color)

  // Right
  immediate_line(corners[7], corners[2], color)
  immediate_line(corners[6], corners[1], color)
}

immediate_pyramid :: proc(tip, base0, base1, base2, base3: vec3, color := WHITE,
                          depth_test: Depth_Test_Mode = .LESS) {
  wish_primitive := Immediate_Primitive.TRIANGLES
  wish_space     := Immediate_Space.WORLD
  wish_texture   := immediate.white_texture
  immediate_begin(wish_primitive, wish_texture, wish_space, depth_test)

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

// Only wire frame for now
// TODO: Filled in option too
immediate_sphere :: proc(center: vec3, radius: f32, color := WHITE,
                         latitude_rings := 16,
                         longitude_rings := 16,
                         depth_test: Depth_Test_Mode = .LESS) {
  wish_primitive := Immediate_Primitive.LINE_STRIPS
  wish_space     := Immediate_Space.WORLD
  wish_texture   := immediate.white_texture
  immediate_begin(wish_primitive, wish_texture, wish_space, depth_test)

  // Draw the horizontal rings
  for r in 1..<latitude_rings {
    // Which ring are we on, as an angle
    theta := f32(r) / f32(latitude_rings) * PI

    // The individual line segemnts that make up the ring
    for s in 0..=longitude_rings {
      phi := f32(s) / f32(longitude_rings) * PI * 2.0

      // Just a rotation matrix basically based on theta and phi, then translating by the center
      immediate_vertex({(cos(phi) * sin(theta) * radius) + center.x,
                        (cos(theta) * radius) + center.y,
                        (sin(phi) * sin(theta) * radius) + center.z}, color)
    }
  }

  // Same for the vertical rings
  for s in 0..<longitude_rings {
    // Which ring are we on, as an angle
    phi := f32(s) / f32(longitude_rings) * PI * 2.0

    // The individual line segemnts that make up the ring
    for r in 0..=latitude_rings {
      theta := f32(r) / f32(latitude_rings) * PI

      // Just a rotation matrix basically based on theta and phi, then translating by the center
      immediate_vertex({(cos(phi) * sin(theta) * radius) + center.x,
                        (cos(theta) * radius) + center.y,
                        (sin(phi) * sin(theta) * radius) + center.z}, color)
    }
  }

  // So that if another line strip batch follows immediately after
  // it doesn't get connected to this
  immediate_begin_force()
}

// NOTE: Can control if flushing world space immediates, screen space immediates, or both
// This is used to draw any world space immediates in the main pass, allowing them to recive MSAA and to sample
// the main scene's depth buffer if they wish
// TODO: Maybe consider just having two different immediate systems, one for things that should be flushed in the main pass
// And others that ought to be flushed in the overlay/ui pass
immediate_flush :: proc(flush_world := true, flush_screen := true) {
  assert(state.began_drawing, "Tried to flush immediate vertex info before we have begun drawing this frame.")

  if immediate.vertex_count > 0 {
    bind_shader_program(immediate.shader)

    bind_vertex_buffer(immediate.vertex_buffer)
    defer unbind_vertex_buffer()

    // Transforms
    orthographic := mat4_orthographic(0, f32(state.window.w), f32(state.window.h), 0, state.z_near, state.z_far)
    perspective  := get_camera_perspective(state.camera) * get_camera_view(state.camera)

    gl.Disable(gl.CULL_FACE)

    frame_base := gpu_buffer_frame_offset(immediate.vertex_buffer) / size_of(Immediate_Vertex)
    for batch in immediate.batches {
      if batch.vertex_count > 0 {
        // TODO: Again make this a more generalizable thing probably
        depth_func_before: i32; gl.GetIntegerv(gl.DEPTH_FUNC, &depth_func_before)
        defer gl.DepthFunc(u32(depth_func_before))

        gl_depth_map := [Depth_Test_Mode]u32 {
          .DISABLED   = 0,
          .ALWAYS     = gl.ALWAYS,
          .LESS       = gl.LESS,
          .LESS_EQUAL = gl.LEQUAL,
        }

        gl.DepthFunc(gl_depth_map[batch.depth])

        switch batch.space {
        case .SCREEN:
          if !flush_screen { continue } // We shouldn't flush screen immediates

          set_shader_uniform("transform", orthographic)
        case .WORLD:
          if !flush_world { continue } // We shouldn't flush screen immediates

          set_shader_uniform("transform", perspective)
        }

        bind_texture("tex", batch.texture)

        first_vertex := i32(frame_base + batch.vertex_base)
        vertex_count := i32(batch.vertex_count)

        switch batch.primitive {
        case .TRIANGLES:
          gl.DrawArrays(gl.TRIANGLES, first_vertex, vertex_count)
        case .LINES:
          gl.DrawArrays(gl.LINES, first_vertex, vertex_count)
        case .LINE_STRIPS:
          gl.DrawArrays(gl.LINE_STRIP, first_vertex, vertex_count)
        }
      }
    }
  }
}
