package main

import "core:os"
import "core:log"
import "core:strings"
import "core:fmt"
import "core:time"
import "core:slice"
import "base:runtime"

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

@(private="file")
compile_shader_source :: proc(file_name, source: string, type: Shader_Type, allocator: runtime.Allocator) -> (code: []byte, ok: bool)
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

  return code, ok
}

@(private="file")
compile_shader_file :: proc(file_name: string, type: Shader_Type, allocator: runtime.Allocator) -> (code: []byte, ok: bool)
{
  source, err := os.read_entire_file(file_name, context.temp_allocator)

  if err != nil
  {
    log.errorf("Couldn't read shader file: %s", file_name)
    ok = false
  }
  else
  {
    code, ok = compile_shader_source(file_name, string(source), type, allocator)
  }

  return code, ok
}

// NOTE: For now will not do recursive includes, but maybe won't be necessary
make_pipeline :: proc(allocator: runtime.Allocator, vert_name, frag_name: string,
                      color_format: Pixel_Format, depth_format: Pixel_Format = .NONE) -> (pipeline: Pipeline, ok: bool)
{
  vert_path := join_file_path({SHADER_DIR, vert_name}, context.temp_allocator)
  frag_path := join_file_path({SHADER_DIR, frag_name}, context.temp_allocator)

  vert, vert_ok := compile_shader_file(vert_path, .VERTEX, context.temp_allocator)
  frag, frag_ok := compile_shader_file(frag_path, .FRAGMENT, context.temp_allocator)

  ok = vert_ok && frag_ok

  if ok
  {
    pipeline.internal = vk_make_pipeline(vert, frag, color_format, depth_format)
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
