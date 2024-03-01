@vertex
#version 430 core

layout (location = 0) in vec3 position;
layout (location = 1) in vec3 color;
layout (location = 2) in vec3 normal;

uniform mat4 model;
uniform mat4 view;
uniform mat4 projection;
uniform vec3 sun_direction;

out vec4 vtx_color;
out vec3 vtx_pos;

void main ()
{
    gl_Position = projection * view * model * vec4 (position, 1.0);
    float sun_angle = dot (sun_direction, normal);
    vtx_color = vec4 (color, 1.0) * sun_angle;
    vtx_pos = position;
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


