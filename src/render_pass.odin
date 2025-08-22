package main

import "core:log"
import "core:slice"

import gl "vendor:OpenGL"
import "vendor:glfw"

Frame_Buffer :: struct {
  id:            u32,

  attachments:   []Frame_Buffer_Attachment,
  color_targets: []Texture,
  depth_target:  Texture,

  sample_count:  int,
  width:  int,
  height: int,
}

Frame_Buffer_Attachment :: enum {
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

begin_render_pass :: proc(fb: Frame_Buffer, depth_mode: Depth_Test_Mode, cull_mode: Face_Cull_Mode) {

}

// For now depth target can either be depth only or depth+stencil,
// also can only have one attachment of each type
make_framebuffer :: proc(width, height: int, samples: int = 0, array_depth: int = 0,
                         attachments: []Frame_Buffer_Attachment = {.COLOR, .DEPTH_STENCIL},
                         ) -> (buffer: Frame_Buffer, ok: bool) {
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
clear_framebuffer :: proc(fb: Frame_Buffer = {}, color := BLACK) {
  clear_color := color

  // Hmm may want this to be controllable maybe
  default_depth:   f32 = 1.0
  default_stencil: i32 = 0

  // This is the default framebuffer
  if fb.id == 0 {
    gl.ClearNamedFramebufferfv(fb.id, gl.COLOR, 0, raw_data(&clear_color))
    gl.ClearNamedFramebufferfi(fb.id, gl.DEPTH_STENCIL, 0, default_depth, default_stencil)
  } else {
    // This is a created framebuffer

    // Clear ALL the draw buffers
    for _, idx in fb.color_targets {
      gl.ClearNamedFramebufferfv(fb.id, gl.COLOR, i32(idx), raw_data(&clear_color))
    }

    // Clear depth stencil target if it exists
    if fb.depth_target.format == .DEPTH24_STENCIL8 {
      gl.ClearNamedFramebufferfi(fb.id, gl.DEPTH_STENCIL, 0, default_depth, default_stencil)
    }

    // Clear depth target if it exists
    if fb.depth_target.format == .DEPTH32 {
      gl.ClearNamedFramebufferfv(fb.id, gl.DEPTH, 0, &default_depth)
    }
  }
}

bind_framebuffer :: proc(fb: Frame_Buffer) {
  gl.BindFramebuffer(gl.FRAMEBUFFER, fb.id)
}

free_framebuffer :: proc(fb: ^Frame_Buffer) {
  for &c in fb.color_targets {
    free_texture(&c)
  }
  free_texture(&fb.depth_target)
  gl.DeleteFramebuffers(1, &fb.id)
}

// NOTE: This blits the entire size of the targets, respectively
// As well as always blitting color and depth buffer info
blit_framebuffers :: proc(from, to: Frame_Buffer) {
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
remake_framebuffer :: proc(frame_buffer: ^Frame_Buffer, width, height: int) -> (new_buffer: Frame_Buffer, ok: bool) {
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

  // This simple?
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
}

begin_main_pass :: proc() {
  bind_framebuffer(state.hdr_ms_buffer)

  gl.Viewport(0, 0, i32(state.window.w), i32(state.window.h))
  gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT | gl.STENCIL_BUFFER_BIT)

  gl.Enable(gl.DEPTH_TEST)

  gl.Enable(gl.CULL_FACE)
  gl.CullFace(gl.BACK)

  gl.Enable(gl.BLEND)
  gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
}

begin_post_pass :: proc() {
  gl.Viewport(0, 0, i32(state.window.w), i32(state.window.h))
  gl.Disable(gl.DEPTH_TEST)
}

begin_ui_pass :: proc() {
  // We draw straight to the screen in this case... maybe we want to do other stuff later
  gl.BindFramebuffer(gl.FRAMEBUFFER, 0)

  gl.Viewport(0, 0, i32(state.window.w), i32(state.window.h))

  gl.Disable(gl.DEPTH_TEST)

  gl.Enable(gl.BLEND)
  gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

  gl.Disable(gl.CULL_FACE)
}

// For now excludes transparent objects and the skybox
begin_shadow_pass :: proc(framebuffer: Frame_Buffer) {
  assert(framebuffer.depth_target.id > 0, "Framebuffer must have depth target for shadow mapping")
  gl.BindFramebuffer(gl.FRAMEBUFFER, framebuffer.id)

  x := 0
  y := 0
  width  := framebuffer.depth_target.width
  height := framebuffer.depth_target.height

  gl.Viewport(i32(x), i32(y), i32(width), i32(height))
  gl.Clear(gl.DEPTH_BUFFER_BIT)
  gl.Enable(gl.DEPTH_TEST)
  gl.Enable(gl.CULL_FACE)
  gl.CullFace(gl.FRONT) // Peter-panning fix for shadow bias
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
