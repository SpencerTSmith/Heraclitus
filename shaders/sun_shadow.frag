#version 460 core

#include "generated.glsl"

in VS_OUT
{
  vec2 uv;

  flat int draw_id;
} fs_in;

void main()
{
  Material_Uniform material = materials[draw_uniforms[fs_in.draw_id].material_index];
  float alpha = texture(material.diffuse, fs_in.uv).a;

  if (alpha < 0.5)
  {
    discard;
  }
}
