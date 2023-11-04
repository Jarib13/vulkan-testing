#version 450

layout(location = 0) in vec3 frag_color;
layout(location = 1) in vec2 frag_texcoord;
layout(binding = 1) uniform sampler2D diffuse_sampler;

layout(location = 0) out vec4 out_color;

void main() {
    float lux = (dot(frag_color, normalize(vec3(-1,2,-1))) + 1) / 2;
    out_color = texture(diffuse_sampler, vec2(frag_texcoord.x, 1-frag_texcoord.y));
}