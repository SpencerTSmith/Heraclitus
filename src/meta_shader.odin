package main

import "core:strings"
import "core:fmt"
import "core:os"
import "core:reflect"
import "core:log"
import "core:time"

// NOTE: This is simply a little meta-program to reduce code duplication between glsl and odin

UBO_Bind :: enum u32 {
  FRAME    = 0,
  TEXTURES = 1,
}

MAX_POINT_LIGHTS :: 128

Point_Light_Uniform :: struct #align(16) {
  proj_views:    [6]mat4,

  position:  vec4,

  color:     vec4,

  radius:    f32,
  intensity: f32,
  ambient:   f32,
}

Direction_Light_Uniform :: struct #align(16) {
  proj_view: mat4,

  direction: vec4,

  color:     vec4,

  intensity: f32,
  ambient:   f32,
}

Frame_Uniform :: struct {
  projection:      mat4,
  orthographic:    mat4,
  view:            mat4,
  proj_view:       mat4,
  camera_position: vec4,
  z_near:          f32,
  z_far:           f32,
  scene_extents:   vec4,

  sun_light:    Direction_Light_Uniform,
  point_lights: [MAX_POINT_LIGHTS]Point_Light_Uniform,
  points_count: u32,
  flash_light:  Spot_Light_Uniform,
}

Spot_Light_Uniform :: struct #align(16) {
  position:     vec4,
  direction:    vec4,
  color:        vec4,

  radius:       f32,
  intensity:    f32,
  ambient:      f32,

  inner_cutoff: f32,
  outer_cutoff: f32,
}

gen_glsl_code :: proc() {
  b := strings.builder_make(allocator=context.temp_allocator)

  buf: [time.MIN_YYYY_DATE_LEN]u8
  buf2: [time.MIN_HMS_12_LEN]u8
  now := time.now()
  date  := time.to_string_dd_mm_yyyy(now, buf[:])
  hours := time.to_string_hms_12(now, buf2[:])
  fmt.sbprintf(&b, "// NOTE: This code was generated on %v (%v)\n\n", date, hours)

  // Gotta have it
  fmt.sbprint(&b, "#extension GL_ARB_bindless_texture : require\n\n")

  to_glsl_basic_type_string :: proc(type: typeid) -> string {
    s: string
    switch type {
    case f32:
      s = "float"
    case mat4:
      s = "mat4"
    case vec4:
      s = "vec4"
    case u32:
      s = "int"
    }

    return s
  }

  //
  // Parse and append uniform structs
  //

  // FIXME: Make sure that if we encounter a structure it has already been parsed
  // Also just other more rigorous things as described in later comments
  to_glsl_struct :: proc(b: ^strings.Builder, t: typeid) {
    assert(reflect.is_struct(type_info_of(t)))

    fmt.sbprintf(b, "struct %v {{\n", t)
    for field in reflect.struct_fields_zipped(t) {
      if reflect.is_struct(field.type) {
        // TODO: Assert that we have already generated the code for this struct, if not we need to go do that before we generate this struct
        // GLSL does not allow out of order declaration
        fmt.sbprintf(b, "  %v %v;\n", field.type.id, field.name)
      } else {
        basic := to_glsl_basic_type_string(field.type.id)

        // Wasn't one of the above basic types
        if basic == "" {
          info := reflect.type_info_base(type_info_of(field.type.id))

          // Is it an array?
          if reflect.is_array(info) {
            array_info := info.variant.(reflect.Type_Info_Array)

            // Is it possibly an array of basic types?
            array_type := to_glsl_basic_type_string(array_info.elem.id)

            if array_type == "" {
              // NOTE: Its an array of structures probably, but an assumption
              assert(reflect.is_struct(array_info.elem), "Unkown array type enountered for GLSL Code Generation")

              fmt.sbprintf(b, "  %v %v[%v];\n", array_info.elem.id, field.name, array_info.count)
            } else {
              // Its an array of basic types
              fmt.sbprintf(b, "  %v %v[%v];\n", array_type, field.name, array_info.count)
            }
          } else {
            log.errorf("Uh oh, don't know how to handle this type for GLSL Code Generation: %v", field)
          }
        } else { // Was just a basic type
          fmt.sbprintf(b, "  %v %v;\n", basic, field.name)
        }
      }
    }
    fmt.sbprint(b, "};\n\n")
  }

  // TODO: There's gotta be some way to 'tag' structs as ones that need to match up with the generated GLSL code
  // That way, don't need to remember to add it here and can instead
  to_glsl_struct(&b, Direction_Light_Uniform)
  to_glsl_struct(&b, Spot_Light_Uniform)
  to_glsl_struct(&b, Point_Light_Uniform)
  to_glsl_struct(&b, Frame_Uniform)

  //
  // Generate buffer bindings
  //
  bind_names: [UBO_Bind]string
  for e in UBO_Bind {
    enum_string, ok := fmt.enum_value_to_string(e)
    if !ok {
      log.errorf("GLSL Code Generation unable to map UBO Bind point enum to string %v", e)
    }

    bind_names[e] = fmt.tprintf("%v_BINDING", enum_string)

    fmt.sbprintf(&b, "#define %v %v\n", bind_names[e], int(e))
  }
  fmt.sbprintln(&b)
  fmt.sbprintf(&b, "layout(binding = %v, std140) uniform Frame_Uniform_UBO {{\n", bind_names[.FRAME])
  fmt.sbprintf(&b, "  %v frame;\n", typeid_of(Frame_Uniform))
  fmt.sbprintf(&b, "};\n\n")

  fmt.sbprintf(&b, "layout(binding = %v, std430) readonly buffer Texture_Handles {{\n", bind_names[.TEXTURES])
  fmt.sbprintf(&b, "  sampler2D textures[];\n")
  fmt.sbprintf(&b, "};\n\n")

  append_always := `
vec4 bindless_sample(int index, vec2 uv) {
  return texture(textures[index], uv);
}
`

  fmt.sbprint(&b, append_always)

  os.write_entire_file(SHADER_DIR + "generated.glsl", transmute([]u8) strings.to_string(b))
}

