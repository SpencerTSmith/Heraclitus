package main

import "core:log"

Entity_Flags :: enum {
  COLLISION,
  RENDERABLE,
  STATIC, // Should never 'move'
}

// TODO: Point light should probably be a handle and not a pointer, depends on if we keep the global point light array as dynamic
Entity :: struct {
  flags:    bit_set[Entity_Flags],

  position: vec3,
  scale:    vec3,
  rotation: vec3,

  velocity: vec3,

  color: vec4,

  model: Model_Handle,

  point_light: ^Point_Light, // Optional
}

// NOTE: Automatically sets the aabb of the entity to match the AABB of the model
make_entity :: proc(model: string,
                    flags: bit_set[Entity_Flags] = {.COLLISION, .RENDERABLE},
                    position: vec3 = {0, 0, 0},
                    rotation: vec3 = {0, 0, 0},
                    scale:    vec3 = {1, 1, 1},
                    color:    vec4 = {1, 1, 1, 1}) -> Entity {
  model, ok := load_model(model)
  if !ok {
    log.warnf("Entity failed to load model: %v", model)
  }

  assert(.STATIC not_in flags || .COLLISION in flags, "Static entities must have collsion")

  entity := Entity {
    flags    = flags,
    position = position,
    scale    = scale,
    rotation = rotation,
    color    = color,

    model    = model,
  }

  return entity
}

//
// Common entity combos
//
make_point_light_entity :: proc(position: vec3, color: vec4, radius, intensity: f32, cast_shadows := false) -> Entity {
  append(&state.point_lights, Point_Light {
    position  = position,
    color     = color,
    intensity = 0.7,
    radius    = radius,
    cast_shadows = cast_shadows,
  })

  entity := Entity {
    position = position,
    scale    = {1, 1, 1},
    color    = color,
    point_light = &state.point_lights[len(state.point_lights) - 1],
  }

  return entity
}

entity_has_transparency :: proc(e: Entity) -> bool {
  model := get_model(e.model)

  if model != nil {
    return model_has_transparency(model^)
  } else {
    return false
  }
}

// NOTE: This layer of drawing deals with assets not being present yet
// the draw_model call is only for if we KNOW the model is loaded
draw_entity :: proc(e: Entity, color: vec4 = WHITE, instances: int = 1, draw_aabbs := false) {
  if draw_aabbs {
    draw_aabb(entity_world_aabb(e))

    // for mesh in model.meshes {
    //   draw_aabb(transform_aabb(mesh.aabb, e.position, e.rotation, e.scale), BLUE)
    // }
  }

  if .RENDERABLE not_in e.flags { return }

  model := get_model(e.model)

  if model != nil {
    set_shader_uniform("model", entity_model_mat4(e))
    set_shader_uniform("mul_color", e.color)

    draw_model(model^, mul_color=color, instances=instances)
  } else {
    log.warnf("Tried to draw entity with unloaded model")
  }
}

// TODO: Cache these and only recompute if we've moved
entity_world_aabb :: proc(e: Entity) -> (world_aabb: AABB) {
  model := get_model(e.model)

  // If it has a model
  if model != nil {
    world_aabb = transform_aabb(model.aabb, e.position, e.rotation, e.scale)
  }

  return world_aabb
}

// yxz euler angle
entity_model_mat4 :: proc(e: Entity) -> (model: mat4) {
  t   := mat4_translate(e.position)
  r_y := mat4_rotate(MODEL_UP,      radians(e.rotation.y))
  r_x := mat4_rotate(MODEL_RIGHT,   radians(e.rotation.x))
  r_z := mat4_rotate(MODEL_FORWARD, radians(e.rotation.z))
  s   := mat4_scale(e.scale)

  model = t * r_y * r_x * r_z * s
  return model
}
