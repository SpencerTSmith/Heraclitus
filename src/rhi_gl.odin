package main

import "base:runtime"
import "core:log"

import glfw "vendor:glfw"
import gl   "vendor:OpenGL"

GL_MAJOR :: 4
GL_MINOR :: 6

init_rhi :: proc() -> (window: Window, ok: bool)
{
  gl.load_up_to(GL_MAJOR, GL_MINOR, glfw.gl_set_proc_address)

  gl.DebugMessageCallback(proc "c" (source: u32, type: u32, id: u32, severity: u32, length: i32, message: cstring, userParam: rawptr)
  {
    // Too much voodoo?
    log_proc: proc(fmt_str: string, args: ..any, location := #caller_location)
    switch (severity)
    {
      case gl.DEBUG_SEVERITY_NOTIFICATION:
        log_proc = log.debugf
      case gl.DEBUG_SEVERITY_LOW:
        log_proc = log.infof
      case gl.DEBUG_SEVERITY_MEDIUM:
        log_proc = log.warnf
      case gl.DEBUG_SEVERITY_HIGH:
        log_proc = log.errorf
    }
    context = runtime.default_context()

    log_proc("GL: %v", string(message))
  }, nil)

  //
  // Query GL extensions
  //
  needed_extensions: []string =
  {
    "GL_ARB_shader_viewport_layer_array",
    "GL_ARB_bindless_texture",
  }

  extension_count: i32
  gl.GetIntegerv(gl.NUM_EXTENSIONS, &extension_count)
  for i in 0..<extension_count
  {
    have := gl.GetStringi(gl.EXTENSIONS, u32(i))

    for need in needed_extensions
    {
      if string(have) == need
      {
        log.infof("Necessary GL extension: %v is supported!", need)
      }
    }
  }

  return window, ok
}
