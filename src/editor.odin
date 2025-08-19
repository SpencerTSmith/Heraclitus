package main

import "core:fmt"

import "vendor:glfw"

Editor_State :: struct {
  selected_entity: ^Entity,
}

@(private="file")
editor: Editor_State

pick_entity :: proc(screen_x, screen_y: f32, camera: Camera) -> (entity: ^Entity) {
  //
  // Convert screen position to world position
  //

  w := cast (f32) state.window.w
  h := cast (f32) state.window.h

  // From screen coords to ndc [-1, 1]
  ndc_x := 2 * (screen_x / w) - 1
  ndc_y := 1 - 2 * (screen_y / h) // flip y... as screen coords grow down
  ndc_z := cast(f32) -1.0 // Because screen is on the near plane

  ndc_coord := vec4{ndc_x, ndc_y, ndc_z, 1}

  // Where is this coord in the camera's view space, meaning we need to unproject
  inv_proj := inverse(get_camera_perspective(camera))
  view_coord := inv_proj * ndc_coord
  view_coord /= view_coord.w // And do perspective divide

  // Now undo the camera transform, put it into world space
  inv_view := inverse(get_camera_view(camera))
  world_coord := inv_view * view_coord

  ray := make_ray(camera.position, world_coord.xyz - camera.position)

  closest_t := F32_MAX
  for &e in state.entities {
    entity_aabb := entity_world_aabb(e)

    if yes, t_min, _ := ray_intersects_aabb(ray, entity_aabb); yes {
      // Get the closest entity
      if t_min < closest_t {
        entity = &e
      }
    }
  }

  return entity
}

move_camera_edit :: proc(camera: ^Camera, dt_s: f64) {
  if mouse_down(.MIDDLE) {
    update_camera_look(camera, dt_s)
  } else {
    glfw.SetInputMode(state.window.handle, glfw.CURSOR, glfw.CURSOR_NORMAL)
  }

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

  if mouse_pressed(.LEFT) {
    x, y := mouse_position()
    editor.selected_entity = pick_entity(x, y, camera^)
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

  draw_text_with_background(entity_text, state.default_font, x, y, YELLOW, align=.CENTER, padding=5.0)
}
