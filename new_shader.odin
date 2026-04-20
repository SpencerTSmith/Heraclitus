package main

import "base:runtime"
import "core:os"
import "core:log"
import "core:strings"
import "core:fmt"
import "core:time"
import "core:slice"
import "core:reflect"

import "slang"

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
  IMMEDIATE,
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
  file_name:   string,
  modify_time: time.Time,

  push: typeid,
}

// NOTE: This is simply a little meta-program to reduce code duplication between glsl and odin

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
  // Indices
  diffuse:  u32,
  specular: u32,
  emissive: u32,
  normal:   u32,

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

  // Texture descriptor heap indices
  sun_shadow_index:   u32,
  point_shadow_index: u32,
  skybox_index:       u32,

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

GLSL_Layout :: enum
{
  STD430,
  SCALAR,
}

Nil_Push :: struct {}

@(private="file")
to_glsl_basic_type_string :: proc(type: typeid, allow_vec: bool) -> string
{
  s: string
  switch type {
  case f32:
    s = "float"
  case mat4:
    s = "mat4"
  case vec2:
    if allow_vec { s = "vec2" }
  case vec3:
    if allow_vec { s = "vec3" }
  case vec4:
    if allow_vec { s = "vec4" }
  case u32:
    s = "uint"
  case i32:
    s = "int"
  case rawptr:
    s = "uint64_t"
  }

  return s
}

