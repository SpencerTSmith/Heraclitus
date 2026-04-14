#version 460

layout(location = 0) in FS_IN
{
  vec3 color;
} fs_in;

layout(location = 0) out vec4 out_color;

#push_constant

void main() {
    out_color = vec4(fs_in.color, 1.0) * push.color;
}
