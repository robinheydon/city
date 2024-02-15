@vertex
#version 330 core

layout (location = 0) in vec3 position;

void main ()
{
    gl_Position = vec4 (position, 1.0);
}

@fragment
#version 330 core

out vec4 FragColor;

void main ()
{
    FragColor = vec4 (1.0, 0.0, 1.0, 1.0);
}

