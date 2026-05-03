package main

Render_Target_Flag :: enum
{
  WINDOW_SIZED,
}
Render_Target_Flags :: bit_set[Render_Target_Flag]

Render_Target_Attachment :: enum
{
  DEPTH,
  COLOR_0,
  COLOR_1,
  COLOR_2,
  COLOR_3,
}

Render_Target :: struct
{
  attachments: [Render_Target_Attachment]Texture_Handle,

  flags:       Render_Target_Flags,
  width:       u32,
  height:      u32,
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
  LESS_NO_WRITE,
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
  viewport:    Viewport, // Optional, see flags
}

MAIN_PASS :: Render_Pass {
  depth_test = .LESS,
  face_cull  = .BACK,
}

POST_PASS :: Render_Pass {
  depth_test = .NONE,
  face_cull  = .BACK,
}

SUN_SHADOW_PASS :: Render_Pass {
  depth_test = .LESS,
  face_cull  = .NONE,
}

POINT_SHADOW_PASS :: Render_Pass {
  depth_test = .LESS,
  face_cull  = .NONE,
}

UI_PASS :: Render_Pass {
  depth_test = .NONE,
  face_cull  = .NONE,
  flags      = {.NO_CLEAR},
}

make_render_target :: proc(width, height, samples: u32, color_attachments: []Pixel_Format, depth_attachment: Pixel_Format = .NONE, flags: Render_Target_Flags = {}) -> (target: Render_Target)
{
  for format, idx in color_attachments
  {
    attachment_key: Render_Target_Attachment = .COLOR_0 + Render_Target_Attachment(idx)
    texture := alloc_texture(.D2, {.TARGET}, format, .CLAMP_WHITE, width, height, samples=samples)
    target.attachments[attachment_key] = register_texture(texture)
  }

  if depth_attachment != .NONE
  {
    texture := alloc_texture(.D2, {.TARGET}, depth_attachment, .CLAMP_WHITE, width, height, samples=samples)
    target.attachments[.DEPTH] = register_texture(texture)
  }

  target.flags = flags

  target.width  = width
  target.height = height

  return target
}

begin_render_pass :: proc(pass: Render_Pass, target: ^Render_Target, blit_source: ^Render_Target = nil, sampled: []^Render_Target = {})
{
  // Viewport, if no custom viewport just set to the whole thing.
  pass := pass
  if .CUSTOM_VIEWPORT not_in pass.flags
  {
    pass.viewport.x = 0
    pass.viewport.y = 0
    pass.viewport.w = target.width
    pass.viewport.h = target.height
  }

  vk_begin_render_pass(pass, target, blit_source, sampled)
}

end_render_pass :: proc()
{
  vk_end_render_pass()
}

set_render_viewport :: proc(viewport: Viewport)
{
  vk_set_render_viewport(viewport)
}
