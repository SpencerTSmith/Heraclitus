#version 450 core

#include "generated.glsl"

in VS_OUT {
  vec3 uvw;
} fs_in;

layout(binding = 0) uniform samplerCube skybox;

out vec4 frag_color;

void main() {
  vec4 result = vec4(0.0);
  result = texture(skybox, fs_in.uvw);

  frag_color = result;
}
