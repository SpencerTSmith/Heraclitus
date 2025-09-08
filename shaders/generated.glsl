// NOTE: This code was generated on 08-09-2025 (04:46:30 am)

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

#define FRAME_BINDING 0
#define TEXTURES_BINDING 1

layout(binding = FRAME_BINDING, std140) uniform Frame_Uniform_UBO {
  Frame_Uniform frame;
};

layout(binding = TEXTURES_BINDING, std430) readonly buffer Texture_Handles {
  sampler2D textures[];
};


vec4 bindless_sample(int index, vec2 uv) {
  return texture(textures[index], uv);
}
