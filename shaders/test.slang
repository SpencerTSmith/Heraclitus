import generated;

struct VSOutput
{
  float4 position : SV_Position;
}

[shader("vertex")]
VSOutput vert_main(uniform Mega_Push push, uint vertex_id : SV_VulkanVertexID, uint draw_id : SV_DrawIndex)
{
  Mesh_Vertex vertex = push.vertices[vertex_id];

  float4x4 camera_proj_view = push.frame_uniform->proj_view;
  float4x4 model            = push.draw_uniforms[draw_id].model;

  VSOutput o;
  o.position = mul(camera_proj_view, mul(model, float4(vertex.position, 1.0)));
  return o;
}

[shader("fragment")]
float4 frag_main(uniform Mega_Push push, VSOutput i) : SV_Target0
{
  return float4(1.0);
}
