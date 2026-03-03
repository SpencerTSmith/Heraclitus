#version 460 core

#include "generated.glsl"

layout(location = 0) in vec3 vert_position;
layout(location = 1) in vec2 vert_uv;

out VS_OUT {
  vec2 uv;

  flat int draw_id;
} vs_out;

void main() {
  vs_out.draw_id = gl_DrawID;
  vs_out.uv      = vert_uv;

  mat4 model     = draw_uniforms[gl_DrawID].model;
  mat4 proj_view = frame.sun_light.proj_view;

  gl_Position = proj_view * model * vec4(vert_position, 1.0);
}
