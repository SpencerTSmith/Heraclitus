#version 450 core

#include "generated.glsl"

layout(location = 0) in vec3 vert_position;
layout(location = 1) in vec2 vert_uv;

out VS_OUT {
  vec2 uv;
} vs_out;

uniform mat4 model;

void main() {
  mat4 proj_view = frame.sun_light.proj_view;

  vs_out.uv = vert_uv;

  gl_Position = proj_view * model * vec4(vert_position, 1.0);
}
