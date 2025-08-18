package main

import "core:math"
import "core:math/rand"
import "core:mem"
import "core:mem/virtual"
import "core:strings"
import "core:time"
import "core:slice"
import "core:log"

import gl "vendor:OpenGL"
import "vendor:glfw"

State :: struct {
  running: bool,
  mode: Program_Mode,

  gl_is_initialized:  bool,

  window: Window,

  perm:       virtual.Arena,
  perm_alloc: mem.Allocator,

  camera: Camera,

  entities: [dynamic]Entity,

  point_lights: [dynamic]Point_Light,

  start_time: time.Time,

  hdr_ms_buffer:      Framebuffer,
  post_buffer:        Framebuffer,
  ping_pong_buffers:  [2]Framebuffer,
  point_depth_buffer: Framebuffer,

  fps:              f64,
  frame_count:      uint,
  frames:           [FRAMES_IN_FLIGHT]Frame_Info,
  curr_frame_index: int,

  began_drawing: bool,

  draw_calls: int,

  z_near: f32,
  z_far:  f32,

  sun:              Direction_Light,
  sun_depth_buffer: Framebuffer,

  flashlight:Spot_Light,

  sun_on:          bool,
  flashlight_on:   bool,
  point_lights_on: bool,

  // Could maybe replace this but this makes it easier to add them
  shaders: map[string]Shader_Program,

  skybox: Skybox,

  frame_uniforms: GPU_Buffer,

  texture_handles:       GPU_Buffer,
  texture_handles_count: int,

  // TODO: Maybe these should be pointers and not copies
  current_shader:   Shader_Program,
  current_material: Material,
  bound_textures:   [16]Texture,

  // NOTE: Needed to make draw calls, even if not using one
  empty_vao:          u32,

  input:              Input_State,

  draw_debug:   bool,
  default_font: Font,

  bloom_on: bool,
}

// NOTE: Global
state: State

