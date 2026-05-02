package main

import "base:runtime"
import "core:fmt"
import "core:log"
import "core:math/linalg"
import "core:math/linalg/glsl"
import "core:path/filepath"
import "core:os"

// NOTE: For everything that doesn't have a home yet
DEFAULT_FONT_SIZE :: 25.0

Program_Mode :: enum
{
  GAME,
  EDIT,
  MENU,
}

Point_Light :: struct
{
  position:    vec3,

  color:       vec4,

  radius:      f32,
  intensity:   f32,
  ambient:     f32,

  // TODO: Maybe flags
  cast_shadows: bool,
  dirty_shadow: bool, // For caching shadow maps
}

Direction_Light :: struct
{
  direction: vec3,

  color:     vec4,

  intensity: f32,
  ambient:   f32,
  cascades:  u32,
}

Spot_Light :: struct
{
  position:     vec3,
  direction:    vec3,

  color:        vec4,

  radius:       f32,
  intensity:    f32,
  ambient:      f32,

  // Cosines
  inner_cutoff: f32,
  outer_cutoff: f32,
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

set_alpha :: proc(color: vec4, alpha: f32) -> (tweaked: vec4)
{
  return {color.r, color.g, color.b, alpha}
}

PATH_SLASH :: filepath.SEPARATOR_STRING

BILLION :: 1_000_000_000
PI      :: glsl.PI

F32_MIN :: min(f32)
F32_MAX :: max(f32)
U64_MAX :: max(u64)

// Purely for convenience because I am lazy and don't want to go to top of file to import a module to do a little print debugging
print :: fmt.println

// Hmm, good idea? Just hate having to import and prepend for such common operations
vec2 :: glsl.vec2
vec3 :: glsl.vec3
vec4 :: glsl.vec4

mat3 :: glsl.mat3
mat4 :: glsl.mat4

dot        :: glsl.dot
cross      :: glsl.cross
normalize  :: glsl.normalize
normalize0 :: linalg.normalize0
length     :: glsl.length
sign       :: glsl.sign

cos :: glsl.cos
sin :: glsl.sin
tan :: glsl.tan
radians :: glsl.radians

vmin  :: glsl.min
vmax  :: glsl.max
round :: glsl.round
ceil  :: glsl.round
floor :: glsl.round

inverse           :: glsl.inverse
inverse_transpose :: glsl.inverse_transpose

mat4_translate :: glsl.mat4Translate
mat4_rotate    :: glsl.mat4Rotate
mat4_scale     :: glsl.mat4Scale

// For vulkan clip space.
mat4_perspective  :: proc(fovy, aspect, near, far: f32) -> (m: mat4)
{
	tan_half_fovy := tan(0.5 * fovy)
	m[0, 0] = 1 / (aspect * tan_half_fovy)
	m[1, 1] = -1 / (tan_half_fovy)
	m[2, 2] = -far / (far - near)
	m[3, 2] = -1
	m[2, 3] = -far * near / (far - near)

	return m
}

mat4_orthographic :: proc(left, right, bottom, top, near, far: f32) -> (m: mat4)
{
	m[0, 0] = +2 / (right - left)
	m[1, 1] = -2 / (top - bottom)
	m[2, 2] = -1 / (far - near)
	m[0, 3] = -(right + left)   / (right - left)
  m[1, 3] = -(bottom + top) / (bottom - top)
	m[2, 3] = -near / (far - near)
	m[3, 3] = 1

  return m
}
mat4_look_at :: glsl.mat4LookAt

lerp :: glsl.lerp

join_file_path :: proc(strings: []string, allocator: runtime.Allocator) -> (path: string)
{
  err: os.Error
  path, err = os.join_path(strings, allocator)

  // Shouldn't ever fire, but ok
  if err != nil
  {
    log.errorf("Failed to join filepath.")
  }

  return path
}

// Adds a 1 to the end by default
vec4_from_3 :: proc(vec: vec3, w: f32 = 1.0) -> vec4
{
  return {vec.x, vec.y, vec.z, w}
}

// NOTE: Unprojects the the near plane
// TODO: Maybe think about caching ray inverses if we are doing this operation a lot
unproject_screen_coord :: proc(screen_coord: vec2, view, proj: mat4) -> (world_coord: vec3)
{
  screen_width  := cast (f32) state.window.w
  screen_height := cast (f32) state.window.h

  // From screen coords to ndc [-1, 1]
  ndc_x := 2 * (screen_coord.x / screen_width) - 1
  ndc_y := 2 * (screen_coord.y / screen_height) - 1 // Since using a vulkan projection no need to flip
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

squared_distance :: proc(a_pos: vec3, b_pos: vec3) -> f32
{
  delta := a_pos - b_pos

  return dot(delta, delta)
}

Quad :: struct
{
  top_left: vec2,
  width:    f32,
  height:   f32,
}

point_in_rect :: proc(point: vec2, left, top, bottom, right: f32) -> bool
{
  return point.x >= left && point.x <= right && point.y >= top && point.y <= bottom
}

lerp_colors :: proc(t: f32, color_a, color_b: vec4) -> (lerped: vec4)
{
  t := t
  t *= t
  lerped = lerp(color_a, color_b, vec4{t, t, t, t})

  return lerped
}
