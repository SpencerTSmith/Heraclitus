package main

// TODO: Begin moving all direct gl calls here, so can reimplement the interface with Vulkan. Delete gl backend after.

import gl "vendor:OpenGL"

gl_debug_callback :: proc "c" (source: u32, type: u32, id: u32, severity: u32, length: i32, message: cstring, userParam: rawptr) {
  
}
