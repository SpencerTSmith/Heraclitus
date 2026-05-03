import generated;
import common;

struct Vert_Out
{
  float4   position : SV_Position;
  float2   uv;
  float4   world_position;
  float3x3 TBN;

  nointerpolation uint draw_id;
}

[shader("vertex")]
Vert_Out vert_main(uniform Mega_Push push, uint vertex_id : SV_VulkanVertexID, uint draw_id : SV_DrawIndex)
{
  Mesh_Vertex vertex = push.vertices[vertex_id];

  float4x4 camera_proj_view = push.frame_uniform.proj_view;
  float4x4 model            = push.draw_uniforms[draw_id].model;

  // NOTE: Only correct for uniformly scaled things.
  float3x3 normal_matrix = float3x3(model);

  float3 tangent   = normalize(mul(normal_matrix, vertex.tangent.xyz));
  float3 normal    = normalize(mul(normal_matrix, vertex.normal));
  tangent          = normalize(tangent - dot(tangent, normal) * normal);
  float3 bitangent = cross(normal, tangent) * vertex.tangent.w;

  Vert_Out o;
  o.uv                 = vertex.uv;
  o.world_position     = mul(model, float4(vertex.position, 1.0));
  o.position           = mul(camera_proj_view, o.world_position);
  o.draw_id            = draw_id;
  o.TBN                = transpose(float3x3(tangent, bitangent, normal)); // HACK: Transpose since the constructor here takes in rows.
  return o;
}

[shader("fragment")]
float4 frag_main(uniform Mega_Push push, Vert_Out i) : SV_Target0
{
  float3 result = float3(0.0);

  Frame_Uniform *frame = push.frame_uniform;

  Draw_Uniform draw = push.draw_uniforms[i.draw_id];

  Material_Uniform material = push.material_uniforms[draw.material_index];

  float4 mul_color = draw.mul_color;

  float alpha            = sample_2D(material.diffuse, i.uv).a;
  float3 diffuse_sample  = sample_2D(material.diffuse, i.uv).rgb;
  float3 specular_sample = sample_2D(material.specular, i.uv).rgb;
  float3 emissive_sample = sample_2D(material.emissive, i.uv).rgb;
  float3 normal_sample   = sample_2D(material.normal, i.uv).rgb;

  // Move range from [0, 1] to [-1, 1]
  float3 normal_map = normalize(normal_sample * 2.0 - 1.0);

  // Find actual transformed normal
  float3 normal = normalize(mul(i.TBN, normal_map));

  float3 view_direction = normalize(frame.camera_position.xyz - i.world_position.xyz);

  float3 ambient = float3(0.02);

  float3 all_point_phong = float3(0.0);
  for (uint shadow_index = 0; shadow_index < frame.shadow_points_count; shadow_index++)
  {
    Shadow_Point_Light_Uniform light = frame.shadow_point_lights[shadow_index];

    float point_shadow = 1.0 - point_shadow(frame.point_shadow_index, shadow_index,
                                            i.world_position.xyz, normal,
                                            light.position.xyz, light.radius,
                                            frame.camera_position.xyz);

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

    all_point_phong += point_phong;

    ambient += phong_ambient(light.ambient, light.color.xyz);
  }

  for (uint point_index = 0; point_index < frame.points_count; point_index++)
  {
    Point_Light_Uniform light = frame.point_lights[point_index];

    float3 point_phong = point_phong(light, diffuse_sample, specular_sample, material.shininess,
                                     normal, view_direction, i.world_position.xyz);
    all_point_phong += point_phong;

    ambient += phong_ambient(light.ambient, light.color.xyz);
  }

  float3 direction_phong = direction_phong(frame.sun_light, diffuse_sample, specular_sample,
                                           material.shininess, normal, view_direction);

  float view_depth = -mul(frame.view, i.world_position).z;
  float direction_shadow = 1.0 - direction_shadow(frame.sun_light, frame.sun_shadow_index,
                                                  i.world_position.xyz, i.position.xy, normal, view_depth);

  direction_phong *= direction_shadow;

  ambient += phong_ambient(frame.sun_light.ambient, frame.sun_light.color.xyz);

  float3 spot_phong = spot_phong(frame.flash_light, diffuse_sample, specular_sample, material.shininess,
                                 normal, view_direction, i.world_position.xyz);

  ambient += phong_ambient(frame.flash_light.ambient, frame.flash_light.color.xyz);

  ambient *= diffuse_sample;

  result = all_point_phong + direction_phong + spot_phong + emissive_sample + ambient;

  return float4(result, alpha) * mul_color;
}
