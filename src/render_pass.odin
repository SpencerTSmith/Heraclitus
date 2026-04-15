package main

import gl "vendor:OpenGL"

Render_Target :: struct
{
  attachments: [dynamic; 4]Texture,
}

Attachment_Description :: enum u8
{
  COLOR,
  HDR_COLOR,
  DEPTH,
  DEPTH_STENCIL,
  DEPTH_CUBE,
  DEPTH_CUBE_ARRAY,
}

Face_Cull_Mode :: enum u8
{
  DISABLED,
  FRONT,
  BACK,
}

Depth_Test_Mode :: enum u8
{
  DISABLED,
  ALWAYS,
  LESS,
  LESS_EQUAL,
}

Vertex_Primitive :: enum u8
{
  TRIANGLES,
  LINES,
}

// NOTE: Read left to right as src factor and dst factor
Blend_Mode :: enum u8
{
  DISABLED,
  ALPHA_ONE_MINUS_ALPHA,
}

Viewport :: struct
{
  x: u32,
  y: u32,
  w: u32,
  h: u32,
}

Render_Pass_Flag :: enum
{
  NO_CLEAR,
  CUSTOM_VIEWPORT,
}
Render_Pass_Flags :: bit_set[Render_Pass_Flag]

Render_Pass :: struct
{
  flags: Render_Pass_Flags,

  clear_color: vec4,
  depth_test:  Depth_Test_Mode,
  face_cull:   Face_Cull_Mode,
  blend:       Blend_Mode,
  viewport:    Viewport, // Optional, see flags
}

MAIN_PASS :: Render_Pass {
  depth_test = .LESS,
  face_cull  = .BACK,
  blend      = .ALPHA_ONE_MINUS_ALPHA,
}

POST_PASS :: Render_Pass {
  depth_test = .DISABLED,
  face_cull  = .BACK,
  blend      = .ALPHA_ONE_MINUS_ALPHA,
}

SUN_SHADOW_PASS :: Render_Pass {
  depth_test = .LESS,
  face_cull  = .FRONT,
  blend      = .ALPHA_ONE_MINUS_ALPHA,
}

POINT_SHADOW_PASS :: Render_Pass {
  depth_test = .LESS,
  face_cull  = .DISABLED,
  blend      = .ALPHA_ONE_MINUS_ALPHA,
}

UI_PASS :: Render_Pass {
  depth_test = .LESS,
  face_cull  = .DISABLED,
  blend      = .ALPHA_ONE_MINUS_ALPHA,
}

make_render_target :: proc(width, height: u32, attachments: []Attachment_Description) -> (target: Render_Target)
{
  assert(len(attachments) < cap(target.attachments), "Too many attachments specified for render target creation.")

  for attachment in attachments
  {
    texture: Texture
    switch attachment
    {
      case .COLOR:
        texture = alloc_texture(.D2, {.TARGET}, .RGBA16F, .CLAMP_LINEAR, u32(state.window.w), u32(state.window.h))
      case .HDR_COLOR:
        unimplemented()
      case .DEPTH:
        unimplemented()
      case .DEPTH_STENCIL:
        unimplemented()
      case .DEPTH_CUBE:
        unimplemented()
      case .DEPTH_CUBE_ARRAY:
        unimplemented()
    }
    append(&target.attachments, texture)
  }

  return target
}

begin_render_pass :: proc(pass: Render_Pass, target: ^Render_Target)
{
  // May also assert that the size of these attachments are the same, but eh
  assert(len(target.attachments) != 0)

  // Viewport, if no custom viewport just set to the whole thing.
  pass := pass
  if .CUSTOM_VIEWPORT not_in pass.flags
  {
    pass.viewport.x = 0
    pass.viewport.y = 0
    pass.viewport.w = target.attachments[0].width
    pass.viewport.h = target.attachments[0].height
  }

  vk_begin_render_pass(pass, target)
}

end_render_pass :: proc()
{
  vk_end_render_pass()
}

// For now depth target can either be depth only or depth+stencil,
// also can only have one attachment of each type

