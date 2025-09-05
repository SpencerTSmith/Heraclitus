package main

import "core:log"
import "core:slice"

import gl "vendor:OpenGL"
import "vendor:glfw"

Framebuffer :: struct {
  id:            u32,

  attachments:   []Framebuffer_Attachment,
  color_targets: []Texture,
  depth_target:  Texture,

  sample_count:  int,
  width:  int,
  height: int,
}

DEFAULT_FRAMEBUFFER :: Framebuffer{}

Framebuffer_Attachment :: enum {
  COLOR,
  HDR_COLOR,
  DEPTH,
  DEPTH_STENCIL,
  DEPTH_CUBE,
  DEPTH_CUBE_ARRAY,
}

Face_Cull_Mode :: enum {
  DISABLED,
  FRONT,
  BACK,
}

Depth_Test_Mode :: enum {
  DISABLED,
  ALWAYS,
  LESS,
  LESS_EQUAL,
}

// NOTE: Read left to right as src factor and dst factor
Blend_Mode :: enum {
  DISABLED,
  ALPHA_ONE_MINUS_ALPHA,
}

Viewport :: struct {
  x: i32,
  y: i32,
  w: i32,
  h: i32,
}

Render_Pass_Flags :: enum {
  CLEAR_FRAMEBUFFER,
  USE_ALL_FRAMEBUFFER_VIEWPORT,
  USE_WINDOW_VIEWPORT,
}

Render_Pass :: struct {
  flags:      bit_set[Render_Pass_Flags],

  depth_test: Depth_Test_Mode,
  face_cull:  Face_Cull_Mode,
  blend:      Blend_Mode,

  // Optionally filled out if don't want to use the full
  // Framebuffer size in a render pass, set by flag
  viewport: Viewport,
}

MAIN_PASS :: Render_Pass {
  flags      = {.CLEAR_FRAMEBUFFER, .USE_ALL_FRAMEBUFFER_VIEWPORT},
  depth_test = .LESS,
  face_cull  = .BACK,
  blend      = .ALPHA_ONE_MINUS_ALPHA,
}

POST_PASS :: Render_Pass {
  flags      = {.CLEAR_FRAMEBUFFER, .USE_ALL_FRAMEBUFFER_VIEWPORT},
  depth_test = .DISABLED,
  face_cull  = .BACK,
  blend      = .ALPHA_ONE_MINUS_ALPHA,
}

SUN_SHADOW_PASS :: Render_Pass {
  flags      = {.CLEAR_FRAMEBUFFER, .USE_ALL_FRAMEBUFFER_VIEWPORT},
  depth_test = .LESS,
  face_cull  = .FRONT,
  blend      = .ALPHA_ONE_MINUS_ALPHA,
}

POINT_SHADOW_PASS :: Render_Pass {
  flags      = {.USE_ALL_FRAMEBUFFER_VIEWPORT},
  depth_test = .LESS,
  face_cull  = .FRONT,
  blend      = .ALPHA_ONE_MINUS_ALPHA,
}

UI_PASS :: Render_Pass {
  flags      = {.CLEAR_FRAMEBUFFER, .USE_WINDOW_VIEWPORT},
  depth_test = .LESS,
  face_cull  = .DISABLED,
  blend      = .ALPHA_ONE_MINUS_ALPHA,
}

