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

  state.main_context = context

  state.perm_mem = make([]byte, mem.Megabyte * 256)
  mem.arena_init(&state.perm, state.perm_mem)
  state.perm_alloc = mem.arena_allocator(&state.perm)

  state.mode = .EDIT // Edit by default

  state.window = make_window(WINDOW_DEFAULT_W, WINDOW_DEFAULT_H,
                             WINDOW_DEFAULT_TITLE, BACKEND) or_return

  switch BACKEND
  {
    case .OPENGL:
      init_opengl(state.window)
    case .VULKAN:
      init_vulkan(state.window)
  }

  // Make the meta shader
  gen_glsl_code()

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

  state.running = true

  state.shaders[.PHONG]       = make_shader_program("simple.vert", "phong.frag",  allocator=state.perm_alloc) or_return
  state.shaders[.SKYBOX]      = make_shader_program("skybox.vert", "skybox.frag", allocator=state.perm_alloc) or_return
  state.shaders[.RESOLVE_HDR] = make_shader_program("to_screen.vert", "resolve_hdr.frag", allocator=state.perm_alloc) or_return
  state.shaders[.SUN_DEPTH]   = make_shader_program("sun_shadow.vert", "sun_shadow.frag", allocator=state.perm_alloc) or_return
  state.shaders[.POINT_DEPTH] = make_shader_program("point_shadows.vert", "point_shadows.frag", allocator=state.perm_alloc) or_return
  state.shaders[.GAUSSIAN]    = make_shader_program("to_screen.vert", "gaussian.frag", allocator=state.perm_alloc) or_return
  state.shaders[.GET_BRIGHT]  = make_shader_program("to_screen.vert", "get_bright_spots.frag", allocator=state.perm_alloc) or_return

  state.samplers = make_samplers()

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

  state.draw_debug = true

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

  init_entities()

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

  GRID_SIZE :: 20
  GRID_SPACING :: 5
  for x in 0..<GRID_SIZE
  {
    for y in 0..<GRID_SIZE
    {
      for z in 0..<GRID_SIZE
      {
        pos := vec3{
          f32(x) * GRID_SPACING - (GRID_SIZE * GRID_SPACING / 2) + 100,
          f32(y) * GRID_SPACING - (GRID_SIZE * GRID_SPACING / 2),
          f32(z) * GRID_SPACING - (GRID_SIZE * GRID_SPACING / 2) - 100,
        }
        block := make_entity("cube/BoxTextured.gltf", flags={.RENDERABLE}, position=pos)
      }
    }
  }

  for pos in DEFAULT_MODEL_POSITIONS
  {
    make_entity("cube/BoxTextured.gltf", position=pos - {20,0,30})
  }

  make_entity("cube/BoxTextured.gltf", flags={.COLLISION, .RENDERABLE, .STATIC}, position={0, -8, 0}, scale={1000.0, 1.0, 1000.0})

  make_entity("cube/BoxTextured.gltf", position={0, -2, -30}, scale={10.0, 10.0, 10.0})

  make_entity("helmet2/SciFiHelmet.gltf", position={10.0, 0.0, 0.0})

  make_entity("guitar/scene.gltf", position={5.0, 0.0, 4.0}, scale={0.01, 0.01, 0.01})

  make_entity("lantern/Lantern.gltf", position={-20, -8.0, 0}, scale={0.5, 0.5, 0.5})

  make_point_light_entity({1, 1, 1}, RED, 30, 1.0, cast_shadows=true)

  make_point_light_entity({5, 1, -5}, GREEN, 30, 1.0, cast_shadows=true)

  make_point_light_entity({-5, 1, -10}, BLUE, 30, 1.0, cast_shadows=true)

  sponza_handle := make_entity("sponza/Sponza.gltf", flags={.RENDERABLE}, position={20, -2.0 ,-60}, scale={2.0, 2.0, 2.0})

  // Sponza lights
  {
    sponza := get_entity(sponza_handle)
    spacing := 20
    bounds  := 4
    y_bounds := bounds/2
    for x in 0..<bounds
    {
      for y in 0..<y_bounds
      {
        x0 := (x - bounds/2) * spacing
        y0 := y * spacing / 2 + 1

        position := vec3{sponza.position.x + f32(x0), sponza.position.y + f32(y0), sponza.position.z}
        color    := vec4{rand.float32() * 10.0, rand.float32() * 10.0, rand.float32() * 10.0, 1.0}

        make_point_light_entity(position, color, 10, 1.0, cast_shadows=false)
      }
    }
  }

  make_entity("helmet/DamagedHelmet.gltf", position={-5.0, 0.0, 0.0})

  make_entity("duck/Duck.gltf", position={5.0, 0.0, -10.0})

  make_entity("duck/Duck.gltf", position={5.0, 0.0, -5.0})

  // Clean up temp allocator from initialization... fresh for per-frame allocations
  free_all(context.temp_allocator)

  last_frame_time := time.tick_now()
  dt_s := 0.0
  for (!should_close(state.window))
  {
    // Resize check, this
    if state.window.should_resize
    {
      if (!resize_window(&state.window))
      {
        break
      }
    }

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

    poll_input_state(dt_s)

    if key_pressed(.ESCAPE)
    {
      toggle_menu()
    }

    if key_pressed(.F1)
    {
      state.draw_debug = !state.draw_debug
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
      state.bloom_on = !state.bloom_on
    }

    // 'Simulate' (not really doing much right now) if in game mode
    if state.mode == .GAME
    {
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

    }

    if state.mode == .EDIT
    {
      do_editor(&state.camera, dt_s)
    }

    //
    // Update entities with point lights, AFTER we do everything else
    //
    for e in all_entities()
    {
      if e.point_light != nil
      {

        // Check if the point light has moved
        if e.point_light.position != e.position
        {
          e.point_light.dirty_shadow = true
        }

        e.point_light.position = e.position
      }
    }


    // Frame sync and send all per frame uniform info
    begin_drawing()

    // What to draw based on mode
    switch state.mode
    {
    case .EDIT: fallthrough
    case .GAME:
      //
      // Shadow passes
      //
      if state.sun_on
      {
        begin_render_pass(SUN_SHADOW_PASS, state.sun_depth_buffer)
        bind_shader(.SUN_DEPTH)

        // TODO: Can do frustum culling on the sun's view point too!
        for e in all_entities()
        {
          draw_entity(e)
        }
        multi_draw(&state.mds)
      }

      if state.point_lights_on
      {
        begin_render_pass(POINT_SHADOW_PASS, state.point_depth_buffer)
        bind_shader(.POINT_DEPTH)

        shadow_light_idx := 0
        for &l in state.point_lights
        {
          // TODO if objects in the lights radius move, need to do recalc
          if l.cast_shadows
          {
            // We cache shadow maps and only recompute if point light has moved
            if l.dirty_shadow
            {

              // Clear the part of the texture corresponding to this light
              depth_clear: f32 = 1.0
              gl.ClearTexSubImage(state.point_depth_buffer.depth_target.id, 0, 0, 0,
                i32(6 * shadow_light_idx),
                512, 512, 6,
                gl.DEPTH_COMPONENT, gl.FLOAT, &depth_clear)

              // Cull models not in light's radius
              light_sphere: Sphere =
              {
                center = l.position,
                radius = l.radius,
              }
              for e in all_entities()
              {
                if sphere_intersects_aabb(light_sphere, entity_world_aabb(e))
                {
                  draw_entity(e, instances=6, light_index = cast(u32)shadow_light_idx)
                }
              }

              l.dirty_shadow = false
            }

            shadow_light_idx += 1
          }
        }

        multi_draw(&state.mds)
      }

      //
      // Main Geometry Pass
      //
      begin_render_pass(MAIN_PASS, state.hdr_ms_buffer)
      {
        bind_shader(.PHONG)

        if state.sun_on
        {
          bind_texture("skybox", get_texture(state.skybox)^)
        }
        else
        {
          bind_texture("skybox", Texture{})
        }
        bind_texture("sun_shadow_map", state.sun_depth_buffer.depth_target)
        bind_texture("point_light_shadows", state.point_depth_buffer.depth_target)

        // Frustum Culling!
        frustum := make_frustum(state.camera, window_aspect_ratio(state.window), state.camera.z_near, state.camera.z_far)
        frustum_entities := make([dynamic]^Entity, context.temp_allocator)
        for &e in all_entities()
        {
          aabb := entity_world_aabb(e)
          sphere := make_sphere(aabb)

          if sphere_inside_frustum(sphere, frustum)
          {
            append(&frustum_entities, &e)
          }
        }

        // Go through and draw opque entities, collect transparent entities
        transparent_entities := make([dynamic]^Entity, context.temp_allocator)
        for e in frustum_entities
        {
          if entity_has_transparency(e^)
          {
              append(&transparent_entities, e)
              continue
          }

          // We're good we can just draw opaque entities
          draw_entity(e^, draw_aabbs=state.draw_debug)
        }
        // multi_draw(&state.mds)

        // Transparent models
        bind_shader(.PHONG)
        // Sort so that further entities get drawn first
        slice.sort_by(transparent_entities[:], proc(a, b: ^Entity) -> bool {
          da := squared_distance(a.position, state.camera.position)
          db := squared_distance(b.position, state.camera.position)
          return da > db
        })
        for e in transparent_entities
        {
          draw_entity(e^)
        }
        multi_draw(&state.mds)

        // Skybox here so it is seen behind transparent objects, binds its own shader
        if state.sun_on {
          draw_skybox(state.skybox)
        }

        // Draw point light billboards
        if state.point_lights_on
        {
          for l in state.point_lights
          {
            w: f32 = 1.0
            h: f32 = 1.0
            normal := normalize(l.position - state.camera.position) // Billboard it!
            draw_quad(l.position, normal, w, h, l.color, uv0=vec2{0,1},uv1=vec2{1,0}, texture=load_texture("point_light.png"))
          }
        }

        if state.draw_debug
        {
          draw_grid(color = {1.0, 1.0, 1.0, 0.2})
        }

        // Flush any accumulated 3D draw calls
        immediate_flush(flush_world=true, flush_screen=false)
      }

      //
      // Post-Processing Pass
      //
      begin_render_pass(POST_PASS, state.post_buffer)
      {
        // Resolve multi-sampling buffer to post_buffer
        blit_framebuffers(state.hdr_ms_buffer, state.post_buffer)
        //
        // Bloom
        //
        BLOOM_GAUSSIAN_COUNT :: 5
        if state.bloom_on
        {
          // Now collect bright spots
          bind_framebuffer(state.ping_pong_buffers[0])
          bind_shader(.GET_BRIGHT)
          bind_texture("image", state.post_buffer.color_targets[0])
          draw_screen_quad()

          // Now do the blur
          bind_shader(.GAUSSIAN)

          // Begin ping ponging
          bind_framebuffer(state.ping_pong_buffers[1])
          bind_texture("image", state.ping_pong_buffers[0].color_targets[1]) // The bright spot texture
          horizontal := true

          for _ in 0..<BLOOM_GAUSSIAN_COUNT
          {
            set_shader_uniform("horizontal", horizontal)
            draw_screen_quad()

            horizontal = !horizontal
            read_index  := 0 if horizontal else 1
            write_index := 1 - read_index

            bind_texture("image", state.ping_pong_buffers[read_index].color_targets[0])
            bind_framebuffer(state.ping_pong_buffers[write_index])
          }
        }
      }

      begin_render_pass(UI_PASS, {})
      {
        // Resolve hdr (with bloom) to backbuffer
        bind_shader(.RESOLVE_HDR)
        bind_texture("screen_texture", state.post_buffer.color_targets[0])
        bind_texture("bloom_blur", state.ping_pong_buffers[0].color_targets[0])
        draw_screen_quad()

        if state.draw_debug
        {
          draw_debug_stats()
        }

        draw_ui()

        // Flush any accumulated 2D or screen space draws
        immediate_flush(flush_world=false, flush_screen=true)
      }

    case .MENU:
      update_menu_input()
      draw_menu()
    }

    // Frame sync, swap backbuffers, reset immediate batches
    flush_drawing()

    // Free any temp allocations
    free_all(context.temp_allocator)
  }
}

free_state :: proc()
{
  free_immediate_renderer()

  free_assets()

  free_gpu_buffer(&state.frame_uniforms)

  for &shader in state.shaders
  {
    free_shader_program(&shader)
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
