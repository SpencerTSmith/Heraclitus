import generated;
import common;

struct Vert_Out
{
  float4 position : SV_Position;
  float2 uv;
  float4 color;
}

[shader("vertex")]
Vert_Out vert_main(uniform Immediate_Push push, uint vertex_id : SV_VulkanVertexID)
{
  Immediate_Vertex vertex = push.vertices[vertex_id];

  Vert_Out o;
  o.uv       = vertex.uv;
  o.color    = vertex.color;
  o.position = mul(push.transform, float4(vertex.position, 1.0));
  return o;
}

[shader("fragment")]
float4 frag_main(uniform Immediate_Push push, Vert_Out i) : SV_Target0
{
  return sample_2D_uniform(push.texture, i.uv) * i.color;
}
