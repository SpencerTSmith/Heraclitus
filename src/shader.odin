package main

import "core:os"
import "core:log"
import "core:strings"
import "core:path/filepath"

import gl "vendor:OpenGL"

SHADER_DIR :: "shaders" + PATH_SLASH

Shader_Type :: enum u32 {
  VERT,
  FRAG,
}

Shader :: distinct u32

Shader_Program :: struct {
  id:       u32,

  // NOTE: Does not store the full path, just the name
  parts: [Shader_Type]struct {
    name:        string,
    modify_time: os.File_Time,
  },

  uniforms:  map[string]Uniform,
}

// TODO: Not sure I really like doing this, but I prefer having nice debug info
// If I wanted to do this in a nicer way, maybe I could do it like how I do the
// table for glfw input table
Uniform_Type :: enum i32 {
  F32  = gl.FLOAT,
  I32  = gl.INT,
  BOOL = gl.BOOL,

  VEC3 = gl.FLOAT_VEC3,
  VEC4 = gl.FLOAT_VEC4,

  MAT4 = gl.FLOAT_MAT4,

  SAMPLER_2D    = gl.SAMPLER_2D,
  SAMPLER_CUBE  = gl.SAMPLER_CUBE,
  SAMPLER_2D_MS = gl.SAMPLER_2D_MULTISAMPLE,

  SAMPLER_CUBE_ARRAY = gl.SAMPLER_CUBE_MAP_ARRAY,
}

Uniform :: struct {
  name:     string,
  type:     Uniform_Type,
  location: i32,
  size:     i32,
  binding:  i32, // For things that are bindable
}

make_shader_from_string :: proc(source: string, type: Shader_Type) -> (shader: Shader, ok: bool) {
  // Resolve all #includes
  // TODO: For now will not do recursive includes, but maybe won't be nessecary
  lines := strings.split_lines(source, context.temp_allocator)

  to_gl_type := [Shader_Type]u32 {
    .VERT = gl.VERTEX_SHADER,
    .FRAG = gl.FRAGMENT_SHADER,
  }

  include_builder := strings.builder_make_none(context.temp_allocator)
  for line in lines {
    trim := strings.trim_space(line)
    if strings.starts_with(trim, "#include") {
      first := strings.index(trim, "\"")
      last  := strings.last_index(trim, "\"")

      if first != -1 && last > first {
        file     := trim[first + 1:last]
        rel_path := filepath.join({SHADER_DIR, file}, context.temp_allocator)

        include_code, file_ok := os.read_entire_file(rel_path, context.temp_allocator)
        if !file_ok {
          log.errorf("Couldn't read shader file: %s, for include", rel_path)
          ok = false
          return
        }

        strings.write_string(&include_builder, string(include_code))
      }
    } else {
      strings.write_string(&include_builder, line)
      strings.write_string(&include_builder, "\n")
    }
  }

  with_include := strings.to_string(include_builder)

  c_str     := strings.clone_to_cstring(with_include, allocator = context.temp_allocator)
  c_str_len := i32(len(with_include))

  gl_type := to_gl_type[type]

  shader =  Shader(gl.CreateShader(gl_type))
  gl.ShaderSource(u32(shader), 1, &c_str, &c_str_len)
  gl.CompileShader(u32(shader))

  success: i32
  gl.GetShaderiv(u32(shader), gl.COMPILE_STATUS, &success)
  if success == 0 {
    info: [512]u8
    gl.GetShaderInfoLog(u32(shader), 512, nil, &info[0])
    log.errorf("Error compiling shader:\n%s\n", string(info[:]))
    log.errorf("%s", with_include)
    ok = false
    return
  }

  // NOTE: What errors could there be?
  ok = true
  return
}

make_shader_from_file :: proc(file_name: string, type: Shader_Type, prepend_common: bool = true) -> (shader: Shader, ok: bool) {
  source, file_ok := os.read_entire_file(file_name, context.temp_allocator)
  if !file_ok {
    log.errorf("Couldn't read shader file: %s", file_name)
    ok = false
    return
  }

  shader, ok = make_shader_from_string(string(source), type)
  return
}

free_shader :: proc(shader: Shader) {
  gl.DeleteShader(u32(shader))
}

make_shader_program :: proc(vert_name, frag_name: string, allocator := context.allocator) -> (program: Shader_Program, ok: bool) {
  vert_path := filepath.join({SHADER_DIR, vert_name}, context.temp_allocator)
  frag_path := filepath.join({SHADER_DIR, frag_name}, context.temp_allocator)

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
  if success == 0 {
    info: [512]u8
    gl.GetProgramInfoLog(program.id, 512, nil, &info[0])
    log.errorf("Error linking shader program:\n%s", string(info[:]))
    return program, false
  }

  program.uniforms = make_shader_uniform_map(program, allocator = allocator)

  err: os.Error

  // NOTE: Since we should not be generating new names, all names should just be static strings, so hopefully this is ok
  program.parts[.VERT].name = vert_name
  program.parts[.VERT].modify_time, err = os.last_write_time_by_name(vert_path)
  if err != nil {
    log.errorf("Could not collect modify time for vertex shader: %v... error: %v", vert_name, err)
  }

  program.parts[.FRAG].name = frag_name
  program.parts[.FRAG].modify_time, err = os.last_write_time_by_name(frag_path)
  if err != nil {
    log.errorf("Could not collect modify time for fragment shader: %v... error: %v", frag_name, err)
  }

  ok = true
  return program, ok
}

