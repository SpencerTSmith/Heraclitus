package main

import "core:log"
import "core:mem"

GPU_Upload :: struct
{
  // Considering store pointers instead of the actual structs here.
  src_buffer: GPU_Buffer(byte),
  src_offset: int,

  dst: union
  {
    GPU_Buffer(byte),
    Texture,
  },
  dst_offset: int,
  size:       int,
}

Renderer :: struct
{
  pipelines: [Pipeline_Key]Pipeline,
  samplers:  [Sampler_Preset]u32,

  // TODO: Hmm maybe should be enum array too, these must all be the same dimensions as backbuffer
  // so simple to loop over enum array when resizing swapchain/window
  // hdr_ms_buffer:     Framebuffer,
  // post_buffer:       Framebuffer,
  // ping_pong_buffers: [2]Framebuffer,
  //
  // point_depth_buffer: Framebuffer,
  // sun_depth_buffer:   Framebuffer,

  bound_pipeline: Pipeline,

  upload_queue: [dynamic; 32]GPU_Upload,

  // Mega buffers
  vertex_buffer:   GPU_Buffer(Mesh_Vertex),
  vertex_count:    int,
  index_buffer:    GPU_Buffer(Mesh_Index),
  index_count:     int,
  material_buffer: GPU_Buffer(Material_Uniform),
  material_count:  int,

  // Mapped buffers that need to be buffered per frame
  // May be better to just have one big one that each frame keeps track of where they were at
  // that way any one frame has a higher likelihood of having more memory to work with...

  uniform_buffer: [FRAMES_IN_FLIGHT]GPU_Buffer(Frame_Uniform),

  staging_buffer: [FRAMES_IN_FLIGHT]GPU_Buffer(byte),
  staging_offset: int,

  draw_commands: [FRAMES_IN_FLIGHT]GPU_Buffer(Draw_Command),
  draw_uniforms: [FRAMES_IN_FLIGHT]GPU_Buffer(Draw_Uniform),
  draw_head:     int, // Start of current portion
  draw_count:    int, // Total

  // Immediate/dynamic vertex data
  immediate: struct
  {
    vertex_buffer: [FRAMES_IN_FLIGHT]GPU_Buffer(Immediate_Vertex),
    vertex_count:  int, // TOTAL for the current frame
    batches: [dynamic; 256]Immediate_Batch,
  },

  frame_began: bool,
  bloom_on:    bool,
  draw_debug:  bool,
}

MAX_DRAWS     :: 64 * mem.Kilobyte
MAX_VERTICES  :: 4  * mem.Megabyte
MAX_INDICES   :: 16 * mem.Megabyte
MAX_MATERIALS :: 512

MAX_IMMEDIATE_VERTICES :: 256 * mem.Kilobyte

Immediate_Vertex :: struct
{
  position: vec3,
  uv:       vec2,
  color:    vec4,
}

// NOTE: When an immediate_* function takes in a vec2 for position it means its in screen coords
// When taking in a vec3 for position its in world space

Immediate_Space :: enum
{
  SCREEN,
  WORLD,
}

// Just a view into the main vertex buffer
// TODO: Maybe each batch should store vertices itself so that we can check if there is a batch
// that matches state but is not the current batch?
Immediate_Batch :: struct
{
  vertex_base:  u32, // First vertex in batch
  vertex_count: u32, // How many vertices in batch

  primitive: Vertex_Primitive,
  texture:   Texture_Handle,
  space:     Immediate_Space,
  depth:     Depth_Test_Mode,
}

Immediate_Push :: struct
{
  transform:     mat4,
  vertices:      rawptr,
  texture_index: u32,
}

init_renderer :: proc() -> (ok: bool)
{
  init_vulkan(state.window)
  generate_glsl()

  state.renderer.vertex_buffer   = make_gpu_buffer(Mesh_Vertex, MAX_VERTICES, {.VERTEX_DATA, .DEVICE_LOCAL})
  state.renderer.index_buffer    = make_gpu_buffer(Mesh_Index, MAX_VERTICES, {.INDEX_DATA, .DEVICE_LOCAL})
  state.renderer.material_buffer = make_gpu_buffer(Material_Uniform, MAX_MATERIALS, {.STORAGE_DATA, .DEVICE_LOCAL})

  state.renderer.uniform_buffer = make_ring_gpu_buffers(Frame_Uniform, 1, {.UNIFORM_DATA, .CPU_MAPPED}, FRAMES_IN_FLIGHT)
  state.renderer.staging_buffer = make_ring_gpu_buffers(byte, 64 * mem.Megabyte, {.UNIFORM_DATA, .CPU_MAPPED}, FRAMES_IN_FLIGHT)

  state.renderer.draw_commands = make_ring_gpu_buffers(Draw_Command, MAX_DRAWS, {.STORAGE_DATA, .CPU_MAPPED}, FRAMES_IN_FLIGHT)
  state.renderer.draw_uniforms = make_ring_gpu_buffers(Draw_Uniform, MAX_DRAWS, {.STORAGE_DATA, .CPU_MAPPED}, FRAMES_IN_FLIGHT)

  state.renderer.immediate.vertex_buffer = make_ring_gpu_buffers(Immediate_Vertex, MAX_IMMEDIATE_VERTICES, {.CPU_MAPPED, .VERTEX_DATA}, FRAMES_IN_FLIGHT)

  // Always have a default batch
  append(&state.renderer.immediate.batches, Immediate_Batch{})

  state.renderer.pipelines[.IMMEDIATE], ok = make_pipeline("immediate.vert", "immediate.frag", Immediate_Push, .RGBA16F)
  assert(ok)
  // state.renderer.pipelines[.PHONG], ok = make_pipeline("simple.vert", "phong.frag", )

  state.renderer.bloom_on = true
  state.renderer.draw_debug = true

  return ok
}

