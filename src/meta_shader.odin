package main

import "core:strings"
import "core:fmt"
import "core:os"
import "core:reflect"
import "core:log"

// NOTE: This is simply a little meta-program to reduce code duplication between glsl and odin

UBO_Bind :: enum u32 {
  FRAME    = 0,
  TEXTURES = 1,
}

MAX_POINT_LIGHTS :: 128

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

gen_glsl_code :: proc() {
  b := strings.builder_make(allocator=context.temp_allocator)

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
        fmt.sbprintf(b, "  %v %v;\n", field.type.id, field.name)
      } else {
        s := to_glsl_basic_type_string(field.type.id)

        // Wasn't one of the above basic types
        if s == "" {
          info := reflect.type_info_base(type_info_of(field.type.id))

          // Is it an array?
          if reflect.is_array(info) {
            array_type := info.variant.(reflect.Type_Info_Array)
            count := array_type.count

            basic_type := to_glsl_basic_type_string(array_type.elem.id)

            if basic_type == "" {
              // FIXME: Its an array of structures probably, but an assumption
              fmt.sbprintf(b, "  %v %v[%v];\n", array_type.elem.id, field.name, count)
            } else {
              // Its an array of basic types
              fmt.sbprintf(b, "  %v %v[%v];\n", basic_type, field.name, count)
            }
          } else {
            log.errorf("Uh oh, don't know how to handle this type for GLSL Code Generation: %v", field)
          }
        } else { // Was just a basic type
          fmt.sbprintf(b, "  %v %v;\n", s, field.name)
        }
      }
    }
    fmt.sbprint(b, "};\n\n")
  }

  to_glsl_struct(&b, Direction_Light_Uniform)
  to_glsl_struct(&b, Spot_Light_Uniform)
  to_glsl_struct(&b, Point_Light_Uniform)
  to_glsl_struct(&b, Frame_Uniform)

  //
  // Generate bind points
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
