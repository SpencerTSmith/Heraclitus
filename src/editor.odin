package main

import "core:fmt"
import "core:mem"
import "core:math/rand"
import "core:log"
// import "core:slice"

import "vendor:glfw"

Editor_Gizmo_Kind :: enum
{
  AXIS,
  PLANE,
  ROTATE,
}

// Could probably store a 'mask' of what directions this gizmo is allowed to move things in instead of the enum
Editor_Gizmo :: struct
{
  kind:   Editor_Gizmo_Kind,
  color:  vec4,
  basis:  [2]vec3,
  size:   f32,
  offset: f32,
}

Editor_State :: struct
{
  selected_entity: Entity_Handle,

  selected_gizmo: uint,

  // For manipulating entities
  hit_plane:         Plane,
  anchor_plane_hit:  vec3,
  anchor_entity_pos: vec3,
}

@(private="file")
editor: Editor_State

EDITOR_GIZMO_OPACITY :: 0.9
EDITOR_SELECTED_GIZMO_COLOR :: vec4 {WHITE.r, WHITE.g, WHITE.b, EDITOR_GIZMO_OPACITY}

AXIS_SIZE    :: 5
PLANE_SIZE   :: 2
PLANE_OFFSET :: 2

EDITOR_GIZMOS := []Editor_Gizmo {
  // Empty
  {},
  // X axis
  {
    kind  = .AXIS,
    basis = {WORLD_RIGHT, {}},
    color = {RED.r, RED.g, RED.b, EDITOR_GIZMO_OPACITY},
    size  = AXIS_SIZE,
  },
  // Y axis
  {
    kind  = .AXIS,
    basis = {WORLD_UP, {}},
    color = {GREEN.r, GREEN.g, GREEN.b, EDITOR_GIZMO_OPACITY},
    size  = AXIS_SIZE,
  },
  // Z axis
  {
    kind  = .AXIS,
    basis = {WORLD_FORWARD, {}},
    color = {BLUE.r, BLUE.g, BLUE.b, EDITOR_GIZMO_OPACITY},
    size  = AXIS_SIZE,
  },
  // XY plane
  {
    kind   = .PLANE,
    basis  = {WORLD_RIGHT, WORLD_UP},
    color  = {RED.r, RED.g, RED.b, EDITOR_GIZMO_OPACITY},
    size   = PLANE_SIZE,
    offset = PLANE_OFFSET,
  },
  // XZ plane
  {
    kind   = .PLANE,
    basis  = {WORLD_RIGHT, WORLD_FORWARD},
    color  = {GREEN.r, GREEN.g, GREEN.b, EDITOR_GIZMO_OPACITY},
    size   = PLANE_SIZE,
    offset = PLANE_OFFSET,
  },
  // YZ plane
  {
    kind   = .PLANE,
    basis  = {WORLD_UP, WORLD_FORWARD},
    color  = {BLUE.r, BLUE.g, BLUE.b, EDITOR_GIZMO_OPACITY},
    size   = PLANE_SIZE,
    offset = PLANE_OFFSET,
  },
  // XY Rotation
  {
    kind   = .ROTATE,
    basis  = {WORLD_RIGHT, WORLD_UP},
    color  = {RED.r, RED.g, RED.b, EDITOR_GIZMO_OPACITY},
    size   = PLANE_SIZE,
    offset = PLANE_OFFSET,
  },
}

editor_selected_entity_center :: proc() -> (center: vec3)
{
  selected_entity := get_entity(editor.selected_entity)
  assert(selected_entity != nil)
  entity_aabb := entity_world_aabb(selected_entity^)
  center = aabb_center(entity_aabb)

  return center
}

calc_axis_gizmo_visual :: proc(gizmo: Editor_Gizmo, center_around, camera_pos: vec3) -> (position, direction: vec3)
{
  // Flip around the visual position based on camera location
  visual_sign := sign(dot(camera_pos - center_around, gizmo.basis[0]))

  direction = gizmo.basis[0] * visual_sign
  position  = center_around + direction * gizmo.offset

  return position, direction
}

calc_plane_gizmo_visual :: proc(gizmo: Editor_Gizmo, center_around, camera_pos: vec3) -> (center, normal: vec3)
{
  // Flip around the visual positions based on camera location
  sign_0 := sign(dot(camera_pos - center_around, gizmo.basis[0]))
  sign_1 := sign(dot(camera_pos - center_around, gizmo.basis[1]))

  // Nestled in between respective axes
  normal = cross(gizmo.basis[0], gizmo.basis[1])
  center = center_around + ((sign_0 * gizmo.basis[0] + sign_1 * gizmo.basis[1])  * gizmo.offset)

  return center, normal
}

