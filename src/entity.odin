package main

import "core:log"

Entity_Flags :: enum {
  COLLISION,
  RENDERABLE,
  STATIC, // Should never 'move'
}

Entity :: struct {
  flags:    bit_set[Entity_Flags],

  position: vec3,
  scale:    vec3,
  rotation: vec3,

  velocity: vec3,

  model:    Model_Handle,
}

make_entity :: proc(model:    string,
                    flags:    bit_set[Entity_Flags] = {.COLLISION, .RENDERABLE},
                    position: vec3   = {0, 0, 0},
                    rotation: vec3   = {0, 0, 0},
                    scale:    vec3   = {1, 1, 1}) -> Entity {
  model, ok := load_model(model)
  if !ok {
    // TODO: Unique handles for each entity would make debugging simpler
    log.warnf("Entity failed to load model: %v", model)
  }

  if .STATIC in flags {
    assert(.STATIC in flags, "Static entities must have collsion")
  }

  entity := Entity {
    flags    = flags,
    position = position,
    scale    = scale,
    rotation = rotation,
    model    = model,
  }

  return entity
}

entity_has_transparency :: proc(e: Entity) -> bool {
  model := get_model(e.model)

  return model_has_transparency(model^)
}

draw_entity :: proc(e: Entity, color: vec4 = WHITE, instances: int = 1, draw_aabbs := false) {
  if draw_aabbs {
    draw_aabb(entity_world_aabb(e))

    // for mesh in model.meshes {
    //   draw_aabb(transform_aabb(mesh.aabb, e.position, e.rotation, e.scale), BLUE)
    // }
  }

  if .RENDERABLE not_in e.flags { return }

  model := get_model(e.model)

  set_shader_uniform("model", entity_model_mat4(e))
  draw_model(model^, mul_color=color, instances=instances)
}

// TODO: Cache these and only recomputing if we've moved
entity_world_aabb :: proc(e: Entity) -> AABB {
  model      := get_model(e.model)
  world_aabb := transform_aabb(model.aabb, e.position, e.rotation, e.scale)

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
