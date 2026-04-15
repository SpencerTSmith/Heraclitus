#version 460 core

#extension GL_EXT_buffer_reference : require
#extension GL_EXT_scalar_block_layout : require
#extension GL_EXT_shader_explicit_arithmetic_types_int64 : require

layout(location=0) out VS_OUT
{
  vec2 uv;
  vec4 color;
} vs_out;

#push_constant

struct Immediate_Vertex {
  vec3 position;
  vec2 uv;
  vec4 color;
};

layout(buffer_reference, scalar) readonly buffer Immediate_Vertices
{
  Immediate_Vertex immediate_vertices[];
};

void main()
{
  Immediate_Vertices vertices = Immediate_Vertices(push.vertices);

  Immediate_Vertex vertex = vertices.immediate_vertices[gl_VertexIndex];

  vec3 vert_position = vertex.position;
  vec2 vert_uv       = vertex.uv;
  vec4 vert_color    = vertex.color;

  vs_out.uv    = vert_uv;
  vs_out.color = vert_color;

  gl_Position = push.transform * vec4(vert_position, 1.0);
}