// TODO: Save state as it was before this pass, perhaps as an optional return
begin_render_pass :: proc(pass: Render_Pass, fb: Framebuffer) {
  bind_framebuffer(fb)
  if .CLEAR_FRAMEBUFFER in pass.flags {
    clear_framebuffer(fb)
  }

  /////////
  // GL State Changes
  ////////

  DISABLED_SENTINEL :: 0

  // Depth Testing
  gl_depth_map: [Depth_Test_Mode]u32 = {
    .DISABLED   = DISABLED_SENTINEL,

    .ALWAYS     = gl.ALWAYS,
    .LESS       = gl.LESS,
    .LESS_EQUAL = gl.LESS,
  }
  gl_depth := gl_depth_map[pass.depth_test]

  if gl_depth == DISABLED_SENTINEL {
    gl.Disable(gl.DEPTH_TEST)
  } else {
    gl.Enable(gl.DEPTH_TEST)
    gl.DepthFunc(gl_depth)
  }

  // Face Culling
  gl_cull_map: [Face_Cull_Mode]u32 = {
    .DISABLED = DISABLED_SENTINEL,

    .FRONT    = gl.FRONT,
    .BACK     = gl.BACK,
  }
  gl_cull := gl_cull_map[pass.face_cull]

  if gl_cull == DISABLED_SENTINEL {
    gl.Disable(gl.CULL_FACE)
  } else {
    gl.Enable(gl.CULL_FACE)
    gl.CullFace(gl_cull)
  }

  // Blending
  gl_blend_map: [Blend_Mode][2]u32 = {
    .DISABLED = {DISABLED_SENTINEL, DISABLED_SENTINEL},

    .ALPHA_ONE_MINUS_ALPHA = {gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA},
  }
  gl_blend := gl_blend_map[pass.blend]

  if gl_blend == DISABLED_SENTINEL {
    gl.Disable(gl.BLEND)
  } else {
    gl.Enable(gl.BLEND)
    gl.BlendFunc(gl_blend[0], gl_blend[1])
  }

  // Viewport
  vp: Viewport
  if .USE_ALL_FRAMEBUFFER_VIEWPORT in pass.flags {
    vp.x = 0
    vp.y = 0
    vp.w = cast(i32) fb.width
    vp.h = cast(i32) fb.height
  } else if .USE_WINDOW_VIEWPORT in pass.flags {
    vp.x = 0
    vp.y = 0
    vp.w = cast(i32) state.window.w
    vp.h = cast(i32) state.window.h
  } else {
    vp = pass.viewport
  }

  gl.Viewport(vp.x, vp.y, vp.w, vp.h)
}

// For now depth target can either be depth only or depth+stencil,
// also can only have one attachment of each type
make_framebuffer :: proc(width, height: int, samples: int = 0, array_depth: int = 0,
                         attachments: []Framebuffer_Attachment = {.COLOR, .DEPTH_STENCIL},
                         ) -> (buffer: Framebuffer, ok: bool) {
  fbo: u32
  gl.CreateFramebuffers(1, &fbo)

  color_targets := make([dynamic]Texture, context.temp_allocator)
  depth_target: Texture

  gl_attachments := make([dynamic]u32, context.temp_allocator)

  for attachment in attachments {
    switch attachment {
    case .COLOR:
      color_target := alloc_texture(._2D, .RGBA8, .NONE, width, height, samples=samples)
      attachment := cast(u32) (gl.COLOR_ATTACHMENT0 + len(color_targets))
      gl.NamedFramebufferTexture(fbo,  attachment, color_target.id, 0)

      append(&color_targets, color_target)
      append(&gl_attachments, attachment)

    case .HDR_COLOR:
      color_target := alloc_texture(._2D, .RGBA16F, .NONE, width, height, samples=samples)
      attachment := cast(u32) (gl.COLOR_ATTACHMENT0 + len(color_targets))
      gl.NamedFramebufferTexture(fbo,  attachment, color_target.id, 0)

      append(&color_targets, color_target)
      append(&gl_attachments, attachment)

    case .DEPTH:
      assert(depth_target.id == 0) // Only one depth attachment

      depth_target = alloc_texture(._2D, .DEPTH32, .NONE, width, height)

      // Really for shadow mapping... but eh
      gl.TextureParameteri(depth_target.id, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_BORDER)
      gl.TextureParameteri(depth_target.id, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_BORDER)
      border_color := vec4{1.0, 1.0, 1.0, 1.0}
      gl.TextureParameterfv(depth_target.id, gl.TEXTURE_BORDER_COLOR, &border_color[0])

      gl.NamedFramebufferTexture(fbo, gl.DEPTH_ATTACHMENT, depth_target.id, 0)

    case .DEPTH_STENCIL:
      assert(depth_target.id == 0)

      depth_target = alloc_texture(._2D, .DEPTH24_STENCIL8, .NONE, width, height, samples=samples)
      gl.NamedFramebufferTexture(fbo, gl.DEPTH_ATTACHMENT, depth_target.id, 0)

    case .DEPTH_CUBE:
      assert(depth_target.id == 0)

      depth_target = alloc_texture(.CUBE, .DEPTH32, .CLAMP_LINEAR, width, height)
      gl.NamedFramebufferTexture(fbo, gl.DEPTH_ATTACHMENT, depth_target.id, 0)

    case .DEPTH_CUBE_ARRAY:
      assert(depth_target.id == 0)

      assert(array_depth > 0)
      depth_target = alloc_texture(.CUBE_ARRAY, .DEPTH32, .CLAMP_LINEAR, width, height, array_depth=array_depth)
      gl.NamedFramebufferTexture(fbo, gl.DEPTH_ATTACHMENT, depth_target.id, 0)
    }
  }

  gl.NamedFramebufferDrawBuffers(fbo, cast(i32)len(color_targets), raw_data(gl_attachments))

  buffer = {
    id            = fbo,
    attachments   = slice.clone(attachments, state.perm_alloc),
    color_targets = slice.clone(color_targets[:], state.perm_alloc),
    depth_target  = depth_target,
    sample_count  = samples,
    width         = width,
    height        = height,
  }
  if gl.CheckNamedFramebufferStatus(fbo, gl.FRAMEBUFFER) != gl.FRAMEBUFFER_COMPLETE {
    log.error("Unable to create complete framebuffer: %v", buffer)
    return {}, false
  }

  ok = true
  return buffer, ok
}

