import generated;

[[vk::binding(0)]]
Sampler2D textures_2D[];
[[vk::binding(1)]]
SamplerCube textures_cube[];
[[vk::binding(2)]]
SamplerCubeArray textures_cube_array[];

// TODO: It might be worth having a separate paths for when the index is actually uniform
float4 sample_2D(uint index, float2 uv)
{
  return textures_2D[NonUniformResourceIndex(index)].Sample(uv);
}
float4 sample_cube(uint index, float3 uvw)
{
  return textures_cube[NonUniformResourceIndex(index)].Sample(uvw);
}
float4 sample_2D_uniform(uint index, float2 uv)
{
  return textures_2D[index].Sample(uv);
}
float4 sample_cube_uniform(uint index, float3 uvw)
{
  return textures_cube[index].Sample(uvw);
}

float point_shadow(uint cube_array_index, uint light_index,
                   float3 frag_position, float3 frag_normal, float3 light_pos,
                   float light_z_far, float3 view_position)
{
  // TODO
  return 0.0;
}

float3 point_phong(Point_Light_Uniform light, float3 diffuse_sample, float3 specular_sample,
                   float shininess, float3 normal, float3 view_direction, float3 frag_position)
{
  // TODO
  return 0.0;
}

float3 phong_ambient(float ambient_intensity, float3 color)
{
	float3 ambient = ambient_intensity * color;

  return ambient;
}