spot_light_uniform :: proc(light: Spot_Light) -> (uniform: Spot_Light_Uniform) {
  uniform = Spot_Light_Uniform{
    position  = vec4_from_3(light.position),
    direction = vec4_from_3(light.direction),

    color     = light.color,

    radius    = light.radius,
    intensity = light.intensity,
    ambient   = light.ambient,

    inner_cutoff = light.inner_cutoff,
    outer_cutoff = light.outer_cutoff,
  }

  return uniform
}

point_light_uniform :: proc(light: Point_Light) -> (uniform: Point_Light_Uniform) {
  uniform = Point_Light_Uniform{
    proj_views = point_light_projviews(light),
    position   = vec4_from_3(light.position),

    color     = light.color,

    radius    = light.radius,
    intensity = light.intensity,
    ambient   = light.ambient,
  }

  return uniform
}

// FIXME: AHHHHHHH... just learn how to do cascaded shadow maps
@(private)
prev_center: vec3

direction_light_uniform :: proc(light: Direction_Light) -> (uniform: Direction_Light_Uniform) {
  scene_bounds: f32 = 50.0
  sun_distance: f32 = 50.0

  center := state.camera.position

  // FIXME: Just a hack to prevent shadow swimming until i can unstick my head out of my ass and figure
  // out the texel snapping shit
  if length(center - prev_center) < 10.0 {
    center = prev_center
  }

  prev_center = center

  light_proj := mat4_orthographic(-scene_bounds, scene_bounds, -scene_bounds, scene_bounds, 5.0, sun_distance * 2.0)

  sun_position := center - (light.direction * sun_distance)
  light_view := mat4_look_at(sun_position, center, WORLD_UP)

  uniform = Direction_Light_Uniform {
    proj_view = light_proj * light_view,

    direction = vec4_from_3(light.direction),

    color     = light.color,

    intensity = light.intensity,
    ambient   = light.ambient,
  }

  return uniform
}


// NOTE: Assumes the shadow CUBE map is a CUBE so 1:1 aspect ratio for each side
point_light_projviews :: proc(light: Point_Light) -> [6]mat4 {
  Z_NEAR :: f32(1.0)
  ASPECT :: f32(1.0)
  FOV    :: f32(90.0)

  proj := mat4_perspective(radians(FOV), ASPECT, Z_NEAR, light.radius)
  projviews := [6]mat4{
    proj * get_view(light.position.xyz, { 1.0,  0.0,  0.0}, {0.0, -1.0,  0.0}),
    proj * get_view(light.position.xyz, {-1.0,  0.0,  0.0}, {0.0, -1.0,  0.0}),
    proj * get_view(light.position.xyz, { 0.0,  1.0,  0.0}, {0.0,  0.0,  1.0}),
    proj * get_view(light.position.xyz, { 0.0, -1.0,  0.0}, {0.0,  0.0, -1.0}),
    proj * get_view(light.position.xyz, { 0.0,  0.0,  1.0}, {0.0, -1.0,  0.0}),
    proj * get_view(light.position.xyz, { 0.0,  0.0, -1.0}, {0.0, -1.0,  0.0}),
  }

  return projviews
}
