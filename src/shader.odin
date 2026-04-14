package main

import "base:runtime"
import "core:os"
import "core:log"
import "core:strings"
import "core:fmt"
import "core:time"
import "core:slice"
import "core:reflect"

import sc "shaderc"

SHADER_DIR :: "shaders" + PATH_SLASH

Pipeline_Key :: enum
{
  PHONG,
  SKYBOX,
  RESOLVE_HDR,
  SUN_DEPTH,
  POINT_DEPTH,
  GAUSSIAN,
  GET_BRIGHT,
}

Shader_Type :: enum u32
{
  VERTEX,
  FRAGMENT,
  COMPUTE,
}

Pipeline :: struct
{
  internal: Renderer_Internal,

  // NOTE: Does not store the full path, just the name
  files: [Shader_Type]struct
  {
    name:        string,
    modify_time: time.Time,
  },
}

// NOTE: This is simply a little meta-program to reduce code duplication between glsl and odin

UBO_Bind :: enum u32
{
  FRAME         = 0,
  MATERIALS     = 1,
  DRAW_UNIFORMS = 2,
  MESH_VERTICES = 3,
  IMM_VERTICES  = 4,
}

MAX_SHADOW_POINT_LIGHTS :: 8
MAX_POINT_LIGHTS :: 128

Shadow_Point_Light_Uniform :: struct #align(16)
{
  proj_views: [6]mat4,

  position:  vec4,

  color:     vec4,

  radius:    f32,
  intensity: f32,
  ambient:   f32,
}

Point_Light_Uniform :: struct #align(16)
{
  position:  vec4,

  color:     vec4,

  radius:    f32,
  intensity: f32,
  ambient:   f32,
}

Direction_Light_Uniform :: struct #align(16)
{
  proj_view: mat4,

  direction: vec4,

  color:     vec4,

  intensity: f32,
  ambient:   f32,
}

Spot_Light_Uniform :: struct #align(16)
{
  position:     vec4,
  direction:    vec4,
  color:        vec4,

  radius:       f32,
  intensity:    f32,
  ambient:      f32,

  inner_cutoff: f32,
  outer_cutoff: f32,
}

Material_Uniform :: struct
{
  // Handles
  diffuse:  u64,
  specular: u64,
  emissive: u64,
  normal:   u64,

  shininess: f32,
}

Frame_Uniform :: struct
{
  projection:      mat4,
  orthographic:    mat4,
  view:            mat4,
  proj_view:       mat4,
  camera_position: vec4,
  z_near:          f32,
  z_far:           f32,
  scene_extents:   vec4,

  shadow_point_lights: [MAX_SHADOW_POINT_LIGHTS]Shadow_Point_Light_Uniform,
  shadow_points_count: u32,

  point_lights: [MAX_POINT_LIGHTS]Point_Light_Uniform,
  points_count: u32,

  sun_light:    Direction_Light_Uniform,
  flash_light:  Spot_Light_Uniform,
}

Draw_Command :: struct
{
  count:          u32,
  instance_count: u32,
  first_index:    u32,
  base_vertex:    u32,
  base_instance:  u32,
}

// Maybe consider pulling these out, these could just be indices, since will be redundantly uploading for passes drawing the same objects, shadow mapping, main passes, etc.
Draw_Uniform :: struct
{
  model:     mat4,
  mul_color: vec4,

  material_index: u32,
  light_index:    u32, // Here for point light shader
}

Nil_Push :: struct {}

@(private="file")
to_glsl_basic_type_string :: proc(type: typeid, allow_vec4: bool) -> string
{
  s: string
  switch type {
  case f32:
    s = "float"
  case mat4:
    s = "mat4"
  case vec4:
    if allow_vec4 { s = "vec4" }
  case u32:
    s = "int"
  case i32:
    s = "int"
  case u64:
    s = "sampler2D" // HACK: !!!
  }

  return s
}

