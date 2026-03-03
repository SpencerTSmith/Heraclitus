#version 460 core

#include "generated.glsl"

layout(location = 0) in vec3 vert_position;
layout(location = 1) in vec2 vert_uv;

in VS_OUT {
  vec2 uv;

  flat int draw_id;
} fs_in;

void main() {
  Material_Uniform material = draw_uniforms[fs_in.draw_id].material;
  float alpha = bindless_sample(material.diffuse_idx, fs_in.uv).a;

  if (alpha < 0.5) {
    discard;
  }
}
