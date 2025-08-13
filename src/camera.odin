package main

import "core:math"
import "core:log"
import "core:math/linalg"
import "core:math/linalg/glsl"

CAMERA_UP :: vec3{0.0, 1.0, 0.0}

Camera :: struct {
  position:   vec3,
  velocity:   vec3,

  yaw, pitch:  f32, // Degrees
  sensitivity: f32,

  curr_fov_y:   f32, // Degrees
  target_fov_y: f32, // Degrees

  on_ground: bool,

  aabb: AABB,
}

update_camera_look :: proc(dt_s: f64) {

  // Don't really need the precision?
  x_delta := f32(state.input.mouse.curr_pos.x - state.input.mouse.prev_pos.x)
  y_delta := f32(state.input.mouse.curr_pos.y - state.input.mouse.prev_pos.y)

  state.camera.yaw   -= state.camera.sensitivity * x_delta
  state.camera.pitch -= state.camera.sensitivity * y_delta
  state.camera.pitch = clamp(state.camera.pitch, -89.0, 89.0)

  if mouse_scrolled_up() {
    state.camera.target_fov_y -= 5.0
  }
  if mouse_scrolled_down() {
    state.camera.target_fov_y += 5.0
  }
  state.camera.target_fov_y = clamp(state.camera.target_fov_y, 10.0, 120)

  CAMERA_ZOOM_SPEED :: 10.0
  state.camera.curr_fov_y = linalg.lerp(state.camera.curr_fov_y, state.camera.target_fov_y, CAMERA_ZOOM_SPEED * f32(dt_s))
}

update_camera_edit :: proc(camera: ^Camera, dt_s: f64) {
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

  FREECAM_SPEED :: 35.0
  camera.position += input_direction * FREECAM_SPEED * f32(dt_s)
  camera.velocity  = {0,0,0}
  camera.on_ground = false
}

update_camera_game :: proc(camera: ^Camera, dt_s: f64) {
  using linalg

  dt_s := f32(dt_s)

  wish_dir: vec3

  camera_forward, camera_up, camera_right := get_camera_axes(camera^)

  ground_forward := normalize0(vec3{camera_forward.x, 0, camera_forward.z})

  // Z, forward
  if key_down(.W) {
    wish_dir += ground_forward
  }
  if key_down(.S) {
    wish_dir -= ground_forward
  }
  // X, strafe
  if key_down(.D) {
    wish_dir += camera_right
  }
  if key_down(.A) {
    wish_dir -= camera_right
  }

  wish_dir.y = 0
  wish_dir = normalize0(wish_dir)

  //
  // Accelerate!
  //
  if length(wish_dir) > 0 {
    MAX_SPEED :: 40.0

    // How fast are we going in the direction we want to go?
    curr_speed_in_wish_dir := dot(camera.velocity, wish_dir)

    // How much to get to max speed from current speed?
    add_speed := MAX_SPEED - curr_speed_in_wish_dir

    // If we have room to grow in speed?
    if add_speed > 0 {
      GROUND_ACCELERATION :: 10.0
      AIR_ACCELERATION    :: 1.0

      factor: f32 = GROUND_ACCELERATION if camera.on_ground else AIR_ACCELERATION

      accel_speed := factor * MAX_SPEED * dt_s

      // If we can accelerate to more in this step than max, then just add only enough to get to max
      if accel_speed > add_speed {
        accel_speed = add_speed
      }

      acceleration := wish_dir * accel_speed

      camera.velocity += acceleration
    }
  }

  //
  // Friction
  //
  GROUND_FRICTION :: 6.0
  AIR_FRICTION    :: 0.2
  friction: f32 = GROUND_FRICTION if camera.on_ground else AIR_FRICTION
  speed := length(camera.velocity)

  if speed > 1 {
    // How much speed to lose per frame
    drop := speed * friction * dt_s

    new_speed := speed - drop

    // Just stop
    if new_speed < 0 { new_speed = 0 }

    new_speed /= speed

    applied := camera.velocity * new_speed

    camera.velocity = applied
  }

  //
  // Gravity! and Jumpin'
  //

  if key_pressed(.SPACE) && camera.on_ground {
    camera.velocity.y = 10.0
    camera.on_ground  = false
  }

  GRAVITY :: -30

  if !camera.on_ground {
    camera.velocity.y += GRAVITY * dt_s
  }

  //
  // Shitty Collision!
  //
  wish_pos := camera.position + camera.velocity * dt_s

  cam_aabb      := camera_world_aabb(camera^)
  wish_cam_aabb := cam_aabb
  wish_cam_aabb.min += (wish_pos - camera.position)
  wish_cam_aabb.max += (wish_pos - camera.position)

  if state.draw_debug {
    draw_aabb(cam_aabb)
    draw_aabb(wish_cam_aabb, CORAL)
  }

  for e in state.entities {
    if .HAS_COLLISION not_in e.flags { continue }
    entity_aabb := entity_world_aabb(e)

    if aabbs_intersect(wish_cam_aabb, entity_aabb) {
      offset := aabb_min_penetration_vector(wish_cam_aabb, entity_aabb)

      wish_pos += offset // push the camera out of collision

      // Surface normal, should be close to this right?
      normal := normalize0(offset)

      if normal.y > 0.1 {
        camera.on_ground = true
        camera.velocity.y = 0
        continue
      }

      // Reproject velocity
      OVERBOUNCE :: 1.4
      reproject := dot(camera.velocity, normal) * OVERBOUNCE
      camera.velocity -= reproject * normal // Only the velocity thats going into the wall gets subtracted away
    }
  }

  // Come to complete stop if going slow enough
  if length(camera.velocity) < 1 {
    camera.velocity = {0,0,0}
  }

  camera.position = wish_pos
}

