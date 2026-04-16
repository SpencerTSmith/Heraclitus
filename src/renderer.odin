package main

import "core:log"
import "core:mem"

GPU_Upload :: struct
{
  // Considering store pointers instead of the actual structs here.
  src_buffer: GPU_Buffer,
  src_offset: int,

  dst: union
  {
    GPU_Buffer,
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
  vertex_buffer:   GPU_Buffer,
  vertex_count:    int,
  index_buffer:    GPU_Buffer,
  index_count:     int,
  material_buffer: GPU_Buffer,
  material_count:  int,

  // Mapped buffers that need to be buffered per frame
  // note to self: With current backend vulkan allocator, buffers created one after the other
  // are guaranteed linear in memory, so its alright to have multiple 'GPU_buffers' and not just one
  // giant ring buffer... however if i chagne backend allocation in future this should probably change.
  uniform_buffer: [FRAMES_IN_FLIGHT]GPU_Buffer,

  staging_buffer: [FRAMES_IN_FLIGHT]GPU_Buffer,
  staging_offset: int,

  draw_commands: [FRAMES_IN_FLIGHT]GPU_Buffer,
  draw_uniforms: [FRAMES_IN_FLIGHT]GPU_Buffer,
  draw_head:     int, // Start of current portion
  draw_count:    int, // Total

  // Immediate vertices
  // immediate_buffer: [FRAMES_IN_FLIGHT]GPU_Buffer,
  // immediate_count:  uint,

  bloom_on: bool,

  draw_debug: bool,
}

MAX_DRAWS     :: 1  * mem.Megabyte
MAX_VERTICES  :: 4  * mem.Megabyte
MAX_INDICES   :: 16 * mem.Megabyte
MAX_MATERIALS :: 512

init_renderer :: proc()
{
  init_vulkan(state.window)
  generate_glsl()
  init_immediate_renderer()
  state.renderer.vertex_buffer   = make_vertex_buffer(Mesh_Vertex, MAX_VERTICES, {.VERTEX_DATA, .DEVICE_LOCAL})
  state.renderer.index_buffer    = make_index_buffer(Mesh_Index, MAX_VERTICES, {.INDEX_DATA, .DEVICE_LOCAL})
  state.renderer.material_buffer = make_gpu_buffer(size_of(Material_Uniform) * MAX_MATERIALS, {.STORAGE_DATA})

  state.renderer.uniform_buffer = make_ring_gpu_buffers(size_of(Frame_Uniform), {.UNIFORM_DATA, .CPU_MAPPED}, FRAMES_IN_FLIGHT)
  state.renderer.staging_buffer = make_ring_gpu_buffers(64 * mem.Megabyte, {.UNIFORM_DATA, .CPU_MAPPED}, FRAMES_IN_FLIGHT)

  state.renderer.draw_commands = make_gpu_buffer(size_of(Draw_Command) * MAX_DRAWS,
                                                 flags = {.STORAGE_DATA, .CPU_MAPPED})
  state.renderer.draw_uniforms = make_gpu_buffer(size_of(Draw_Uniform) * MAX_DRAWS,
                                                 flags = {.STORAGE_DATA, .CPU_MAPPED})

  state.renderer.bloom_on = true
  state.renderer.draw_debug = true
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
  }

  return ok
}

// NOTE: Will use the very first attachment
flush_render_frame :: proc(to_display: Texture)
{
  immediate_frame_reset()
  state.renderer.draw_count = 0
  state.renderer.draw_head  = 0
  state.renderer.staging_offset = 0
  clear(&state.renderer.upload_queue)

  vk_flush_render_frame(to_display)
}

queue_buffer_upload :: proc(data: []byte, dst: GPU_Buffer, dst_offset: int)
{
  assert(state.renderer.staging_offset + len(data) < state.renderer.staging_buffer[curr_frame_idx()].size)

  upload: GPU_Upload =
  {
    src_buffer = state.renderer.staging_buffer[curr_frame_idx()],
    src_offset = state.renderer.staging_offset,
    dst        = dst,
    dst_offset = dst_offset,
    size       = len(data),
  }

  // Copy to staging.
  staging_ptr := uintptr(state.renderer.staging_buffer[curr_frame_idx()].cpu_base) + uintptr(state.renderer.staging_offset)
  mem.copy(rawptr(staging_ptr), raw_data(data), upload.size)

  append(&state.renderer.upload_queue, upload)

  state.renderer.staging_offset += upload.size
}

upload_model :: proc(vertices: []Mesh_Vertex, indices: []Mesh_Index) -> (vertex_offset, index_offset: i32)
{
  if state.renderer.vertex_count + len(vertices) <= MAX_VERTICES &&
     state.renderer.index_count + len(indices)   <= MAX_INDICES
  {
    queue_buffer_upload(mem.byte_slice(raw_data(vertices), size_of(vertices[0]) * len(vertices)),
                        state.renderer.vertex_buffer, state.renderer.vertex_count * size_of(vertices[0]))

    vertex_offset = cast(i32) state.renderer.vertex_count
    state.renderer.vertex_count += len(vertices)

    queue_buffer_upload(mem.byte_slice(raw_data(indices), size_of(indices[0]) * len(indices)),
                        state.renderer.index_buffer, state.renderer.index_count * size_of(indices[0]))

    index_offset = cast(i32) state.renderer.index_count
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
      state.renderer.material_count += 1
    }

    // write_gpu_buffer(state.renderer.material_buffer, write_offset, len(uniforms) * size_of(uniforms[0]), raw_data(uniforms))
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

      draw_ptr := cast([^]Draw_Command)state.renderer.draw_commands[curr_frame_idx()].cpu_base
      draw_ptr[state.renderer.draw_count] = command
    }

    // Draw Uniform
    {
      uniform := uniform
      uniform_ptr := cast([^]Draw_Uniform)state.renderer.draw_uniforms[curr_frame_idx()].cpu_base
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
  // bind_vertex_buffer(state.renderer.vertex_buffer)
  // gl.BindBuffer(gl.DRAW_INDIRECT_BUFFER, state.renderer.draw_commands.id)

  // Since we can't bind the base we do a frame offset here
  // frame_offset := gpu_buffer_frame_offset(state.renderer.draw_commands)
  // batch_offset := cast(uintptr)(frame_offset + state.renderer.draw_head * size_of(Draw_Command))

  batch_count := cast(i32) (state.renderer.draw_count - state.renderer.draw_head)

  // gl.MultiDrawElementsIndirect(gl.TRIANGLES, gl.UNSIGNED_INT,
  //   cast([^]gl.DrawElementsIndirectCommand)batch_offset, batch_count, 0)

  state.renderer.draw_head = state.renderer.draw_count // Move head pointer up
}
