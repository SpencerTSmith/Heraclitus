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
}

Framebuffer_Attachment :: enum {
  COLOR,
  HDR_COLOR,
  DEPTH,
  DEPTH_STENCIL,
  DEPTH_CUBE,
  DEPTH_CUBE_ARRAY,
}

// For now depth target can either be depth only or depth+stencil,
// also can only have one attachment of each type
make_framebuffer :: proc(width, height: int, samples: int = 0, array_depth: int = 0,
                         attachments: []Framebuffer_Attachment = {.COLOR, .DEPTH_STENCIL}
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
  }
  if gl.CheckNamedFramebufferStatus(fbo, gl.FRAMEBUFFER) != gl.FRAMEBUFFER_COMPLETE {
    log.error("Unable to create complete framebuffer: %v", buffer)
    return {}, false
  }

  ok = true
  return buffer, ok
}

bind_framebuffer :: proc(buffer: Framebuffer) {
  gl.BindFramebuffer(gl.FRAMEBUFFER, buffer.id)
}

free_framebuffer :: proc(frame_buffer: ^Framebuffer) {
  for &c in frame_buffer.color_targets {
    free_texture(&c)
  }
  free_texture(&frame_buffer.depth_target)
  gl.DeleteFramebuffers(1, &frame_buffer.id)
}

// Will use the same sample count as the old
remake_framebuffer :: proc(frame_buffer: ^Framebuffer, width, height: int) -> (new_buffer: Framebuffer, ok: bool) {
  old_samples     := frame_buffer.sample_count
  old_attachments := frame_buffer.attachments
  free_framebuffer(frame_buffer)
  new_buffer, ok = make_framebuffer(width, height, old_samples, attachments=old_attachments)

  return new_buffer, ok
}

begin_drawing :: proc() {
  // This simple?
  frame := &state.frames[state.curr_frame_index]
  if frame.fence != nil {
    gl.ClientWaitSync(frame.fence, gl.SYNC_FLUSH_COMMANDS_BIT, U64_MAX)
    gl.DeleteSync(frame.fence)

    frame.fence = nil
  }

  clear := WHITE
  gl.ClearNamedFramebufferfv(state.ping_pong_buffers[0].id, gl.COLOR, 0, raw_data(&clear))
  gl.ClearNamedFramebufferfv(state.ping_pong_buffers[1].id, gl.COLOR, 0, raw_data(&clear))
  gl.ClearNamedFramebufferfv(state.post_buffer.id,          gl.COLOR, 0, raw_data(&clear))

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

  clear := BLACK
  gl.ClearNamedFramebufferfv(state.ping_pong_buffers[0].id, gl.COLOR, 0, raw_data(&clear))
  gl.ClearNamedFramebufferfv(state.ping_pong_buffers[1].id, gl.COLOR, 0, raw_data(&clear))
  gl.ClearNamedFramebufferfv(state.post_buffer.id,          gl.COLOR, 0, raw_data(&clear))
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
begin_shadow_pass :: proc(framebuffer: Framebuffer) {
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

  // Remember to flush the remaining portion
  immediate_frame_flush()

  // And set up for next frame
  frame := &state.frames[state.curr_frame_index]
  frame.fence = gl.FenceSync(gl.SYNC_GPU_COMMANDS_COMPLETE, 0)
  state.curr_frame_index = (state.curr_frame_index + 1) % FRAMES_IN_FLIGHT

  state.began_drawing = false
  state.draw_calls = 0

  glfw.SwapBuffers(state.window.handle)
}
