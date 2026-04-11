package main

import "core:log"
import "core:mem"

import gl "vendor:OpenGL"

MAX_DRAWS     :: 1  * mem.Megabyte
MAX_VERTICES  :: 4  * mem.Megabyte
MAX_INDICES   :: 16 * mem.Megabyte
MAX_MATERIALS :: 512

Multi_Draw_State :: struct
{
  vertex_buffer: GPU_Buffer,
  vertex_count:  int,
  index_count:   int,

  material_buffer: GPU_Buffer,
  material_count:  int,

  // All triple buffered
  draw_commands: GPU_Buffer,
  draw_uniforms: GPU_Buffer,
  draw_head:  int,
  draw_count: int, // Total
}

init_multi_draw :: proc() -> (mds: Multi_Draw_State)
{
  mds.vertex_buffer = make_vertex_buffer(Mesh_Vertex, MAX_VERTICES, Mesh_Index, MAX_INDICES)
  bind_gpu_buffer_base(mds.vertex_buffer, .MESH_VERTICES)

  mds.material_buffer = make_gpu_buffer(size_of(Material_Uniform) * MAX_MATERIALS, flags={})
  bind_gpu_buffer_base(mds.material_buffer, .MATERIALS)

  mds.draw_commands = make_gpu_buffer(size_of(Draw_Command) * MAX_DRAWS,
                                      flags = {.PERSISTENT, .FRAME_BUFFERED})
  mds.draw_uniforms = make_gpu_buffer(size_of(Draw_Uniform) * MAX_DRAWS,
                                      flags = {.PERSISTENT, .FRAME_BUFFERED})

  return mds
}

upload_vertices :: proc(mds: ^Multi_Draw_State, vertices: []Mesh_Vertex, indices: []Mesh_Index) -> (vertex_offset, index_offset: i32)
{
  if mds.vertex_count + len(vertices) < MAX_VERTICES &&
     mds.index_count + len(indices)   < MAX_INDICES
  {
    vertex_offset = cast(i32) mds.vertex_count

    vertex_byte_offset := size_of(vertices[0]) * mds.vertex_count
    write_gpu_buffer(mds.vertex_buffer, vertex_byte_offset, size_of(vertices[0]) * len(vertices), raw_data(vertices))

    mds.vertex_count += len(vertices)

    index_offset = cast(i32) mds.index_count
    index_byte_offset := mds.vertex_buffer.index_offset + size_of(indices[0]) * mds.index_count
    write_gpu_buffer(mds.vertex_buffer, index_byte_offset, size_of(indices[0]) * len(indices), raw_data(indices))
    mds.index_count += len(indices)
  }
  else
  {
    log.errorf("Cannot push any more vertices to mega buffer.")
  }

  return vertex_offset, index_offset
}

upload_materials :: proc(mds: ^Multi_Draw_State, materials: ^[]Material)
{
  if (mds.material_count + len(materials)) < MAX_MATERIALS
  {
    uniforms := make([]Material_Uniform, len(materials), context.temp_allocator)
    write_offset := mds.material_count * size_of(uniforms[0])

    for &material, idx in materials
    {
      uniforms[idx] = material_uniform(material)
      material.buffer_index = u32(mds.material_count)
      mds.material_count += 1
    }

    write_gpu_buffer(mds.material_buffer, write_offset, len(uniforms) * size_of(uniforms[0]), raw_data(uniforms))
  }
  else
  {
    log.errorf("Cannot push materials to mega buffer.")
  }
}

push_draw :: proc(mds: ^Multi_Draw_State, command: Draw_Command, uniform: Draw_Uniform)
{
  if (mds.draw_count + 1 < MAX_DRAWS)
  {
    // Draw Command
    {
      command := command

      // NOTE: Using this to index into the total buffer. As we have to do multiple
      // multidraws per frame due to shadow mapping,
      // gl_DrawID no longer works perfectly to index
      command.base_instance = cast(u32)mds.draw_count
      command.first_index += cast(u32)mds.vertex_buffer.index_offset/4

      offset := size_of(Draw_Command) * mds.draw_count
      write_gpu_buffer_frame(mds.draw_commands, offset, size_of(command), &command)
    }

    // Draw Uniform
    {
      uniform := uniform
      offset := size_of(Draw_Uniform) * mds.draw_count
      write_gpu_buffer_frame(mds.draw_uniforms, offset, size_of(uniform), &uniform)
    }

    mds.draw_count += 1
  }
  else
  {
    log.errorf("Cannot push any more draw commands.");
  }
}

multi_draw :: proc(mds: ^Multi_Draw_State)
{
  bind_vertex_buffer(mds.vertex_buffer)
  gl.BindBuffer(gl.DRAW_INDIRECT_BUFFER, mds.draw_commands.id)

  // Since we can't bind the base we do a frame offset here
  frame_offset := gpu_buffer_frame_offset(mds.draw_commands)
  batch_offset := cast(uintptr)(frame_offset + mds.draw_head * size_of(Draw_Command))

  batch_count := cast(i32) (mds.draw_count - mds.draw_head)

  gl.MultiDrawElementsIndirect(gl.TRIANGLES, gl.UNSIGNED_INT,
    cast([^]gl.DrawElementsIndirectCommand)batch_offset, batch_count, 0)

  mds.draw_head = mds.draw_count // Move head pointer up
}

// NOTE: Per frame.
reset_multi_draw :: proc(mds: ^Multi_Draw_State)
{
  mds.draw_count = 0
  mds.draw_head  = 0
}