@(private="file")
to_glsl_struct :: proc(b: ^strings.Builder, t: typeid, prefix: string = "struct", suffix: string = "", allow_vec: bool = true)
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
      basic := to_glsl_basic_type_string(field.type.id, allow_vec)

      // Wasn't one of the above basic types
      if basic == ""
      {
        info := reflect.type_info_base(type_info_of(field.type.id))

        // Is it an array?
        if reflect.is_array(info)
        {
          array_info := info.variant.(reflect.Type_Info_Array)

          // Is it possibly an array of basic types?
          array_type := to_glsl_basic_type_string(array_info.elem.id, allow_vec)

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


generate_glsl :: proc()
{
  b := strings.builder_make(allocator=context.temp_allocator)

  buf: [time.MIN_YYYY_DATE_LEN]u8
  buf2: [time.MIN_HMS_12_LEN]u8
  now := time.now()
  date  := time.to_string_dd_mm_yyyy(now, buf[:])
  hours := time.to_string_hms_12(now, buf2[:])
  fmt.sbprintf(&b, "// NOTE: This code was generated on %v (%v)\n\n", date, hours)

  // Gotta have em
  fmt.sbprintf(&b, "#extension GL_EXT_buffer_reference : require\n")
  fmt.sbprintf(&b, "#extension GL_EXT_scalar_block_layout : require\n")
  fmt.sbprintf(&b, "#extension GL_EXT_shader_explicit_arithmetic_types_int64 : require\n")
  fmt.sbprintf(&b, "#extension GL_EXT_nonuniform_qualifier : require\n")

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
  to_glsl_struct(&b, Mesh_Vertex)
  to_glsl_struct(&b, Immediate_Vertex)

  fmt.sbprintf(&b, "layout(set = 0, binding = %v) uniform sampler2D   textures_2D[];\n", TEXTURE_BINDING[.D2])
  fmt.sbprintf(&b, "layout(set = 0, binding = %v) uniform samplerCube textures_cube[];\n", TEXTURE_BINDING[.CUBE])
  fmt.sbprintf(&b, "layout(set = 0, binding = %v) uniform samplerCubeArray   textures_cube_array[];\n", TEXTURE_BINDING[.CUBE_ARRAY])

  // FIXME: Automate somehow. I have an idea for every time a gpu buffer is made at game start it registers a queue to be printed out here.
  fmt.sbprintln(&b)
  fmt.sbprintf(&b, "layout(buffer_reference, std430) readonly buffer Frame_Uniforms {{\n",)
  fmt.sbprintf(&b, "  Frame_Uniform v;\n")
  fmt.sbprintf(&b, "};\n\n")

  fmt.sbprintf(&b, "layout(buffer_reference, std430) readonly buffer Mesh_Materials {{\n")
  fmt.sbprintf(&b, "  Material_Uniform v[];\n")
  fmt.sbprintf(&b, "};\n\n")

  fmt.sbprintf(&b, "layout(buffer_reference, std430) readonly buffer Draw_Uniforms {{\n",)
  fmt.sbprintf(&b, "  Draw_Uniform v[];\n")
  fmt.sbprintf(&b, "};\n\n")

  fmt.sbprintf(&b, "layout(buffer_reference, scalar) readonly buffer Mesh_Vertices {{\n")
  fmt.sbprintf(&b, "  Mesh_Vertex v[];\n")
  fmt.sbprintf(&b, "};\n\n")

  fmt.sbprintf(&b, "layout(buffer_reference, scalar) readonly buffer Immediate_Vertices {{\n")
  fmt.sbprintf(&b, "  Immediate_Vertex v[];\n")
  fmt.sbprintf(&b, "};\n\n")

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
     uniform.diffuse  = diffuse.index
     uniform.specular = specular.index
     uniform.emissive = emissive.index
     uniform.normal   = normal.index

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


@(private="file")
global_session: ^slang.IGlobalSession

// NOTE: Injects push constant if passed
@(private="file")
compile_shader_file :: proc(file_name: string, $push: typeid) -> (code: []byte, put_push, ok: bool)
{
  source, err := os.read_entire_file(file_name, context.temp_allocator)

  has_push := push != Nil_Push

  if err == nil
  {
    ok = true

    // Resolve all #includes and #push_constants
    lines := strings.split_lines(string(source), context.temp_allocator)

    processed_builder := strings.builder_make_none(context.temp_allocator)
    for line in lines
    {
      trim := strings.trim_space(line)

      if trim == "#push_constant" && has_push
      {
        assert(size_of(push) <= 128, "Push Constants may only be a maximum of 128 bytes.")
        to_glsl_struct(&processed_builder, push, "layout(push_constant) uniform", "push")
        put_push = true
      }
      else
      {
        strings.write_string(&processed_builder, line)
        strings.write_string(&processed_builder, "\n")
      }
    }

    processed := strings.to_string(processed_builder)

    if global_session == nil
    {
      slang.createGlobalSession(slang.SLANG_API_VERSION, &global_session)
    }


    target: slang.TargetDesc =
    {
      structureSize = size_of(slang.TargetDesc),
      format        = .SPIRV,
      profile       = global_session->findProfile("spirv_1_6"),
      flags         = .GENERATE_SPIRV_DIRECTLY,
    }


    compiler_options: []slang.CompilerOptionEntry =
    {
      { name = .VulkanUseEntryPointName, value = { intValue0 = 1 }}
    }

    search_path  := strings.clone_to_cstring(SHADER_DIR, context.temp_allocator)
    search_paths := []cstring { search_path }

    session_desc: slang.SessionDesc =
    {
      structureSize            = size_of(slang.SessionDesc),
      targets                  = &target,
      targetCount              = 1,
      searchPaths              = raw_data(search_paths),
      searchPathCount          = len(search_paths),
      compilerOptionEntries    = raw_data(compiler_options),
      compilerOptionEntryCount = u32(len(compiler_options)),
    }


    session: ^slang.ISession
    global_session->createSession(&session_desc, &session)
    defer session->release()


    diagnostic: ^slang.IBlob
    defer { if diagnostic != nil { diagnostic->release() }}

    c_name := strings.clone_to_cstring(file_name, context.temp_allocator)
    c_str  := strings.clone_to_cstring(processed, context.temp_allocator)

    module := session->loadModuleFromSourceString(c_name, c_name, c_str, &diagnostic)

    if module != nil
    {
      vert_entry_point: ^slang.IEntryPoint
      module->findEntryPointByName("vert_main", &vert_entry_point)
      defer vert_entry_point->release()

      frag_entry_point: ^slang.IEntryPoint
      module->findEntryPointByName("frag_main", &frag_entry_point)
      defer frag_entry_point->release()

      components: []^slang.IComponentType =
      {
        module,
        vert_entry_point,
        frag_entry_point,
      }

      composite: ^slang.IComponentType

      if slang.result_failed(session->createCompositeComponentType(raw_data(components), len(components), &composite, &diagnostic))
      {
        log.errorf("Error compiling shader:\n%s", string(([^]byte)(diagnostic->getBufferPointer())[:diagnostic->getBufferSize()]))
      }
      defer composite->release()

      linked: ^slang.IComponentType
      if slang.result_failed(composite->link(&linked, &diagnostic))
      {
        log.errorf("Error compiling shader:\n%s", string(([^]byte)(diagnostic->getBufferPointer())[:diagnostic->getBufferSize()]))
      }
      defer linked->release()


      vert_blob: ^slang.IBlob
      if slang.result_failed(linked->getEntryPointCode(0, 0, &vert_blob, &diagnostic))
      {
        log.errorf("Error compiling shader:\n%s", string(([^]byte)(diagnostic->getBufferPointer())[:diagnostic->getBufferSize()]))
      }
      defer vert_blob->release()

      frag_blob: ^slang.IBlob
      if slang.result_failed(linked->getEntryPointCode(1, 0, &frag_blob, &diagnostic))
      {
        log.errorf("Error compiling shader:\n%s", string(([^]byte)(diagnostic->getBufferPointer())[:diagnostic->getBufferSize()]))
      }
      defer frag_blob->release()

      assert(vert_blob != nil)
      assert(frag_blob != nil)

      // So don't have to deal with slang release bullshit.
      vert_code = slice.clone(slice.bytes_from_ptr(vert_blob->getBufferPointer(), int(vert_blob->getBufferSize())))
      frag_code = slice.clone(slice.bytes_from_ptr(frag_blob->getBufferPointer(), int(frag_blob->getBufferSize())))
      ok = true
    }
    else
    {
      log.errorf("Error compiling shader.")
      if diagnostic != nil
      {
        // TODO:
      }
      ok = false
    }
  }
  else
  {
    log.errorf("Couldn't read shader file: %s", file_name)
    ok = false
  }

  return vert_code, frag_code, put_push, ok
}

// NOTE: For now will not do recursive includes, but maybe won't be necessary
make_pipeline :: proc(name: string, $push: typeid,
                      color_format: Pixel_Format, depth_format: Pixel_Format = .NONE) -> (pipeline: Pipeline, ok: bool)
{
  path := join_file_path({SHADER_DIR, name}, context.temp_allocator)

  code: []byte
  vert, frag: []byte
  if !strings.ends_with(path, ".slang")
  {
    vert, frag, _, ok = compile_shader_file(context.temp_allocator, path, push)
    _=os.write_entire_file(SHADER_DIR + "immediate.vert.spv", vert)
    _=os.write_entire_file(SHADER_DIR + "immediate.frag.spv", frag)
  }
  else
  {
    code,_ = os.read_entire_file(SHADER_DIR + "shader.spv", context.temp_allocator)
    ok = true
    print(code)
  }

  // has_push := push != Nil_Push
  // if has_push && !put_push
  // {
  //   log.errorf("Shaders: %v, Push constants type passed but no #push_constants.", name)
  //   // This might be recoverable so just proceed
  // }

  if ok
  {
    pipeline.internal = vk_make_pipeline(code, color_format, depth_format, size_of(push))

    pipeline.file_name = name
    pipeline.modify_time, _ = os.modification_time_by_path(path)

    pipeline.push = push
  }

  return pipeline, ok
}

hot_reload_shaders :: proc(shaders: ^[Pipeline_Key]Pipeline, allocator: runtime.Allocator)
{
  // TODO: Maybe keep track of includes... any programs that include get recompiled
  // for &s, tag in shaders
  // {
  //   needs_reload := false
  //   for &p in s.files
  //   {
  //     path := join_file_path({SHADER_DIR, p.name}, context.temp_allocator)
  //     new_modify_time, err := os.modification_time_by_path(path)
  //     if err != nil
  //     {
  //       log.errorf("Could not collect modify time for shader file: %v... error: %v", p.name, err)
  //       continue
  //     }
  //
  //     if time.diff(new_modify_time, p.modify_time) != 0
  //     {
  //       needs_reload = true
  //     }
  //   }
  //
  //   if needs_reload
  //   {
  //     // hot, ok := make_pipeline(allocator, s.files[.VERTEX].name, s.files[.FRAGMENT].name)
  //     // if ok
  //     // {
  //     //   free_pipeline(&s)
  //     //   s = hot
  //     //   log.debugf("Hot reloaded shader %v", tag)
  //     // }
  //     // else
  //     // {
  //     //   log.errorf("Unable to hot reload shader %v, keeping the old", tag)
  //     // }
  //   }
  // }
}

bind_pipeline :: proc
{
  bind_pipeline_direct,
  bind_pipeline_key,
}

// TODO: Check against current render target to ensure that pipeline is compatible.
bind_pipeline_direct :: proc(pipeline: Pipeline)
{
  ensure(state.renderer.frame_began)

  state.renderer.bound_pipeline = pipeline
  vk_bind_pipeline(pipeline)
}

bind_pipeline_key :: proc(tag: Pipeline_Key)
{
  bind_pipeline_direct(state.renderer.pipelines[tag])
}

free_pipeline :: proc(pipeline: ^Pipeline)
{
  pipeline^ = {}
}
