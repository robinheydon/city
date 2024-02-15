@vertex
#version 330 core

layout (location = 0) in vec3 position;
layout (location = 1) in vec3 color;

uniform mat4 model;
uniform mat4 view;
uniform mat4 projection;

out vec4 vtx_color;

void main ()
{
    gl_Position = projection * view * model * vec4 (position, 1.0);
    vtx_color = vec4 (color, 1);
}

@fragment
#version 330 core

out vec4 FragColor;

in vec4 vtx_color;

void main ()
{
    FragColor = vtx_color;
}

