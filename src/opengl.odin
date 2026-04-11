package main

import "core:log"

import gl "vendor:OpenGL"
import "vendor:glfw"

init_opengl :: proc(window: Window)
{
  glfw.MakeContextCurrent(window.handle)
  glfw.SwapInterval(1)

  gl.load_up_to(GL_MAJOR, GL_MINOR, glfw.gl_set_proc_address)
  glfw.gl_set_proc_address(&glUniformHandleui64ARB, "glUniformHandleui64ARB")

  gl.DebugMessageCallback(proc "c" (source: u32, type: u32, id: u32, severity: u32, length: i32, message: cstring, userParam: rawptr)
  {
    context = state.main_context
    // Too much voodoo?
    log_proc: proc(fmt_str: string, args: ..any, location := #caller_location)
    switch (severity)
    {
    case gl.DEBUG_SEVERITY_NOTIFICATION:
      log_proc = log.infof
    case gl.DEBUG_SEVERITY_LOW:
      log_proc = log.debugf
    case gl.DEBUG_SEVERITY_MEDIUM:
      log_proc = log.errorf
    case gl.DEBUG_SEVERITY_HIGH:
      log_proc = log.fatalf
    }

    log_proc("GL: %v", string(message))
  }, nil)

  gl.Enable(gl.DEBUG_OUTPUT);
  gl.Enable(gl.DEBUG_OUTPUT_SYNCHRONOUS);

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
}
