package main

import "core:log"
import "core:mem"
import "core:time"

FRAMES_IN_FLIGHT :: 3
TARGET_FPS :: 240
TARGET_FRAME_TIME_NS :: time.Duration(BILLION / TARGET_FPS)

MAX_DRAWS     :: 64 * mem.Kilobyte
MAX_VERTICES  :: 4 * mem.Megabyte
MAX_INDICES   :: 8 * mem.Megabyte
MAX_MATERIALS :: 512

MAX_IMMEDIATE_VERTICES :: 256 * mem.Kilobyte

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

Pipeline_Key :: enum
{
  PHONG,
  SKYBOX,
  RESOLVE_HDR,
  SUN_DEPTH,
  POINT_DEPTH,
  GAUSSIAN,
  GET_BRIGHT,
  IMMEDIATE,
}

Renderer :: struct
{
  pipelines: [Pipeline_Key]Pipeline,
  samplers:  [Sampler_Preset]u32,

  // TODO: Hmm maybe should be enum array too, these must all be the same dimensions as backbuffer
  // so simple to loop over enum array when resizing swapchain/window
  main_target: Render_Target,
  post_target: Render_Target,

  ping_pong_targets: [2]Render_Target,

  point_shadow_target: Render_Target,
  sun_shadow_target:   Render_Target,

  bound_pipeline: Pipeline,

  upload_queue: [dynamic; 256]GPU_Upload,

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

  staging_buffer: GPU_Buffer(byte),
  staging_offset: int,
  staging_tails:  [FRAMES_IN_FLIGHT]int,

  draw_commands: [FRAMES_IN_FLIGHT]GPU_Buffer(Draw_Command),
  draw_uniforms: [FRAMES_IN_FLIGHT]GPU_Buffer(Draw_Uniform),
  draw_head:     int, // Start of batch
  draw_count:    int, // Total

  // Immediate/dynamic vertex data
  immediate: struct
  {
    vertex_buffer: [FRAMES_IN_FLIGHT]GPU_Buffer(Immediate_Vertex),
    vertex_count:  int, // TOTAL for the current frame
    batches:       [dynamic; 256]Immediate_Batch,
  },

  frame_began: bool,
  bloom_on:    bool,
  draw_debug:  bool,
}

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
  transform: mat4,
  texture:   u32,
  vertices:  [^]Immediate_Vertex,
}

Mega_Push :: struct
{
  frame_uniform:     [^]Frame_Uniform,
  draw_uniforms:     [^]Draw_Uniform,
  vertices:          [^]Mesh_Vertex,
  material_uniforms: [^]Material_Uniform,
}

init_renderer :: proc() -> (ok: bool)
{
  init_vulkan(state.window)
  generate_slang()

  state.renderer.main_target = make_render_target(u32(state.window.w), u32(state.window.h), {.COLOR, .DEPTH})
  state.renderer.post_target = make_render_target(u32(state.window.w), u32(state.window.h), {.COLOR})

  state.renderer.vertex_buffer   = make_gpu_buffer(Mesh_Vertex, MAX_VERTICES, {.VERTEX_DATA, .DEVICE_LOCAL})
  state.renderer.index_buffer    = make_gpu_buffer(Mesh_Index, MAX_INDICES, {.INDEX_DATA, .DEVICE_LOCAL})
  state.renderer.material_buffer = make_gpu_buffer(Material_Uniform, MAX_MATERIALS, {.STORAGE_DATA, .DEVICE_LOCAL})

  state.renderer.uniform_buffer = make_ring_gpu_buffers(Frame_Uniform, 1, {.UNIFORM_DATA, .CPU_MAPPED}, FRAMES_IN_FLIGHT)

  // FIXME: Just brute forcing staging being simple by having a GINORMOUS staging buffer
  state.renderer.staging_buffer = make_gpu_buffer(byte, 448 * mem.Megabyte, {.STORAGE_DATA, .CPU_MAPPED})

  state.renderer.draw_commands = make_ring_gpu_buffers(Draw_Command, MAX_DRAWS, {.STORAGE_DATA, .CPU_MAPPED}, FRAMES_IN_FLIGHT)
  state.renderer.draw_uniforms = make_ring_gpu_buffers(Draw_Uniform, MAX_DRAWS, {.STORAGE_DATA, .CPU_MAPPED}, FRAMES_IN_FLIGHT)

  state.renderer.immediate.vertex_buffer = make_ring_gpu_buffers(Immediate_Vertex, MAX_IMMEDIATE_VERTICES, {.CPU_MAPPED, .VERTEX_DATA}, FRAMES_IN_FLIGHT)

  // Always have a default batch.
  append(&state.renderer.immediate.batches, Immediate_Batch{})

  state.renderer.pipelines[.IMMEDIATE], ok = make_pipeline("immediate.slang", .RGBA16F, .DEPTH32)
  assert(ok)

  // FIXME: Using test shaders.
  state.renderer.pipelines[.PHONG], ok = make_pipeline("phong.slang", .RGBA16F, .DEPTH32)
  assert(ok)

  state.renderer.pipelines[.SKYBOX], ok = make_pipeline("skybox.slang", .RGBA16F, .DEPTH32)
  assert(ok)

  state.renderer.bloom_on = true
  state.renderer.draw_debug = true

  return ok
}

