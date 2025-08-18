#version 450 core

#include "include.glsl"

in VS_OUT {
  vec2 uv;
} fs_in;

out vec4 frag_color;

uniform int mat_diffuse_idx;

uniform vec4 mul_color;

void main() {
  frag_color = bindless_sample(mat_diffuse_idx, fs_in.uv) * mul_color;
}