// NOTE: If none passed in clear the default framebuffer
clear_framebuffer :: proc(fb: Framebuffer, color := BLACK) {
  clear_color := color

  // Hmm may want this to be controllable maybe
  DEFAULT_DEPTH   :: 1.0
  DEFAULT_STENCIL :: 0.0

  // This is the default framebuffer
  if fb.id == 0 {
    gl.ClearNamedFramebufferfv(fb.id, gl.COLOR, 0, raw_data(&clear_color))
    gl.ClearNamedFramebufferfi(fb.id, gl.DEPTH_STENCIL, 0, DEFAULT_DEPTH, DEFAULT_STENCIL)
  } else {
    // This is a created framebuffer

    // Clear ALL the draw buffers
    for _, idx in fb.color_targets {
      gl.ClearNamedFramebufferfv(fb.id, gl.COLOR, i32(idx), raw_data(&clear_color))
    }

    // Clear depth stencil target if it exists
    if fb.depth_target.format == .DEPTH24_STENCIL8 {
      gl.ClearNamedFramebufferfi(fb.id, gl.DEPTH_STENCIL, 0, DEFAULT_DEPTH, DEFAULT_STENCIL)
    }

    // Clear depth target if it exists
    if fb.depth_target.format == .DEPTH32 {
      default_depth: f32 = DEFAULT_DEPTH // Since we need a pointer, can't use constant
      gl.ClearNamedFramebufferfv(fb.id, gl.DEPTH, 0, &default_depth)
    }
  }
}

bind_framebuffer :: proc(fb: Framebuffer) {
  // Should be fine for binding default if pass in empty struct
  gl.BindFramebuffer(gl.FRAMEBUFFER, fb.id)
}

free_framebuffer :: proc(fb: ^Framebuffer) {
  for &c in fb.color_targets {
    free_texture(&c)
  }
  free_texture(&fb.depth_target)
  gl.DeleteFramebuffers(1, &fb.id)
}

// NOTE: This blits the entire size of the targets, respectively
// As well as always blitting color and depth buffer info
blit_framebuffers :: proc(from, to: Framebuffer) {
  gl_filter: u32 = gl.NEAREST

  // TODO: Is this a good idea? Basically only use filtering if we aren't blitting from a multisample buffer
  // and they are not the same size
  if from.sample_count > 1 && (from.width != to.width || from.height != to.height) {
    log.info("Blitting with linear filtering, check if that was something you wished to do")
    gl_filter = gl.LINEAR
  }

  gl.BlitNamedFramebuffer(from.id, to.id,
    0, 0, cast(i32) from.width, cast(i32) from.height,
    0, 0, cast(i32) to.width,   cast(i32) to.height,
    gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT,
    gl_filter)
}

