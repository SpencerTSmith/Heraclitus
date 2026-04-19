#version 460 core

#include "generated.glsl"

layout(location = 0) in VS_OUT
{
  vec2 uv;
  vec4 color;
} fs_in;

layout(location = 0) out vec4 frag_color;

#push_constant

void main()
{
  frag_color = texture(textures_2D[push.texture], fs_in.uv) * fs_in.color;
}
