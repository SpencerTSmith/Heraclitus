import generated;
import common;

struct VSOutput
{
  float4   position : SV_Position;
  float2   uv;
  float3   normal; // FIXME: Info contained in TBN matrix.
  float4   world_position;
  float4   sun_space_position;
  float3x3 TBN;

  nointerpolation uint draw_id;
}

[shader("vertex")]
VSOutput vert_main(uniform Mega_Push push, uint vertex_id : SV_VulkanVertexID, uint draw_id : SV_DrawIndex)
{
  Mesh_Vertex vertex = push.vertices[vertex_id];

  float4x4 sun_proj_view    = push.frame_uniform->sun_light.proj_view;
  float4x4 camera_proj_view = push.frame_uniform->proj_view;
  float4x4 model            = push.draw_uniforms[draw_id].model;

  // FIXME:
  float3x3 normal_matrix = transpose(inverse(float3x3(model)));

  float3 tangent   = normalize(mul(normal_matrix, vertex.tangent.xyz));
  float3 normal    = mul(normal_matrix, vertex.normal);
  tangent          = normalize(tangent - dot(tangent, N) * N);
  float3 bitangent = cross(N, tangent) * vert_tangent.w;

  VSOutput o;
  o.uv                 = vertex.uv;
  o.world_position     = mul(model, float4(vertex.position, 1.0));
  o.sun_space_position = mul(sun_proj_view, o.world_position);
  o.position           = mul(camera_proj_view, o.world_position);
  o.draw_id            = draw_id;
  o.normal             = normal;
  o.TBN                = float3x3(tangent, bitangent, normal);
  return o;
}

[shader("fragment")]
float4 frag_main(uniform Mega_Push push, VSOutput i) : SV_Target0
{
  float3 result = float3(0.0);

  Frame_Uniform *frame = push.frame_uniform;

  Draw_Uniform draw = push.draw_uniforms[i.draw_id];

  Material_Uniform material = push.material_uniforms[draw.material_index];

  float4 mul_color = draw.mul_color;

  float alpha            = sample2D(material.diffuse, i.uv).a;
  float3 diffuse_sample  = sample2D(material.diffuse, i.uv).rgb;
  float3 specular_sample = sample2D(material.specular, i.uv).rgb;
  float3 emissive_sample = sample2D(material.emissive, i.uv).rgb;
  float3 normal_sample   = sample2D(material.normal, i.uv).rgb;

  // Move range from [0, 1] to [-1, 1]
  float3 normal_map = normalize(normal_sample * 2.0 - 1.0);

  // Find actual transformed normal
  float3 normal = normalize(mul(i.TBN, normal_map));

  float3 view_direction = normalize(frame->camera_position.xyz - i.world_position.xyz);

  float3 ambient = float3(0.02);

  float3 all_point_phong = float3(0.0);
  for (uint shadow_index = 0; shadow_index < frame->shadow_points_count; shadow_index++)
  {
    Shadow_Point_Light_Uniform light = frame->shadow_point_lights[shadow_index];

    float point_shadow = 1.0 - point_shadow(point_shadow_index, shadow_index,
                                            i.world_position.xyz, normal,
                                            light.position.xyz, light.radius,
                                            frame->camera_position.xyz);

    Point_Light_Uniform temp =
    {
      light.position,
      light.color,
      light.radius,
      light.intensity,
      light.ambient,
    };

    float3 point_phong = point_phong(temp, diffuse_sample, specular_sample, material.shininess,
                                     normal, view_direction, i.world_position.xyz);
    point_phong *= point_shadow;

    ambient += phong_ambient(light.ambient, light.color.xyz);
  }

  return float4(result, alpha) * mul_color;
}
