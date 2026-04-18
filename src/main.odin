package main

import "core:mem"
import "core:time"
import "core:log"
import "base:runtime"

import "vendor:glfw"

Color_Push :: struct
{
  color:    vec4,
  vertices: rawptr,
}

// TODO: Probably split game specific things from rendering specific things
State :: struct {
  main_context :runtime.Context,

  running: bool,

  mode: Program_Mode,

  perm_mem:   []byte,
  perm:       mem.Arena,
  perm_alloc: mem.Allocator,

  camera: Camera,

  entities: Entities,

  point_lights:    [dynamic; MAX_POINT_LIGHTS + MAX_SHADOW_POINT_LIGHTS]Point_Light,
  point_lights_on: bool,

  start_time: time.Time,
  tick_count: u64,

  sun:    Direction_Light,
  sun_on: bool,

  flashlight:    Spot_Light,
  flashlight_on: bool,


  window: Window,
  input:  Input_State,
  fps:    f64,

  default_font: Font,
  skybox: Texture_Handle,

  renderer: Renderer
}

// NOTE: Global
state: State

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
                             WINDOW_DEFAULT_TITLE) or_return

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

  init_entities()
  init_renderer()

  init_assets()

  // init_menu() or_return
  //
  state.default_font = make_font("Diablo_Light.ttf", DEFAULT_FONT_SIZE) or_return
  //
  // cube_map_sides: [6]string =
  // {
  //   "skybox/right.jpg",
  //   "skybox/left.jpg",
  //   "skybox/top.jpg",
  //   "skybox/bottom.jpg",
  //   "skybox/front.jpg",
  //   "skybox/back.jpg",
  // }
  // state.skybox = load_skybox(cube_map_sides) or_return

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

  // for pos in DEFAULT_MODEL_POSITIONS
  // {
  //   make_entity("cube/BoxTextured.gltf", position=pos - {20,0,30})
  // }
  //
  // make_entity("cube/BoxTextured.gltf", flags={.COLLISION, .RENDERABLE, .STATIC}, position={0, -8, 0}, scale={1000.0, 1.0, 1000.0})
  //
  // make_entity("cube/BoxTextured.gltf", position={0, -2, -30}, scale={10.0, 10.0, 10.0})
  //
  // make_entity("helmet2/SciFiHelmet.gltf", position={10.0, 0.0, 0.0})

  // make_entity("guitar/scene.gltf", position={5.0, 0.0, 4.0}, scale={0.01, 0.01, 0.01})

  // make_entity("lantern/Lantern.gltf", position={-20, -8.0, 0}, scale={0.5, 0.5, 0.5})

  position := vec2{100, 100}

  main_target := make_render_target(u32(state.window.w), u32(state.window.h), {.COLOR})

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

    state.tick_count += 1
    last_frame_time = time.tick_now()

    poll_input_state(state.window, dt_s)

    move_camera_editor(&state.camera, dt_s)

    if begin_render_frame()
    {
      defer flush_render_frame(main_target.attachments[0])

      begin_render_pass({clear_color = LEARN_OPENGL_BLUE}, &main_target)
      {
        defer end_render_pass()

        immediate_begin(.TRIANGLES, {}, .SCREEN, .DISABLED)
        {
          defer immediate_flush(true, true)

          draw_quad(position, 100, 100, color=LEARN_OPENGL_ORANGE)
          draw_quad_world({0,0,-5}, {0,0,1}, 10, 10, texture=load_texture("missing.png"))
          draw_debug_stats()
        }
      }
    }

    free_all(context.temp_allocator)
  }
}

free_state :: proc()
{
  free_assets()

  free_vulkan()

  glfw.DestroyWindow(state.window.handle)
  // glfw.Terminate() // Causing crashes?
  log.infof("Arena Size at closedown: %v", state.perm.peak_used)
  delete(state.perm_mem)
}

seconds_since_start :: proc() -> (seconds: f64)
{
  return time.duration_seconds(time.since(state.start_time))
}