begin_render_frame :: proc() -> (ok: bool)
{
  // TODO: Get shader hot reloading up and running
  // TODO: Bind global frame uniforms
  // TODO: Resize render targets to window size if changed

  ok = vk_begin_render_frame()

  if ok
  {
    vk_do_uploads(state.renderer.upload_queue)
    clear(&state.renderer.upload_queue)
    state.renderer.frame_began = true
  }

  return ok
}

// NOTE: Will use the very first attachment
flush_render_frame :: proc(to_display: Texture)
{
  state.renderer.immediate.vertex_count = 0
  clear(&state.renderer.immediate.batches)
  append(&state.renderer.immediate.batches, Immediate_Batch{})

  state.renderer.draw_count = 0
  state.renderer.draw_head  = 0
  state.renderer.staging_offset = 0

  vk_flush_render_frame(to_display)
  state.renderer.frame_began = false
}

// This may be voodoo with the polymorphism
queue_buffer_upload :: proc(data: []$Type, dst: GPU_Buffer(Type), dst_offset: int)
{
  byte_size   := len(data) * size_of(Type)
  byte_offset := dst_offset * size_of(Type)

  assert(state.renderer.staging_offset + byte_size < state.renderer.staging_buffer[curr_frame_idx()].count)

  upload: GPU_Upload =
  {
    src_buffer = state.renderer.staging_buffer[curr_frame_idx()],
    src_offset = state.renderer.staging_offset,
    dst        = gpu_buffer_as_bytes(dst),
    dst_offset = byte_offset,
    size       = byte_size,
  }

  // Copy to staging.
  staging_ptr := uintptr(state.renderer.staging_buffer[curr_frame_idx()].cpu_base) + uintptr(state.renderer.staging_offset)
  mem.copy(rawptr(staging_ptr), raw_data(data), upload.size)

  append(&state.renderer.upload_queue, upload)

  state.renderer.staging_offset += upload.size
}

upload_texture :: proc(data: []byte, dst: Texture)
{
  assert(state.renderer.staging_offset + len(data) < state.renderer.staging_buffer[curr_frame_idx()].count)

  upload: GPU_Upload =
  {
    src_buffer = state.renderer.staging_buffer[curr_frame_idx()],
    src_offset = state.renderer.staging_offset,
    dst        = dst,
    size       = len(data),
  }

  // Copy to staging.
  staging_ptr := uintptr(state.renderer.staging_buffer[curr_frame_idx()].cpu_base) + uintptr(state.renderer.staging_offset)
  mem.copy(rawptr(staging_ptr), raw_data(data), upload.size)

  append(&state.renderer.upload_queue, upload)

  state.renderer.staging_offset += upload.size
}

upload_model :: proc(vertices: []Mesh_Vertex, indices: []Mesh_Index) -> (vertex_offset, index_offset: u32)
{
  if state.renderer.vertex_count + len(vertices) <= MAX_VERTICES &&
     state.renderer.index_count + len(indices)   <= MAX_INDICES
  {
    queue_buffer_upload(vertices, state.renderer.vertex_buffer, state.renderer.vertex_count)

    vertex_offset = cast(u32)state.renderer.vertex_count
    state.renderer.vertex_count += len(vertices)

    queue_buffer_upload(indices, state.renderer.index_buffer, state.renderer.index_count)

    index_offset = cast(u32)state.renderer.index_count
    state.renderer.index_count += len(indices)
  }
  else
  {
    log.errorf("Cannot push any more vertices to mega buffer.")
  }

  return vertex_offset, index_offset
}

upload_materials :: proc(materials: ^[]Material)
{
  if (state.renderer.material_count + len(materials)) < MAX_MATERIALS
  {
    uniforms := make([]Material_Uniform, len(materials), context.temp_allocator)
    write_offset := state.renderer.material_count * size_of(uniforms[0])

    for &material, idx in materials
    {
      uniforms[idx] = material_uniform(material)
      material.buffer_index = u32(state.renderer.material_count)
    }

    queue_buffer_upload(uniforms, state.renderer.material_buffer, state.renderer.material_count)

    state.renderer.material_count += len(uniforms)
  }
  else
  {
    log.errorf("Cannot push materials to mega buffer.")
  }
}

