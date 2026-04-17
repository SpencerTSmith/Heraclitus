// NOTE: This code was generated on 17-04-2026 (06:33:37 pm)

#extension GL_EXT_buffer_reference : require
#extension GL_EXT_scalar_block_layout : require
#extension GL_EXT_shader_explicit_arithmetic_types_int64 : require
struct Immediate_Vertex {
  vec3 position;
  vec2 uv;
  vec4 color;
};

layout(buffer_reference, scalar) readonly buffer Immediate_Vertices {
  Immediate_Vertex immediate_vertices[];
};


// vec3 mesh_vertex_position(int index)
// {
//   return vec3(mesh_vertices[index].position[0],
//               mesh_vertices[index].position[1],
//               mesh_vertices[index].position[2]);
// }
// vec2 mesh_vertex_uv(int index)
// {
//   return vec2(mesh_vertices[index].uv[0],
//               mesh_vertices[index].uv[1]);
// }
// vec3 mesh_vertex_normal(int index)
// {
//   return vec3(mesh_vertices[index].normal[0],
//               mesh_vertices[index].normal[1],
//               mesh_vertices[index].normal[2]);
// }
// vec4 mesh_vertex_tangent(int index)
// {
//   return vec4(mesh_vertices[index].tangent[0],
//               mesh_vertices[index].tangent[1],
//               mesh_vertices[index].tangent[2],
//               mesh_vertices[index].tangent[3]);
// }

// vec3 immediate_vertex_position(Immediate_Vertices vertices, int index)
// {
//   return vec3(vertices[index].position[0],
//               vertices[index].position[1],
//               vertices[index].position[2]);
// }
// vec2 immediate_vertex_uv(Immediate_Vertices vertices, int index)
// {
//   return vec2(vertices[index].uv[0],
//               vertices[index].uv[1]);
// }
// vec4 immediate_vertex_color(Immediate_Vertex vertex)
// {
//   return vec4(vertices[index].color[0],
//               vertices[index].color[1],
//               vertices[index].color[2],
//               vertices[index].color[3]);
// }

