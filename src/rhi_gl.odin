package main

import "base:runtime"
import "core:log"
import "core:strings"
import "core:math"
import "core:fmt"

import glfw "vendor:glfw"
import gl   "vendor:OpenGL"

GL_MAJOR :: 4
GL_MINOR :: 6

init_platform_graphics :: proc(window_width:  int,
                               window_height: int,
                               window_title:  string) -> (window: Window, ok: bool)
{
  if glfw.Init() == glfw.TRUE
  {
    glfw.WindowHint(glfw.RESIZABLE, glfw.TRUE)
    glfw.WindowHint(glfw.OPENGL_FORWARD_COMPAT, glfw.TRUE)
    glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
    glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, GL_MAJOR)
    glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, GL_MINOR)
    glfw.WindowHint(glfw.OPENGL_DEBUG_CONTEXT, glfw.TRUE)

    c_title := strings.clone_to_cstring(window_title, context.temp_allocator)
    window.handle = glfw.CreateWindow(i32(window_width), i32(window_height), c_title, nil, nil)
    if window.handle != nil
    {
      ok = true

      window.w     = window_width
      window.h     = window_height
      window.title = window_title

      if glfw.RawMouseMotionSupported() {
        glfw.SetInputMode(window.handle, glfw.CURSOR, glfw.CURSOR_DISABLED)
        glfw.SetInputMode(window.handle, glfw.RAW_MOUSE_MOTION, 1)
      }

      glfw.MakeContextCurrent(window.handle)
      glfw.SwapInterval(1)

      // Ehh, accessing global state here....
      glfw.SetFramebufferSizeCallback(window.handle, proc "c" (window: glfw.WindowHandle, width, height: i32)
      {
        state.window.w = int(width)
        state.window.h = int(height)
        state.window.resized = true
      })
      glfw.SetScrollCallback(window.handle, proc "c" (window: glfw.WindowHandle, x_scroll, y_scroll: f64)
      {
        // Just get the direction
        dir_x := math.sign(x_scroll)
        dir_y := math.sign(y_scroll)

        state.input.mouse.delta_scroll.x += dir_x
        state.input.mouse.delta_scroll.y += dir_y
      })

      gl.load_up_to(GL_MAJOR, GL_MINOR, glfw.gl_set_proc_address)


      gl.DebugMessageCallback(proc "c" (source: u32, type: u32, id: u32, severity: u32, length: i32, message: cstring, userParam: rawptr)
      {
        context = state.main_context
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

        log_proc("GL: %v", string(message))
      }, nil)

      gl.Enable(gl.DEBUG_OUTPUT);
      gl.Enable(gl.DEBUG_OUTPUT_SYNCHRONOUS);
      gl.DebugMessageInsert(gl.DEBUG_SOURCE_APPLICATION,
                            gl.DEBUG_TYPE_ERROR,
                            1,
                            gl.DEBUG_SEVERITY_HIGH,
                            -1,
                            "hello");

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
    else
    {
      log.fatal("Failed to create GLFW window")
    }
  }
  else
  {
    log.fatal("Failed to initialize GLFW")
  }

  return window, ok
}
