#version 460 core

// So don't have to deal with geometry shader nonsense
#extension GL_ARB_shader_viewport_layer_array : enable
#include "generated.glsl"

out VS_OUT
{
  vec4 world_position;
  vec2 uv;

  flat int light_index;
  flat int draw_id;
} vs_out;

// NOTE: This only works with a cubemap array target!
void main()
{
  vec3 vert_position = mesh_vertex_position(gl_VertexID);
  vec2 vert_uv       = mesh_vertex_uv(gl_VertexID);

  mat4 model = draw_uniforms[gl_BaseInstance].model;

  int light_index = draw_uniforms[gl_BaseInstance].light_index;
  int face_index = gl_InstanceID;

  Shadow_Point_Light_Uniform light = frame.shadow_point_lights[light_index];

  mat4 proj_view = light.proj_views[face_index];

  vec4 world_pos = model * vec4(vert_position, 1.0);

  gl_Position = proj_view * world_pos;

  // We can use instanced rendering to do just one draw call for the entire cubemap, in the array,
  // as well as bypassing trying to do the same in the geometry shader
  gl_Layer = light_index * 6 + face_index;

  vs_out.world_position = world_pos;
  vs_out.uv             = vert_uv;

  vs_out.light_index    = light_index;
  vs_out.draw_id        = gl_BaseInstance;
}
