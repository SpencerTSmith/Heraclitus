#version 460 core

#include "generated.glsl"

layout(location = 0) in vec3 vert_position;
layout(location = 1) in vec2 vert_uv;
layout(location = 2) in vec3 vert_normal;
layout(location = 3) in vec4 vert_tangent;

out VS_OUT {
  vec2 uv;
  vec3 normal;
  vec3 world_position;
  vec4 sun_space_position;
  mat3 TBN;

  flat int draw_id;
} vs_out;

void main() {
  vs_out.draw_id = gl_BaseInstance;
  vs_out.uv = vert_uv;
  mat4 model = draw_uniforms[gl_BaseInstance].model;

  vs_out.world_position = vec3(model * vec4(vert_position, 1.0));

  mat4 sun_proj_view = frame.sun_light.proj_view;
  vs_out.sun_space_position = sun_proj_view * vec4(vs_out.world_position, 1.0);

  // FIXME: slow, probably
  mat3 normal_mat = transpose(inverse(mat3(model)));

  vs_out.normal = normalize(normal_mat * vert_normal);

  vec3 T = normalize(normal_mat * vert_tangent.xyz);
  vec3 N = vs_out.normal;
  T = normalize(T - dot(T, N) * N);
  vec3 B = cross(N, T) * vert_tangent.w;

  vs_out.TBN = mat3(T, B, N);

  gl_Position = frame.proj_view * vec4(vs_out.world_position, 1.0);
}
