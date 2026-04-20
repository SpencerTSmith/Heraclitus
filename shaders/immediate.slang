struct Immediate_Vertex
{
  float3 position;
  float2 uv;
  float4 color;
}

[[vk::push_constant]]
cbuffer Push
{
  column_major float4x4 transform;
  uint                  texture_index;
  Immediate_Vertex *vertices;
};

[[vk::binding(0, 0)]]
Sampler2D textures_2D[];

struct VSOutput
{
  float2 uv    : TEXCOORD0;
  float4 color : COLOR0;
  float4 pos   : SV_Position;
};

[shader("vertex")]
VSOutput vert_main(uint vid : SV_VulkanVertexID)
{
  Immediate_Vertex vertex = vertices[vid];

  VSOutput o;
  o.uv    = vertex.uv;
  o.color = vertex.color;
  o.pos   = mul(transform, float4(vertex.position, 1.0));
  return o;
}

[shader("fragment")]
float4 frag_main(VSOutput fs_in) : SV_Target0
{
  return textures_2D[NonUniformResourceIndex(texture_index)].Sample(fs_in.uv) * fs_in.color;
}
