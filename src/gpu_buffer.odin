package main

import "core:mem"
import "core:log"

// NOTE: CPU mapped is just for writing, the memory is host coherent, not host cached.
GPU_Buffer_Flag :: enum
{
  VERTEX_DATA,
  INDEX_DATA,
  UNIFORM_DATA,
  STORAGE_DATA,
  CPU_MAPPED,
  DEVICE_LOCAL,
}
GPU_Buffer_Flags :: bit_set[GPU_Buffer_Flag]

GPU_Buffer :: struct
{
  flags:      GPU_Buffer_Flags,

  cpu_base: rawptr,
  gpu_base: rawptr,

  total_size: int,
}

align_size_for_gpu :: proc(size: int) -> (aligned: int)
{
  min_alignment: i32
  // gl.GetIntegerv(gl.UNIFORM_BUFFER_OFFSET_ALIGNMENT, &min_alignment)

 aligned = mem.align_forward_int(size, int(min_alignment))
 return aligned
}

// NOTE: Since I control memory allocation and I know its just a bump allocator, frame/ring buffer is no longer needed
// conceptually... buffers made one after another are next to each other in memory, so just make FRAMES_IN_FLIGHT GPU_Buffers
make_gpu_buffer :: proc(size: int, data: rawptr = nil, flags: GPU_Buffer_Flags) -> (buffer: GPU_Buffer)
{
  buffer.gpu_base, buffer.cpu_base = vk_alloc_buffer(size, flags)
  buffer.flags = flags

  return buffer
}

write_gpu_buffer :: proc(buffer: GPU_Buffer, offset, size: int, data: rawptr)
{
  // if data != nil
  // {
  //   if gpu_buffer_is_mapped(buffer)
  //   {
  //     ptr := uintptr(buffer.cpu_base) + uintptr(offset)
  //     mem.copy(rawptr(ptr), data, size)
  //   }
  //   else
  //   {
  //     // gl.NamedBufferSubData(buffer.id, offset, size, data)
  //   }
  // }
}

bind_gpu_buffer_base :: proc(buffer: GPU_Buffer, binding: UBO_Bind)
{
  // gl_target: u32 = gl.UNIFORM_BUFFER if .UNIFORM_DATA in buffer.flags else gl.SHADER_STORAGE_BUFFER

  // gl.BindBufferBase(gl_target, u32(binding), buffer.id)
}

bind_gpu_buffer_range :: proc(buffer: GPU_Buffer, binding: UBO_Bind, offset, size: int)
{
  // gl_target: u32 = gl.UNIFORM_BUFFER if .UNIFORM_DATA in buffer.flags else gl.SHADER_STORAGE_BUFFER

  // gl.BindBufferRange(gl_target, u32(binding), buffer.id, offset, size)
}

// Helper fast paths for triple buffered frame dependent buffers
// gpu_buffer_frame_offset :: proc(buffer: GPU_Buffer, frame_index: int = state.curr_frame_index) -> int
// {
//   assert(frame_index < FRAMES_IN_FLIGHT && frame_index >= 0)
//   // frame_offset := buffer.range_size * frame_index
//
//   return frame_offset
// }

// bind_gpu_buffer_frame_range :: proc(buffer: GPU_Buffer, binding: UBO_Bind, frame_index: int = state.curr_frame_index)
// {
//   frame_offset := gpu_buffer_frame_offset(buffer, frame_index)
//
//   bind_gpu_buffer_range(buffer, binding, frame_offset, buffer.range_size)
// }

// write_gpu_buffer_frame :: proc(buffer: GPU_Buffer, offset, size: int, data: rawptr, frame_index: int = state.curr_frame_index)
// {
//   assert(size <= buffer.range_size)
//
//   frame_offset := gpu_buffer_frame_offset(buffer, frame_index)
//
//   write_gpu_buffer(buffer, frame_offset + offset, size, data)
// }

// gpu_buffer_frame_base_ptr :: proc(buffer: GPU_Buffer, frame_index: int = state.curr_frame_index) -> rawptr
// {
//   frame_offset := gpu_buffer_frame_offset(buffer, frame_index)
//
//   address := uintptr(buffer.cpu_base) + uintptr(frame_offset)
//
//   return rawptr(address)
// }

// free_gpu_buffer :: proc(buffer: ^GPU_Buffer)
// {
//   if buffer.id != 0
//   {
//     // if gpu_buffer_is_mapped(buffer^)
//     // {
//     //   // gl.UnmapNamedBuffer(buffer.id)
//     // }
//     // gl.DeleteBuffers(1, &buffer.id)
//   }
//   buffer^ = {}
// }

// Now just a fast path for putting vertices and indices into a SSBO.
make_vertex_buffer :: proc($vertex_type: typeid,
                           vertex_count: int,
                           $index_type:  typeid,
                           index_count:  int = 0,
                           vertex_data:  rawptr = nil,
                           index_data:   rawptr = nil,
                           flags: GPU_Buffer_Flags = {}) -> (buffer: GPU_Buffer)
{

  // vertex_length := vertex_count * size_of(vertex_type)
  // index_length  := index_count  * size_of(index_type)
  //
  // vertex_length_align := align_size_for_gpu(vertex_length)
  // index_length_align  := align_size_for_gpu(index_length)
  //
  // total_size := vertex_length_align + index_length_align
  //
  // buffer = make_gpu_buffer(total_size, flags = flags)
  //
  // // Ack
  // // gl.CreateVertexArrays(1, &buffer.vao);
  // if index_length > 0
  // {
  //   // gl.VertexArrayElementBuffer(buffer.vao, buffer.id);
  // }
  //
  // // buffer.index_offset = vertex_length_align
  //
  // write_gpu_buffer(buffer, 0, vertex_length, vertex_data)
  // // write_gpu_buffer(buffer, buffer.index_offset, index_length, index_data)
  //
  return buffer
}

bind_vertex_buffer :: proc(buffer: GPU_Buffer)
{
  // assert(.VERTEX_DATA in buffer.flags)
  // gl.BindVertexArray(buffer.vao)
}

unbind_vertex_buffer :: proc()
{
  // gl.BindVertexArray(0)
}