push_draw :: proc(command: Draw_Command, uniform: Draw_Uniform)
{
  if (state.renderer.draw_count + 1 < MAX_DRAWS)
  {
    // Draw Command
    {
      command := command

      // NOTE: Using this to index into the total buffer. As we have to do multiple
      // multidraws per frame due to shadow mapping,
      // gl_DrawID no longer works perfectly to index
      command.base_instance = cast(u32)state.renderer.draw_count
      command.first_index += cast(u32)state.renderer.index_count

      state.renderer.draw_commands[curr_frame_idx()].cpu_base[state.renderer.draw_count] = command
    }

    // Draw Uniform
    {
      state.renderer.draw_uniforms[curr_frame_idx()].cpu_base[state.renderer.draw_count] = uniform
    }

    state.renderer.draw_count += 1
  }
  else
  {
    log.errorf("Cannot push any more draw commands.");
  }
}

mega_draw :: proc()
{
  // Since we can't bind the base we do a frame offset here
  // frame_offset := gpu_buffer_frame_offset(state.renderer.draw_commands)
  // batch_offset := cast(uintptr)(frame_offset + state.renderer.draw_head * size_of(Draw_Command))

  batch_count := cast(i32) (state.renderer.draw_count - state.renderer.draw_head)

  // gl.MultiDrawElementsIndirect(gl.TRIANGLES, gl.UNSIGNED_INT,
  //   cast([^]gl.DrawElementsIndirectCommand)batch_offset, batch_count, 0)

  state.renderer.draw_head = state.renderer.draw_count // Move head pointer up
}

// Starts a new batch if necessary
immediate_begin :: proc(wish_primitive: Vertex_Primitive, wish_texture: Texture_Handle, wish_space: Immediate_Space, wish_depth: Depth_Test_Mode)
{
  current := state.renderer.immediate.batches[len(state.renderer.immediate.batches) - 1]
  if current.primitive != wish_primitive ||
     current.space     != wish_space     ||
     current.texture   != wish_texture   ||
     current.depth     != wish_depth
  {
    appended := append(&state.renderer.immediate.batches, Immediate_Batch {
      vertex_base = cast(u32)state.renderer.immediate.vertex_count,
      primitive   = wish_primitive,
      texture     = wish_texture,
      space       = wish_space,
      depth       = wish_depth,
    })

    if appended == 0
    {
      log.errorf("Too many immediate draw batches.")
    }
  }
}

// NOTE: Does not check batch info. Trusts the caller to make sure that all batch info is right
immediate_vertex :: proc(position: vec3, color: vec4 = WHITE, uv: vec2 = {0.0, 0.0})
{
  if state.renderer.immediate.vertex_count + 1 < MAX_IMMEDIATE_VERTICES
  {
    current := &state.renderer.immediate.batches[len(state.renderer.immediate.batches) - 1]

    // Write into the current batch.
    offset := current.vertex_base + current.vertex_count

    // To the gpu buffer!
    state.renderer.immediate.vertex_buffer[curr_frame_idx()].cpu_base[offset] =
    {
      position = position,
      uv       = uv,
      color    = color,
    }

    state.renderer.immediate.vertex_count += 1

    // And remember to add to the current batches count.
    current.vertex_count += 1
  }
  else
  {
    log.errorf("Too many immediate vertices.", state.renderer.immediate.vertex_count)
  }
}

// NOTE: Can control if flushing world space immediates, screen space immediates, or both
// This is used to draw any world space immediates in the main pass, allowing them to recive MSAA and to sample
// the main scene's depth buffer if they wish
// TODO: Maybe consider just having two different immediate systems, one for things that should be flushed in the main pass
// And others that ought to be flushed in the overlay/ui pass
immediate_flush :: proc(flush_world := false, flush_screen := false)
{
  if state.renderer.immediate.vertex_count > 0
  {
    bind_pipeline_key(.IMMEDIATE)

    // Screenspace
    orthographic := mat4_orthographic(0, f32(state.window.w), f32(state.window.h), 0, -1, 1)

    // Worldspace
    perspective  := camera_perspective(state.camera, window_aspect_ratio(state.window)) * camera_view(state.camera)

    for batch in state.renderer.immediate.batches
    {
      if batch.vertex_count > 0
      {
        transform: mat4
        switch batch.space
        {
        case .SCREEN:
          if !flush_screen { continue } // We shouldn't flush screen immediates
          transform = orthographic
        case .WORLD:
          if !flush_world { continue } // We shouldn't flush world immediates
          transform = perspective
        }

        push: Immediate_Push =
        {
          transform     = transform,
          vertices      = state.renderer.immediate.vertex_buffer[curr_frame_idx()].gpu_base,
          texture_index = get_texture(batch.texture).index,
        }
        vk_draw_vertices(batch.vertex_base, batch.vertex_count, push)
      }
    }
  }
}

