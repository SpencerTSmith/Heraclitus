#version 460 core

#include "generated.glsl"

layout(location=0) in VS_OUT
{
  vec2 uv;
  vec4 color;
} fs_in;

layout(location = 0) out vec4 frag_color;

#push_constant

void main()
{
  // frag_color = fs_in.color;
  frag_color = texture(textures_2D[nonuniformEXT(push.texture_index)], fs_in.uv) * fs_in.color;
  // frag_color = vec4(fs_in.uv, 0, 1);
}
