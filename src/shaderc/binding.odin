package shaderc

// NOTE: Only doing bindings for what I need.

when ODIN_OS == .Windows
{
    foreign import lib "shaderc_combined.lib"
}
when ODIN_OS == .Linux
{
    foreign import lib "system:shaderc_combined"
}

import "core:c"

Compiler        :: distinct rawptr
Compile_Options :: distinct rawptr
Result          :: distinct rawptr

Source_Language :: enum i32
{
  GLSL,
}

Shader_Kind :: enum i32
{
  VERTEX,
  FRAGMENT,
  COMPUTE,
}

Optimization_Level :: enum i32
{
  ZERO,
  SIZE,
  PERFORMANCE,
}

Target_Environment :: enum i32
{
  VULKAN,
}

Environment_Version :: enum i32
{
  VULKAN_1_3 = (1 << 22) | (3 << 12),
}

Compilation_Status :: enum i32
{
  SUCCESS              = 0,
  INVALID_STAGE        = 1,
  COMPILATION_ERROR    = 2,
  INTERNAL_ERROR       = 3,
  NULL_RESULT_OBJECT   = 4,
  INVALID_ASSEMBLY     = 5,
  VALIDATION_ERROR     = 6,
  TRANSFORMATION_ERROR = 7,
  CONFIGURATION_ERROR  = 8,
}

@(default_calling_convention = "c")
@(link_prefix = "shaderc_")
foreign lib
{
  compiler_initialize :: proc() -> Compiler ---;
  compile_options_initialize :: proc() -> Compile_Options ---;
  compiler_release :: proc(compiler: Compiler) ---;
  compile_options_release :: proc(options: Compile_Options) ---;

  compile_options_set_source_language :: proc(options: Compile_Options, language: Source_Language) ---;
  compile_options_set_optimization_level :: proc(options: Compile_Options, level: Optimization_Level) ---;
  compile_options_set_target_env :: proc(options: Compile_Options, environment: Target_Environment, version: Environment_Version) ---;

  compile_into_spv :: proc(compiler: Compiler, source: cstring, source_size: uint,
                           kind: Shader_Kind, input_file_name: cstring, entry_point_name: cstring, options: Compile_Options) -> Result ---;

  result_release :: proc(result: Result) ---;
  result_get_compilation_status :: proc(result: Result) -> Compilation_Status ---;
  result_get_error_message :: proc(result: Result) -> cstring ---;
  result_get_bytes  :: proc(result: Result) -> [^]byte ---;
  result_get_length :: proc(result: Result) -> uint ---;
}