init_state :: proc() -> (ok: bool) {
  state.start_time = time.now()

  if glfw.Init() != glfw.TRUE {
    log.fatal("Failed to initialize GLFW")
    return
  }

  state.mode = .GAME

  glfw.WindowHint(glfw.RESIZABLE, glfw.TRUE)
  glfw.WindowHint(glfw.OPENGL_FORWARD_COMPAT, glfw.TRUE)
  glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
  glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, GL_MAJOR)
  glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, GL_MINOR)

  state.window.handle = glfw.CreateWindow(WINDOW_DEFAULT_W, WINDOW_DEFAULT_H, WINDOW_DEFAULT_TITLE, nil, nil)
  if state.window.handle == nil {
    log.fatal("Failed to create GLFW window")
    return
  }

  state.window.w     = WINDOW_DEFAULT_W
  state.window.h     = WINDOW_DEFAULT_H
  state.window.title = WINDOW_DEFAULT_TITLE

  c_title := strings.clone_to_cstring(state.window.title, allocator = context.temp_allocator)
  defer free_all(context.temp_allocator)

  glfw.SetWindowTitle(state.window.handle, c_title)

  if glfw.RawMouseMotionSupported() {
    glfw.SetInputMode(state.window.handle, glfw.CURSOR, glfw.CURSOR_DISABLED)
    glfw.SetInputMode(state.window.handle, glfw.RAW_MOUSE_MOTION, 1)
  }

  glfw.MakeContextCurrent(state.window.handle)
  glfw.SwapInterval(1)

  glfw.SetFramebufferSizeCallback(state.window.handle, resize_window_callback)
  glfw.SetScrollCallback(state.window.handle, mouse_scroll_callback)

  gl.load_up_to(GL_MAJOR, GL_MINOR, glfw.gl_set_proc_address)

  //
  // Query GL extensions
  //
  needed_extensions := []string {
    "GL_ARB_shader_viewport_layer_array",
    "GL_ARB_bindless_texture",
  }

  extension_count: i32
  gl.GetIntegerv(gl.NUM_EXTENSIONS, &extension_count)
  for i in 0..<extension_count {
    have := gl.GetStringi(gl.EXTENSIONS, u32(i))

    for need in needed_extensions {
      if string(have) == need {
        log.infof("Necessary GL extension: %v is supported!", need)
      }
    }
  }

  gl.Enable(gl.MULTISAMPLE)

  gl.Enable(gl.DEPTH_TEST)

  gl.Enable(gl.CULL_FACE)
  gl.Enable(gl.TEXTURE_CUBE_MAP_SEAMLESS)

  gl.Enable(gl.BLEND)
  gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

  gl.Enable(gl.STENCIL_TEST)
  gl.StencilOp(gl.KEEP, gl.KEEP, gl.REPLACE)

  state.gl_is_initialized = true

  err := virtual.arena_init_growing(&state.perm)
  if err != .None {
    log.fatal("Failed to create permanent arena")
    return
  }
  state.perm_alloc = virtual.arena_allocator(&state.perm)

  init_assets()

  state.camera = {
    sensitivity  = 0.2,
    yaw          = 270.0,
    position     = {0.0, 0.0, 5.0},
    curr_fov_y   = 90.0,
    target_fov_y = 90.0,
    aabb         = {{-1.0, -4.0, -1.0}, {1.0, 1.0, 1.0},},
  }

  state.entities     = make([dynamic]Entity, state.perm_alloc)
  state.point_lights = make([dynamic]Point_Light, state.perm_alloc)

  state.running = true

  state.z_near = 0.1
  state.z_far  = 1000.0

  state.shaders = make(map[string]Shader_Program, allocator=state.perm_alloc)

  state.shaders["phong"]         = make_shader_program("simple.vert", "phong.frag",  allocator=state.perm_alloc) or_return
  state.shaders["skybox"]        = make_shader_program("skybox.vert", "skybox.frag", allocator=state.perm_alloc) or_return
  state.shaders["resolve_hdr"]   = make_shader_program("to_screen.vert", "resolve_hdr.frag", allocator=state.perm_alloc) or_return
  state.shaders["billboard"]     = make_shader_program("billboard.vert", "billboard.frag", allocator=state.perm_alloc) or_return
  state.shaders["sun_depth"]     = make_shader_program("sun_shadow.vert", "sun_shadow.frag", allocator=state.perm_alloc) or_return
  state.shaders["point_shadows"] = make_shader_program("point_shadows.vert", "point_shadows.frag", allocator=state.perm_alloc) or_return
  state.shaders["gaussian"]      = make_shader_program("to_screen.vert", "gaussian.frag", allocator=state.perm_alloc) or_return
  state.shaders["get_bright"]    = make_shader_program("to_screen.vert", "get_bright_spots.frag", allocator=state.perm_alloc) or_return

  state.sun = {
    direction = {-0.5, -1.0,  0.7},
    color     = { 0.8,  0.7,  0.6, 1.0},
    intensity = 1.0,
    ambient   = 0.05,
  }
  state.sun.direction = normalize(state.sun.direction)
  state.sun_on = true

  state.bloom_on = true

  state.flashlight = {

    direction = {0.0, 0.0, -1.0},
    position  = state.camera.position,

    color     = {0.3, 0.8,  1.0, 1.0},

    radius    = 50.0,
    intensity = 1.0,
    ambient   = 0.001,

    inner_cutoff = math.cos(math.to_radians_f32(12.5)),
    outer_cutoff = math.cos(math.to_radians_f32(17.5)),
  }
  state.flashlight_on = false

  SAMPLES :: 4
  state.hdr_ms_buffer = make_framebuffer(state.window.w, state.window.h, SAMPLES, attachments={.HDR_COLOR, .DEPTH_STENCIL}) or_return

  state.post_buffer = make_framebuffer(state.window.w, state.window.h, attachments={.HDR_COLOR, .HDR_COLOR, .DEPTH_STENCIL}) or_return

  state.ping_pong_buffers[0] = make_framebuffer(state.window.w, state.window.h, attachments={.HDR_COLOR, .DEPTH_STENCIL}) or_return
  state.ping_pong_buffers[1] = make_framebuffer(state.window.w, state.window.h, attachments={.HDR_COLOR, .DEPTH_STENCIL}) or_return

  state.point_depth_buffer = make_framebuffer(POINT_SHADOW_MAP_SIZE, POINT_SHADOW_MAP_SIZE, array_depth=MAX_POINT_LIGHTS, attachments={.DEPTH_CUBE_ARRAY}) or_return

  state.frame_uniforms = make_gpu_buffer(.UNIFORM, size_of(Frame_UBO), persistent=true)

  // For bindless textures!
  state.texture_handles = make_gpu_buffer(.STORAGE, size_of(u64) * MAX_TEXTURE_HANDLES, persistent=true)
  bind_gpu_buffer_base(state.texture_handles, .TEXTURES)

  cube_map_sides := [6]string{
    "skybox/right.jpg",
    "skybox/left.jpg",
    "skybox/top.jpg",
    "skybox/bottom.jpg",
    "skybox/front.jpg",
    "skybox/back.jpg",
  }
  state.skybox = make_skybox(cube_map_sides) or_return

  gl.CreateVertexArrays(1, &state.empty_vao)

  init_immediate_renderer() or_return

  init_menu() or_return

  state.draw_debug = true

  state.default_font = make_font("Diablo_Light.ttf", 30.0) or_return

  return true
}

