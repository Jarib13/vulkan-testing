#version 450

layout(location = 0) out vec3 frag_color;

vec2 positions[3] = vec2[](
    vec2(0.0, 0.5),
    vec2(-0.5, -0.5),
    vec2(0.5, -0.5)
);

void main() {
    gl_Position = vec4(positions[gl_VertexIndex].xy, 0, 1);
    frag_color = positions[gl_VertexIndex].rgg;
}