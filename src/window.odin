package main

import "base:runtime"
import "core:log"
import "core:strings"
import "core:math"

import "vendor:glfw"
import gl "vendor:OpenGL"

GL_MAJOR :: 4
GL_MINOR :: 6
glUniformHandleui64ARB: proc "c" (location: i32, value: u64)

Window :: struct
{
  handle: glfw.WindowHandle,
  w, h:   int,
  title:  string,
  should_resize: bool,
}

window_aspect_ratio :: proc(window: Window) -> (aspect: f32)
{
  aspect = f32(window.w) / f32(window.h)
  return aspect
}

should_close :: proc(window: Window) -> bool
{
  return bool(glfw.WindowShouldClose(window.handle)) || !state.running
}

Render_Backend :: enum
{
  OPENGL,
  VULKAN,
}

make_window :: proc(window_width:  int,
                    window_height: int,
                    window_title:  string,
                    backend: Render_Backend) -> (window: Window, ok: bool)
{
  if glfw.Init() == glfw.TRUE
  {
    glfw.WindowHint(glfw.RESIZABLE, glfw.TRUE)

    switch backend
    {
      case .OPENGL:
        glfw.WindowHint(glfw.OPENGL_FORWARD_COMPAT, glfw.TRUE)
        glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
        glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, GL_MAJOR)
        glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, GL_MINOR)
      case .VULKAN:
        glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
    }

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

      // Ehh, accessing global state here....
      glfw.SetFramebufferSizeCallback(window.handle, proc "c" (window: glfw.WindowHandle, width, height: i32)
      {
        context = runtime.default_context()
        assert(state.window.handle == window)

        state.window.w = int(width)
        state.window.h = int(height)
        state.window.should_resize = true
      })
      glfw.SetScrollCallback(window.handle, proc "c" (window: glfw.WindowHandle, x_scroll, y_scroll: f64)
      {
        // Just get the direction
        dir_x := math.sign(x_scroll)
        dir_y := math.sign(y_scroll)

        state.input.mouse.delta_scroll.x += dir_x
        state.input.mouse.delta_scroll.y += dir_y
      })

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