begin_render_frame :: proc() -> (ok: bool)
{
  // TODO: Resize render targets to window size if changed
  hot_reload_shaders(&state.renderer.pipelines)

  ok = vk_begin_render_frame()

  if ok
  {
    // Write out frame uniforms
    projection := camera_perspective(state.camera, window_aspect_ratio(state.window))
    view       := camera_view(state.camera)

    frame := &state.renderer.uniform_buffer[curr_frame_idx()].cpu_base[0]
    frame^ =
    {
      projection      = projection,
      view            = view,
      proj_view       = projection * view,
      camera_position = vec4_from_3(state.camera.position),
      z_near          = state.camera.z_near,
      z_far           = state.camera.z_far,
      sun_light       = direction_light_uniform(state.sun),
      flash_light     = spot_light_uniform(state.flashlight),
      skybox_index    = get_texture(state.skybox).index,
    }

    for pl in state.point_lights
    {
      // Try to add shadow casting to the shadow casting array first
      if pl.cast_shadows && frame.shadow_points_count <= MAX_SHADOW_POINT_LIGHTS
      {
        idx := frame.shadow_points_count
        frame.shadow_point_lights[idx] = shadow_point_light_uniform(pl)
        frame.shadow_points_count += 1
      }
      else
      {
        // If we had too many try to add to the normal point lights
        if pl.cast_shadows
        {
          log.errorf("Too many shadow casting point lights! Attempting to add to non shadow casting lights.")
        }

        if frame.points_count <= MAX_POINT_LIGHTS
        {
          idx := frame.points_count
          frame.point_lights[idx] = point_light_uniform(pl)
          frame.points_count += 1
        }
        else
        {
          log.errorf("Too many point lights! Ignoring.")
        }
      }
    }

    // Do any queued uploads
    vk_do_uploads(state.renderer.upload_queue)
    clear(&state.renderer.upload_queue)
    state.renderer.frame_began = true
  }

  return ok
}

// NOTE: Will use the very first attachment
flush_render_frame :: proc(to_display: Texture)
{
  state.renderer.staging_tails[curr_frame_idx()] = state.renderer.staging_offset

  state.renderer.immediate.vertex_count = 0
  clear(&state.renderer.immediate.batches)
  append(&state.renderer.immediate.batches, Immediate_Batch{})

  state.renderer.draw_count = 0
  state.renderer.draw_head  = 0

  vk_flush_render_frame(to_display)
  state.renderer.frame_began = false
}

