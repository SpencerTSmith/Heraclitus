#version 460
#extension GL_EXT_scalar_block_layout : require
#extension GL_ARB_shader_draw_parameters : require
#extension GL_EXT_buffer_reference : require
#extension GL_EXT_buffer_reference2 : require
layout(row_major) uniform;
layout(row_major) buffer;

#line 1 0
struct Immediate_Vertex_0
{
    vec3 position_0;
    vec2 uv_0;
    vec4 color_0;
};


#line 29
layout(buffer_reference, std430, buffer_reference_align = 4) buffer BufferPointer_Immediate_Vertex_0_1
{
    Immediate_Vertex_0 _data;
};

#line 9
struct SLANG_ParameterGroup_Push_0
{
    mat4x4 transform_0;
    uint texture_index_0;
    BufferPointer_Immediate_Vertex_0_1 vertices_0;
};


#line 9
layout(push_constant)
layout(scalar) uniform block_SLANG_ParameterGroup_Push_0
{
    mat4x4 transform_0;
    uint texture_index_0;
    layout(offset = 68) BufferPointer_Immediate_Vertex_0_1 vertices_0;
}Push_0;

#line 13441 1
layout(location = 0)
out vec2 entryPointParam_vert_main_uv_0;


#line 13441
layout(location = 1)
out vec4 entryPointParam_vert_main_color_0;


#line 19 0
struct VSOutput_0
{
    vec2 uv_1;
    vec4 color_1;
    vec4 pos_0;
};


void main()
{
    Immediate_Vertex_0 vertex_0 = (Push_0.vertices_0 + uint(gl_VertexIndex - gl_BaseVertex))._data;

    VSOutput_0 o_0;
    o_0.uv_1 = (Push_0.vertices_0 + uint(gl_VertexIndex - gl_BaseVertex))._data.uv_0;
    o_0.color_1 = vertex_0.color_0;
    o_0.pos_0 = (((vec4(vertex_0.position_0, 1.0)) * (Push_0.transform_0)));
    VSOutput_0 _S2 = o_0;

#line 35
    entryPointParam_vert_main_uv_0 = o_0.uv_1;

#line 35
    entryPointParam_vert_main_color_0 = _S2.color_1;

#line 35
    gl_Position = _S2.pos_0;

#line 35
    return;
}