get_camera_view :: proc(camera: Camera) -> (view: mat4) {
  forward := get_camera_forward(camera)
  // the target is the camera position + the forward direction
  return get_view(camera.position, forward, CAMERA_UP)
}

get_look_at :: proc(position, eye, up: vec3) -> (view: mat4) {
  return glsl.mat4LookAt(position, eye, up)
}

get_view :: proc(position, forward, up: vec3) -> (view: mat4) {
  return glsl.mat4LookAt(position, forward + position, up)
}

camera_world_aabb :: proc(c: Camera) -> AABB {
  world_aabb := transform_aabb(c.aabb, c.position, vec3{0,0,0}, vec3{1,1,1})

  return world_aabb
}

// Returns normalized
get_camera_forward :: proc(camera: Camera) -> (forward: vec3) {
  using camera
  rad_yaw   := glsl.radians_f32(yaw)
  rad_pitch := glsl.radians_f32(pitch)
  forward = {
    -math.cos(rad_pitch) * math.cos(rad_yaw),
    math.sin(rad_pitch),
    math.cos(rad_pitch) * math.sin(rad_yaw),
  }
  forward = linalg.normalize0(forward)

  return forward
}

get_camera_perspective :: proc(camera: Camera, z_far: f32 = state.z_far) -> (perspective: mat4){
  return get_perspective(camera.curr_fov_y, get_aspect_ratio(state.window), state.z_near, z_far)
}

// Fov in degrees
get_perspective :: proc(fov_y, aspect_ratio, z_near, z_far: f32) -> (perspective: mat4) {
  return glsl.mat4Perspective(glsl.radians(fov_y), aspect_ratio, z_near, z_far)
}

// Ehh this can go here
get_orthographic :: proc(left, right, bottom, top, z_near, z_far: f32) -> (orthographic: mat4) {
 return glsl.mat4Ortho3d(left, right, bottom, top, z_near, z_far);
}

get_camera_axes :: proc(camera: Camera) -> (forward, up, right: vec3) {
  forward = get_camera_forward(camera)
  up = CAMERA_UP
  right = linalg.normalize(glsl.cross(forward, up))
  return forward, up, right
}
