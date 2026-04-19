#version 460 core

#include "generated.glsl"

layout(location = 0) out VS_OUT
{
  vec2 uv;
  vec4 color;
} vs_out;

#push_constant

void main()
{
  Immediate_Vertex vertex = Immediate_Vertices(push.vertices).v[gl_VertexIndex];

  vec3 vert_position = vertex.position;
  vec2 vert_uv       = vertex.uv;
  vec4 vert_color    = vertex.color;

  vs_out.uv    = vert_uv;
  vs_out.color = vert_color;

  gl_Position = push.transform * vec4(vert_position, 1.0);
}
