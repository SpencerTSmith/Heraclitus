package main

import "core:fmt"
import "core:mem"
import "core:math/rand"
import "core:log"

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

// Could probably store a 'mask' of what directions this gizmo is allowed to move things in instead of the enum
Editor_Gizmo_Info :: struct {
  hitbox: AABB,

  // For manipulating entities
  hit_plane:         Plane,
  anchor_plane_hit:  vec3,
  anchor_entity_pos: vec3,
}

Editor_State :: struct {
  selected_entity: ^Entity,
  selected_entity_idx: int,

  selected_gizmo: Editor_Gizmo,
  gizmos: [Editor_Gizmo]Editor_Gizmo_Info,
}

@(private="file")
editor: Editor_State

pick_entity :: proc(ray: Ray, camera: Camera) -> (entity: ^Entity, index: int) {
  closest_t := F32_MAX
  for &e, idx in state.entities {
    entity_aabb := entity_world_aabb(e)
    if yes, t_min, _ := ray_intersects_aabb(ray, entity_aabb); yes {
      // Get the closest entity
      if t_min < closest_t {
        closest_t = t_min
        entity = &e
        index = idx
      }
    }
  }

  return entity, index
}

pick_gizmo :: proc(ray: Ray, camera: Camera) -> (gizmo: Editor_Gizmo) {
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

  // FIXME: This sucks
  ui_was_interacted := false

  panel_pos := vec2 {f32(state.window.w) * 0.8, f32(state.window.h) * 0.1}
  ui_push_parent(ui_panel(panel_pos, 300, 100))
  {
    defer ui_pop_parent()

    if ui_button("Clear Entity").clicked {
      editor.selected_entity = nil

      // FIXME: This sucks
      ui_was_interacted = true
    }

    if ui_button("Dupe Entity").clicked {
      if editor.selected_entity != nil {
        dupe := duplicate_entity(editor.selected_entity^)
        dupe.position += (rand.float32() * 2.0) - 1.0
        append(&state.entities, dupe)
        // Should it auto select the copy?
      }

      // FIXME: This sucks
      ui_was_interacted = true
    }

    if ui_button("Delete Entity").clicked {
      if editor.selected_entity != nil {
        unordered_remove(&state.entities, editor.selected_entity_idx)
        editor.selected_entity = nil
      }

      // FIXME: This sucks
      ui_was_interacted = true
    }
  }

  //
  // 3D Editor interactions
  //
  screen_x, screen_y := mouse_position()
  world_coord := unproject_screen_coord(screen_x, screen_y, get_camera_view(camera^), get_camera_perspective(camera^))
  mouse_ray := make_ray(camera.position, world_coord - camera.position)

  // FIXME: This seems hacky
  if ui_was_interacted {
    editor.selected_gizmo = .NONE
  }

  if !ui_was_interacted {
    // Pick entity or gizmo only if not doing ui
    if mouse_pressed(.LEFT) {

      // If we can select a gizmo
      if editor.selected_entity != nil {
        // Preferentially pick gizmo first
        editor.selected_gizmo  = pick_gizmo(mouse_ray, camera^)
        the_gizmo := &editor.gizmos[editor.selected_gizmo]

        // Plane should be orthogonal to camera
        normal := -get_camera_forward(state.camera)

        hit_plane := make_plane(normal, editor.selected_entity.position)
        the_gizmo.hit_plane = hit_plane

        intersect, t, hit_point := ray_intersects_plane(mouse_ray, the_gizmo.hit_plane)
        assert(intersect)
        the_gizmo.anchor_plane_hit = hit_point
        the_gizmo.anchor_entity_pos = editor.selected_entity.position
      }

      // If we didn't select a gizmo
      if editor.selected_gizmo == .NONE {
        editor.selected_entity, editor.selected_entity_idx = pick_entity(mouse_ray, camera^)
      }
    }
  }

  if editor.selected_gizmo != .NONE && mouse_down(.LEFT) {
    the_gizmo := editor.gizmos[editor.selected_gizmo]

    intersect, _, hit_now := ray_intersects_plane(mouse_ray, the_gizmo.hit_plane)
    assert(intersect)

    delta_plane := hit_now - the_gizmo.anchor_plane_hit

    basis_0, basis_1: vec3
    switch editor.selected_gizmo {
    case .NONE:
      assert(false, "What da")
    case .X_AXIS:
      basis_0 = WORLD_RIGHT
    case .Y_AXIS:
      basis_0 = WORLD_UP
    case .Z_AXIS:
      basis_0 = -WORLD_FORWARD
    case .XY_PLANE:
      basis_0 = WORLD_RIGHT
      basis_1 = WORLD_UP
    case .XZ_PLANE:
      basis_0 = WORLD_RIGHT
      basis_1 = -WORLD_FORWARD
    case .YZ_PLANE:
      basis_0 = WORLD_UP
      basis_1 = -WORLD_FORWARD
    }

    // Now project the move in the plane into the world
    move_0 := dot(delta_plane, basis_0) * basis_0
    move_1 := dot(delta_plane, basis_1) * basis_1
    delta_in_world := move_0 + move_1

    editor.selected_entity.position = the_gizmo.anchor_entity_pos + delta_in_world
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

      make_axis_hitbox :: proc(axis_index: int, entity_center: vec3) -> (hitbox: AABB) {
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

      make_plane_hitbox :: proc(position: vec3) -> (hitbox: AABB) {
        BOUNDING_RANGE :: 0.5

        hitbox = {
          min = position - BOUNDING_RANGE,
          max = position + BOUNDING_RANGE,
        }

        return hitbox
      }

      OPACITY :: 0.9

      editor.gizmos[.X_AXIS].hitbox = make_axis_hitbox(0, entity_center)
      editor.gizmos[.Y_AXIS].hitbox = make_axis_hitbox(1, entity_center)
      editor.gizmos[.Z_AXIS].hitbox = make_axis_hitbox(2, entity_center)
      draw_vector(entity_center, WORLD_RIGHT * AXIS_GIZMO_LENGTH,
                  set_alpha(RED, OPACITY), tip_bounds=0.25, depth_test = .ALWAYS)
      draw_vector(entity_center, WORLD_UP * AXIS_GIZMO_LENGTH,
                  set_alpha(GREEN, OPACITY), tip_bounds=0.25, depth_test = .ALWAYS)
      draw_vector(entity_center, WORLD_FORWARD * AXIS_GIZMO_LENGTH,
                  set_alpha(BLUE, OPACITY), tip_bounds=0.25, depth_test = .ALWAYS)

      immediate_begin(.TRIANGLES, {}, .WORLD, .ALWAYS)
      xy_pos := entity_center
      xy_pos.z = entity_aabb.max.z + 2.0
      editor.gizmos[.XY_PLANE].hitbox = make_plane_hitbox(xy_pos)
      immediate_quad(xy_pos, WORLD_FORWARD, 1, 1, set_alpha(RED, OPACITY))

      xz_pos := entity_center
      xz_pos.y = entity_aabb.min.y - 2.0
      editor.gizmos[.XZ_PLANE].hitbox = make_plane_hitbox(xz_pos)
      immediate_quad(xz_pos, WORLD_UP, 1, 1, set_alpha(GREEN, OPACITY))

      yz_pos := entity_center
      yz_pos.x = entity_aabb.min.x - 2.0
      editor.gizmos[.YZ_PLANE].hitbox = make_plane_hitbox(yz_pos)
      immediate_quad(yz_pos, WORLD_RIGHT, 1, 1, set_alpha(BLUE, OPACITY))
    }
  } else {
    // No active entity then clear out the gizmos
    editor.selected_gizmo = .NONE

    for &giz in editor.gizmos {
      giz = {}
    }
  }

  FREECAM_SPEED :: 35.0
  camera.position += input_direction * FREECAM_SPEED * f32(dt_s)
  camera.velocity  = {0,0,0}
  camera.on_ground = false
}

// These can maybe just be draw directly after we make them instad of having this function
draw_editor_gizmos :: proc() {
  entity_text := fmt.tprintf("%v", editor.selected_entity^)

  x := f32(state.window.w) * 0.5
  y := f32(state.window.h) - f32(state.window.h) * 0.05

  draw_text_with_background(entity_text, state.default_font, x, y, YELLOW * 2.0, align=.CENTER, padding=10.0)
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
