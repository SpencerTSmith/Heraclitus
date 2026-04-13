package main

import "core:math/rand"
import "core:mem"
import "core:time"
import "core:slice"
import "core:log"
import "base:runtime"
import gl "vendor:OpenGL"

import "vendor:glfw"

// TODO: Probably split game specific things from rendering specific things
State :: struct {
  main_context :runtime.Context,

  running: bool,

  mode: Program_Mode,

  window: Window,

  perm_mem:   []byte,
  perm:       mem.Arena,
  perm_alloc: mem.Allocator,

  camera: Camera,

  entities: Entities,

  point_lights: [dynamic; MAX_POINT_LIGHTS + MAX_SHADOW_POINT_LIGHTS]Point_Light,

  start_time: time.Time,

  // TODO: Hmm maybe should be enum array, these must all be the same dimensions as backbuffer
  // so simple to loop over enum array when resizing window
  hdr_ms_buffer:      Framebuffer,
  post_buffer:        Framebuffer,
  ping_pong_buffers:  [2]Framebuffer,

  point_depth_buffer: Framebuffer,
  sun_depth_buffer:   Framebuffer,

  fps:              f64,
  frame_count:      int,
  frames:           [FRAMES_IN_FLIGHT]Frame_Info,
  curr_frame_index: int,

  began_drawing: bool,

  sun: Direction_Light,

  flashlight:Spot_Light,

  sun_on:          bool,
  flashlight_on:   bool,
  point_lights_on: bool,

  // Could maybe replace this but this makes it easier to add them
  shaders: [Shader_Tag]Shader_Program,

  samplers: [Sampler_Preset]u32,

  skybox: Texture_Handle,

  frame_uniforms: GPU_Buffer,

  mds: Multi_Draw_State,

  // TODO: Maybe these should be pointers and not copies
  current_shader:   Shader_Program,
  bound_textures:   [16]Texture,

  input: Input_State,

  draw_debug:   bool,
  default_font: Font,

  bloom_on: bool,
}

// NOTE: Global
state: State

BACKEND :: Render_Backend.VULKAN

init_state :: proc() -> (ok: bool)
{
  state.start_time = time.now()

  state.running = true

  state.main_context = context

  state.perm_mem = make([]byte, mem.Megabyte * 256)
  mem.arena_init(&state.perm, state.perm_mem)
  state.perm_alloc = mem.arena_allocator(&state.perm)

  state.mode = .EDIT // Edit by default

  state.window = make_window(WINDOW_DEFAULT_W, WINDOW_DEFAULT_H,
                             WINDOW_DEFAULT_TITLE, BACKEND) or_return

  state.camera =
  {
    sensitivity  = 0.2,
    yaw          = 270.0,
    z_near       = 0.1,
    z_far        = 1000.0,
    position     = {0.0, 0.0, 5.0},
    curr_fov_y   = 90.0,
    target_fov_y = 90.0,
    aabb         = {{-1.0, -4.0, -1.0}, {1.0, 1.0, 1.0},},
  }

  state.point_lights_on = true

  state.sun =
  {
    direction = {0.5, -1.0,  0.7},
    color     = {0.8,  0.7,  0.6, 1.0},
    intensity = 1.0,
    ambient   = 0.05,
  }
  state.sun.direction = normalize(state.sun.direction)
  state.sun_on = true

  state.bloom_on = true

  state.flashlight =
  {

    direction = {0.0, 0.0, -1.0},
    position  = state.camera.position,

    color     = {0.3, 0.8,  1.0, 1.0},

    radius    = 50.0,
    intensity = 1.0,
    ambient   = 0.001,

    inner_cutoff = cos(radians(cast(f32)12.5)),
    outer_cutoff = cos(radians(cast(f32)17.5)),
  }
  state.flashlight_on = true

  state.draw_debug = true

  init_entities()

  switch BACKEND
  {
    case .OPENGL:
      init_opengl(state.window)

      // Make the meta shader
      gen_glsl_code()

      state.shaders[.PHONG]       = make_shader_program("simple.vert", "phong.frag",  allocator=state.perm_alloc) or_return
      state.shaders[.SKYBOX]      = make_shader_program("skybox.vert", "skybox.frag", allocator=state.perm_alloc) or_return
      state.shaders[.RESOLVE_HDR] = make_shader_program("to_screen.vert", "resolve_hdr.frag", allocator=state.perm_alloc) or_return
      state.shaders[.SUN_DEPTH]   = make_shader_program("sun_shadow.vert", "sun_shadow.frag", allocator=state.perm_alloc) or_return
      state.shaders[.POINT_DEPTH] = make_shader_program("point_shadows.vert", "point_shadows.frag", allocator=state.perm_alloc) or_return
      state.shaders[.GAUSSIAN]    = make_shader_program("to_screen.vert", "gaussian.frag", allocator=state.perm_alloc) or_return
      state.shaders[.GET_BRIGHT]  = make_shader_program("to_screen.vert", "get_bright_spots.frag", allocator=state.perm_alloc) or_return

      state.samplers = make_samplers()

      SAMPLES :: 4
      state.hdr_ms_buffer = make_framebuffer(state.window.w, state.window.h, SAMPLES, attachments={.HDR_COLOR, .DEPTH_STENCIL}) or_return

      state.post_buffer = make_framebuffer(state.window.w, state.window.h, attachments={.HDR_COLOR, .DEPTH_STENCIL}) or_return

      // This will have two attachments so we can collect bright spots
      state.ping_pong_buffers[0] = make_framebuffer(state.window.w, state.window.h, attachments={.HDR_COLOR, .HDR_COLOR}) or_return
      state.ping_pong_buffers[1] = make_framebuffer(state.window.w, state.window.h, attachments={.HDR_COLOR}) or_return

      state.point_depth_buffer = make_framebuffer(POINT_SHADOW_MAP_SIZE, POINT_SHADOW_MAP_SIZE, array_depth=MAX_SHADOW_POINT_LIGHTS, attachments={.DEPTH_CUBE_ARRAY}) or_return
      state.sun_depth_buffer = make_framebuffer(SUN_SHADOW_MAP_SIZE, SUN_SHADOW_MAP_SIZE, attachments={.DEPTH}) or_return

      state.frame_uniforms = make_gpu_buffer(size_of(Frame_Uniform), flags = {.UNIFORM_DATA, .PERSISTENT, .FRAME_BUFFERED})

      state.mds = init_multi_draw()

      init_assets(state.perm_alloc)

      init_immediate_renderer(state.perm_alloc) or_return

      init_menu() or_return

      state.default_font = make_font("Diablo_Light.ttf", DEFAULT_FONT_SIZE) or_return

      cube_map_sides: [6]string =
      {
        "skybox/right.jpg",
        "skybox/left.jpg",
        "skybox/top.jpg",
        "skybox/bottom.jpg",
        "skybox/front.jpg",
        "skybox/back.jpg",
      }
      state.skybox = load_skybox(cube_map_sides) or_return

    case .VULKAN:
      init_vulkan(state.window)
  }

  return true
}

