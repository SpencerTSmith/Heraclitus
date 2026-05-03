package main

import "core:mem"
import "core:time"
import "core:log"
import "base:runtime"

// TODO: Probably split game specific things from rendering specific things
State :: struct {
  main_context: runtime.Context,

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

  state.mode = .EDIT

  state.window = make_window() or_return

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
    direction = {0.5, -1.0,  0.0},
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
  state.flashlight_on = false

  init_entities()
  init_assets()

  init_renderer()

  load_default_assets()

  state.default_font = make_font("Diablo_Light.ttf", DEFAULT_FONT_SIZE)

  init_menu()

  cube_map_sides: [6]string =
  {
    "skybox/right.jpg",
    "skybox/left.jpg",
    "skybox/top.jpg",
    "skybox/bottom.jpg",
    "skybox/front.jpg",
    "skybox/back.jpg",
  }
  state.skybox = load_skybox(cube_map_sides)

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

  make_entity("sponza/Sponza.gltf", flags={.RENDERABLE}, position={20, -2.0 ,-60}, scale={1.0, 1.0, 1.0})

  make_entity("duck/Duck.gltf", position={5.0, 0.0, -10.0})

  for pos in DEFAULT_MODEL_POSITIONS
  {
    make_entity("cube/BoxTextured.gltf", position=pos)
  }

  make_entity("helmet/DamagedHelmet.gltf", position={-5.0, 0.0, 0.0})

  make_entity("cube/BoxTextured.gltf", flags={.COLLISION, .RENDERABLE, .STATIC}, position={0, -508, 0}, scale={1000.0, 1000.0, 1000.0})

  make_entity("helmet2/SciFiHelmet.gltf", position={10.0, 0.0, 0.0})

  make_entity("lantern/Lantern.gltf", position={-20, -8.0, 0}, scale={0.5, 0.5, 0.5})

  make_point_light_entity({1, 1, 1}, RED, 30, 1.0, cast_shadows=true)

  make_point_light_entity({5, 1, -5}, GREEN, 30, 1.0, cast_shadows=true)

  make_point_light_entity({-5, 1, -10}, BLUE, 30, 1.0, cast_shadows=true)

  // GRID_SIZE :: 20
  // GRID_SPACING :: 5
  // for x in 0..<GRID_SIZE
  // {
  //   for y in 0..<GRID_SIZE
  //   {
  //     for z in 0..<GRID_SIZE
  //     {
  //       pos := vec3{
  //         f32(x) * GRID_SPACING - (GRID_SIZE * GRID_SPACING / 2) + 100,
  //         f32(y) * GRID_SPACING - (GRID_SIZE * GRID_SPACING / 2) + 100,
  //         f32(z) * GRID_SPACING - (GRID_SIZE * GRID_SPACING / 2) - 100,
  //       }
  //       make_entity("cube/BoxTextured.gltf", flags={.RENDERABLE}, position=pos)
  //     }
  //   }
  // }

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

    state.tick_count += 1
    last_frame_time = time.tick_now()

    poll_input_state(state.window, dt_s)

    if key_pressed(.ESCAPE)
    {
      toggle_menu()
    }

    if key_pressed(.F1)
    {
      state.renderer.draw_debug = !state.renderer.draw_debug
    }

    if key_pressed(.TAB)
    {
      state.mode = .EDIT if state.mode == .GAME else .GAME
    }

    if key_pressed(.L)
    {
      state.sun_on = !state.sun_on
    }
    if key_pressed(.P)
    {
      state.point_lights_on = !state.point_lights_on
    }
    if key_pressed(.F)
    {
      state.flashlight_on = !state.flashlight_on
    }

    if key_pressed(.B)
    {
      state.renderer.bloom_on = !state.renderer.bloom_on
    }

    if key_down(.M)
    {
      state.sun.direction.x += 0.25 * f32(dt_s)
    }
    if key_down(.N)
    {
      state.sun.direction.x -= 0.25 * f32(dt_s)
    }
    if key_down(.J)
    {
      state.sun.direction.z += 0.25 * f32(dt_s)
    }
    if key_down(.K)
    {
      state.sun.direction.z -= 0.25 * f32(dt_s)
    }

    // UPDATE
    switch state.mode
    {
      case .GAME:
        move_camera_game(&state.camera, dt_s)
        state.flashlight.position  = state.camera.position
        state.flashlight.direction = camera_forward(state.camera)

        //
        // Collision
        //
        for &e in all_entities()
        {
          if .STATIC in e.flags { continue } // Static things should not be movable
          if .COLLISION not_in e.flags { continue }

          entity_aabb := entity_world_aabb(e)

          for &o in all_entities()
          {
            if &o == &e { continue } // Same entity

            if .COLLISION not_in o.flags
            { continue }

            other_aabb := entity_world_aabb(o)

            if aabbs_intersect(entity_aabb, other_aabb)
            {
              min_pen := aabb_min_penetration_vector(entity_aabb, other_aabb)

              e.position += min_pen
            }
          }
        }
      case .EDIT:
        do_editor(&state.camera, dt_s)
      case .MENU:
        update_menu()
    }

    for &e in all_entities()
    {
      if e.point_light != nil
      {
        e.point_light.position = e.position
      }
    }

    // RENDER
    if begin_render_frame()
    {
      defer flush_render_frame(state.renderer.post_target)

      switch state.mode
      {
        case .GAME, .EDIT:
          if state.sun_on
          {
            begin_render_pass(SUN_SHADOW_PASS, &state.renderer.sun_shadow_target)
            {
              defer end_render_pass()

              for cascade in 0..<CASCADE_COUNT
              {
                set_render_viewport(CASCADE_VIEWPORTS[cascade])
                for e in all_entities()
                {
                  draw_entity(e)
                }
                mega_draw(.SUN_DEPTH, cascade_index=u32(cascade))
              }
            }
          }

          begin_render_pass(MAIN_PASS, &state.renderer.main_target, sampled={&state.renderer.sun_shadow_target})
          {
            defer end_render_pass()

            for e in all_entities()
            {
              draw_entity(e)
            }
            mega_draw(.PHONG)

            draw_skybox(state.skybox)

            // Draw point light billboards
            if state.point_lights_on
            {
              for l in state.point_lights
              {
                // Billboard it!
                draw_quad(l.position, l.position - state.camera.position, 1, 1, l.color, uv0=vec2{0,1},uv1=vec2{1,0}, texture=load_texture("point_light.png"))
              }
            }

            immediate_flush(.WORLD)
          }

          begin_render_pass(UI_PASS, &state.renderer.post_target, blit_source=&state.renderer.main_target)
          {
            defer end_render_pass()

            draw_debug_stats()
            draw_ui()

            immediate_flush(.SCREEN)
          }
        case .MENU:
          draw_menu()
      }

    }

    free_all(context.temp_allocator)
  }
}

free_state :: proc()
{
  free_assets()

  free_vulkan()

  free_window(&state.window)

  log.infof("Arena Size at closedown: %v", state.perm.peak_used)
  delete(state.perm_mem)
}

seconds_since_start :: proc() -> (seconds: f64)
{
  return time.duration_seconds(time.since(state.start_time))
}