make_gizmo_hitbox :: proc(gizmo: Editor_Gizmo, center_around, camera_pos: vec3) -> (hitbox: AABB)
{
  switch gizmo.kind
  {
  case .AXIS:
    position, direction := calc_axis_gizmo_visual(gizmo, center_around, camera_pos)
    start := position
    stop  := position + (direction * gizmo.size)
    hitbox =
    {
      min = start - 0.25,
      max = stop  + 0.25,
    }
  case .PLANE:
    center, _ := calc_plane_gizmo_visual(gizmo, center_around, camera_pos)
    size_vector := (gizmo.basis[0] + gizmo.basis[1]) * (gizmo.size * 0.5)
    hitbox =
    {
      min = center - size_vector,
      max = center + size_vector,
    }
  case .ROTATE:
  }

  return hitbox
}

draw_gizmo :: proc(gizmo: Editor_Gizmo, center_around, camera_pos: vec3, color: vec4)
{
  switch gizmo.kind
  {
  case .AXIS:
    position, direction := calc_axis_gizmo_visual(gizmo, center_around, camera_pos)
    draw_vector(position, direction * gizmo.size, color, thickness=0.25, depth_test = .ALWAYS)
  case .PLANE:
    center, normal := calc_plane_gizmo_visual(gizmo, center_around, camera_pos)
    draw_quad(center, normal, gizmo.size, gizmo.size, color, depth_test = .ALWAYS)
  case .ROTATE:
  }
}

pick_gizmo :: proc(ray: Ray, center_around: vec3, camera_pos: vec3) -> (gizmo: uint)
{
  gizmo = 0

  closest_t := F32_MAX
  for g, i in EDITOR_GIZMOS
  {
    hitbox := make_gizmo_hitbox(g, center_around, camera_pos)
    if yes, t_min, _ := ray_intersects_aabb(ray, hitbox); yes
    {
      // Get the closest gizmo
      if t_min < closest_t
      {
        closest_t = t_min
        gizmo = uint(i)
      }
    }
  }

  return gizmo
}

@(private="file")
clear_editor_selected_entity :: proc()
{
  editor.selected_entity = {}
}

move_camera_editor :: proc(camera: ^Camera, dt_s: f64)
{
  if mouse_down(.MIDDLE) || key_down(.Q)
  {
    glfw.SetInputMode(state.window.handle, glfw.CURSOR, glfw.CURSOR_DISABLED)
    update_camera_look(camera, mouse_position_delta(), dt_s)
  }
  else
  {
    glfw.SetInputMode(state.window.handle, glfw.CURSOR, glfw.CURSOR_NORMAL)
  }

  dt_s := f32(dt_s)

  input_direction: vec3

  camera_forward, _, camera_right := get_camera_axes(camera^)

  // Z, forward
  if key_down(.W)
  {
    input_direction += camera_forward
  }
  if key_down(.S)
  {
    input_direction -= camera_forward
  }

  // Y, vertical, but in world space not camera up
  if key_down(.SPACE)
  {
    input_direction += WORLD_UP
  }
  if key_down(.LEFT_CONTROL)
  {
    input_direction -= WORLD_UP
  }

  // X, strafe
  if key_down(.D)
  {
    input_direction += camera_right
  }
  if key_down(.A)
  {
    input_direction -= camera_right
  }

  FREECAM_SPEED :: 35.0
  camera.position += input_direction * FREECAM_SPEED * f32(dt_s)
  camera.velocity  = {0,0,0}
  camera.on_ground = false
}

editor_ui :: proc() -> (had_interaction: bool)
{
  panel_pos := vec2 {f32(state.window.w) * 0.8, f32(state.window.h) * 0.1}
  ui_push_parent(ui_panel(panel_pos, 300, 100))
  {
    defer ui_pop_parent()

    if entity_handle_valid(editor.selected_entity)
    {
      if ui_button("Clear Entity").clicked
      {
        clear_editor_selected_entity()
      }

      if ui_button("Dupe Entity").clicked
      {
        dupe := duplicate_entity(editor.selected_entity)
        get_entity(dupe).position += (rand.float32() * 2.0) - 1.0

        log.infof("Copied entity at index %v", editor.selected_entity)
      }

      // TODO: Probably just work on pool strucuture... needs to be done at some point at there are bugs when removing entities right now
      // specifically when that entity has an attached point light, does not get removed.
      if ui_button("Delete Entity").clicked
      {
        remove_entity(editor.selected_entity)
        clear_editor_selected_entity()
      }
    }
  }

  return ui_had_interaction()
}

