#version 460 core

#include "generated.glsl"

out VS_OUT {
  vec2 uv;
  vec4 color;
} vs_out;

uniform mat4 transform;

void main() {
  vec3 vert_position = immediate_vertex_position(gl_VertexID);
  vec2 vert_uv       = immediate_vertex_uv(gl_VertexID);
  vec4 vert_color    = immediate_vertex_color(gl_VertexID);

  vs_out.uv    = vert_uv;
  vs_out.color = vert_color;

  gl_Position = transform * vec4(vert_position, 1.0);
}
