#version 450 core

#include "include.glsl"

in VS_OUT {
  vec2 uv;
} fs_in;

out vec4 frag_color;

layout(binding = 0) uniform sampler2D mat_diffuse;

uniform float mul_color;

void main() {
  frag_color = texture(mat_diffuse, fs_in.uv) * mul_color;
}