// TODO: Find a way to assert that the currently bound shader has the to_screen vertex shader
draw_screen_quad :: proc() {
  gl.BindVertexArray(state.empty_vao)
  gl.DrawArrays(gl.TRIANGLES, 0, 6)
}

// Will use the same sample count and attachment list as the old
remake_framebuffer :: proc(frame_buffer: ^Framebuffer, width, height: int) -> (new_buffer: Framebuffer, ok: bool) {
  old_samples     := frame_buffer.sample_count
  old_attachments := frame_buffer.attachments
  free_framebuffer(frame_buffer)
  new_buffer, ok = make_framebuffer(width, height, old_samples, attachments=old_attachments)

  return new_buffer, ok
}

begin_drawing :: proc() {
  // Probably fine to have a little bit of fragmenting in perm_arena...
  // only going to be doing hot reloads while developing
  hot_reload_shaders(&state.shaders, state.perm_alloc)

  frame := &state.frames[state.curr_frame_index]
  if frame.fence != nil {
    gl.ClientWaitSync(frame.fence, gl.SYNC_FLUSH_COMMANDS_BIT, U64_MAX)
    gl.DeleteSync(frame.fence)

    frame.fence = nil
  }

  clear := BLACK
  gl.ClearNamedFramebufferfv(0, gl.COLOR, 0, raw_data(&clear))
  clear_framebuffer(state.hdr_ms_buffer)
  clear_framebuffer(state.ping_pong_buffers[0])
  clear_framebuffer(state.ping_pong_buffers[1])
  clear_framebuffer(state.post_buffer)

  state.began_drawing = true

  //
  // Update frame uniform
  //
  projection := get_camera_perspective(state.camera)
  view       := get_camera_view(state.camera)
  frame_ubo: Frame_Uniform = {
    projection      = projection,
    view            = view,
    proj_view       = projection * view,
    orthographic    = mat4_orthographic(0, f32(state.window.w), f32(state.window.h), 0, state.z_near, state.z_far),
    camera_position = {state.camera.position.x, state.camera.position.y, state.camera.position.z,  0.0},
    z_near          = state.z_near,
    z_far           = state.z_far,

    // And the lights
    sun_light   = direction_light_uniform(state.sun) if state.sun_on else {},
    flash_light = spot_light_uniform(state.flashlight) if state.flashlight_on else {},
  }

  if state.point_lights_on {
    for pl in state.point_lights {
      if pl.cast_shadows {
        if frame_ubo.shadow_points_count >= MAX_SHADOW_POINT_LIGHTS {
          log.errorf("Too many shadow casting point lights! Adding to non shadow casting lights.")

          idx := frame_ubo.points_count
          frame_ubo.point_lights[idx] = point_light_uniform(pl)
          frame_ubo.points_count += 1
        } else {
          idx := frame_ubo.shadow_points_count
          frame_ubo.shadow_point_lights[idx] = shadow_point_light_uniform(pl)
          frame_ubo.shadow_points_count += 1
        }
      } else {
        if frame_ubo.shadow_points_count >= MAX_POINT_LIGHTS {
          log.errorf("Too many shadow casting point lights! Ignoring.")
        } else {
          idx := frame_ubo.points_count
          frame_ubo.point_lights[idx] = point_light_uniform(pl)
          frame_ubo.points_count += 1
        }
      }
    }
  }
  write_gpu_buffer_frame(state.frame_uniforms, 0, size_of(frame_ubo), &frame_ubo)
  bind_gpu_buffer_frame_range(state.frame_uniforms, .FRAME)
}

flush_drawing :: proc() {
  immediate_frame_reset()

  // And set up for next frame
  frame := &state.frames[state.curr_frame_index]
  frame.fence = gl.FenceSync(gl.SYNC_GPU_COMMANDS_COMPLETE, 0)
  state.curr_frame_index = (state.curr_frame_index + 1) % FRAMES_IN_FLIGHT

  state.began_drawing = false
  state.mesh_draw_calls = 0

  glfw.SwapBuffers(state.window.handle)
}
