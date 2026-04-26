// NOTE: This code was generated on 26-04-2026 (02:17:30 am)

struct Direction_Light_Uniform
{
  float4x4 proj_view;
  float4 direction;
  float4 color;
  float intensity;
  float ambient;
}

struct Spot_Light_Uniform
{
  float4 position;
  float4 direction;
  float4 color;
  float radius;
  float intensity;
  float ambient;
  float inner_cutoff;
  float outer_cutoff;
}

struct Shadow_Point_Light_Uniform
{
  float4x4 proj_views[6];
  float4 position;
  float4 color;
  float radius;
  float intensity;
  float ambient;
}

struct Point_Light_Uniform
{
  float4 position;
  float4 color;
  float radius;
  float intensity;
  float ambient;
}

struct Material_Uniform
{
  uint diffuse;
  uint specular;
  uint emissive;
  uint normal;
  float shininess;
}

struct Draw_Uniform
{
  float4x4 model;
  float4 mul_color;
  uint material_index;
  uint light_index;
}

struct Frame_Uniform
{
  float4x4 projection;
  float4x4 orthographic;
  float4x4 view;
  float4x4 proj_view;
  float4 camera_position;
  float z_near;
  float z_far;
  uint sun_shadow_index;
  uint point_shadow_index;
  uint skybox_index;
  Direction_Light_Uniform sun_light;
  Shadow_Point_Light_Uniform shadow_point_lights[8];
  uint shadow_points_count;
  Point_Light_Uniform point_lights[128];
  uint points_count;
  Spot_Light_Uniform flash_light;
}

struct Mesh_Vertex
{
  float3 position;
  float2 uv;
  float3 normal;
  float4 tangent;
}

struct Immediate_Vertex
{
  float3 position;
  float2 uv;
  float4 color;
}

struct Immediate_Push
{
  float4x4 transform;
  uint texture;
  Immediate_Vertex *vertices;
}

struct Mega_Push
{
  Frame_Uniform *frame_uniform;
  Draw_Uniform *draw_uniforms;
  Mesh_Vertex *vertices;
  Material_Uniform *material_uniforms;
}

struct Skybox_Push
{
  Frame_Uniform *frame_uniform;
}

