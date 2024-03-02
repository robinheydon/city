@vertex
#version 430 core

layout (location = 0) in vec3 position;
layout (location = 1) in vec3 color;
layout (location = 2) in vec3 normal;

uniform mat4 model;
uniform mat4 view;
uniform mat4 projection;
uniform vec3 sun_direction;

out vec3 vtx_color;
out vec3 vtx_pos;

void main ()
{
    gl_Position = projection * view * model * vec4 (position, 1.0);
    float sun_angle = 0.5 + clamp (dot (sun_direction, normal), 0, 1) * 0.5;
    vtx_color = color * sun_angle;
    vtx_pos = position;
}

@fragment
#version 430 core

out vec4 FragColor;
uniform vec3 camera;
uniform float show_contour;
uniform float show_grid;

in vec3 vtx_color;
in vec3 vtx_pos;

void main ()
{
    float dist = distance (camera, vtx_pos);
    float opacity = clamp (dist / 32000, 0, 1);
    float visibility = 1 - opacity;

    vec3 f1 = fract (vtx_pos / 20.0);
    vec3 df1 = fwidth (vtx_pos / 20.0);
    vec3 g1 = smoothstep (-3*df1, 3*df1, f1);

    vec3 f2 = fract (vtx_pos / 100.0);
    vec3 df2 = fwidth (vtx_pos / 100.0);
    vec3 g2 = smoothstep (-4*df2, 4*df2, f2);

    vec3 f3 = fract (vtx_pos / 100.0);
    vec3 df3 = fwidth (vtx_pos / 100.0);
    vec3 g3 = smoothstep (-2*df3, 2*df3, f3);

    vec3 f4 = fract (vtx_pos / 1000.0);
    vec3 df4 = fwidth (vtx_pos / 1000.0);
    vec3 g4 = smoothstep (-5*df4, 5*df4, f4);

    float con = max (1-(show_contour*visibility), g1.z * g1.z * g1.z * g2.z * g2.z);
    float minor_grid = max (1-(show_grid*visibility*visibility), g3.x * g3.y * g3.x * g3.y);
    float major_grid = max (1-(show_grid*visibility), g4.x * g4.y);

    vec4 col = vec4 (vtx_color * con * minor_grid * major_grid, 1);

    FragColor = mix (col, vec4 (0.4, 0.4, 0.4, 1), opacity);
}


