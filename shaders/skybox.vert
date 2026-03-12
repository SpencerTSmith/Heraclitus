#version 460 core

#include "generated.glsl"

// Hardcode verts here so don't need it anywhere else.
vec3 verts[] = {
  vec3(-1.0,  1.0, -1.0),
  vec3(-1.0, -1.0, -1.0),
  vec3( 1.0, -1.0, -1.0),
  vec3( 1.0, -1.0, -1.0),
  vec3( 1.0,  1.0, -1.0),
  vec3(-1.0,  1.0, -1.0),
  vec3(-1.0, -1.0,  1.0),
  vec3(-1.0, -1.0, -1.0),
  vec3(-1.0,  1.0, -1.0),
  vec3(-1.0,  1.0, -1.0),
  vec3(-1.0,  1.0,  1.0),
  vec3(-1.0, -1.0,  1.0),
  vec3( 1.0, -1.0, -1.0),
  vec3( 1.0, -1.0,  1.0),
  vec3( 1.0,  1.0,  1.0),
  vec3( 1.0,  1.0,  1.0),
  vec3( 1.0,  1.0, -1.0),
  vec3( 1.0, -1.0, -1.0),
  vec3(-1.0, -1.0,  1.0),
  vec3(-1.0,  1.0,  1.0),
  vec3( 1.0,  1.0,  1.0),
  vec3( 1.0,  1.0,  1.0),
  vec3( 1.0, -1.0,  1.0),
  vec3(-1.0, -1.0,  1.0),
  vec3(-1.0,  1.0, -1.0),
  vec3( 1.0,  1.0, -1.0),
  vec3( 1.0,  1.0,  1.0),
  vec3( 1.0,  1.0,  1.0),
  vec3(-1.0,  1.0,  1.0),
  vec3(-1.0,  1.0, -1.0),
  vec3(-1.0, -1.0, -1.0),
  vec3(-1.0, -1.0,  1.0),
  vec3( 1.0, -1.0, -1.0),
  vec3( 1.0, -1.0, -1.0),
  vec3(-1.0, -1.0,  1.0),
  vec3( 1.0, -1.0,  1.0),
};

out VS_OUT {
  vec3 uvw;
} vs_out;

void main() {
  vec3 vert_position = verts[gl_VertexID];

  vs_out.uvw = vert_position;

  // View without translation transformations, gives the effect of a HUGE cube
  mat4 view_mod = mat4(mat3(frame.view));
  vec4 position = frame.projection * view_mod * vec4(vert_position, 1.0);

  // And save w in z as well so that after perspective divice, the position will have the max depth
  // and thus fail all depth tests, meaning it get overwritten
  gl_Position = position.xyww;
}
