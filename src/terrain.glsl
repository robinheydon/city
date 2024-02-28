@vertex
#version 430 core

layout (location = 0) in vec3 pos;
layout (location = 1) in vec3 color;

uniform mat4 model;
uniform mat4 view;
uniform mat4 projection;

out vec4 vtx_color;
out vec3 vtx_pos;

void main ()
{
    gl_Position = projection * view * model * vec4 (pos, 1.0);
    vtx_color = vec4 (color, 1.0);
    vtx_pos = pos;
}

@fragment
#version 430 core

out vec4 FragColor;
uniform vec3 camera;

in vec4 vtx_color;
in vec3 vtx_pos;

void main ()
{
    float dist = distance (camera, vtx_pos);
    float opacity = clamp (dist / 16000, 0, 1);

    FragColor = mix (vtx_color, vec4 (0.4, 0.4, 0.4, 1), opacity);
}


