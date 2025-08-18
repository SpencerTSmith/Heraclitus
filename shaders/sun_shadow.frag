#version 450 core

#include "include.glsl"

layout(location = 0) in vec3 vert_position;
layout(location = 1) in vec2 vert_uv;

in VS_OUT {
  vec2 uv;
} fs_in;

uniform int mat_diffuse_idx;

void main() {
  float alpha = bindless_sample(mat_diffuse_idx, fs_in.uv).a;

  if (alpha < 0.5) {
    discard;
  }
}
