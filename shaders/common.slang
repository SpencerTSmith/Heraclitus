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

float3 phong_diffuse(float3 normal, float3 light_direction, float3 diffuse_color)
{
	float diffuse_intensity = max(dot(normal, light_direction), 0.0);
	float3 diffuse = diffuse_intensity * diffuse_color;

  return diffuse;
}

float3 phong_specular(float3 normal, float3 light_direction, float3 view_direction, float3 specular_color, float shininess)
{
  float3 halfway_direction = normalize(light_direction + view_direction);

	float specular_intensity = pow(max(dot(normal, halfway_direction), 0.0), shininess);
	float3 specular = specular_intensity * specular_color;

  return specular;
}

float point_shadow(uint cube_array_index, uint light_index,
                   float3 frag_position, float3 frag_normal, float3 light_pos,
                   float light_z_far, float3 view_position)
{
  // TODO
  return 0.0;
}

float attenuation(float3 light_position, float light_radius, float3 frag_position)
{
  float distance = length(light_position - frag_position);

  float ratio = distance / light_radius;
  float falloff = 1.0 - ratio * ratio;

  return smoothstep(0.0, 1.0, falloff);
}

float3 point_phong(Point_Light_Uniform light, float3 diffuse_sample, float3 specular_sample,
                   float shininess, float3 normal, float3 view_direction, float3 frag_position)
{
	float3 light_direction = normalize(light.position.xyz - frag_position);

	float3 diffuse = phong_diffuse(normal, light_direction, diffuse_sample);

	float3 specular = phong_specular(normal, light_direction, view_direction, specular_sample, shininess);

	float attenuation = attenuation(light.position.xyz, light.radius, frag_position);

	float3 phong = attenuation * light.intensity * light.color.rgb * (diffuse + specular);

	return saturate(phong);
}

float3 direction_phong(Direction_Light_Uniform light, float3 diffuse_sample, float3 specular_sample,
                       float shininess, float3 normal, float3 view_direction)
{
  float3 light_direction = normalize(-light.direction.xyz);

  float3 diffuse  = phong_diffuse(normal, light_direction, diffuse_sample);
  float3 specular = phong_specular(normal, light_direction, view_direction, specular_sample, shininess);

  float3 phong = light.intensity * light.color.rgb * (diffuse + specular);

  return saturate(phong);
}

float3 spot_phong(Spot_Light_Uniform light, float3 diffuse_sample, float3 specular_sample,
                  float shininess, float3 normal, float3 view_direction, float3 frag_position)
{
  // TODO
  return 0.0;
}

float direction_shadow(uint shadow_map_index, float4 light_space_position, float3 to_light_dir, float3 normal)
{
  // TODO
  return 0.0;
}

float3 phong_ambient(float ambient_intensity, float3 color)
{
	float3 ambient = ambient_intensity * color;

  return ambient;
}
