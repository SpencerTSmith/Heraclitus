#version 460 core

layout(location=0) in VS_OUT
{
  vec2 uv;
  vec4 color;
} fs_in;

layout(location = 0) out vec4 frag_color;

void main()
{
  frag_color = fs_in.color;
  // frag_color = texture(tex, fs_in.uv) * fs_in.color;
}
