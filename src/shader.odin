package main

import "core:os"
import "core:log"
import "core:strings"
import "core:fmt"
import "core:time"
import "base:runtime"

import gl "vendor:OpenGL"

SHADER_DIR :: "shaders" + PATH_SLASH

Shader_Tag :: enum
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
  VERT,
  FRAG,
}

Shader :: distinct u32

Shader_Program :: struct
{
  id: u32,

  // NOTE: Does not store the full path, just the name
  files: [Shader_Type]struct
  {
    name:        string,
    modify_time: time.Time,
  },

  uniforms: map[string]Uniform,
}

// TODO: Not sure I really like doing this, but I prefer having nice debug info
// If I wanted to do this in a nicer way, maybe I could do it like how I do the
// table for glfw input table
Uniform_Type :: enum i32
{
  F32,
  I32,
  BOOL,

  VEC3,
  VEC4,

  MAT4,

  SAMPLER_2D,
  SAMPLER_CUBE,
  SAMPLER_2D_MS,

  SAMPLER_CUBE_ARRAY,
}

Uniform :: struct
{
  name:     string,
  type:     Uniform_Type,
  location: i32,
  size:     i32,
  binding:  i32, // For things that are bindable
}

// NOTE: For now will not do recursive includes, but maybe won't be necessary
make_shader_from_string :: proc(source: string, type: Shader_Type) -> (shader: Shader, ok: bool)
{
  ok = true

  // Resolve all #includes
  lines := strings.split_lines(source, context.temp_allocator)

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
    else
    {
      strings.write_string(&include_builder, line)
      strings.write_string(&include_builder, "\n")
    }
  }

  if ok
  {
    with_include := strings.to_string(include_builder)

    c_str     := strings.clone_to_cstring(with_include, context.temp_allocator)
    c_str_len := i32(len(with_include))


    to_gl_type: [Shader_Type]u32 =
    {
      .VERT = gl.VERTEX_SHADER,
      .FRAG = gl.FRAGMENT_SHADER,
    }

    gl_type := to_gl_type[type]

    shader =  Shader(gl.CreateShader(gl_type))
    gl.ShaderSource(u32(shader), 1, &c_str, &c_str_len)
    gl.CompileShader(u32(shader))

    success: i32
    gl.GetShaderiv(u32(shader), gl.COMPILE_STATUS, &success)

    if success == 0
    {
      info: [512]u8
      length: i32
      gl.GetShaderInfoLog(u32(shader), 512, &length, &info[0])
      log.errorf("Error compiling shader:\n%s", string(info[:length]))

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

  return shader, ok
}

make_shader_from_file :: proc(file_name: string, type: Shader_Type, prepend_common: bool = true) -> (shader: Shader, ok: bool)
{
  source, err := os.read_entire_file(file_name, context.temp_allocator)

  if err != nil
  {
    log.errorf("Couldn't read shader file: %s", file_name)
    ok = false
  }
  else
  {
    shader, ok = make_shader_from_string(string(source), type)
  }

  return shader, ok
}

free_shader :: proc(shader: Shader) {
  gl.DeleteShader(u32(shader))
}

make_shader_program :: proc(vert_name, frag_name: string, allocator: runtime.Allocator) -> (program: Shader_Program, ok: bool)
{
  vert_path := join_file_path({SHADER_DIR, vert_name}, context.temp_allocator)
  frag_path := join_file_path({SHADER_DIR, frag_name}, context.temp_allocator)

  vert := make_shader_from_file(vert_path, .VERT) or_return
  defer free_shader(vert)
  frag := make_shader_from_file(frag_path, .FRAG) or_return
  defer free_shader(frag)

  program.id   = gl.CreateProgram()
  gl.AttachShader(program.id, u32(vert))
  gl.AttachShader(program.id, u32(frag))
  gl.LinkProgram(program.id)

  success: i32
  gl.GetProgramiv(program.id, gl.LINK_STATUS, &success)
  if success == 0
  {
    info: [512]u8
    gl.GetProgramInfoLog(program.id, 512, nil, &info[0])
    log.errorf("Error linking shader program: %v, %v\n%s", vert_name, frag_name, string(info[:]))
    return program, false
  }

  program.uniforms = make_shader_uniform_map(program, allocator = allocator)

  err: os.Error

  // NOTE: Since we should not be generating new names, all names should just be static strings, so hopefully this is ok
  program.files[.VERT].name = vert_name
  program.files[.VERT].modify_time, err = os.modification_time_by_path(vert_path)
  if err != nil
  {
    log.errorf("Could not collect modify time for vertex shader: %v... error: %v", vert_name, err)
  }

  program.files[.FRAG].name = frag_name
  program.files[.FRAG].modify_time, err = os.modification_time_by_path(frag_path)
  if err != nil
  {
    log.errorf("Could not collect modify time for fragment shader: %v... error: %v", frag_name, err)
  }

  ok = true
  return program, ok
}

make_shader_uniform_map :: proc(program: Shader_Program, allocator: runtime.Allocator) -> (uniforms: map[string]Uniform)
{
  uniform_count: i32
  gl.GetProgramiv(program.id, gl.ACTIVE_UNIFORMS, &uniform_count)

  uniforms = make(map[string]Uniform, allocator = allocator)
  // reserve(&uniforms, uniform_count) Way overestimated considering this also collects ubo uniforms

  for i in 0..<uniform_count
  {
    uniform: Uniform
    len: i32
    name_buf: [256]byte // Surely no uniform name is going to be >256 chars

    type: u32
    gl.GetActiveUniform(program.id, u32(i), 256, &len, &uniform.size, &type, &name_buf[0])

    switch type
    {
    case gl.FLOAT:                   uniform.type = .F32
    case gl.INT:                     uniform.type = .I32
    case gl.BOOL:                    uniform.type = .BOOL
    case gl.FLOAT_VEC3:              uniform.type = .VEC3
    case gl.FLOAT_VEC4:              uniform.type = .VEC4
    case gl.FLOAT_MAT4:              uniform.type = .MAT4
    case gl.SAMPLER_2D:              uniform.type = .SAMPLER_2D
    case gl.SAMPLER_CUBE:            uniform.type = .SAMPLER_CUBE
    case gl.SAMPLER_2D_MULTISAMPLE:  uniform.type = .SAMPLER_2D_MS
    case gl.SAMPLER_CUBE_MAP_ARRAY:  uniform.type = .SAMPLER_CUBE_ARRAY
    }

    // Only collect uniforms not in blocks
    uniform.location = gl.GetUniformLocation(program.id, cstring(&name_buf[0]))
    if uniform.location != -1
    {
      uniform.name = strings.clone(string(name_buf[:len]), allocator=allocator)

      // Check the initial binding point
      // NOTE: will be junk if not actually set in shader
      // TODO: should proably be more thorough in checking types that might have
      // binding
      if uniform.type == .SAMPLER_2D    ||
         uniform.type == .SAMPLER_CUBE  ||
         uniform.type == .SAMPLER_2D_MS ||
         uniform.type == .SAMPLER_CUBE_ARRAY
      {
        gl.GetUniformiv(program.id, uniform.location, &uniform.binding)
      }

      uniforms[uniform.name] = uniform
    }
  }

  return uniforms
}

hot_reload_shaders :: proc(shaders: ^[Shader_Tag]Shader_Program, allocator: runtime.Allocator)
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
      hot, ok := make_shader_program(s.files[.VERT].name, s.files[.FRAG].name, allocator)
      if ok
      {
        free_shader_program(&s)
        s = hot
        log.debugf("Hot reloaded shader %v", tag)
      }
      else
      {
        log.errorf("Unable to hot reload shader %v, keeping the old", tag)
      }
    }
  }
}

