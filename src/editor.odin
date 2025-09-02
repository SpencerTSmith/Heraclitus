package main

import "core:fmt"
import "core:mem"
import "core:math/rand"

import "vendor:glfw"

AXIS_GIZMO_LENGTH :: 10.0

Editor_Gizmo :: enum {
  NONE,
  X_AXIS,
  Y_AXIS,
  Z_AXIS,
  XY_PLANE,
  XZ_PLANE,
  YZ_PLANE,
}

Editor_Gizmo_Info :: struct {
  hitbox: AABB,
}

Editor_State :: struct {
  selected_entity: ^Entity,
  selected_gizmo:  Editor_Gizmo,

  gizmos: [Editor_Gizmo]Editor_Gizmo_Info,
}

@(private="file")
editor: Editor_State

// TODO: Maybe these pick_* should just take in the unprojected point so don't have to recalc twice...
pick_entity :: proc(screen_x, screen_y: f32, camera: Camera) -> (entity: ^Entity) {
  world_coord := unproject_screen_coord(screen_x, screen_y, get_camera_view(camera), get_camera_perspective(camera))

  ray := make_ray(camera.position, world_coord - camera.position)

  closest_t := F32_MAX
  for &e in state.entities {
    entity_aabb := entity_world_aabb(e)
    if yes, t_min, _ := ray_intersects_aabb(ray, entity_aabb); yes {
      // Get the closest entity
      if t_min < closest_t {
        closest_t = t_min
        entity = &e
      }
    }
  }

  return entity
}

pick_gizmo :: proc(screen_x, screen_y: f32, camera: Camera) -> (gizmo: Editor_Gizmo) {
  world_coord := unproject_screen_coord(screen_x, screen_y, get_camera_view(camera), get_camera_perspective(camera))

  ray := make_ray(camera.position, world_coord - camera.position)

  gizmo = .NONE

  closest_t := F32_MAX
  for info, g in editor.gizmos {
    if yes, t_min, _ := ray_intersects_aabb(ray, info.hitbox); yes {
      // Get the closest gizmo
      if t_min < closest_t {
        closest_t = t_min
        gizmo = g
      }
    }
  }

  return gizmo
}

