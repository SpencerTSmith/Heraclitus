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

// TODO: It would be cool if these could also be polymorphic and castable as a pointer to an actual type...
// just some way to encode a type
GPU_Buffer :: struct
{
  flags: GPU_Buffer_Flags,

  cpu_base: rawptr,
  gpu_base: rawptr,

  size: int,
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
make_gpu_buffer :: proc(size: int, flags: GPU_Buffer_Flags) -> (buffer: GPU_Buffer)
{
  buffer.gpu_base, buffer.cpu_base = vk_alloc_buffer(size, flags)
  buffer.flags = flags
  buffer.size  = size

  return buffer
}

// Helper for making a few of the same type... having this api set up will help in case i ever change backend allocation to at least keep buffers
// created through this api to be linear in memory.
make_ring_gpu_buffers :: proc(size: int, flags: GPU_Buffer_Flags, $N: uint) -> (buffers: [N]GPU_Buffer)
{
  if .CPU_MAPPED not_in flags { log.warnf("Did you mean to create GPU ring buffers without asking for cpu mapped memory?") }

  // Simple since allocation is just bump on backend.
  for &buffer in buffers
  {
    buffer = make_gpu_buffer(size, flags)
  }

  return buffers
}
