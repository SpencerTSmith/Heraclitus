package main

Render_Target :: struct
{
  attachments: [dynamic; 4]Texture,
}

Attachment_Description :: enum u8
{
  COLOR, // HDR always right now. If i ever do a gbuffer type thing probably then time to be more granular
  DEPTH,
  DEPTH_CUBE,
  DEPTH_CUBE_ARRAY,
}

Face_Cull_Mode :: enum u8
{
  NONE,
  FRONT,
  BACK,
}

Depth_Test_Mode :: enum u8
{
  NONE,
  ALWAYS,
  LESS,
}

Vertex_Primitive :: enum u8
{
  TRIANGLES,
  LINES,
}

// NOTE: Read left to right as src factor and dst factor
Blend_Mode :: enum u8
{
  NONE,
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

Skybox_Push :: struct
{
  frame_uniform: [^]Frame_Uniform,
}

MAIN_PASS :: Render_Pass {
  depth_test = .LESS,
  face_cull  = .NONE,
  blend      = .ALPHA_ONE_MINUS_ALPHA,
}

POST_PASS :: Render_Pass {
  depth_test = .NONE,
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
  face_cull  = .NONE,
  blend      = .ALPHA_ONE_MINUS_ALPHA,
}

UI_PASS :: Render_Pass {
  depth_test = .LESS,
  face_cull  = .NONE,
  blend      = .ALPHA_ONE_MINUS_ALPHA,
}

make_render_target :: proc(width, height: u32, attachments: []Attachment_Description) -> (target: Render_Target)
{
  assert(len(attachments) < cap(target.attachments), "Too many attachments specified for render target creation.")

  for attachment in attachments
  {
    format:  Pixel_Format
    type:    Texture_Type
    sampler: Sampler_Preset

    switch attachment
    {
      case .COLOR:
        format  = .RGBA16F
        type    = .D2
        sampler = .CLAMP_WHITE
      case .DEPTH:
        format  = .DEPTH32
        type    = .D2
        sampler = .CLAMP_WHITE
      case .DEPTH_CUBE:
        format  = .DEPTH32
        type    = .CUBE
        sampler = .CLAMP_WHITE
      case .DEPTH_CUBE_ARRAY:
        format  = .DEPTH32
        type    = .CUBE
        sampler = .CLAMP_WHITE
    }

    texture := alloc_texture(type, {.TARGET}, format, sampler, u32(state.window.w), u32(state.window.h))
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
