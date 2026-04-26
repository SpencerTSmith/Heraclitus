package main

import "core:log"
import "core:strings"
import "core:math"

import "vendor:glfw"

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

make_window :: proc(window_width  := 2560,
                    window_height := 1440,
                    window_title  := "Heraclitus") -> (window: Window, ok: bool)
{
  glfw.InitHint(glfw.PLATFORM, glfw.PLATFORM_X11)

  if glfw.Init() == glfw.TRUE
  {
    glfw.WindowHint(glfw.RESIZABLE, glfw.FALSE)
    glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)

    c_title := strings.clone_to_cstring(window_title, context.temp_allocator)
    window.handle = glfw.CreateWindow(i32(window_width), i32(window_height), c_title, nil, nil)
    if window.handle != nil
    {
      ok = true

      glfw.SetWindowPos(window.handle, 300, 300)

      window.w     = window_width
      window.h     = window_height
      window.title = window_title

      // Ehh, accessing global state here....
      glfw.SetFramebufferSizeCallback(window.handle, proc "c" (window: glfw.WindowHandle, width, height: i32)
      {
        state.window.w = int(width)
        state.window.h = int(height)
        state.window.should_resize = true
      })
      glfw.SetScrollCallback(window.handle, proc "c" (window: glfw.WindowHandle, x_scroll, y_scroll: f64)
      {
        // Just get the direction
        dir_x := math.sign(f32(x_scroll))
        dir_y := math.sign(f32(y_scroll))

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

free_window :: proc(window: ^Window)
{
  glfw.DestroyWindow(window.handle)
  glfw.Terminate() // Causing crashes?
  window^ = {}
}