@(private="file")
to_glsl_struct :: proc(b: ^strings.Builder, t: typeid, prefix: string = "struct", suffix: string = "", allow_vec4: bool = true)
{
  assert(reflect.is_struct(type_info_of(t)))

  fmt.sbprintf(b, "%v %v {{\n", prefix, t)
  for field in reflect.struct_fields_zipped(t)
  {
    if reflect.is_struct(field.type)
    {
      // TODO: Assert that we have already generated the code for this struct, if not we need to go do that before we generate this struct
      // GLSL does not allow out of order declaration
      fmt.sbprintf(b, "  %v %v;\n", field.type.id, field.name)
    }
    else
    {
      basic := to_glsl_basic_type_string(field.type.id, allow_vec4)

      // Wasn't one of the above basic types
      if basic == ""
      {
        info := reflect.type_info_base(type_info_of(field.type.id))

        // Is it an array?
        if reflect.is_array(info)
        {
          array_info := info.variant.(reflect.Type_Info_Array)

          // Is it possibly an array of basic types?
          array_type := to_glsl_basic_type_string(array_info.elem.id, allow_vec4)

          if array_type == ""
          {
            // NOTE: Its an array of structures probably, but an assumption
            assert(reflect.is_struct(array_info.elem), "Unkown array type enountered for GLSL Code Generation")

            fmt.sbprintf(b, "  %v %v[%v];\n", array_info.elem.id, field.name, array_info.count)
          }
          else
          {
            // Its an array of basic types
            fmt.sbprintf(b, "  %v %v[%v];\n", array_type, field.name, array_info.count)
          }
        }
        else
        {
          log.errorf("Uh oh, don't know how to handle this type for GLSL Code Generation: %v", field)
        }
      }
      else
      { // Was just a basic type
        fmt.sbprintf(b, "  %v %v;\n", basic, field.name)
      }
    }
  }
  fmt.sbprintf(b, "}%v;\n\n", suffix)
}


