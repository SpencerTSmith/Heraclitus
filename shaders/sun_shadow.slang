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

  Draw_Uniform draw = push.draw_uniforms[draw_id];

  float4x4 proj_view = push.frame_uniform.sun_light.proj_view;

  Vert_Out o;
  o.position = mul(proj_view, mul(draw.model, float4(vertex.position, 1.0)));
  o.uv       = vertex.uv;
  o.draw_id  = draw_id;
  return o;
}

[shader("fragment")]
void frag_main(uniform Mega_Push push, Vert_Out i)
{
  Material_Uniform material = push.material_uniforms[push.draw_uniforms[i.draw_id].material_index];
  float alpha = sample_2D(material.diffuse, i.uv).a;

  if (alpha < 0.5)
  {
    discard;
  }
}
