#version 460 core

#extension GL_ARB_bindless_texture : require

in VS_OUT
{
  vec2 uv;
  vec4 color;
} fs_in;

layout(location = 0) out vec4 frag_color;

layout(bindless_sampler) uniform sampler2D tex;

void main()
{
  // float alpha = texture(tex, fs_in.uv).r * fs_in.color.a;
  frag_color = texture(tex, fs_in.uv) * fs_in.color;
}
