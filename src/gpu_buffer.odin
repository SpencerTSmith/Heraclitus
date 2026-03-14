package main

import "core:mem"
// import "core:reflect"

import gl "vendor:OpenGL"

// NOTE: This might end up being a needless abstraction layer
// But I would like a common interface for getting and writing to GPU buffers without worrying whether it is mapped or not
// As well as writing to them, at the right index

// Is this even useful anymore? Used to separate buffers more, but seems less useful now.
GPU_Buffer_Type :: enum {
  NONE,
  UNIFORM,
  STORAGE,
}

GPU_Buffer_Flag :: enum {
  PERSISTENT,
  FRAME_BUFFERED,
}
GPU_Buffer_Flags :: bit_set[GPU_Buffer_Flag]

// NOTE: Fat struct... too much voodoo?
GPU_Buffer :: struct #no_copy {
  id:         u32,
  type:       GPU_Buffer_Type,
  flags:      GPU_Buffer_Flags,

  mapped:     rawptr,
  total_size: int,

  // Aligned, frame range, for mapped buffers
  range_size: int,

  // Vertex specific stuff
  vao:          u32,
  index_offset: int,
}

align_size_for_gpu :: proc(size: int) -> (aligned: int) {
  min_alignment: i32
  gl.GetIntegerv(gl.UNIFORM_BUFFER_OFFSET_ALIGNMENT, &min_alignment)

 aligned = mem.align_forward_int(size, int(min_alignment))
 return aligned
}

// NOTE: right now not possible to get a buffer you can read from with this interface
make_gpu_buffer :: proc(type: GPU_Buffer_Type, size: int, data: rawptr = nil, flags: GPU_Buffer_Flags = {}) -> (buffer: GPU_Buffer) {
  assert(state.gl_initialized)

  is_persistent := .PERSISTENT in flags
  is_buffered   := .FRAME_BUFFERED in flags

  buffer.type = type
  buffer.range_size = align_size_for_gpu(size)
  buffer.total_size = buffer.range_size * FRAMES_IN_FLIGHT if is_buffered else buffer.range_size

  gl.CreateBuffers(1, &buffer.id)

  gl_flags: u32 = gl.MAP_WRITE_BIT|gl.MAP_PERSISTENT_BIT|gl.MAP_COHERENT_BIT if is_persistent else 0

  gl.NamedBufferStorage(buffer.id, buffer.total_size, data, gl_flags | gl.DYNAMIC_STORAGE_BIT)

  if is_persistent {
    buffer.mapped = gl.MapNamedBufferRange(buffer.id, 0, buffer.total_size, gl_flags)
  }

  return buffer
}

gpu_buffer_is_mapped :: proc(buffer: GPU_Buffer) -> bool {
  return buffer.mapped != nil
}

write_gpu_buffer :: proc(buffer: GPU_Buffer, offset, size: int, data: rawptr) {
  if data != nil {
    if buffer.mapped != nil {
      ptr := uintptr(buffer.mapped) + uintptr(offset)
      mem.copy(rawptr(ptr), data, size)
    } else {
      gl.NamedBufferSubData(buffer.id, offset, size, data)
    }
  }
}

buffer_type_to_gl: [GPU_Buffer_Type]u32 = {
  .NONE    = 0,
  .UNIFORM = gl.UNIFORM_BUFFER,
  .STORAGE = gl.SHADER_STORAGE_BUFFER,
}

bind_gpu_buffer_base :: proc(buffer: GPU_Buffer, binding: UBO_Bind) {
  assert(buffer.type == .UNIFORM || buffer.type == .STORAGE, "Only Uniform and Storage Buffers may be bound to locations")

  gl_target := buffer_type_to_gl[buffer.type]

  gl.BindBufferBase(gl_target, u32(binding), buffer.id)
}

bind_gpu_buffer_range :: proc(buffer: GPU_Buffer, binding: UBO_Bind, offset, size: int) {
  assert(buffer.type == .UNIFORM || buffer.type == .STORAGE, "Only Uniform and Storage Buffers may be bound to locations")

  gl_target := buffer_type_to_gl[buffer.type]

  gl.BindBufferRange(gl_target, u32(binding), buffer.id, offset, size)
}

// Helper fast paths for triple buffered frame dependent buffers
gpu_buffer_frame_offset :: proc(buffer: GPU_Buffer, frame_index: int = state.curr_frame_index) -> int {
  assert(frame_index < FRAMES_IN_FLIGHT && frame_index >= 0)
  frame_offset := buffer.range_size * frame_index

  return frame_offset
}

bind_gpu_buffer_frame_range :: proc(buffer: GPU_Buffer, binding: UBO_Bind, frame_index: int = state.curr_frame_index) {
  frame_offset := gpu_buffer_frame_offset(buffer, frame_index)

  bind_gpu_buffer_range(buffer, binding, frame_offset, buffer.range_size)
}

write_gpu_buffer_frame :: proc(buffer: GPU_Buffer, offset, size: int, data: rawptr, frame_index: int = state.curr_frame_index) {
  assert(size <= buffer.range_size)

  frame_offset := gpu_buffer_frame_offset(buffer, frame_index)

  write_gpu_buffer(buffer, frame_offset + offset, size, data)
}

gpu_buffer_frame_base_ptr :: proc(buffer: GPU_Buffer, frame_index: int = state.curr_frame_index) -> rawptr {
  frame_offset := gpu_buffer_frame_offset(buffer, frame_index)

  address := uintptr(buffer.mapped) + uintptr(frame_offset)

  return rawptr(address)
}

free_gpu_buffer :: proc(buffer: ^GPU_Buffer) {
  if buffer.id != 0 {
    if buffer.mapped != nil {
      gl.UnmapNamedBuffer(buffer.id)
    }
    gl.DeleteBuffers(1, &buffer.id)
  }
}

// Now just a fast path for putting vertices and indices into a SSBO.
make_vertex_buffer :: proc($vertex_type: typeid, vertex_count: int, index_count: int = 0,
                           vertex_data: rawptr = nil, index_data: rawptr = nil, flags: GPU_Buffer_Flags = {}) -> (buffer: GPU_Buffer) {

  vertex_length := vertex_count * size_of(vertex_type)
  index_length  := index_count  * size_of(Mesh_Index) // FIXME: Hardcoded, but can't pass in compile time known arg defaults

  vertex_length_align := align_size_for_gpu(vertex_length)
  index_length_align  := align_size_for_gpu(index_length)

  total_size := vertex_length_align + index_length_align

  buffer = make_gpu_buffer(.STORAGE, total_size, flags = flags)

  // Ack
  gl.CreateVertexArrays(1, &buffer.vao);
  if (index_length > 0) {
    gl.VertexArrayElementBuffer(buffer.vao, buffer.id);
  }

  buffer.index_offset = vertex_length_align

  write_gpu_buffer(buffer, 0, vertex_length, vertex_data)
  write_gpu_buffer(buffer, buffer.index_offset, index_length, index_data)

  return buffer
}

bind_vertex_buffer :: proc(buffer: GPU_Buffer) {
  gl.BindVertexArray(buffer.vao)
}

unbind_vertex_buffer :: proc() {
  gl.BindVertexArray(0)
}

