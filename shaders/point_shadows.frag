#version 460 core

#include "generated.glsl"

in VS_OUT
{
  vec4 world_position;
  vec2 uv;
  flat int light_index;
  flat int draw_id;
} fs_in;

void main()
{
  Material_Uniform material = draw_uniforms[fs_in.draw_id].material;
  float alpha = bindless_sample(material.diffuse_idx, fs_in.uv).a;

  if (alpha < 0.5)
  {
    discard;
  }

  Shadow_Point_Light_Uniform light = frame.shadow_point_lights[fs_in.light_index];

  // get distance between fragment and light source
  float light_dist = length(fs_in.world_position.xyz - light.position.xyz);

  // map to [0;1] range by dividing by far_plane
  light_dist /= light.radius;

  // write this as modified depth
  gl_FragDepth = light_dist;
}