do_editor :: proc(camera: ^Camera, dt_s: f64) {
  if mouse_down(.MIDDLE) || key_down(.Q) {
    update_camera_look(camera, dt_s)
  } else {
    glfw.SetInputMode(state.window.handle, glfw.CURSOR, glfw.CURSOR_NORMAL)
  }

  dt_s := f32(dt_s)

  input_direction: vec3

  camera_forward, camera_up, camera_right := get_camera_axes(camera^)

  // Z, forward
  if key_down(.W) {
    input_direction += camera_forward
  }
  if key_down(.S) {
    input_direction -= camera_forward
  }

  // Y, vertical
  if key_down(.SPACE) {
    input_direction += camera_up
  }
  if key_down(.LEFT_CONTROL) {
    input_direction -= camera_up
  }

  // X, strafe
  if key_down(.D) {
    input_direction += camera_right
  }
  if key_down(.A) {
    input_direction -= camera_right
  }

  ui_was_interacted := false


  panel_pos := vec2 {f32(state.window.w) * 0.8, f32(state.window.h) * 0.1}

  panel, _ := make_ui_widget({.DRAW_BACKGROUND}, panel_pos, 300, 100, "")
  ui_push_parent(panel)
  {
    defer ui_pop_parent()

    if ui_button("Clear Entity").clicked {
      editor.selected_entity = nil

      ui_was_interacted = true
    }

    if ui_button("Duplicate Entity").clicked {
      dupe := duplicate_entity(editor.selected_entity^)
      dupe.position += (rand.float32() * 2.0) - 1.0
      append(&state.entities, dupe)

      // Should it auto select the copy?

      ui_was_interacted = true
    }
  }


  if !ui_was_interacted {
    // Pick entity or gizmo only if not doing ui
    if mouse_pressed(.LEFT) {
      x, y := mouse_position()

      // Preferentially pick gizmo first
      editor.selected_gizmo  = pick_gizmo(x, y, camera^)

      if editor.selected_gizmo == .NONE {
        editor.selected_entity = pick_entity(x, y, camera^)
      }
    }
  }

  // FIXME: While neat this method works, its not the best way to do it...
  // Blender does a different thing with ray intersecting a plane on the axis and taking the delta
  // Of the initial and current intersection points
  if editor.selected_gizmo != .NONE && mouse_down(.LEFT) {
    prev_x, prev_y := mouse_position_prev()
    curr_x, curr_y := mouse_position()

    prev_world := unproject_screen_coord(prev_x, prev_y, get_camera_view(camera^), get_camera_perspective(camera^))

    curr_world := unproject_screen_coord(curr_x, curr_y, get_camera_view(camera^), get_camera_perspective(camera^))

    // FIXME: JAAAAAANNNNNNKK!
    delta_world := (curr_world - prev_world) * 100.0
    delta_world = normalize0(delta_world)

    GIZMO_SENSITIVITY :: 0.2
    switch editor.selected_gizmo {
    case .NONE:
      assert(false, "What da")
    case .X_AXIS:
      delta_in_axis := dot(delta_world, WORLD_RIGHT)
      editor.selected_entity.position.x += delta_in_axis * GIZMO_SENSITIVITY
    case .Y_AXIS:
      delta_in_axis := dot(delta_world, WORLD_UP)
      editor.selected_entity.position.y += delta_in_axis * GIZMO_SENSITIVITY
    case .Z_AXIS:
      delta_in_axis := dot(delta_world, WORLD_FORWARD)
      editor.selected_entity.position.z -= delta_in_axis * GIZMO_SENSITIVITY
    case .XY_PLANE:
    case .XZ_PLANE:
    case .YZ_PLANE:
    }
  }

  if mouse_pressed(.RIGHT) {
    editor.selected_entity = nil
  }

  // Manipulate picked entity
  if editor.selected_entity != nil {
    EDITOR_PICKED_MOVE_SPEED :: 10.0

    // TODO: Think about if these should be relative to the camera's axes or to the world axes?
    // But won't matter as much once we get more sophisticated widgets and ui

    if key_down(.LEFT) {
      editor.selected_entity.position.x -= EDITOR_PICKED_MOVE_SPEED * dt_s
    }
    if key_down(.RIGHT) {
      editor.selected_entity.position.x += EDITOR_PICKED_MOVE_SPEED * dt_s
    }

    if key_down(.LEFT_SHIFT) {
      if key_down(.UP) {
        editor.selected_entity.position.z -= EDITOR_PICKED_MOVE_SPEED * dt_s
      }
      if key_down(.DOWN) {
        editor.selected_entity.position.z += EDITOR_PICKED_MOVE_SPEED * dt_s
      }
    } else {
      if key_down(.UP) {
        editor.selected_entity.position.y += EDITOR_PICKED_MOVE_SPEED * dt_s
      }
      if key_down(.DOWN) {
        editor.selected_entity.position.y -= EDITOR_PICKED_MOVE_SPEED * dt_s
      }
    }

    // Create gizmos
    {
      e := editor.selected_entity^
      entity_aabb := entity_world_aabb(e)
      entity_center := aabb_center(entity_aabb)

      create_axis_hitbox :: proc(axis_index: int, entity_center: vec3) -> (hitbox: AABB) {
        BOUNDING_RANGE :: 0.5

        // Since not all world directions in my coordinate space are in the positive direction
        world_axes := WORLD_AXES
        axis_add   := AXIS_GIZMO_LENGTH * world_axes[axis_index]

        hitbox = {
          min = entity_center - BOUNDING_RANGE,
          max = entity_center + BOUNDING_RANGE,
        }

        hitbox.max += axis_add

        return hitbox
      }

      editor.gizmos[.X_AXIS].hitbox = create_axis_hitbox(0, entity_center)
      editor.gizmos[.Y_AXIS].hitbox = create_axis_hitbox(1, entity_center)
      editor.gizmos[.Z_AXIS].hitbox = create_axis_hitbox(2, entity_center)
    }
  } else {
    // No active entity then clear out the gizmos
    editor.selected_gizmo = .NONE
    editor.gizmos[.X_AXIS].hitbox = {}
    editor.gizmos[.Y_AXIS].hitbox = {}
    editor.gizmos[.Z_AXIS].hitbox = {}
  }

  FREECAM_SPEED :: 35.0
  camera.position += input_direction * FREECAM_SPEED * f32(dt_s)
  camera.velocity  = {0,0,0}
  camera.on_ground = false
}

