package main

import "core:log"
import "core:mem"
import "core:math"

import gl "vendor:OpenGL"

MAX_IMMEDIATE_VERTEX_COUNT :: 4096 * 4

Immediate_Vertex :: struct {
  position: vec3,
  uv:       vec2,
  color:    vec4,
}

// NOTE: When an immediate_* function takes in a vec2 for position it usually means its in screen coords
// When taking in a vec3 for position its in world space

Immediate_Mode :: enum {
  TRIANGLES,
  LINES,
  LINE_STRIPS,
}

Immediate_Space :: enum {
  SCREEN,
  WORLD,
}

// NOTE: This is not integrated with the general asset system and deals with actual textures and such...
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

  mode:    Immediate_Mode,
  texture: Texture,
  space:   Immediate_Space,
}

// "Singleton" in c++ terms, but less stupid
@(private="file")
immediate: Immediate_State

init_immediate_renderer :: proc() -> (ok: bool) {
  assert(state.gl_is_initialized)

  vertex_buffer := make_vertex_buffer(Immediate_Vertex, MAX_IMMEDIATE_VERTEX_COUNT, persistent = true)

  shader := make_shader_program("immediate.vert", "immediate.frag", state.perm_alloc) or_return

  immediate = {
    vertex_buffer = vertex_buffer,
    vertex_count  = 0,
    shader        = shader,

    batches = make([dynamic]Immediate_Batch, state.perm_alloc)
  }

  // FIXME: AHHHHHHHHH
  white_tex_handle: Texture_Handle
  white_tex_handle, ok = load_texture("white.png")

  immediate.white_texture = get_texture(white_tex_handle)^

  return ok
}

immediate_frame_flush :: proc() {
  immediate_flush()
  immediate.vertex_count = 0
}

// Returns the pointer to the new batch in the batches dynamic array.
@(private="file")
start_new_batch :: proc(mode: Immediate_Mode, texture: Texture, space: Immediate_Space) -> (batch_pointer: ^Immediate_Batch) {
  append(&immediate.batches, Immediate_Batch{
    vertex_base = immediate.vertex_count, // Always on the end.

    mode = mode,
    texture = texture,
    space = space,
  })

  return &immediate.batches[len(immediate.batches) - 1]
}

// Starts a new batch if necessary
immediate_begin :: proc(wish_mode: Immediate_Mode, wish_texture: Texture, wish_space: Immediate_Space) {
  if immediate.curr_batch == nil || // Should short circuit and not do any nil dereferences
     immediate.curr_batch.mode    != wish_mode  ||
     immediate.curr_batch.space   != wish_space ||
     immediate.curr_batch.texture != wish_texture {
    immediate.curr_batch = start_new_batch(wish_mode, wish_texture, wish_space)
  }
}

free_immediate_renderer :: proc() {
  free_gpu_buffer(&immediate.vertex_buffer)
  free_shader_program(&immediate.shader)
}

