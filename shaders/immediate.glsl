#version 460 core

#extension GL_EXT_buffer_reference : require
#extension GL_EXT_scalar_block_layout : require
#extension GL_EXT_shader_explicit_arithmetic_types_int64 : require
#extension GL_EXT_nonuniform_qualifier : require
struct Immediate_Vertex
{
  vec3 position;
  vec2 uv;
  vec4 color;
};

layout(set = 0, binding = 0) uniform sampler2D   textures_2D[];
layout(set = 0, binding = 1) uniform samplerCube textures_cube[];
layout(set = 0, binding = 2) uniform samplerCubeArray   textures_cube_array[];
layout(buffer_reference, scalar) readonly buffer Immediate_Vertices
{
  Immediate_Vertex v[];
};


layout(push_constant) uniform Immediate_Push
{
  mat4     transform;
  uint     texture;
  Immediate_Vertices vertices;
} push;

#ifdef VERTEX_SHADER

layout(location = 0) out VS_OUT
{
  vec2 uv;
  vec4 color;
} vs_out;

void main()
{
  Immediate_Vertex vertex = push.vertices.v[gl_VertexIndex];

  vec3 vert_position = vertex.position;
  vec2 vert_uv       = vertex.uv;
  vec4 vert_color    = vertex.color;

  vs_out.uv    = vert_uv;
  vs_out.color = vert_color;

  gl_Position = push.transform * vec4(vert_position, 1.0);
}

#endif // VERTEX_SHADER

#ifdef FRAGMENT_SHADER

layout(location = 0) in VS_OUT
{
  vec2 uv;
  vec4 color;
} fs_in;

layout(location = 0) out vec4 frag_color;

void main()
{
  frag_color = texture(textures_2D[nonuniformEXT(push.texture)], fs_in.uv) * fs_in.color;
}

#endif // FRAGMENT_SHADER