make_shader_uniform_map :: proc(program: Shader_Program, allocator := context.allocator) -> (uniforms: map[string]Uniform) {
  uniform_count: i32
  gl.GetProgramiv(program.id, gl.ACTIVE_UNIFORMS, &uniform_count)

  uniforms = make(map[string]Uniform, allocator = allocator)

  for i in 0..<uniform_count {
    uniform: Uniform
    len: i32
    name_buf: [256]byte // Surely no uniform name is going to be >256 chars

    type: u32
    gl.GetActiveUniform(program.id, u32(i), 256, &len, &uniform.size, &type, &name_buf[0])

    uniform.type = Uniform_Type(type)

    // Only collect uniforms not in blocks
    uniform.location = gl.GetUniformLocation(program.id, cstring(&name_buf[0]))
    if uniform.location != -1 {
      uniform.name = strings.clone(string(name_buf[:len])) // May just want to do fixed size

      // Check the initial binding point
      // NOTE: will be junk if not actually set in shader
      // FIXME: should proably be more thorough in checking types that might have
      // binding
      if uniform.type == .SAMPLER_2D   ||
         uniform.type == .SAMPLER_CUBE ||
         uniform.type == .SAMPLER_2D_MS ||
         uniform.type == .SAMPLER_CUBE_ARRAY {
           gl.GetUniformiv(program.id, uniform.location, &uniform.binding)
      }

      uniforms[uniform.name] = uniform
    }
  }

  return uniforms
}

hot_reload_shaders :: proc(shaders: ^[Shader_Tag]Shader_Program, allocator := context.allocator) {
  // TODO: Maybe keep track of includes... any programs that include get recompiled
  for &s, tag in shaders {
    needs_reload := false
    for &p in s.parts {

      path := filepath.join({SHADER_DIR, p.name}, context.temp_allocator)
      new_modify_time, err := os.last_write_time_by_name(path)
      if err != nil {
        log.errorf("Could not collect modify time for shader file: %v... error: %v", p.name, err)
        continue
      }

      if new_modify_time > p.modify_time {
        needs_reload = true
      }
    }

    if needs_reload {
      hot, ok := make_shader_program(s.parts[.VERT].name, s.parts[.FRAG].name, state.perm_alloc)
      if !ok {
        log.errorf("Unable to hot reload shader %v", tag)
        state.running = false
      }

      free_shader_program(&s)
      s = hot
      log.infof("Hot reloaded shader %v", tag)
    }
  }
}

bind_shader :: proc(tag: Shader_Tag) {
  bind_shader_program(state.shaders[tag])
}

bind_shader_program :: proc(program: Shader_Program) {
  if state.current_shader.id != program.id {
    gl.UseProgram(program.id)

    state.current_shader = program
  }
}

free_shader_program :: proc(program: ^Shader_Program) {
  gl.DeleteProgram(program.id)

  for _, uniform in program.uniforms {
    delete(uniform.name)
  }
  delete(program.uniforms)
}

set_shader_uniform :: proc(name: string, value: $T,
                           program: Shader_Program = state.current_shader) {
  assert(state.current_shader.id == program.id)

  if name in program.uniforms {
    when T == i32 || T == int || T == bool {
      gl.Uniform1i(program.uniforms[name].location, i32(value))
    } else when T == f32 {
      gl.Uniform1f(program.uniforms[name].location, value)
    } else when T == vec3 {
      gl.Uniform3f(program.uniforms[name].location, value.x, value.y, value.z)
    } else when T == vec4 {
      gl.Uniform4f(program.uniforms[name].location, value.x, value.y, value.z, value.w)
    } else when T == mat4 {
      copy := value
      gl.UniformMatrix4fv(program.uniforms[name].location, 1, gl.FALSE, raw_data(&copy))
    } else when T == []mat4 {
      copy := value
      length := i32(len(value))
      assert(length <= program.uniforms[name].size)
      gl.UniformMatrix4fv(program.uniforms[name].location, length, gl.FALSE, raw_data(raw_data(copy)))
    } else {
	    log.warn("Unable to match type (%v) to gl call for uniform\n", typeid_of(T))
    }
  } else {
    // log.warnf("Uniform (\"%v\") not in current shader (id = %v)\n", name, program.id)
  }
}