bind_shader :: proc(tag: Shader_Tag)
{
  bind_shader_program(state.shaders[tag])
}

bind_shader_program :: proc(program: Shader_Program)
{
  if state.current_shader.id != program.id
  {
    gl.UseProgram(program.id)

    state.current_shader = program
  }
}

free_shader_program :: proc(program: ^Shader_Program)
{
  gl.DeleteProgram(program.id)
  delete(program.uniforms)
}

set_shader_uniform :: proc(name: string, value: $T,
                           program: Shader_Program = state.current_shader)
{
  assert(state.current_shader.id == program.id)

  if name in program.uniforms
  {
    location := program.uniforms[name].location
    when T == i32 || T == int || T == bool
    {
      gl.Uniform1i(program.uniforms[name].location, i32(value))
    }
    else when T == f32
    {
      gl.Uniform1f(program.uniforms[name].location, value)
    }
    else when T == vec3
    {
      gl.Uniform3f(program.uniforms[name].location, value.x, value.y, value.z)
    }
    else when T == vec4
    {
      gl.Uniform4f(program.uniforms[name].location, value.x, value.y, value.z, value.w)
    }
    else when T == mat4
    {
      copy := value
      gl.UniformMatrix4fv(program.uniforms[name].location, 1, gl.FALSE, raw_data(&copy))
    }
    else when T == []mat4
    {
      copy := value
      length := i32(len(value))
      assert(length <= program.uniforms[name].size)
      gl.UniformMatrix4fv(program.uniforms[name].location, length, gl.FALSE, raw_data(raw_data(copy)))
    }
    else when T == u64
    {
      glUniformHandleui64ARB(location, value);
    }
    else {
	    log.warn("Unable to match type (%v) to gl call for uniform\n", typeid_of(T))
    }
  }
  else
  {
    // log.warnf("Uniform (\"%v\") not in current shader (id = %v)", name, program.id)
  }
}