gen_glsl_code :: proc()
{
  b := strings.builder_make(allocator=context.temp_allocator)

  buf: [time.MIN_YYYY_DATE_LEN]u8
  buf2: [time.MIN_HMS_12_LEN]u8
  now := time.now()
  date  := time.to_string_dd_mm_yyyy(now, buf[:])
  hours := time.to_string_hms_12(now, buf2[:])
  fmt.sbprintf(&b, "// NOTE: This code was generated on %v (%v)\n\n", date, hours)

  // Gotta have it
  fmt.sbprint(&b, "#extension GL_ARB_bindless_texture : require\n\n")

  //
  // Parse and append uniform structs
  //

  // TODO: There's gotta be some way to 'tag' structs as ones that need to match up with the generated GLSL code
  // That way, don't need to remember to add it here and can instead
  to_glsl_struct(&b, Direction_Light_Uniform)
  to_glsl_struct(&b, Spot_Light_Uniform)
  to_glsl_struct(&b, Shadow_Point_Light_Uniform)
  to_glsl_struct(&b, Point_Light_Uniform)
  to_glsl_struct(&b, Material_Uniform)
  to_glsl_struct(&b, Draw_Uniform)
  to_glsl_struct(&b, Frame_Uniform)
  to_glsl_struct(&b, Mesh_Vertex, allow_vec4 = false)
  to_glsl_struct(&b, Immediate_Vertex, allow_vec4 = false)

  //
  // Generate buffer bindings
  //
  bind_names: [UBO_Bind]string
  for e in UBO_Bind
  {
    enum_string, ok := fmt.enum_value_to_string(e)
    if !ok
    {
      log.errorf("GLSL Code Generation unable to map UBO Bind point enum to string %v", e)
    }

    bind_names[e] = fmt.tprintf("%v_BINDING", enum_string)

    fmt.sbprintf(&b, "#define %v %v\n", bind_names[e], int(e))
  }
  fmt.sbprintln(&b)
  fmt.sbprintf(&b, "layout(binding = %v, std140) uniform Frame_Uniform_UBO {{\n",
               bind_names[.FRAME])
  fmt.sbprintf(&b, "  %v frame;\n", typeid_of(Frame_Uniform))
  fmt.sbprintf(&b, "};\n\n")

  fmt.sbprintf(&b, "layout(binding = %v, std430) readonly buffer Mesh_Materials {{\n",
               bind_names[.MATERIALS])
  fmt.sbprintf(&b, "  Material_Uniform materials[];\n")
  fmt.sbprintf(&b, "};\n\n")

  fmt.sbprintf(&b, "layout(binding = %v, std430) readonly buffer Draw_Uniforms {{\n",
               bind_names[.DRAW_UNIFORMS])
  fmt.sbprintf(&b, "  Draw_Uniform draw_uniforms[];\n")
  fmt.sbprintf(&b, "};\n\n")

  fmt.sbprintf(&b, "layout(binding = %v, std430) readonly buffer Mesh_Vertices {{\n",
               bind_names[.MESH_VERTICES])
  fmt.sbprintf(&b, "  Mesh_Vertex mesh_vertices[];\n")
  fmt.sbprintf(&b, "};\n\n")

  fmt.sbprintf(&b, "layout(binding = %v, std430) readonly buffer Immediate_Vertices {{\n",
               bind_names[.IMM_VERTICES])
  fmt.sbprintf(&b, "  Immediate_Vertex immediate_vertices[];\n")
  fmt.sbprintf(&b, "};\n\n")

  // TODO: Can probably generate these instead of hard coding, might not be worth the effort...
  append_always := `
vec3 mesh_vertex_position(int index)
{
  return vec3(mesh_vertices[index].position[0],
              mesh_vertices[index].position[1],
              mesh_vertices[index].position[2]);
}
vec2 mesh_vertex_uv(int index)
{
  return vec2(mesh_vertices[index].uv[0],
              mesh_vertices[index].uv[1]);
}
vec3 mesh_vertex_normal(int index)
{
  return vec3(mesh_vertices[index].normal[0],
              mesh_vertices[index].normal[1],
              mesh_vertices[index].normal[2]);
}
vec4 mesh_vertex_tangent(int index)
{
  return vec4(mesh_vertices[index].tangent[0],
              mesh_vertices[index].tangent[1],
              mesh_vertices[index].tangent[2],
              mesh_vertices[index].tangent[3]);
}

vec3 immediate_vertex_position(int index)
{
  return vec3(immediate_vertices[index].position[0],
              immediate_vertices[index].position[1],
              immediate_vertices[index].position[2]);
}
vec2 immediate_vertex_uv(int index)
{
  return vec2(immediate_vertices[index].uv[0],
              immediate_vertices[index].uv[1]);
}
vec4 immediate_vertex_color(int index)
{
  return vec4(immediate_vertices[index].color[0],
              immediate_vertices[index].color[1],
              immediate_vertices[index].color[2],
              immediate_vertices[index].color[3]);
}

`

  fmt.sbprint(&b, append_always)

  err: os.Error
  err = os.write_entire_file(SHADER_DIR + "generated.glsl", transmute([]u8) strings.to_string(b))
  if err != nil
  {
    log.errorf("Failed to write meta shader.")
  }
}