main :: proc() {
  logger := log.create_console_logger()
  context.logger = logger
  defer log.destroy_console_logger(logger)

  when ODIN_DEBUG {
    track: mem.Tracking_Allocator
    mem.tracking_allocator_init(&track, context.allocator)
    context.allocator = mem.tracking_allocator(&track)

    defer {
      if len(track.allocation_map) > 0 {
        log.errorf("=== %v allocations not freed: ===\n", len(track.allocation_map))
        for _, entry in track.allocation_map {
          log.errorf("- %v bytes @ %v\n", entry.size, entry.location)
        }
      }
      if len(track.bad_free_array) > 0 {
        log.errorf("=== %v incorrect frees: ===\n", len(track.bad_free_array))
        for entry in track.bad_free_array {
          log.errorf("- %p @ %v\n", entry.memory, entry.location)
        }
      }
      mem.tracking_allocator_destroy(&track)
    }
  }

  if !init_state() do return
  defer free_state()

  block := make_entity("cube/BoxTextured.gltf", position={0, -2, -20}, scale={10.0, 10.0, 10.0})
  append(&state.entities, block)

  floor := make_entity("cube/BoxTextured.gltf", position={0, -4, 0}, scale={1000.0, 1.0, 1000.0})
  append(&state.entities, floor)

  duck1 := make_entity("duck/Duck.gltf", position={5.0, 0.0, -10.0})
  append(&state.entities, duck1)

  duck2 := make_entity("duck/Duck.gltf", position={5.0, 0.0, -5.0})
  append(&state.entities, duck2)

  helmet := make_entity("helmet/DamagedHelmet.gltf", position={-5.0, 0.0, 0.0})
  append(&state.entities, helmet)

  helmet2 := make_entity("helmet2/SciFiHelmet.gltf", position={5.0, 0.0, 0.0})
  append(&state.entities, helmet2)

  guitar := make_entity("guitar/scene.gltf", position={5.0, 0.0, 0.0}, scale={0.01, 0.01, 0.01})
  append(&state.entities, guitar)

  sponza := make_entity("sponza/Sponza.gltf", flags={.HAS_RENDERABLE}, position={60, -2.0 ,-60}, scale={2.0, 2.0, 2.0})
  append(&state.entities, sponza)

  // Sponza lights
  {
    spacing := 20
    bounds  := 4
    y_bounds := bounds/2
    for x in 0..<bounds {
      for y in 0..<y_bounds {
        x0 := (x - bounds/2) * spacing
        y0 := y * spacing / 2 + 1

        append(&state.point_lights, Point_Light{
          position  = {sponza.position.x + f32(x0), sponza.position.y + f32(y0), sponza.position.z},
          color     = {rand.float32() * 15.0, rand.float32() * 15.0, rand.float32() * 15.0, 1.0},
          intensity = 0.7,
          ambient   = 0.001,
          radius    = 10,
        })
      }
    }
  }

  lantern := make_entity("lantern/Lantern.gltf", position={-20, -8.0, 0}, scale={0.5, 0.5, 0.5})
  append(&state.entities, lantern)

  chess := make_entity("chess/ABeautifulGame.gltf", position={-20, -4.0, 5.0})
  append(&state.entities, chess)

  light_material,_ := make_material("point_light.png", blend=.BLEND, in_texture_dir=true)
  light_model,_ := make_model(DEFAULT_SQUARE_VERT, DEFAULT_SQUARE_INDX, light_material)
  defer free_model(&light_model)

  sun_depth_buffer,_ := make_framebuffer(SUN_SHADOW_MAP_SIZE, SUN_SHADOW_MAP_SIZE, attachments={.DEPTH})

  // Clean up temp allocator from initialization... fresh for per-frame allocations
  free_all(context.temp_allocator)

  last_frame_time := time.tick_now()
  dt_s := 0.0
  for (!should_close()) {
    // Resize check
    if state.window.resized { resize_window() }

    // dt and sleeping
    if (time.tick_since(last_frame_time) < TARGET_FRAME_TIME_NS) {
      time.accurate_sleep(TARGET_FRAME_TIME_NS - time.tick_since(last_frame_time))
    }

    // New dt after sleeping
    dt_s = f64(time.tick_since(last_frame_time)) / BILLION

    state.fps = 1.0 / dt_s

    state.frame_count += 1
    last_frame_time = time.tick_now()

    poll_input_state(dt_s)

    if key_pressed(.ESCAPE) {
      toggle_menu()
    }

    if key_pressed(.F1) {
      state.draw_debug = !state.draw_debug
    }

    if key_pressed(.TAB) {
      state.mode = .EDIT if state.mode == .GAME else .GAME
    }

    if key_pressed(.L) {
      state.sun_on = !state.sun_on
    }
    if key_pressed(.P) {
      state.point_lights_on = !state.point_lights_on
    }
    if key_pressed(.F) {
      state.flashlight_on = !state.flashlight_on
    }

    if key_pressed(.B) {
      state.bloom_on = !state.bloom_on
    }

    // 'Simulate' (not really doing much right now) if in game mode
    if state.mode == .GAME {
      move_camera_game(&state.camera, dt_s)
      state.flashlight.position  = state.camera.position
      state.flashlight.direction = get_camera_forward(state.camera)

      //
      // Collision
      //
      for &e in state.entities {
        if .HAS_COLLISION not_in e.flags { continue }

        entity_aabb := entity_world_aabb(e)

        for &o in state.entities {
          if &o == &e { continue } // Same entity

          if .HAS_COLLISION not_in o.flags { continue }

          other_aabb := entity_world_aabb(o)

          if aabbs_intersect(entity_aabb, other_aabb) {
            min_pen := aabb_min_penetration_vector(entity_aabb, other_aabb)

            e.position += min_pen
          }
        }
      }

      // Move da point lights around
      seconds := seconds_since_start()
      if state.point_lights_on {
        for &pl in state.point_lights {
          pl.position.x += 2.0 * f32(dt_s) * f32(math.sin(.5 * math.PI * seconds))
          pl.position.y += 2.0 * f32(dt_s) * f32(math.cos(.5 * math.PI * seconds))
          pl.position.z += 2.0 * f32(dt_s) * f32(math.cos(.5 * math.PI * seconds))
        }
      }
    }
    if state.mode == .EDIT {
      move_camera_edit(&state.camera, dt_s)
    }

    // Frame sync
    begin_drawing()

    //
    // Update frame uniform
    //

    projection := get_camera_perspective(state.camera)
    view       := get_camera_view(state.camera)
    frame_ubo: Frame_UBO = {
      projection      = projection,
      view            = view,
      proj_view       = projection * view,
      orthographic    = mat4_orthographic(0, f32(state.window.w), f32(state.window.h), 0, state.z_near, state.z_far),
      camera_position = {state.camera.position.x, state.camera.position.y, state.camera.position.z,  0.0},
      z_near          = state.z_near,
      z_far           = state.z_far,

      // And the lights
      lights = {
        direction = direction_light_uniform(state.sun) if state.sun_on else {},
        spot      = spot_light_uniform(state.flashlight) if state.flashlight_on else {},
      },
    }
    if state.point_lights_on {
      for pl, idx in state.point_lights {
        if idx >= MAX_POINT_LIGHTS {
          log.error("TOO MANY POINT LIGHTS!")
        } else {
          frame_ubo.lights.points[idx] = point_light_uniform(pl)
          frame_ubo.lights.points_count += 1
        }
      }
    }
    write_gpu_buffer_frame(state.frame_uniforms, 0, size_of(frame_ubo), &frame_ubo)
    bind_gpu_buffer_frame_range(state.frame_uniforms, .FRAME)

    // What to draw based on mode
    switch state.mode {
    case .EDIT: fallthrough
    case .GAME:
      if state.sun_on {
        begin_shadow_pass(sun_depth_buffer)
        {
          bind_shader_program(state.shaders["sun_depth"])

          for e in state.entities {
            draw_entity(e)
          }
        }
      }

      if state.point_lights_on {
        begin_shadow_pass(state.point_depth_buffer)
        {
          bind_shader("point_shadows")

          for l, idx in state.point_lights {
            set_shader_uniform("light_index", i32(idx))

            // Cull models not in light's radius
            light_sphere: Sphere = {
              center = l.position,
              radius = l.radius,
            }
            for e in state.entities {
              if sphere_intersects_aabb(light_sphere, entity_world_aabb(e)) {
                draw_entity(e, instances=6)
              }
            }
          }
        }
      }

      begin_main_pass()
      {
        bind_shader_program(state.shaders["phong"])

        if state.sun_on {
          bind_texture("skybox", state.skybox.texture)
        } else {
          bind_texture("skybox", {})
        }

        bind_texture("sun_shadow_map", sun_depth_buffer.depth_target)
        bind_texture("point_light_shadows", state.point_depth_buffer.depth_target)

        // Go through and draw opque entities, collect transparent entities
        transparent_entities := make([dynamic]^Entity, context.temp_allocator)
        for &e in state.entities {
          if entity_has_transparency(e) {
              append(&transparent_entities, &e)
              continue
          }

          // We're good we can just draw opqque entities
          draw_entity(e, draw_aabbs=state.draw_debug)
        }


        // Skybox here so it is seen behind transparent objects, binds its own shader
        if state.sun_on {
          draw_skybox(state.skybox)
        }

        // Transparent models
        bind_shader_program(state.shaders["phong"])
        {
          gl.Disable(gl.CULL_FACE)

          // Sort so that further entities get drawn first
          slice.sort_by(transparent_entities[:], proc(a, b: ^Entity) -> bool {
            da := squared_distance(a.position, state.camera.position)
            db := squared_distance(b.position, state.camera.position)
            return da > db
          })

          for e in transparent_entities {
            draw_entity(e^)
          }
        }

        // Draw point light billboards
        if state.point_lights_on {
          bind_shader_program(state.shaders["billboard"])
          for l in state.point_lights {
            temp := Entity{
              position = l.position.xyz,
              scale    = {1.0, 1.0, 1.0},
            }

            set_shader_uniform("model", entity_model_mat4(temp))
            draw_model(light_model, l.color)

            if state.draw_debug {
              immediate_sphere(l.position, l.radius, l.color)
            }
          }
        }

        if state.draw_debug {
          draw_grid(color = {1.0, 1.0, 1.0, 0.4})
        }

        // Flush any accumulated draw calls (Right now those are just for debug visuals, and conditional text)
        immediate_flush()
      }

      //
      // Post-Processing Pass
      //
      begin_post_pass()
      {
        // Resolve multi-sampling buffer to ping pong as we will then sample this into the post buffer
        gl.BlitNamedFramebuffer(state.hdr_ms_buffer.id, state.ping_pong_buffers[0].id,
          0, 0, cast(i32) state.hdr_ms_buffer.color_targets[0].width, cast(i32) state.hdr_ms_buffer.color_targets[0].height,
          0, 0, cast(i32) state.ping_pong_buffers[0].color_targets[0].width, cast(i32) state.ping_pong_buffers[0].color_targets[0].height,
          gl.COLOR_BUFFER_BIT,
          gl.LINEAR)

        //
        // Bloom
        //
        if state.bloom_on {
          // Now collect bright spots
          bind_framebuffer(state.post_buffer)
          bind_shader("get_bright")
          bind_texture("image", state.ping_pong_buffers[0].color_targets[0])
          gl.BindVertexArray(state.empty_vao)
          gl.DrawArrays(gl.TRIANGLES, 0, 6)

          // Now do da blur
          bind_shader("gaussian")
          bind_texture("image", state.post_buffer.color_targets[1])
          bind_framebuffer(state.ping_pong_buffers[0])

          BLOOM_GAUSSIAN_COUNT :: 10
          horizontal := false

          for _ in 0..<BLOOM_GAUSSIAN_COUNT {
            set_shader_uniform("horizontal", horizontal)
            gl.BindVertexArray(state.empty_vao)
            gl.DrawArrays(gl.TRIANGLES, 0, 6)

            horizontal = !horizontal
            bind_texture("image", state.ping_pong_buffers[int(!horizontal)].color_targets[0])
            bind_framebuffer(state.ping_pong_buffers[int(horizontal)])
          }
        }

        //
        // Resolve hdr (with bloom) to backbuffer
        //
        gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
        bind_shader_program(state.shaders["resolve_hdr"])
        bind_texture("screen_texture", state.post_buffer.color_targets[0])
        bind_texture("bloom_blur", state.ping_pong_buffers[0].color_targets[0])

        set_shader_uniform("exposure", f32(0.5))

        // Hardcoded vertices in post vertex shader, but opengl requires a VAO for draw calls
        gl.BindVertexArray(state.empty_vao)
        gl.DrawArrays(gl.TRIANGLES, 0, 6)
      }

      if state.draw_debug {
        // Gets draw to backbuffer
        begin_ui_pass()
        draw_debug_stats()
      }
    case .MENU:
      update_menu_input()
      draw_menu()
    }

    // Frame sync, swap backbuffers
    flush_drawing()

    // Free any temp allocations
    free_all(context.temp_allocator)
  }
}

free_state :: proc() {
  free_immediate_renderer()

  free_assets()

  free_skybox(&state.skybox)

  free_gpu_buffer(&state.frame_uniforms)

  for _, &shader in state.shaders {
    free_shader_program(&shader)
  }

  glfw.DestroyWindow(state.window.handle)
  // glfw.Terminate() // Causing crashes?
  virtual.arena_destroy(&state.perm)
}

seconds_since_start :: proc() -> (seconds: f64) {
  return time.duration_seconds(time.since(state.start_time))
}