// begin_drawing :: proc()
// {
//   // Probably fine to have a little bit of fragmenting in perm_arena...
//   // only going to be doing hot reloads while developing
//   when ODIN_DEBUG
//   {
//     hot_reload_shaders(&state.shaders, state.perm_alloc)
//   }
//
//   frame := &state.frames[state.curr_frame_index]
//   if frame.fence != nil
//   {
//     gl.ClientWaitSync(frame.fence, gl.SYNC_FLUSH_COMMANDS_BIT, U64_MAX)
//     gl.DeleteSync(frame.fence)
//
//     frame.fence = nil
//   }
//
//   clear := BLACK
//   clear_framebuffer(DEFAULT_FRAMEBUFFER, clear)
//   clear_framebuffer(state.hdr_ms_buffer, clear)
//   clear_framebuffer(state.post_buffer, clear)
//   clear_framebuffer(state.ping_pong_buffers[0], clear)
//   clear_framebuffer(state.ping_pong_buffers[1], clear)
//
//   state.began_drawing = true
//
//   //
//   // Update frame uniform
//   //
//   projection := camera_perspective(state.camera, window_aspect_ratio(state.window))
//   view       := camera_view(state.camera)
//   frame_ubo: Frame_Uniform =
//   {
//     projection      = projection,
//     view            = view,
//     proj_view       = projection * view,
//     orthographic    = mat4_orthographic(0, f32(state.window.w), f32(state.window.h), 0, state.camera.z_near, state.camera.z_far),
//     camera_position = {state.camera.position.x, state.camera.position.y, state.camera.position.z,  0.0},
//     z_near          = state.camera.z_near,
//     z_far           = state.camera.z_far,
//
//     // And the lights
//     sun_light   = direction_light_uniform(state.sun) if state.sun_on else {},
//     flash_light = spot_light_uniform(state.flashlight) if state.flashlight_on else {},
//   }
//
//   if state.point_lights_on
//   {
//     for pl in state.point_lights
//     {
//       // Try to add shadow casting to the shadow casting array first
//       if pl.cast_shadows && frame_ubo.shadow_points_count <= MAX_SHADOW_POINT_LIGHTS
//       {
//         idx := frame_ubo.shadow_points_count
//         frame_ubo.shadow_point_lights[idx] = shadow_point_light_uniform(pl)
//         frame_ubo.shadow_points_count += 1
//       }
//       else
//       {
//         // If we had too many try to add to the normal point lights
//         if pl.cast_shadows
//         {
//           log.errorf("Too many shadow casting point lights! Attempting to add to non shadow casting lights.")
//         }
//
//         if frame_ubo.points_count <= MAX_POINT_LIGHTS
//         {
//           idx := frame_ubo.points_count
//           frame_ubo.point_lights[idx] = point_light_uniform(pl)
//           frame_ubo.points_count += 1
//         }
//         else
//         {
//           log.errorf("Too many point lights! Ignoring.")
//         }
//       }
//     }
//   }
//
//   write_gpu_buffer_frame(state.frame_uniforms, 0, size_of(frame_ubo), &frame_ubo)
//   bind_gpu_buffer_frame_range(state.frame_uniforms, .FRAME)
//
//   bind_gpu_buffer_frame_range(state.mds.draw_uniforms, .DRAW_UNIFORMS)
// }
//
// flush_drawing :: proc()
// {
//   immediate_frame_reset()
//
//   // And set up for next frame
//   frame := &state.frames[state.curr_frame_index]
//   frame.fence = gl.FenceSync(gl.SYNC_GPU_COMMANDS_COMPLETE, 0)
//   state.curr_frame_index = (state.curr_frame_index + 1) % FRAMES_IN_FLIGHT
//
//   state.began_drawing = false
//
//   reset_multi_draw(&state.mds)
//
//   glfw.SwapBuffers(state.window.handle)
// }

// resize_window :: proc(window: ^Window) -> (ok: bool)
// {
//   // Reset
//   window.should_resize = false
//
//   state.hdr_ms_buffer, ok = remake_framebuffer(&state.hdr_ms_buffer, window.w, window.h)
//   state.post_buffer, ok = remake_framebuffer(&state.post_buffer, window.w, window.h)
//   state.ping_pong_buffers[0], ok = remake_framebuffer(&state.ping_pong_buffers[0], window.w, window.h)
//   state.ping_pong_buffers[1], ok = remake_framebuffer(&state.ping_pong_buffers[1], window.w, window.h)
//
//   if !ok
//   {
//     log.fatal("Window has been resized but unable to recreate framebuffers")
//   }
//   else
//   {
//     assert(window.w == state.hdr_ms_buffer.width &&
//            window.h == state.hdr_ms_buffer.height)
//
//     log.infof("Window has resized to %vpx, %vpx", window.w, window.h)
//   }
//
//   return ok
// }

draw_skybox :: proc(handle: Texture_Handle)
{
  // bind_shader(.SKYBOX)

  // Get the depth func before and reset after this call
  // TODO: Do this everywhere, ie push and pop GL state
  depth_func_before: i32; gl.GetIntegerv(gl.DEPTH_FUNC, &depth_func_before)
  gl.DepthFunc(gl.LEQUAL)
  defer gl.DepthFunc(u32(depth_func_before))

  texture := get_texture(handle)^
  assert(texture.type == .CUBE)
  bind_texture("skybox", get_texture(handle)^)

  gl.DrawArrays(gl.TRIANGLES, 0, 36)
}