do_editor :: proc(camera: ^Camera, dt_s: f64)
{
  move_camera_editor(camera, dt_s)

  had_ui_interaction := editor_ui()

  //
  // 3D Editor interactions
  //
  world_coord := unproject_screen_coord(mouse_position(), camera_view(camera^), camera_perspective(camera^, window_aspect_ratio(state.window)))
  mouse_ray := make_ray(camera.position, world_coord - camera.position)

  // Find out if clicked on gizmo or entity
  if !had_ui_interaction && mouse_pressed(.LEFT)
  {

    // Try to select a gizmo
    if selected_entity := get_entity(editor.selected_entity); selected_entity != nil
    {
      picked_gizmo := pick_gizmo(mouse_ray, editor_selected_entity_center(), state.camera.position)

      // Try picking a gizmo first, if not, then try picking an entity
      if picked_gizmo != 0
      {
        editor.selected_gizmo = picked_gizmo

        // Plane should be orthogonal to camera
        editor.hit_plane = make_plane(-camera_forward(camera^), selected_entity.position)

        intersect, t, hit_point := ray_intersects_plane(mouse_ray, editor.hit_plane)
        if intersect && t >= 0.0
        {
          editor.anchor_plane_hit = hit_point
          editor.anchor_entity_pos = selected_entity.position
        }
      }
    }

    // Pick an entity if no gizmo
    if editor.selected_gizmo == 0
    {
      editor.selected_entity = pick_entity(mouse_ray)
    }
  }

  if selected_entity := get_entity(editor.selected_entity); selected_entity != nil
  {
    hovered_gizmo := pick_gizmo(mouse_ray, editor_selected_entity_center(), state.camera.position)

    // Draw the gizmos
    for gizmo, i in EDITOR_GIZMOS
    {
      color := gizmo.color
      if uint(i) == editor.selected_gizmo
      {
        // Selected is flashing
        t := cast(f32)cos(seconds_since_start() * 8.0)
        flashing_color := lerp_colors(t, color, EDITOR_SELECTED_GIZMO_COLOR)
        color = flashing_color
      }
      else if uint(i) == hovered_gizmo
      {
        // Hovered is brightened
        color.rgb *= 3.0
      }

      draw_gizmo(gizmo, editor_selected_entity_center(), state.camera.position, color)
    }

    // Move with the gizmo
    if editor.selected_gizmo != 0 && mouse_down(.LEFT)
    {
      the_gizmo := EDITOR_GIZMOS[editor.selected_gizmo]

      intersect, _, hit_now := ray_intersects_plane(mouse_ray, editor.hit_plane)
      if intersect
      {

        delta_plane := hit_now - editor.anchor_plane_hit

        basis := the_gizmo.basis

        // Now project the move in the plane onto the basis vectors
        move_0 := dot(delta_plane, basis[0]) * basis[0]
        move_1 := dot(delta_plane, basis[1]) * basis[1]
        delta_in_world := move_0 + move_1

        selected_entity.position = editor.anchor_entity_pos + delta_in_world

        // Visualize the movement
        draw_vector(editor.anchor_entity_pos, delta_in_world, YELLOW, depth_test = .ALWAYS)
      }
    }
  }

  // Unselect gizmo when not held down
  if mouse_released(.LEFT)
  {
    editor.selected_gizmo = 0
  }

  if mouse_pressed(.RIGHT)
  {
    clear_editor_selected_entity()
  }
}

draw_debug_stats :: proc()
{
  text := fmt.aprintf(
`FPS: %0.4v
Frametime: %0.4v ms
Draw Commands: %v
Vertices: %v
Perm Arena: %v KB
Entities: %v
Mode: %v
Velocity: %0.4v
Speed: %0.4v
Position: %0.4v
On Ground: %v
Yaw: %0.4v
Pitch: %0.4v
Fov: %0.4v
Bloom On: %v
Sun On: %v
Point Lights: %v`,
  state.fps,
  (1.0 / state.fps) * 1000,
  state.renderer.draw_count,
  state.renderer.vertex_count,
  state.perm.offset / mem.Kilobyte,
  len(state.entities.pool),
  state.mode,
  state.camera.velocity,
  length(state.camera.velocity),
  state.camera.position,
  state.camera.on_ground,
  state.camera.yaw,
  state.camera.pitch,
  state.camera.curr_fov_y,
  state.renderer.bloom_on,
  state.sun_on,
  len(state.point_lights),
  allocator = context.temp_allocator)

  x := f32(state.window.w) * 0.025
  y := f32(state.window.h) * 0.025

  draw_text_with_background(text, state.default_font, x, y, padding=10.0)
}