main :: proc()
{
  logger := log.create_console_logger()
  context.logger = logger
  defer log.destroy_console_logger(logger)

  when ODIN_DEBUG
  {
    track: mem.Tracking_Allocator
    mem.tracking_allocator_init(&track, context.allocator)
    context.allocator = mem.tracking_allocator(&track)

    defer
    {
      if len(track.allocation_map) > 0
      {
        log.errorf("=== %v allocations not freed: ===\n", len(track.allocation_map))
        for _, entry in track.allocation_map
        {
          log.errorf("- %v bytes @ %v\n", entry.size, entry.location)
        }
      }
      if len(track.bad_free_array) > 0
      {
        log.errorf("=== %v incorrect frees: ===\n", len(track.bad_free_array))
        for entry in track.bad_free_array
        {
          log.errorf("- %p @ %v\n", entry.memory, entry.location)
        }
      }
      mem.tracking_allocator_destroy(&track)
    }
  }

  if !init_state()
  {
    log.fatalf("Failed to initialize global state")
    return
  }
  defer free_state()


  last_frame_time := time.tick_now()
  dt_s := 0.0
  for !should_close(state.window)
  {
    // dt and sleeping
    if (time.tick_since(last_frame_time) < TARGET_FRAME_TIME_NS)
    {
      time.accurate_sleep(TARGET_FRAME_TIME_NS - time.tick_since(last_frame_time))
    }

    // New dt after sleeping
    dt_s = f64(time.tick_since(last_frame_time)) / BILLION

    state.fps = 1.0 / dt_s

    state.frame_count += 1
    last_frame_time = time.tick_now()

    poll_input_state(state.window, dt_s)

    begin_drawing()
    flush_drawing()
  }
}

free_state :: proc()
{
  switch BACKEND
  {
    case .OPENGL:
      free_immediate_renderer()

      free_assets()

      free_gpu_buffer(&state.frame_uniforms)

      for &shader in state.shaders
      {
        free_shader_program(&shader)
      }
    case .VULKAN:
      free_vulkan()
  }

  glfw.DestroyWindow(state.window.handle)
  // glfw.Terminate() // Causing crashes?
  log.infof("Arena Size at closedown: %v", state.perm.peak_used)
  delete(state.perm_mem)
}

seconds_since_start :: proc() -> (seconds: f64)
{
  return time.duration_seconds(time.since(state.start_time))
}