// NOTE: Does not check batch info. Trusts the caller to make sure that all batch info is right
immediate_vertex :: proc(xyz: vec3, rgba: vec4 = WHITE, uv: vec2 = {0.0, 0.0}) {
  assert(state.gl_is_initialized)
  assert(gpu_buffer_is_mapped(immediate.vertex_buffer), "Uninitialized Immediate State")

  if immediate.vertex_count + 1 >= MAX_IMMEDIATE_VERTEX_COUNT {
    log.errorf("Too many (%v) immediate vertices!!!!!!\n", immediate.vertex_count)
    return
  }

  vertex := Immediate_Vertex{
    position = xyz,
    uv       = uv,
    color    = rgba,
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

// NOTE: A quad so takes in screen coordinates!
// maybe in future it can be a 3d quad in world space
immediate_quad :: proc(xy: vec2, w, h: f32, rgba: vec4 = WHITE,
                       uv0: vec2 = {0.0, 0.0}, uv1: vec2 = {0.0, 0.0},
                       texture: Texture = immediate.white_texture) {
  wish_mode  := Immediate_Mode.TRIANGLES
  wish_space := Immediate_Space.SCREEN

  immediate_begin(wish_mode, texture, wish_space)

  top_left := Immediate_Vertex{
    position = {xy.x, xy.y, -state.z_near},
    uv       = uv0,
    color    = rgba,
  }
  top_right := Immediate_Vertex{
    position = {xy.x + w, xy.y, -state.z_near},
    uv       = {uv1.x, uv0.y},
    color    = rgba,
  }
  bottom_left := Immediate_Vertex{
    position = {xy.x, xy.y + h, -state.z_near},
    uv       = {uv0.x, uv1.y},
    color    = rgba,
  }
  bottom_right := Immediate_Vertex{
    position = {xy.x + w, xy.y + h, -state.z_near},
    uv       = uv1,
    color    = rgba,
  }

  immediate_vertex(top_left.position, top_left.color, top_left.uv)
  immediate_vertex(top_right.position, top_right.color, top_right.uv)
  immediate_vertex(bottom_left.position, bottom_left.color, bottom_left.uv)

  immediate_vertex(top_right.position, top_right.color, top_right.uv)
  immediate_vertex(bottom_right.position, bottom_right.color, bottom_right.uv)
  immediate_vertex(bottom_left.position, bottom_left.color, bottom_left.uv)
}

immediate_line :: proc {
  immediate_line_2D,
  immediate_line_3D,
}

// NOTE: A 2d line so takes in screen coordinates!
immediate_line_2D :: proc(xy0, xy1: vec2, rgba: vec4 = WHITE) {
  wish_mode    := Immediate_Mode.LINES
  wish_space   := Immediate_Space.SCREEN
  wish_texture := immediate.white_texture

  immediate_begin(wish_mode, wish_texture, wish_space)

  immediate_vertex({xy0.x, xy0.y, -state.z_near}, rgba = rgba)
  immediate_vertex({xy1.x, xy1.y, -state.z_near}, rgba = rgba)
}

// NOTE: 3d line
immediate_line_3D :: proc(xyz0, xyz1: vec3, rgba: vec4 = WHITE) {
  wish_mode    := Immediate_Mode.LINES
  wish_space   := Immediate_Space.WORLD
  wish_texture := immediate.white_texture

  immediate_begin(wish_mode, wish_texture, wish_space)

  immediate_vertex(xyz0, rgba = rgba)
  immediate_vertex(xyz1, rgba = rgba)
}

immediate_box :: proc(xyz_min, xyz_max: vec3, rgba: vec4 = WHITE) {
  corners := box_corners(xyz_min, xyz_max)

  wish_mode    := Immediate_Mode.LINES
  wish_space   := Immediate_Space.WORLD
  wish_texture := immediate.white_texture
  immediate_begin(wish_mode, wish_texture, wish_space)

  immediate_line(corners[0], corners[1], rgba)
  immediate_line(corners[1], corners[2], rgba)
  immediate_line(corners[2], corners[3], rgba)
  immediate_line(corners[3], corners[0], rgba)

  // Front
  immediate_line(corners[4], corners[5], rgba)
  immediate_line(corners[5], corners[6], rgba)
  immediate_line(corners[6], corners[7], rgba)
  immediate_line(corners[7], corners[4], rgba)

  // Left
  immediate_line(corners[4], corners[3], rgba)
  immediate_line(corners[5], corners[0], rgba)

  // Right
  immediate_line(corners[7], corners[2], rgba)
  immediate_line(corners[6], corners[1], rgba)
}

immediate_pyramid :: proc(tip, base0, base1, base2, base3: vec3, rgba: vec4 = WHITE) {
  wish_mode    := Immediate_Mode.TRIANGLES
  wish_space   := Immediate_Space.WORLD
  wish_texture := immediate.white_texture
  immediate_begin(wish_mode, wish_texture, wish_space)

  // Triangle sides
  immediate_vertex(tip, rgba)
  immediate_vertex(base0, rgba)
  immediate_vertex(base1, rgba)

  immediate_vertex(tip, rgba)
  immediate_vertex(base1, rgba)
  immediate_vertex(base2, rgba)

  immediate_vertex(tip, rgba)
  immediate_vertex(base2, rgba)
  immediate_vertex(base3, rgba)

  immediate_vertex(tip, rgba)
  immediate_vertex(base3, rgba)
  immediate_vertex(base0, rgba)

  // Base
  immediate_vertex(base0, rgba)
  immediate_vertex(base3, rgba)
  immediate_vertex(base1, rgba)

  immediate_vertex(base2, rgba)
  immediate_vertex(base0, rgba)
  immediate_vertex(base3, rgba)
}

// Only wire frame for now
// TODO: Filled in option too
immediate_sphere :: proc(center: vec3, radius: f32, rgba: vec4 = WHITE) {
  wish_mode    := Immediate_Mode.LINE_STRIPS
  wish_space   := Immediate_Space.WORLD
  wish_texture := immediate.white_texture
  immediate_begin(wish_mode, wish_texture, wish_space)

  using math

  // Draw the horizontal rings
  LAT_RINGS  :: 8 * 2
  LONG_RINGS :: 8 * 2
  for r in 1..<LAT_RINGS {
    // Which ring are we on, as an angle
    theta := f32(r) / LAT_RINGS * PI

    // The individual line segemnts that make up the ring
    for s in 0..=LONG_RINGS {
      phi := f32(s) / LONG_RINGS * PI * 2.0

      // Just a rotation matrix basically based on theta and phi, then translating by the center
      immediate_vertex({(cos(phi) * sin(theta) * radius) + center.x,
                        (cos(theta) * radius) + center.y,
                        (sin(phi) * sin(theta) * radius) + center.z}, rgba)
    }
  }

  // Same for the vertical rings
  for s in 0..<LONG_RINGS {
    // Which ring are we on, as an angle
    phi := f32(s) / LONG_RINGS * PI * 2.0

    // The individual line segemnts that make up the ring
    for r in 0..=LAT_RINGS {
      theta := f32(r) / LAT_RINGS * PI

      // Just a rotation matrix basically based on theta and phi, then translating by the center
      immediate_vertex({(cos(phi) * sin(theta) * radius) + center.x,
                        (cos(theta) * radius) + center.y,
                        (sin(phi) * sin(theta) * radius) + center.z}, rgba)
    }
  }
}

immediate_flush :: proc() {
  assert(state.began_drawing, "Tried to flush immediate vertex info before we have begun drawing this frame.")

  if immediate.vertex_count > 0 {
    bind_shader_program(immediate.shader)
    bind_vertex_buffer(immediate.vertex_buffer)
    defer unbind_vertex_buffer()

    frame_base := gpu_buffer_frame_offset(immediate.vertex_buffer) / size_of(Immediate_Vertex)
    for batch in immediate.batches {
      if batch.vertex_count > 0 {
        bind_texture(batch.texture, "tex")


        depth_func_before: i32; gl.GetIntegerv(gl.DEPTH_FUNC, &depth_func_before)
        defer gl.DepthFunc(u32(depth_func_before))

        // TODO: Make sure we set relevant GL State
        switch batch.space {
        case .SCREEN:
          gl.DepthFunc(gl.ALWAYS)
          set_shader_uniform("transform", get_orthographic(0, f32(state.window.w), f32(state.window.h), 0, state.z_near, state.z_far))
        case .WORLD:
          set_shader_uniform("transform", get_camera_perspective(state.camera) * get_camera_view(state.camera))
        }

        first_vertex := i32(frame_base + batch.vertex_base)
        vertex_count := i32(batch.vertex_count)

        switch batch.mode {
        case .TRIANGLES:
          gl.DrawArrays(gl.TRIANGLES, first_vertex, vertex_count)
        case .LINES:
          gl.DrawArrays(gl.LINES, first_vertex, vertex_count)
        case .LINE_STRIPS:
          gl.DrawArrays(gl.LINE_STRIP, first_vertex, vertex_count)
        }
      }
    }

    // And reset
    clear(&immediate.batches)
    immediate.curr_batch = nil
  }
}
