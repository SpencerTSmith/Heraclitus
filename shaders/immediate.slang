import generated;

struct VSOutput
{
  float2 uv    : TEXCOORD0;
  float4 color : COLOR0;
  float4 pos   : SV_Position;
}

[shader("vertex")]
VSOutput vert_main(uniform Immediate_Push push, uint vid : SV_VulkanVertexID)
{
  Immediate_Vertex vertex = push.vertices[vid];

  VSOutput o;
  o.uv    = vertex.uv;
  o.color = vertex.color;
  o.pos   = mul(push.transform, float4(vertex.position, 1.0));
  return o;
}

[shader("fragment")]
float4 frag_main(uniform Immediate_Push push, VSOutput fs_in) : SV_Target0
{
  return textures_2D[NonUniformResourceIndex(push.texture)].Sample(fs_in.uv) * fs_in.color;
}
