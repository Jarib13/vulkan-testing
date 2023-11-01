#version 450
layout(location = 0) in vec3 position;
layout(location = 1) in vec3 color;

layout(binding = 0) uniform UniformBufferObject{
    mat4 transform;
} ubo;

layout(location = 0) out vec3 frag_color;

void main() {
    gl_Position = ubo.transform * vec4(position, 1);
    frag_color = color;
}