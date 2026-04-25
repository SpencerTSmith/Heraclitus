package main

import "core:log"

Entity_Flag :: enum
{
  UNUSED,
  COLLISION,
  RENDERABLE,
  STATIC, // Should never 'move'
}
Entity_Flags :: bit_set[Entity_Flag]

Entity_Handle :: struct
{
  slot: u32,
  age:  u32,
}

Entities :: struct
{
  pool: [dynamic; 8192]Entity,
  first_free: Entity_Handle,
}

// TODO: Point light should probably be a handle and not a pointer, depends on if we keep the global point light array as dynamic
Entity :: struct
{
  age: u32,
  next_free: Entity_Handle, // Should be 0 if this is a valid entity

  flags: Entity_Flags,

  position: vec3,
  scale:    vec3,
  rotation: vec3,
  velocity: vec3,

  color: vec4,
  model: Model_Handle,

  point_light: ^Point_Light,
}

init_entities :: proc()
{
  // First entity slot is invalid
  alloc_entity()
}

all_entities :: proc() -> (entities: []Entity)
{
  return state.entities.pool[:]
}

entity_handle_valid :: proc(handle: Entity_Handle) -> bool
{
  return handle != {} && state.entities.pool[handle.slot].age == handle.age
}

@(private="file")
alloc_entity :: proc() -> (handle: Entity_Handle)
{
  // Try to use free list
  if state.entities.first_free != {}
  {
    free_slot := get_entity(state.entities.first_free)
    assert(.UNUSED in free_slot.flags, "An entity in the free list was not unused.")

    handle = state.entities.first_free

    state.entities.first_free = free_slot.next_free
    free_slot.next_free = {}

    log.infof("Reused entity %v", handle)
  }
  else
  {
    // Add to end if no free
    appended := append(&state.entities.pool, Entity{})

    if appended != 0
    {
      handle.slot = u32(len(state.entities.pool)) - 1
      handle.age  = 0
    }
    else
    {
      log.errorf("Attempted to make entity while entity pool is full.")
    }
  }

  return handle
}

// TODO: Maybe these entity creations should just create entities into whatever data structure I decide on instead of creating a single
// And then copying into data structure... this is fine for now while I don't know what data structure gonna go with... I mean probably pool
// or fridge thing but...

// NOTE: Automatically sets the aabb of the entity to match the AABB of the model
make_entity :: proc(model_file: string = "",
                    flags: bit_set[Entity_Flag] = {.COLLISION, .RENDERABLE},
                    position: vec3 = {0, 0, 0},
                    rotation: vec3 = {0, 0, 0},
                    scale:    vec3 = {1, 1, 1},
                    color:    vec4 = {1, 1, 1, 1}) -> (handle: Entity_Handle)
{
  handle = alloc_entity()

  if handle != {}
  {
    model := load_model(model_file)

    assert(.STATIC not_in flags || .COLLISION in flags, "Static entities must have collsion.")

    entity := get_entity(handle)
    entity.flags    = flags
    entity.position = position
    entity.scale    = scale
    entity.rotation = rotation
    entity.color    = color
    entity.model    = model
  }

  return handle
}

//
// Common entity combos
//
make_point_light_entity :: proc(position: vec3, color: vec4, radius, intensity: f32, cast_shadows := false) -> (handle: Entity_Handle)
{
  // FIXME
  append(&state.point_lights, Point_Light {
    position  = position,
    color     = color,
    intensity = 0.7,
    radius    = radius,
    cast_shadows = cast_shadows,
    dirty_shadow = true,
  })

  handle = make_entity(position=position, color=color, flags={})
  get_entity(handle).point_light = &state.point_lights[len(state.point_lights) - 1]

  return handle
}

duplicate_entity :: proc(handle: Entity_Handle) -> (duplicate: Entity_Handle)
{
  if e := get_entity(handle); e != nil
  {
    // Need to make a new point light, model handle is fine to be copied as that's already handled by asset system
    if e.point_light != nil
    {
      pl := e.point_light
      duplicate = make_point_light_entity(e.position, pl.color, pl.radius, pl.intensity, pl.cast_shadows)
    }
    else
    {
      // HACK: doesn't sit right with me
      duplicate = alloc_entity()
      copy_data := e^
      copy_data.age = duplicate.age
      get_entity(duplicate)^ = copy_data
    }
  }

  return duplicate
}

get_entity :: proc(handle: Entity_Handle) -> (entity: ^Entity)
{
  if entity_handle_valid(handle)
  {
    entity = &state.entities.pool[handle.slot]
  }

  return entity
}

remove_entity :: proc(handle: Entity_Handle)
{
  if slot := get_entity(handle); slot != nil
  {
    new_age := slot.age + 1
    slot^ = {}
    slot.next_free = state.entities.first_free
    slot.age = new_age
    slot.flags |= {.UNUSED}

    state.entities.first_free = {handle.slot, new_age}
    log.infof("Removed entity %v", handle)
  }
}

entity_has_transparency :: proc(e: Entity) -> bool
{
  model := get_model(e.model)

  return model_has_transparency(model^)
}

// NOTE: This layer of drawing deals with assets not being present yet
// the draw_model call is only for if we KNOW the model is loaded
draw_entity :: proc(e: Entity, color: vec4 = WHITE, instances: int = 1, draw_aabbs := false, light_index: u32 = 0)
{
  if draw_aabbs
  {
    MAX_DISTANCE :: 75.0
    // Don't have to do the sqrt haha
    if squared_distance(e.position, state.camera.position) < (MAX_DISTANCE * MAX_DISTANCE)
    {
      draw_aabb(entity_world_aabb(e))
    }
  }

  if .RENDERABLE in e.flags
  {
    model := get_model(e.model)
    draw_model(model^, model_mat=entity_model_mat4(e), mul_color=color, instances=instances, light_index=light_index)
  }
}

// TODO: Cache these and only recompute if we've moved
entity_world_aabb :: proc(e: Entity) -> (world_aabb: AABB) {
  model := get_model(e.model)
  world_aabb = transform_aabb(model.aabb, e.position, e.rotation, e.scale)

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

pick_entity :: proc(ray: Ray) -> (handle: Entity_Handle)
{
  closest_t := F32_MAX
  for &e, idx in all_entities()
  {
    entity_aabb := entity_world_aabb(e)
    if yes, t_min, _ := ray_intersects_aabb(ray, entity_aabb); yes
    {
      // Get the closest entity
      if t_min < closest_t
      {
        closest_t = t_min

        handle = { u32(idx), e.age }
      }
    }
  }

  return handle
}
