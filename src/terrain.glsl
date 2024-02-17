@vertex
#version 330 core

layout (location = 0) in vec3 pos;
layout (location = 1) in vec3 color;

uniform mat4 model;
uniform mat4 view;
uniform mat4 projection;

out vec4 vtx_color;

void main ()
{
    float row_index = clamp (mod (gl_VertexID * 1.0, 9), 0.0, 9.0);
    float col_index = floor (gl_VertexID / 9.0);

    vec3 pos = vec3 (
        row_index * 32,
        col_index * 32,
        pos.z
    );
    gl_Position = projection * view * model * vec4 (pos, 1.0);
    vtx_color = vec4 (color, 1.0);
}

@fragment
#version 330 core

out vec4 FragColor;

in vec4 vtx_color;

void main ()
{
    FragColor = vtx_color;
}


