// NOTE: This code was generated on 25-08-2025 (05:20:06 pm)

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

struct Point_Light_Uniform {
  mat4 proj_views[6];
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
  Direction_Light_Uniform sun_light;
  Point_Light_Uniform point_lights[128];
  int points_count;
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