@(private="file")
push_to_staging :: proc(data: []$Type) -> (staging_offset, byte_size: int)
{
  byte_size = len(data) * size_of(Type)

  tail := state.renderer.staging_tails[curr_frame_idx()]

  // No room from here to the end of the physical buffer... check if we can potentially wrap around
  if state.renderer.staging_offset + byte_size >= state.renderer.staging_buffer.count
  {
    // If our tail is behind us and there's room, wrap
    if byte_size < tail
    {
      state.renderer.staging_offset = 0
    }
    else
    {
      panic("Unable to push anything more to GPU staging buffer!")
    }
  }
  else if state.renderer.staging_offset < tail && state.renderer.staging_offset + byte_size >= tail
  {
    panic("Unable to push anything more to GPU staging buffer!")
  }

  staging_ptr := uintptr(state.renderer.staging_buffer.cpu_base) + uintptr(state.renderer.staging_offset)
  mem.copy(rawptr(staging_ptr), raw_data(data), byte_size)

  staging_offset = state.renderer.staging_offset

  state.renderer.staging_offset += byte_size

  return staging_offset, byte_size
}

@(private="file")
queue_buffer_upload :: proc(data: []$Type, dst: GPU_Buffer(Type), dst_offset: int)
{
  staging_offset, byte_size := push_to_staging(data)
  byte_offset := dst_offset * size_of(Type)

  upload: GPU_Upload =
  {
    src_buffer = state.renderer.staging_buffer,
    src_offset = staging_offset,
    dst        = gpu_buffer_as_bytes(dst),
    dst_offset = byte_offset,
    size       = byte_size,
  }

  ensure(append(&state.renderer.upload_queue, upload) == 1)
}

upload_texture :: proc(datas: [][]byte, dst: Texture)
{
  assert(len(datas) == int(dst.array_count))

  staging_offset := -1
  byte_size: int
  for data in datas
  {
    offset, part_size := push_to_staging(data)
    byte_size += part_size
    if staging_offset == -1 { staging_offset = offset }
  }

  upload: GPU_Upload =
  {
    src_buffer = state.renderer.staging_buffer,
    src_offset = staging_offset,
    dst        = dst,
    size       = byte_size,
  }

  ensure(append(&state.renderer.upload_queue, upload) == 1)
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

    for &material, idx in materials
    {
      uniforms[idx] = material_uniform(material)
      material.buffer_index = u32(idx + state.renderer.material_count)
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
    state.renderer.draw_commands[curr_frame_idx()].cpu_base[state.renderer.draw_count] = command
    state.renderer.draw_uniforms[curr_frame_idx()].cpu_base[state.renderer.draw_count] = uniform

    state.renderer.draw_count += 1
  }
  else
  {
    log.errorf("Cannot push any more draw commands.");
  }
}

mega_draw :: proc()
{
  bind_pipeline_key(.PHONG)

  push: Mega_Push =
  {
    frame_uniform     = state.renderer.uniform_buffer[curr_frame_idx()].gpu_base,
    draw_uniforms     = &state.renderer.draw_uniforms[curr_frame_idx()].gpu_base[state.renderer.draw_head],
    vertices          = state.renderer.vertex_buffer.gpu_base,
    material_uniforms = state.renderer.material_buffer.gpu_base,
  }

  batch_count := u32(state.renderer.draw_count - state.renderer.draw_head)
  vk_draw_indirect(state.renderer.index_buffer, state.renderer.draw_commands[curr_frame_idx()], u32(state.renderer.draw_head), batch_count, push)

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
          transform = transform,
          vertices  = state.renderer.immediate.vertex_buffer[curr_frame_idx()].gpu_base,
          texture   = get_texture(batch.texture).index,
        }
        vk_draw_vertices(batch.vertex_base, batch.vertex_count, push)
      }
    }
  }
}

draw_skybox :: proc(handle: Texture_Handle)
{
  bind_pipeline(.SKYBOX)

  // TODO: Eventually, keeping the depth func on less and not temporarily switching to lequal will cause issues.
  push := Skybox_Push{frame_uniform = state.renderer.uniform_buffer[curr_frame_idx()].gpu_base}
  vk_draw_vertices(0, 36, push)
}
