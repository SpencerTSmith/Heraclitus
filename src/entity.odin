package main

import "core:math/linalg/glsl"


Entity_Flags :: enum {
  HAS_COLLISION,
  HAS_RENDERABLE,
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
                    flags:    bit_set[Entity_Flags] = {.HAS_COLLISION, .HAS_RENDERABLE},
                    position: vec3   = {0, 0, 0},
                    rotation: vec3   = {0, 0, 0},
                    scale:    vec3   = {1, 1, 1}) -> Entity {
  model, ok := load_model(model)
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

draw_entity :: proc(e: Entity, color: vec4 = WHITE, instances: int = 0) {
  if .HAS_RENDERABLE not_in e.flags { return }

  model := get_model(e.model)

  if state.draw_debug {
    draw_aabb(entity_world_aabb(e))
  }

  set_shader_uniform("model", entity_model_mat4(e))
  draw_model(model^, mul_color=color, instances=instances)
}

// Could think about caching these and only recomputing if we've moved
// NOTE: This does not ROTATE the aabb!
entity_world_aabb :: proc(e: Entity) -> AABB {
  model      := get_model(e.model)
  world_aabb := transform_aabb_fast(model.aabb, e.position, e.rotation, e.scale)
  // world_aabb := transform_aabb(model.aabb, entity_model_mat4(e))

  return world_aabb
}

// yxz euler angle
entity_model_mat4 :: proc(entity: Entity) -> (model: mat4) {
  translation := glsl.mat4Translate(entity.position)
  rotation_y  := glsl.mat4Rotate({0.0, 1.0, 0.0}, glsl.radians_f32(entity.rotation.y))
  rotation_x  := glsl.mat4Rotate({1.0, 0.0, 0.0}, glsl.radians_f32(entity.rotation.x))
  rotation_z  := glsl.mat4Rotate({0.0, 0.0, 1.0}, glsl.radians_f32(entity.rotation.z))
  scale       := glsl.mat4Scale(entity.scale)

  model = translation * rotation_y * rotation_x * rotation_z * scale
  return model
}
