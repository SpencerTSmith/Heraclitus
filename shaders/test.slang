import generated;
import common;

struct Vert_Out
{
  float4 position : SV_Position;
  float2 uv;

  nointerpolation uint draw_id;
}

[shader("vertex")]
Vert_Out vert_main(uniform Mega_Push push, uint vertex_id : SV_VulkanVertexID, uint draw_id : SV_DrawIndex)
{
  Mesh_Vertex vertex = push.vertices[vertex_id];

  float4x4 camera_proj_view = push.frame_uniform->proj_view;
  float4x4 model            = push.draw_uniforms[draw_id].model;

  Vert_Out o;
  o.position = mul(camera_proj_view, mul(model, float4(vertex.position, 1.0)));
  o.uv       = vertex.uv;
  o.draw_id  = draw_id;
  return o;
}

[shader("fragment")]
float4 frag_main(uniform Mega_Push push, Vert_Out i) : SV_Target0
{
  Draw_Uniform draw = push.draw_uniforms[i.draw_id];

  Material_Uniform material = push.material_uniforms[draw.material_index];

  float4 diffuse_sample = sample2D(material.diffuse, i.uv);

  return diffuse_sample;
}
