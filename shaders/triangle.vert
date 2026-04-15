#version 460
#extension GL_EXT_buffer_reference : require
#extension GL_EXT_scalar_block_layout : require
#extension GL_EXT_shader_explicit_arithmetic_types_int64 : require

layout(location = 0) out VS_OUT
{
  vec3 color;
} vs_out;

layout(buffer_reference, scalar) readonly buffer Vertices
{
  vec2 positions[];
};

#push_constant

void main()
{
  Vertices verts = Vertices(push.vertices);
  gl_Position = vec4(verts.positions[gl_VertexIndex], 0.5, 1.0);
  vs_out.color = push.color.xyz;
}
