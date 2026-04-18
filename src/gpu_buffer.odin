package main

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

// Typed GPU Buffers... really just a convenience. But I think its worth it.
// For untyped buffers like my staging buffer, just pass a byte as the type
GPU_Buffer :: struct($Type: typeid)
{
  flags: GPU_Buffer_Flags,

  cpu_base: [^]Type,
  gpu_base: rawptr,

  count: int,
}

make_gpu_buffer :: proc($Type: typeid, count: int, flags: GPU_Buffer_Flags) -> (buffer: GPU_Buffer(Type))
{
  gpu_ptr, cpu_ptr := vk_alloc_buffer(size_of(Type) * count, flags)

  buffer.gpu_base = gpu_ptr
  buffer.cpu_base = cast([^]Type)cpu_ptr
  buffer.flags    = flags
  buffer.count    = count

  return buffer
}

// Helper for making a few of the same type... having this api set up will help in case i ever change backend allocation to at least keep buffers
// created through this api to be linear in memory.
make_ring_gpu_buffers :: proc($Type: typeid, count: int, flags: GPU_Buffer_Flags, $N: uint) -> (buffers: [N]GPU_Buffer(Type))
{
  // Because i am forgetful.
  if .CPU_MAPPED not_in flags { log.warnf("Did you mean to create GPU ring buffers without asking for CPU mapped memory?") }

  // Simple since allocation is just bump on backend.
  for &buffer in buffers
  {
    buffer = make_gpu_buffer(Type, count, flags)
  }

  return buffers
}

gpu_buffer_as_bytes :: proc(buffer: GPU_Buffer($Type)) -> (byte_buffer: GPU_Buffer(byte))
{
  byte_buffer =
  {
    cpu_base = cast([^]byte)buffer.cpu_base,
    gpu_base = buffer.gpu_base,
    count    = size_of(Type) * buffer.count,
    flags    = buffer.flags,
  }

  return byte_buffer
}
