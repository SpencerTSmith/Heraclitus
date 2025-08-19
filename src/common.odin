package main

import "core:fmt"
import "core:log"
import "core:math/linalg"
import "core:math/linalg/glsl"
import "core:path/filepath"
import "core:time"

import gl "vendor:OpenGL"
import "vendor:glfw"

// NOTE: For everything that doesn't have a home yet

WINDOW_DEFAULT_TITLE :: "Heraclitus"
WINDOW_DEFAULT_W :: 1280 * 2
WINDOW_DEFAULT_H :: 720  * 2

FRAMES_IN_FLIGHT :: 3
TARGET_FPS :: 240
TARGET_FRAME_TIME_NS :: time.Duration(BILLION / TARGET_FPS)

GL_MAJOR :: 4
GL_MINOR :: 6

MAX_TEXTURE_HANDLES :: 512

POINT_SHADOW_MAP_SIZE  :: 512 * 2
SUN_SHADOW_MAP_SIZE    :: 512 * 8

Program_Mode :: enum {
  GAME,
  MENU,
  EDIT,
}

Frame_Info :: struct {
  fence: gl.sync_t,
}

MODEL_UP      :: vec3{0.0, 1.0, 0.0}
MODEL_RIGHT   :: vec3{1.0, 0.0, 0.0}
MODEL_FORWARD :: vec3{0.0, 0.0, 1.0}

WORLD_UP      :: vec3{0.0, 1.0,  0.0}
WORLD_RIGHT   :: vec3{1.0, 0.0,  0.0}
WORLD_FORWARD :: vec3{0.0, 0.0, -1.0}

RED    :: vec4{1.0, 0.0, 0.0,  1.0}
GREEN  :: vec4{0.0, 1.0, 0.0,  1.0}
BLUE   :: vec4{0.0, 0.0, 1.0,  1.0}
YELLOW :: vec4{1.0, 1.0, 0.0,  1.0}
CORAL  :: vec4{1.0, 0.5, 0.31, 1.0}
BLACK  :: vec4{0.0, 0.0, 0.0,  1.0}
WHITE  :: vec4{1.0, 1.0, 1.0,  1.0}

LEARN_OPENGL_BLUE   :: vec4{0.2, 0.3, 0.3, 1.0}
LEARN_OPENGL_ORANGE :: vec4{1.0, 0.5, 0.2, 1.0}

PATH_SLASH :: filepath.SEPARATOR_STRING

BILLION :: 1_000_000_000
PI      :: glsl.PI

F32_MIN :: min(f32)
F32_MAX :: max(f32)
U64_MAX :: max(u64)

// Purely for convenience because I am lazy and don't want to go to top of file to import a module to do a little print debugging
print :: fmt.printf

vec2 :: glsl.vec2
vec3 :: glsl.vec3
vec4 :: glsl.vec4

dvec2 :: glsl.dvec2
dvec3 :: glsl.dvec3
dvec4 :: glsl.dvec4

mat3 :: glsl.mat3
mat4 :: glsl.mat4

// Hmm, good idea? Just hate having to import and prepend for such common operations
dot        :: glsl.dot
cross      :: glsl.cross
normalize  :: glsl.normalize
normalize0 :: linalg.normalize0
length     :: glsl.length

cos :: glsl.cos
sin :: glsl.sin
radians :: glsl.radians

vmin :: glsl.min
vmax :: glsl.max

inverse           :: glsl.inverse
inverse_transpose :: glsl.inverse_transpose

mat4_translate :: glsl.mat4Translate
mat4_rotate    :: glsl.mat4Rotate
mat4_scale     :: glsl.mat4Scale

mat4_perspective  :: glsl.mat4Perspective
mat4_orthographic :: glsl.mat4Ortho3d
mat4_look_at      :: glsl.mat4LookAt

lerp :: glsl.lerp

// Adds a 1 to the end
vec4_from_3 :: proc(vec: vec3) -> vec4 {
  return {vec.x, vec.y, vec.z, 1.0}
}

squared_distance :: proc(a_pos: vec3, b_pos: vec3) -> f32 {
  delta := a_pos - b_pos

  return glsl.dot(delta, delta)
}

point_in_rect :: proc(point: vec2, left, top, bottom, right: f32) -> bool {
  return point.x >= left && point.x <= right && point.y >= top && point.y <= bottom
}

Window :: struct {
  handle:   glfw.WindowHandle,
  w, h:     int,
  title:    string,
  resized:  bool,
}

resize_window :: proc() {
  // Reset
  state.window.resized = false

  ok: bool

  // FIXME: We need to remember which framebuffers need to be the same size as the backbuffer...
  // Could maybe store all these in an map or something so we can just iterate and remember these
  state.hdr_ms_buffer, ok = remake_framebuffer(&state.hdr_ms_buffer, state.window.w, state.window.h)
  state.post_buffer, ok = remake_framebuffer(&state.post_buffer, state.window.w, state.window.h)
  state.ping_pong_buffers[0], ok = remake_framebuffer(&state.ping_pong_buffers[0], state.window.w, state.window.h)
  state.ping_pong_buffers[1], ok = remake_framebuffer(&state.ping_pong_buffers[1], state.window.w, state.window.h)

  if !ok {
    log.fatal("Window has been resized but unable to recreate multisampling framebuffer")
    state.running = false
  }

  log.infof("Window has resized to %vpx, %vpx", state.window.w, state.window.h)
}

resize_window_callback :: proc "c" (window: glfw.WindowHandle, width, height: i32) {
  gl.Viewport(0, 0, width, height)

  state.window.w = int(width)
  state.window.h = int(height)
  state.window.resized = true
}

get_aspect_ratio :: proc(window: Window) -> (aspect: f32) {
  aspect = f32(window.w) / f32(window.h)
  return aspect
}

should_close :: proc() -> bool {
  return bool(glfw.WindowShouldClose(state.window.handle)) || !state.running
}

draw_debug_stats :: proc() {
  text := fmt.aprintf(
`
FPS: %0.4v
Model Draw Calls: %v
Entities: %v
Mode: %v
Velocity: %0.4v
Speed: %0.4v
Position: %0.4v
On Ground: %v
Yaw: %0.4v
Pitch: %0.4v
Fov: %0.4v
Point Lights: %v
`,
  state.fps,
  state.draw_calls,
  len(state.entities),
  state.mode,
  state.camera.velocity,
  length(state.camera.velocity),
  state.camera.position,
  state.camera.on_ground,
  state.camera.yaw,
  state.camera.pitch,
  state.camera.curr_fov_y,
  len(state.point_lights) if state.point_lights_on else 0,
  allocator = context.temp_allocator)

  x := f32(state.window.w) * 0.0125
  y := f32(state.window.h) * 0.0125

  BOX_COLOR :: vec4{0.0, 0.0, 0.0, 0.7}
  BOX_PAD   :: 10.0
  box_width, box_height := text_draw_size(text, state.default_font)

  // HACK: Just looks a bit better to me, not going to work with all fonts probably
  box_height -= state.default_font.line_height * 0.5

  immediate_quad({x - BOX_PAD, y - BOX_PAD}, box_width + BOX_PAD * 2, box_height + BOX_PAD, BOX_COLOR)

  draw_text(text, state.default_font, x, y)
}
