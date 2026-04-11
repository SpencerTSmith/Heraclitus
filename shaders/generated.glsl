// NOTE: This code was generated on 11-04-2026 (02:38:14 am)

#extension GL_ARB_bindless_texture : require

struct Direction_Light_Uniform {
  mat4 proj_view;
  vec4 direction;
  vec4 color;
  float intensity;
  float ambient;
};

struct Spot_Light_Uniform {
  vec4 position;
  vec4 direction;
  vec4 color;
  float radius;
  float intensity;
  float ambient;
  float inner_cutoff;
  float outer_cutoff;
};

struct Shadow_Point_Light_Uniform {
  mat4 proj_views[6];
  vec4 position;
  vec4 color;
  float radius;
  float intensity;
  float ambient;
};

struct Point_Light_Uniform {
  vec4 position;
  vec4 color;
  float radius;
  float intensity;
  float ambient;
};

struct Material_Uniform {
  sampler2D diffuse;
  sampler2D specular;
  sampler2D emissive;
  sampler2D normal;
  float shininess;
};

struct Draw_Uniform {
  mat4 model;
  vec4 mul_color;
  int material_index;
  int light_index;
};

struct Frame_Uniform {
  mat4 projection;
  mat4 orthographic;
  mat4 view;
  mat4 proj_view;
  vec4 camera_position;
  float z_near;
  float z_far;
  vec4 scene_extents;
  Shadow_Point_Light_Uniform shadow_point_lights[8];
  int shadow_points_count;
  Point_Light_Uniform point_lights[128];
  int points_count;
  Direction_Light_Uniform sun_light;
  Spot_Light_Uniform flash_light;
};

struct Mesh_Vertex {
  float position[3];
  float uv[2];
  float normal[3];
  float tangent[4];
};

struct Immediate_Vertex {
  float position[3];
  float uv[2];
  float color[4];
};

#define FRAME_BINDING 0
#define MATERIALS_BINDING 1
#define DRAW_UNIFORMS_BINDING 2
#define MESH_VERTICES_BINDING 3
#define IMM_VERTICES_BINDING 4

layout(binding = FRAME_BINDING, std140) uniform Frame_Uniform_UBO {
  Frame_Uniform frame;
};

layout(binding = MATERIALS_BINDING, std430) readonly buffer Mesh_Materials {
  Material_Uniform materials[];
};

layout(binding = DRAW_UNIFORMS_BINDING, std430) readonly buffer Draw_Uniforms {
  Draw_Uniform draw_uniforms[];
};

layout(binding = MESH_VERTICES_BINDING, std430) readonly buffer Mesh_Vertices {
  Mesh_Vertex mesh_vertices[];
};

layout(binding = IMM_VERTICES_BINDING, std430) readonly buffer Immediate_Vertices {
  Immediate_Vertex immediate_vertices[];
};


vec3 mesh_vertex_position(int index)
{
  return vec3(mesh_vertices[index].position[0],
              mesh_vertices[index].position[1],
              mesh_vertices[index].position[2]);
}
vec2 mesh_vertex_uv(int index)
{
  return vec2(mesh_vertices[index].uv[0],
              mesh_vertices[index].uv[1]);
}
vec3 mesh_vertex_normal(int index)
{
  return vec3(mesh_vertices[index].normal[0],
              mesh_vertices[index].normal[1],
              mesh_vertices[index].normal[2]);
}
vec4 mesh_vertex_tangent(int index)
{
  return vec4(mesh_vertices[index].tangent[0],
              mesh_vertices[index].tangent[1],
              mesh_vertices[index].tangent[2],
              mesh_vertices[index].tangent[3]);
}

vec3 immediate_vertex_position(int index)
{
  return vec3(immediate_vertices[index].position[0],
              immediate_vertices[index].position[1],
              immediate_vertices[index].position[2]);
}
vec2 immediate_vertex_uv(int index)
{
  return vec2(immediate_vertices[index].uv[0],
              immediate_vertices[index].uv[1]);
}
vec4 immediate_vertex_color(int index)
{
  return vec4(immediate_vertices[index].color[0],
              immediate_vertices[index].color[1],
              immediate_vertices[index].color[2],
              immediate_vertices[index].color[3]);
}