spot_light_uniform :: proc(light: Spot_Light) -> (uniform: Spot_Light_Uniform)
{
  uniform =
  {
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

shadow_point_light_uniform :: proc(light: Point_Light) -> (uniform: Shadow_Point_Light_Uniform)
{
  uniform =
  {
    proj_views = point_light_projviews(light),
    position   = vec4_from_3(light.position),

    color     = light.color,

    radius    = light.radius,
    intensity = light.intensity,
    ambient   = light.ambient,
  }

  return uniform
}

point_light_uniform :: proc(light: Point_Light) -> (uniform: Point_Light_Uniform)
{
  uniform =
  {
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

direction_light_uniform :: proc(light: Direction_Light) -> (uniform: Direction_Light_Uniform)
{
  scene_bounds: f32 = 50.0
  sun_distance: f32 = 50.0

  center := state.camera.position

  // FIXME: Just a hack to prevent shadow swimming until i can unstick my head out of my ass and figure
  // out the texel snapping shit
  if length(center - prev_center) < 10.0
  {
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
point_light_projviews :: proc(light: Point_Light) -> [6]mat4
{
  Z_NEAR :: f32(1.0)
  ASPECT :: f32(1.0)
  FOV    :: f32(90.0)

  proj := mat4_perspective(radians(FOV), ASPECT, Z_NEAR, light.radius)
  projviews: [6]mat4 =
  {
    proj * get_view(light.position.xyz, { 1.0,  0.0,  0.0}, {0.0, -1.0,  0.0}),
    proj * get_view(light.position.xyz, {-1.0,  0.0,  0.0}, {0.0, -1.0,  0.0}),
    proj * get_view(light.position.xyz, { 0.0,  1.0,  0.0}, {0.0,  0.0,  1.0}),
    proj * get_view(light.position.xyz, { 0.0, -1.0,  0.0}, {0.0,  0.0, -1.0}),
    proj * get_view(light.position.xyz, { 0.0,  0.0,  1.0}, {0.0, -1.0,  0.0}),
    proj * get_view(light.position.xyz, { 0.0,  0.0, -1.0}, {0.0, -1.0,  0.0}),
  }

  return projviews
}

material_uniform :: proc(material: Material) -> (uniform: Material_Uniform)
{
  diffuse  := get_texture(material.diffuse)
  specular := get_texture(material.specular)
  emissive := get_texture(material.emissive)
  normal   := get_texture(material.normal)

  // NOTE: Only send over the info if all the textures have been loaded
  if diffuse  != nil &&
     specular != nil &&
     emissive != nil &&
     normal   != nil
  {
     // NOTE: We are bindless with materials now!
     // So we just send over indexes

     // uniform.diffuse  = diffuse.handle
     // uniform.specular = specular.handle
     // uniform.emissive = emissive.handle
     // uniform.normal   = normal.handle

     uniform.shininess = material.shininess
  }
  else
  {
    // TODO: Maybe consider having the missing purple texture always
    // present at a specific index in the texture_handles ssbo
    // so that can be set instead,
    log.warnf("Tried to set material with unloaded material")
  }

  return uniform
}


// NOTE: Injects push constant if passed
@(private="file")
compile_shader_file :: proc(allocator: runtime.Allocator, file_name: string, type: Shader_Type, $push: typeid) -> (code: []byte, put_push, ok: bool)
{
  source, err := os.read_entire_file(file_name, context.temp_allocator)

  has_push := push != Nil_Push

  if err == nil
  {
    ok = true

    // Resolve all #includes and #push_constants
    lines := strings.split_lines(string(source), context.temp_allocator)

    include_builder := strings.builder_make_none(context.temp_allocator)
    for line in lines
    {
      trim := strings.trim_space(line)
      if strings.starts_with(trim, "#include")
      {
        first := strings.index(trim, "\"")
        last  := strings.last_index(trim, "\"")

        if first != -1 && last > first
        {
          file     := trim[first + 1:last]
          rel_path := join_file_path({SHADER_DIR, file}, context.temp_allocator)

          include_code, file_ok := os.read_entire_file(rel_path, context.temp_allocator)
          if file_ok != nil
          {
            log.errorf("Couldn't read shader file: %s, for include", rel_path)
            ok = false
            break
          }

          strings.write_string(&include_builder, string(include_code))
        }
      }
      else if trim == "#push_constant" && has_push
      {
        to_glsl_struct(&include_builder, push, "layout(push_constant) uniform", "push")
        put_push = true
      }
      else
      {
        strings.write_string(&include_builder, line)
        strings.write_string(&include_builder, "\n")
      }
    }

    if ok
    {
      with_include := strings.to_string(include_builder)
      print("%v", with_include)

      compiler := sc.compiler_initialize()
      defer sc.compiler_release(compiler)

      // NOTE: Hardcoded for vulkan 1.3.
      options := sc.compile_options_initialize()
      sc.compile_options_set_source_language(options, .GLSL)
      sc.compile_options_set_optimization_level(options, .PERFORMANCE)
      sc.compile_options_set_target_env(options, .VULKAN, .VULKAN_1_3)
      defer sc.compile_options_release(options)

      c_str     := strings.clone_to_cstring(with_include, context.temp_allocator)
      c_str_len := uint(len(with_include))

      to_sc_type: [Shader_Type]sc.Shader_Kind =
      {
        .VERTEX   = .VERTEX,
        .FRAGMENT = .FRAGMENT,
        .COMPUTE  = .COMPUTE,
      }

      c_name := strings.clone_to_cstring(file_name, context.temp_allocator)
      result := sc.compile_into_spv(compiler, c_str, c_str_len, to_sc_type[type], c_name, "main", options)
      defer sc.result_release(result)

      if sc.result_get_compilation_status(result) == .SUCCESS
      {
        bytes := sc.result_get_bytes(result)
        length := sc.result_get_length(result)

        // Copy so its ok to just release the shaderc stuff at the end.
        code = slice.clone(bytes[:length], allocator)
      }
      else
      {
        info := sc.result_get_error_message(result)
        log.errorf("Error compiling shader:\n%s", info)

        // Have line numbers on the error report so can trace compilation errors
        numbered_build := strings.builder_make_none(context.temp_allocator)
        source_lines := strings.split_lines(with_include, context.temp_allocator)
        for l, number in source_lines
        {
          fmt.sbprintln(&numbered_build, number, l)
        }

        numbered_code := strings.to_string(numbered_build)
        log.errorf("%s", numbered_code)

        ok = false
      }
    }
  }
  else
  {
    log.errorf("Couldn't read shader file: %s", file_name)
    ok = false
  }

  return code, put_push, ok
}

// NOTE: For now will not do recursive includes, but maybe won't be necessary
make_pipeline :: proc(allocator: runtime.Allocator, vert_name, frag_name: string, $push: typeid,
                      color_format: Pixel_Format, depth_format: Pixel_Format = .NONE) -> (pipeline: Pipeline, ok: bool)
{
  vert_path := join_file_path({SHADER_DIR, vert_name}, context.temp_allocator)
  frag_path := join_file_path({SHADER_DIR, frag_name}, context.temp_allocator)

  vert, vert_put_push, vert_ok := compile_shader_file(context.temp_allocator, vert_path, .VERTEX, push)
  frag, frag_put_push, frag_ok := compile_shader_file(context.temp_allocator, frag_path, .FRAGMENT, push)

  ok = vert_ok && frag_ok

  has_push := push != Nil_Push
  if has_push && !(vert_put_push || frag_put_push)
  {
    log.errorf("Shaders: %v,%v, Push constants type passed but no #push_constants.", vert_name, frag_name)
    // This might be recoverable so just proceed
  }

  if ok
  {
    pipeline.internal = vk_make_pipeline(vert, frag, color_format, depth_format, size_of(push))
    pipeline.files[.VERTEX].name = vert_name
    pipeline.files[.VERTEX].modify_time, _ = os.modification_time_by_path(vert_path)
    pipeline.files[.FRAGMENT].name = frag_name
    pipeline.files[.FRAGMENT].modify_time, _ = os.modification_time_by_path(frag_path)
  }

  return pipeline, ok
}

hot_reload_shaders :: proc(shaders: ^[Pipeline_Key]Pipeline, allocator: runtime.Allocator)
{
  // TODO: Maybe keep track of includes... any programs that include get recompiled
  for &s, tag in shaders
  {
    needs_reload := false
    for &p in s.files
    {
      path := join_file_path({SHADER_DIR, p.name}, context.temp_allocator)
      new_modify_time, err := os.modification_time_by_path(path)
      if err != nil
      {
        log.errorf("Could not collect modify time for shader file: %v... error: %v", p.name, err)
        continue
      }

      if time.diff(new_modify_time, p.modify_time) != 0
      {
        needs_reload = true
      }
    }

    if needs_reload
    {
      // hot, ok := make_pipeline(allocator, s.files[.VERTEX].name, s.files[.FRAGMENT].name)
      // if ok
      // {
      //   free_pipeline(&s)
      //   s = hot
      //   log.debugf("Hot reloaded shader %v", tag)
      // }
      // else
      // {
      //   log.errorf("Unable to hot reload shader %v, keeping the old", tag)
      // }
    }
  }
}

bind_pipeline :: proc(tag: Pipeline_Key)
{
}

free_pipeline :: proc(pipeline: ^Pipeline)
{
  pipeline^ = {}
}