draw_editor_ui :: proc() {
  entity_text := fmt.tprintf("%v", editor.selected_entity^)

  x := f32(state.window.w) * 0.5
  y := f32(state.window.h) - f32(state.window.h) * 0.05

  draw_text_with_background(entity_text, state.default_font, x, y, YELLOW * 2.0, align=.CENTER, padding=10.0)

  //
  // Draw move widgets
  //
  if editor.selected_entity != nil {
    e := editor.selected_entity^
    aabb := entity_world_aabb(e)

    center_aabb := (aabb.min + aabb.max) * 0.5

    OPACITY :: 0.9

    //
    // Axes
    //
    {
      draw_vector(center_aabb, WORLD_RIGHT * AXIS_GIZMO_LENGTH,
                  set_alpha(RED, OPACITY), tip_bounds=0.25, depth_test = .ALWAYS)
      draw_vector(center_aabb, WORLD_UP * AXIS_GIZMO_LENGTH,
                  set_alpha(GREEN, OPACITY), tip_bounds=0.25, depth_test = .ALWAYS)
      draw_vector(center_aabb, WORLD_FORWARD * AXIS_GIZMO_LENGTH,
                  set_alpha(BLUE, OPACITY), tip_bounds=0.25, depth_test = .ALWAYS)

    }

    //
    // Move planes
    //
    {

      x_pos := center_aabb
      x_pos.x = aabb.min.x - 2.0
      immediate_quad(x_pos, WORLD_RIGHT, 1, 1, set_alpha(RED, OPACITY),
                     depth_test = Depth_Test_Mode.ALWAYS)

      y_pos := center_aabb
      y_pos.y = aabb.min.y - 2.0
      immediate_quad(y_pos, WORLD_UP, 1, 1, set_alpha(GREEN, OPACITY),
                     depth_test = Depth_Test_Mode.ALWAYS)

      z_pos := center_aabb + WORLD_FORWARD * (aabb.max.z + 2.0)
      z_pos.z = aabb.max.z + 2.0
      immediate_quad(z_pos, WORLD_FORWARD, 1, 1, set_alpha(BLUE, OPACITY),
                     depth_test = Depth_Test_Mode.ALWAYS)
    }
  }
}

// Eh, should this go in editor? This is useful even when testing in game mode
draw_debug_stats :: proc() {
  text := fmt.aprintf(
`FPS: %0.4v
Frametime: %0.4v ms
Mesh Draw Calls: %v
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
  state.mesh_draw_calls,
  state.perm.offset / mem.Kilobyte,
  len(state.entities),
  state.mode,
  state.camera.velocity,
  length(state.camera.velocity),
  state.camera.position,
  state.camera.on_ground,
  state.camera.yaw,
  state.camera.pitch,
  state.camera.curr_fov_y,
  state.bloom_on,
  state.sun_on,
  len(state.point_lights) if state.point_lights_on else 0,
  allocator = context.temp_allocator)

  x := f32(state.window.w) * 0.025
  y := f32(state.window.h) * 0.025

  draw_text_with_background(text, state.default_font, x, y, padding=10.0)
}
