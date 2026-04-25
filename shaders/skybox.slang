import generated;
import common;

static float3 verts[] =
{
  float3(-1.0,  1.0, -1.0),
  float3(-1.0, -1.0, -1.0),
  float3( 1.0, -1.0, -1.0),
  float3( 1.0, -1.0, -1.0),
  float3( 1.0,  1.0, -1.0),
  float3(-1.0,  1.0, -1.0),
  float3(-1.0, -1.0,  1.0),
  float3(-1.0, -1.0, -1.0),
  float3(-1.0,  1.0, -1.0),
  float3(-1.0,  1.0, -1.0),
  float3(-1.0,  1.0,  1.0),
  float3(-1.0, -1.0,  1.0),
  float3( 1.0, -1.0, -1.0),
  float3( 1.0, -1.0,  1.0),
  float3( 1.0,  1.0,  1.0),
  float3( 1.0,  1.0,  1.0),
  float3( 1.0,  1.0, -1.0),
  float3( 1.0, -1.0, -1.0),
  float3(-1.0, -1.0,  1.0),
  float3(-1.0,  1.0,  1.0),
  float3( 1.0,  1.0,  1.0),
  float3( 1.0,  1.0,  1.0),
  float3( 1.0, -1.0,  1.0),
  float3(-1.0, -1.0,  1.0),
  float3(-1.0,  1.0, -1.0),
  float3( 1.0,  1.0, -1.0),
  float3( 1.0,  1.0,  1.0),
  float3( 1.0,  1.0,  1.0),
  float3(-1.0,  1.0,  1.0),
  float3(-1.0,  1.0, -1.0),
  float3(-1.0, -1.0, -1.0),
  float3(-1.0, -1.0,  1.0),
  float3( 1.0, -1.0, -1.0),
  float3( 1.0, -1.0, -1.0),
  float3(-1.0, -1.0,  1.0),
  float3( 1.0, -1.0,  1.0),
};


struct Vert_Out
{
  float4 position : SV_Position;
  float3 uvw;
}

[shader("vertex")]
Vert_Out vert_main(uniform Skybox_Push push, uint vertex_id : SV_VulkanVertexID)
{
  float3 vert_position = verts[vertex_id];

  Frame_Uniform *frame = push.frame_uniform;

  float4x4 no_translation_view = float4x4(
      float4(frame->view[0].xyz, 0.0),
      float4(frame->view[1].xyz, 0.0),
      float4(frame->view[2].xyz, 0.0),
      float4(0.0, 0.0, 0.0,      1.0),
  );

  // View without translation transformations, gives the effect of a HUGE cube.
  float4 position = mul(frame.projection, mul(no_translation_view, float4(vert_position, 1.0)));

  Vert_Out o;
  o.uvw      = vert_position;
  // And save w in z as well so that after perspective divide, the position will have the max depth
  // and thus fail all depth tests, meaning it gets overwritten
  o.position = position.xyww;
  return o;
}

[shader("fragment")]
float4 frag_main(uniform Skybox_Push push, Vert_Out i) : SV_Target0
{
  return sample_cube_uniform(push.frame_uniform.skybox_index, i.uvw);
}
