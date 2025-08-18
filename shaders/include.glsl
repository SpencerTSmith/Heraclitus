#extension GL_ARB_bindless_texture : require

struct Point_Light {
  mat4  proj_views[6];
	vec4  position;

	vec4	color;

  float radius;
	float intensity;
	float ambient;
};

struct Direction_Light {
  mat4  proj_view;
	vec4  direction;

	vec4  color;

	float intensity;
	float ambient;
};

struct Spot_Light {
	vec4  position;
	vec4  direction;

	vec4  color;

  float radius;
	float intensity;
	float ambient;

	// Cosine
	float inner_cutoff;
	float outer_cutoff;
};

#define MAX_POINT_LIGHTS 128
struct Lights {
  	Direction_Light direction;
  	Point_Light     points[MAX_POINT_LIGHTS];
  	int							points_count;
    Spot_Light			spot;
};

#define FRAME_UBO_BINDING 0
layout(binding = FRAME_UBO_BINDING, std140) uniform Frame_UBO {
  mat4  projection;
  mat4  orthographic;
  mat4  view;
  mat4  proj_view;
  vec4  camera_position;
  float z_near;
  float z_far;
  vec4  scene_extents;
  Lights lights;
} frame;

//
// Bindless!
//
#define TEXTURE_HANDLES_BINDING 1
layout(binding = TEXTURE_HANDLES_BINDING, std430) readonly buffer Texture_Handles {
  sampler2D textures[];
};

vec4 bindless_sample(int index, vec2 uv) {
  return texture(textures[index], uv);
}
