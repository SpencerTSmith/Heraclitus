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
WINDOW_DEFAULT_W :: 1280
WINDOW_DEFAULT_H :: 720

FRAMES_IN_FLIGHT :: 3
TARGET_FPS :: 240
TARGET_FRAME_TIME_NS :: time.Duration(BILLION / TARGET_FPS)

GL_MAJOR :: 4
GL_MINOR :: 6

MAX_TEXTURE_HANDLES :: 512

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

WORLD_AXES :: [3]vec3{WORLD_RIGHT, WORLD_UP, WORLD_FORWARD}

RED    :: vec4{1.0, 0.0, 0.0,  1.0}
GREEN  :: vec4{0.0, 1.0, 0.0,  1.0}
BLUE   :: vec4{0.0, 0.0, 1.0,  1.0}
YELLOW :: vec4{1.0, 1.0, 0.0,  1.0}
CORAL  :: vec4{1.0, 0.5, 0.31, 1.0}
BLACK  :: vec4{0.0, 0.0, 0.0,  1.0}
WHITE  :: vec4{1.0, 1.0, 1.0,  1.0}

LEARN_OPENGL_BLUE   :: vec4{0.2, 0.3, 0.3, 1.0}
LEARN_OPENGL_ORANGE :: vec4{1.0, 0.5, 0.2, 1.0}

set_alpha :: proc(color: vec4, alpha: f32) -> (tweaked: vec4) {
  return {color.r, color.g, color.b, alpha}
}

PATH_SLASH :: filepath.SEPARATOR_STRING

BILLION :: 1_000_000_000
PI      :: glsl.PI

F32_MIN :: min(f32)
F32_MAX :: max(f32)
U64_MAX :: max(u64)

// Purely for convenience because I am lazy and don't want to go to top of file to import a module to do a little print debugging
print :: fmt.printf

// Hmm, good idea? Just hate having to import and prepend for such common operations
vec2 :: glsl.vec2
vec3 :: glsl.vec3
vec4 :: glsl.vec4

dvec2 :: glsl.dvec2
dvec3 :: glsl.dvec3
dvec4 :: glsl.dvec4

mat3 :: glsl.mat3
mat4 :: glsl.mat4

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

//
// Static array that acts like it is dynamic
//
Array :: struct($Type: typeid, $Capacity: int) {
  data:  [Capacity]Type,
  count: int,
}

array_slice :: proc(array: ^$A/Array($Type, $Capacity)) -> []Type {
  return array.data[:array.count]
}

array_add :: proc(array: ^$A/Array($Type, $Capacity), item: Type) {
  assert(array.count < Capacity, "Not enough elements in static array!")
  array.data[array.count] = item

  array.count += 1
}

// Adds a 1 to the end by default
vec4_from_3 :: proc(vec: vec3, w: f32 = 1.0) -> vec4 {
  return {vec.x, vec.y, vec.z, w}
}

// NOTE: Unprojects the the near plane
// TODO: Maybe think about caching inverse if we are doing this operation a lot
unproject_screen_coord :: proc(screen_x, screen_y: f32, view, proj: mat4) -> (world_coord: vec3){
  screen_width  := cast (f32) state.window.w
  screen_height := cast (f32) state.window.h

  // From screen coords to ndc [-1, 1]
  ndc_x := 2 * (screen_x / screen_width) - 1
  ndc_y := 1 - 2 * (screen_y / screen_height) // flip y... as screen coords grow down
  ndc_z := cast(f32) -1.0 // Because screen is on the near plane

  ndc_coord := vec4{ndc_x, ndc_y, ndc_z, 1}

  // Where is this coord in the camera's view space, meaning we need to unproject
  inv_proj := inverse(proj)
  view_coord := inv_proj * ndc_coord
  view_coord /= view_coord.w // And do perspective divide

  // Now undo the camera transform, put it into world space
  inv_view := inverse(view)
  world_coord = (inv_view * view_coord).xyz

  return world_coord
}

squared_distance :: proc(a_pos: vec3, b_pos: vec3) -> f32 {
  delta := a_pos - b_pos

  return dot(delta, delta)
}

Quad :: struct {
  top_left: vec2,
  width:    f32,
  height:   f32,
}

point_in_rect :: proc(point: vec2, left, top, bottom, right: f32) -> bool {
  return point.x >= left && point.x <= right && point.y >= top && point.y <= bottom
}

Window :: struct {
  handle:  glfw.WindowHandle,
  w, h:    int,
  title:   string,
  resized: bool,
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

  gl.Viewport(0, 0, cast(i32)state.window.w, cast(i32)state.window.h)

  if !ok {
    log.fatal("Window has been resized but unable to recreate multisampling framebuffer")
    state.running = false
  }

  assert(state.window.w == state.hdr_ms_buffer.width &&
         state.window.h == state.hdr_ms_buffer.height)

  log.infof("Window has resized to %vpx, %vpx", state.window.w, state.window.h)
}

window_aspect_ratio :: proc(window: Window) -> (aspect: f32) {
  aspect = f32(window.w) / f32(window.h)
  return aspect
}

should_close :: proc() -> bool {
  return bool(glfw.WindowShouldClose(state.window.handle)) || !state.running
}
