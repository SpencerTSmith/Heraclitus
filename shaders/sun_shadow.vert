#version 460 core

#include "generated.glsl"

out VS_OUT
{
  vec2 uv;

  flat int draw_id;
} vs_out;

void main()
{
  vec3 vert_position = mesh_vertex_position(gl_VertexID);
  vec2 vert_uv       = mesh_vertex_uv(gl_VertexID);

  vs_out.draw_id = gl_BaseInstance;
  vs_out.uv      = vert_uv;

  mat4 model     = draw_uniforms[gl_BaseInstance].model;
  mat4 proj_view = frame.sun_light.proj_view;

  gl_Position = proj_view * model * vec4(vert_position, 1.0);
}
