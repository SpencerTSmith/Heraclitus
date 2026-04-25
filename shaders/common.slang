import generated;

Sampler2D textures_2D[];
SamplerCube textures_cube[];
SamplerCubeArray textures_cube_array[];

float4 sample2D(uint index, float2 uv)
{
  return textures_2D[NonUniformResourceIndex(index)].Sample(uv);
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
