const std = @import("std");

const vectors = @import("vectors.zig");

const vec2 = vectors.vec2;
const ivec2 = vectors.ivec2;
const iivec2 = vectors.iivec2;

const vec3 = vectors.vec3;
const ivec3 = vectors.ivec3;
const iivec3 = vectors.iivec3;

const vec4 = vectors.vec4;
const ivec4 = vectors.ivec4;
const iivec4 = vectors.iivec4;

const mat4 = vectors.mat4;

const c = @cImport({
    @cDefine("GLFW_INCLUDE_VULKAN", {});
    @cInclude("GLFW/glfw3.h");
});

var alloc: std.mem.Allocator = undefined;

var window: ?*c.GLFWwindow = undefined;

var physical_device: c.VkPhysicalDevice = null;
var device: c.VkDevice = undefined;

var surface: c.VkSurfaceKHR = undefined;
var surface_capabilities: c.VkSurfaceCapabilitiesKHR = undefined;
var surface_format: c.VkSurfaceFormatKHR = undefined;
var surface_present_mode: u32 = undefined;

var swapchain: c.VkSwapchainKHR = undefined;
var swapchain_images: []c.VkImage = undefined;
var swapchain_framebuffers: []c.VkFramebuffer = undefined;
var swapchain_extent: c.VkExtent2D = undefined;
var swapchain_image_views: []c.VkImageView = undefined;

var viewport: c.VkViewport = undefined;
var scissor: c.VkRect2D = undefined;

var render_pass: c.VkRenderPass = undefined;

const max_frames_in_flight: u32 = 4;
var render_finished_semaphores: []c.VkSemaphore = undefined;
var image_available_semaphores: []c.VkSemaphore = undefined;
var rendering_fences: []c.VkFence = undefined;

fn name_eql(a: [256]u8, b: []const u8) bool {
    var i: usize = 0;
    while (true) : (i += 1) {
        if (i == b.len) {
            return a[i] == 0;
        }

        if (a[i] != b[i]) {
            return false;
        }
    }
    return false;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    alloc = gpa.allocator();

    var err = c.glfwInit();
    c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_NO_API);
    window = c.glfwCreateWindow(800, 600, "cool", null, null);
    _ = c.glfwSetFramebufferSizeCallback(window, on_window_resize);

    // var extension_count: u32 = 0;
    // _ = c.vkEnumerateInstanceExtensionProperties(null, &extension_count, null);
    // std.debug.print("Vulkan extensions supported: {}\n", .{extension_count});

    var app_info = c.VkApplicationInfo{
        .sType = c.VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pApplicationName = "Vulkan Test",
        .applicationVersion = c.VK_MAKE_VERSION(0, 1, 0),
        .pEngineName = "dogmitus",
        .engineVersion = c.VK_MAKE_VERSION(1, 0, 0),
        .apiVersion = c.VK_API_VERSION_1_0,
    };

    var create_info = c.VkInstanceCreateInfo{};
    create_info.sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    create_info.pApplicationInfo = &app_info;

    var glfw_ext_count: u32 = 0;
    var glfw_exts = c.glfwGetRequiredInstanceExtensions(&glfw_ext_count);

    create_info.enabledExtensionCount = glfw_ext_count;
    create_info.ppEnabledExtensionNames = glfw_exts;
    create_info.enabledLayerCount = 0;

    //validation layers

    var layer_count: u32 = undefined;
    var available_layers: [64]c.VkLayerProperties = undefined;
    const validation_layers: [1][]const u8 = [1][]const u8{
        "VK_LAYER_KHRONOS_validation",
    };

    _ = c.vkEnumerateInstanceLayerProperties(&layer_count, &available_layers);

    var layers_missing: usize = 0;
    for (validation_layers) |validation_layer| {
        var layer_found = false;
        for (available_layers) |available_layer| {
            if (name_eql(available_layer.layerName, validation_layer)) {
                layer_found = true;
                break;
            }
        }

        if (!layer_found) {
            layers_missing += 1;
        }
    }

    if (layers_missing > 0) {
        std.debug.print("{} validation layers not available.\n", .{layers_missing});
        return;
    }

    //create

    create_info.enabledLayerCount = validation_layers.len;
    create_info.ppEnabledLayerNames = @ptrCast(&validation_layers);

    var instance: c.VkInstance = undefined;
    var result = c.vkCreateInstance(&create_info, null, &instance);

    if (result != c.VK_SUCCESS) {
        std.debug.print("Instance create failed", .{});
        return;
    }

    //surface

    err = c.glfwCreateWindowSurface(instance, window, null, &surface);

    //physical device
    var physical_device_count: u32 = 0;

    err = c.vkEnumeratePhysicalDevices(instance, &physical_device_count, null);
    if (err != c.VK_SUCCESS) {
        std.debug.print("Failed to enumerate physical devices: Error: {}", .{err});
    }

    var physical_devices: [*c]c.VkPhysicalDevice = @ptrCast(try alloc.alloc(c.VkPhysicalDevice, physical_device_count));

    err = c.vkEnumeratePhysicalDevices(instance, &physical_device_count, physical_devices);
    if (err != c.VK_SUCCESS) {
        std.debug.print("Failed to enumerate physical devices (array step): Error: {}", .{err});
    }

    if (physical_device_count == 0) {
        std.debug.print("Can't find any physical devices\n", .{});
        return;
    }

    for (0..physical_device_count) |i| {
        var properties: c.VkPhysicalDeviceProperties = undefined;
        c.vkGetPhysicalDeviceProperties(physical_devices[i], &properties);
        std.debug.print("dogmitus: {s}\n", .{properties.deviceName});
        physical_device = physical_devices[i];
    }

    var queue_family_count: u32 = 0;
    c.vkGetPhysicalDeviceQueueFamilyProperties(physical_device, &queue_family_count, null);
    var queue_families: [*c]c.VkQueueFamilyProperties = @ptrCast(try alloc.alloc(c.VkQueueFamilyProperties, queue_family_count));
    c.vkGetPhysicalDeviceQueueFamilyProperties(physical_device, &queue_family_count, queue_families);
    std.debug.print("{} queue families on device 0\n", .{queue_family_count});

    var graphics_queue_family: ?u32 = null;
    var surface_queue_family: ?u32 = null;

    for (0..queue_family_count) |index| {
        var i: u32 = @intCast(index);
        if ((queue_families[i].queueFlags & c.VK_QUEUE_GRAPHICS_BIT) > 0) {
            graphics_queue_family = i;
            std.debug.print("graphics bit on queue[{}]\n", .{i});
        }

        if ((queue_families[i].queueFlags & c.VK_QUEUE_COMPUTE_BIT) > 0) {
            std.debug.print("compute bit on queue[{}]\n", .{i});
        }

        if ((queue_families[i].queueFlags & c.VK_QUEUE_TRANSFER_BIT) > 0) {
            std.debug.print("transfer bit on queue[{}]\n", .{i});
        }

        if ((queue_families[i].queueFlags & c.VK_QUEUE_OPTICAL_FLOW_BIT_NV) > 0) {
            std.debug.print("nv bit on queue[{}]\n", .{i});
        }

        var surface_support: u32 = 0;
        _ = c.vkGetPhysicalDeviceSurfaceSupportKHR(physical_device, i, surface, &surface_support);

        if (surface_support > 0) {
            surface_queue_family = i;
        }
    }

    var device_extensions_required = [_][]const u8{
        c.VK_KHR_SWAPCHAIN_EXTENSION_NAME,
    };

    var extension_count: u32 = 0;
    _ = c.vkEnumerateDeviceExtensionProperties(physical_device, null, &extension_count, null);
    var extensions: [*c]c.VkExtensionProperties = @ptrCast(try alloc.alloc(c.VkExtensionProperties, extension_count));
    _ = c.vkEnumerateDeviceExtensionProperties(physical_device, null, &extension_count, extensions);

    for (device_extensions_required) |required_device_extension_name| {
        var available = false;
        for (0..extension_count) |i| {
            if (name_eql(extensions[i].extensionName, required_device_extension_name)) {
                available = true;
            }
        }

        if (!available) {
            std.debug.print("Missing required extension: {s}\n", .{required_device_extension_name});
            unreachable;
        }
    }

    if (graphics_queue_family == null or surface_queue_family == null) {
        std.debug.print("no queue familiy with graphics support\n", .{});
        return;
    }

    if (graphics_queue_family.? != surface_queue_family.?) {
        std.debug.print("graphics and surface are not in the same queue family (fix!)\n", .{});
        return;
    }

    //verify swap chain

    var surface_formats: [*c]c.VkSurfaceFormatKHR = undefined;
    var surface_present_modes: [*c]c.VkPresentModeKHR = undefined;
    var surface_format_count: u32 = 0;
    var surface_present_mode_count: u32 = 0;

    _ = c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(physical_device, surface, &surface_capabilities);

    _ = c.vkGetPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, &surface_format_count, null);
    _ = c.vkGetPhysicalDeviceSurfacePresentModesKHR(physical_device, surface, &surface_present_mode_count, null);

    surface_formats = @ptrCast(try alloc.alloc(c.VkSurfaceFormatKHR, surface_format_count));
    surface_present_modes = @ptrCast(try alloc.alloc(c.VkPresentModeKHR, surface_present_mode_count));

    _ = c.vkGetPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, &surface_format_count, surface_formats);
    _ = c.vkGetPhysicalDeviceSurfacePresentModesKHR(physical_device, surface, &surface_present_mode_count, surface_present_modes);

    if (surface_format_count == 0) {
        std.debug.print("No avilable surface formats", .{});
        return;
    }

    if (surface_present_mode_count == 0) {
        std.debug.print("No avilable surface present modes", .{});
        return;
    }

    surface_format = surface_formats[0];
    for (0..surface_format_count) |i| {
        var format: c.VkSurfaceFormatKHR = surface_formats[i];
        if (format.format == c.VK_FORMAT_B8G8R8A8_SRGB and format.colorSpace == c.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) {
            surface_format = format;
        }
    }

    surface_present_mode = c.VK_PRESENT_MODE_FIFO_KHR;
    for (surface_present_modes[0..surface_present_mode_count]) |present_mode| {
        if (present_mode == c.VK_PRESENT_MODE_MAILBOX_KHR) {
            surface_present_mode = present_mode;
        }
    }

    //logical device

    var device_queue_create_info = std.mem.zeroes(c.VkDeviceQueueCreateInfo);
    device_queue_create_info.sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
    device_queue_create_info.queueFamilyIndex = graphics_queue_family.?;
    device_queue_create_info.queueCount = 1;
    var queue_priority: f32 = 1.0;
    device_queue_create_info.pQueuePriorities = &queue_priority;

    var physical_device_features_enabled = std.mem.zeroes(c.VkPhysicalDeviceFeatures);

    var device_create_info = std.mem.zeroes(c.VkDeviceCreateInfo);
    device_create_info.sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
    device_create_info.pQueueCreateInfos = &device_queue_create_info;
    device_create_info.queueCreateInfoCount = 1;
    device_create_info.pEnabledFeatures = &physical_device_features_enabled;

    //logical device extensions
    device_create_info.enabledExtensionCount = device_extensions_required.len;
    device_create_info.ppEnabledExtensionNames = @ptrCast(&device_extensions_required);

    //logical device validation layers
    device_create_info.enabledLayerCount = validation_layers.len;
    device_create_info.ppEnabledLayerNames = @ptrCast(&validation_layers);

    err = c.vkCreateDevice(physical_device, &device_create_info, null, &device);

    var graphics_queue: c.VkQueue = undefined;
    c.vkGetDeviceQueue(device, graphics_queue_family.?, 0, &graphics_queue);
    var surface_queue: c.VkQueue = undefined;
    c.vkGetDeviceQueue(device, surface_queue_family.?, 0, &surface_queue);

    // create swap chain
    try create_swapchain();

    //pipeline

    var fragment_shader_bytecode = @embedFile("bytecode/frag.spv");
    var vertex_shader_bytecode = @embedFile("bytecode/vert.spv");

    var fragment_shader_module = try create_shader_module(fragment_shader_bytecode);
    var vertex_shader_module = try create_shader_module(vertex_shader_bytecode);

    var vertex_shader_stage_info = std.mem.zeroes(c.VkPipelineShaderStageCreateInfo);
    vertex_shader_stage_info.sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    vertex_shader_stage_info.stage = c.VK_SHADER_STAGE_VERTEX_BIT;
    vertex_shader_stage_info.module = vertex_shader_module;
    vertex_shader_stage_info.pName = "main";

    var fragment_shader_stage_info = std.mem.zeroes(c.VkPipelineShaderStageCreateInfo);
    fragment_shader_stage_info.sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    fragment_shader_stage_info.stage = c.VK_SHADER_STAGE_FRAGMENT_BIT;
    fragment_shader_stage_info.module = fragment_shader_module;
    fragment_shader_stage_info.pName = "main";

    //dynamic states

    var dynamic_states = [_]c.VkDynamicState{
        c.VK_DYNAMIC_STATE_VIEWPORT,
        c.VK_DYNAMIC_STATE_SCISSOR,
    };

    var dynamic_state_create_info = std.mem.zeroes(c.VkPipelineDynamicStateCreateInfo);
    dynamic_state_create_info.sType = c.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO;
    dynamic_state_create_info.dynamicStateCount = dynamic_states.len;
    dynamic_state_create_info.pDynamicStates = &dynamic_states;

    //vertex input

    var vertex_position_binding_description = c.VkVertexInputBindingDescription{
        .binding = 0,
        .stride = @sizeOf(vec2),
        .inputRate = c.VK_VERTEX_INPUT_RATE_VERTEX,
    };
    var vertex_position_attribute_description = c.VkVertexInputAttributeDescription{
        .binding = 0,
        .format = c.VK_FORMAT_R32G32_SFLOAT,
        .location = 0,
        .offset = 0,
    };
    var vertex_color_binding_description = c.VkVertexInputBindingDescription{
        .binding = 1,
        .stride = @sizeOf(vec3),
        .inputRate = c.VK_VERTEX_INPUT_RATE_VERTEX,
    };
    var vertex_color_attribute_description = c.VkVertexInputAttributeDescription{
        .binding = 1,
        .format = c.VK_FORMAT_R32G32B32_SFLOAT,
        .location = 1,
        .offset = 0,
    };

    var vertex_binding_descriptions = [_]c.VkVertexInputBindingDescription{
        vertex_position_binding_description,
        vertex_color_binding_description,
    };

    var vertex_attribute_descriptions = [_]c.VkVertexInputAttributeDescription{
        vertex_position_attribute_description,
        vertex_color_attribute_description,
    };

    var vertex_input_state_create_info = std.mem.zeroes(c.VkPipelineVertexInputStateCreateInfo);
    vertex_input_state_create_info.sType = c.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO;
    vertex_input_state_create_info.vertexBindingDescriptionCount = vertex_binding_descriptions.len;
    vertex_input_state_create_info.pVertexBindingDescriptions = &vertex_binding_descriptions;
    vertex_input_state_create_info.vertexAttributeDescriptionCount = vertex_attribute_descriptions.len;
    vertex_input_state_create_info.pVertexAttributeDescriptions = &vertex_attribute_descriptions;

    var input_assembly_state_create_info = std.mem.zeroes(c.VkPipelineInputAssemblyStateCreateInfo);
    input_assembly_state_create_info.sType = c.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO;
    input_assembly_state_create_info.topology = c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
    input_assembly_state_create_info.primitiveRestartEnable = c.VK_FALSE;

    var viewport_state_create_info = std.mem.zeroes(c.VkPipelineViewportStateCreateInfo);
    viewport_state_create_info.sType = c.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO;
    viewport_state_create_info.viewportCount = 1;
    viewport_state_create_info.scissorCount = 1;

    var rasterization_state_create_info = std.mem.zeroes(c.VkPipelineRasterizationStateCreateInfo);
    rasterization_state_create_info.sType = c.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO;
    rasterization_state_create_info.depthClampEnable = c.VK_FALSE;
    rasterization_state_create_info.rasterizerDiscardEnable = c.VK_FALSE;
    rasterization_state_create_info.polygonMode = c.VK_POLYGON_MODE_POINT;
    rasterization_state_create_info.lineWidth = 1;
    rasterization_state_create_info.cullMode = c.VK_CULL_MODE_BACK_BIT;
    rasterization_state_create_info.frontFace = c.VK_FRONT_FACE_CLOCKWISE;
    rasterization_state_create_info.depthBiasEnable = c.VK_FALSE;
    rasterization_state_create_info.depthBiasClamp = 0;
    rasterization_state_create_info.depthBiasConstantFactor = 0;
    rasterization_state_create_info.depthBiasSlopeFactor = 0;

    var multisample_state_create_info = std.mem.zeroes(c.VkPipelineMultisampleStateCreateInfo);
    multisample_state_create_info.sType = c.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO;
    multisample_state_create_info.sampleShadingEnable = c.VK_FALSE;
    multisample_state_create_info.rasterizationSamples = c.VK_SAMPLE_COUNT_1_BIT;
    multisample_state_create_info.minSampleShading = 1;
    multisample_state_create_info.pSampleMask = null;
    multisample_state_create_info.alphaToCoverageEnable = c.VK_FALSE;
    multisample_state_create_info.alphaToOneEnable = c.VK_FALSE;

    var color_blend_attachment_state = std.mem.zeroes(c.VkPipelineColorBlendAttachmentState);
    color_blend_attachment_state.colorWriteMask = c.VK_COLOR_COMPONENT_R_BIT | c.VK_COLOR_COMPONENT_B_BIT | c.VK_COLOR_COMPONENT_G_BIT | c.VK_COLOR_COMPONENT_A_BIT;
    color_blend_attachment_state.blendEnable = c.VK_FALSE;
    color_blend_attachment_state.srcColorBlendFactor = c.VK_BLEND_FACTOR_ONE;
    color_blend_attachment_state.srcAlphaBlendFactor = c.VK_BLEND_FACTOR_ZERO;
    color_blend_attachment_state.colorBlendOp = c.VK_BLEND_OP_ADD;
    color_blend_attachment_state.srcAlphaBlendFactor = c.VK_BLEND_FACTOR_ONE;
    color_blend_attachment_state.dstAlphaBlendFactor = c.VK_BLEND_FACTOR_ZERO;
    color_blend_attachment_state.alphaBlendOp = c.VK_BLEND_OP_ADD;

    var color_blend_state_create_info = std.mem.zeroes(c.VkPipelineColorBlendStateCreateInfo);
    color_blend_state_create_info.sType = c.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO;
    color_blend_state_create_info.logicOpEnable = c.VK_FALSE;
    color_blend_state_create_info.logicOp = c.VK_LOGIC_OP_COPY;
    color_blend_state_create_info.attachmentCount = 1;
    color_blend_state_create_info.pAttachments = &color_blend_attachment_state;
    color_blend_state_create_info.blendConstants[0] = 0;
    color_blend_state_create_info.blendConstants[1] = 0;
    color_blend_state_create_info.blendConstants[2] = 0;
    color_blend_state_create_info.blendConstants[3] = 0;

    var pipeline_layout: c.VkPipelineLayout = undefined;

    var pipeline_layout_create_info = c.VkPipelineLayoutCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .setLayoutCount = 0,
        .pSetLayouts = null,
        .pushConstantRangeCount = 0,
        .pPushConstantRanges = 0,
    };
    //no zeroes

    err = c.vkCreatePipelineLayout(device, &pipeline_layout_create_info, null, &pipeline_layout);
    if (err != c.VK_SUCCESS) {
        std.debug.print("Failed to create pipeline layout. error code: {}", .{err});
    }

    var color_attachment_description = c.VkAttachmentDescription{
        .format = surface_format.format,
        .samples = c.VK_SAMPLE_COUNT_1_BIT,
        .loadOp = c.VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = c.VK_ATTACHMENT_STORE_OP_STORE,
        .stencilLoadOp = c.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
        .stencilStoreOp = c.VK_ATTACHMENT_STORE_OP_DONT_CARE,
        .initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
        .finalLayout = c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
    };
    //no zeroes

    var color_attachment_reference = c.VkAttachmentReference{
        .attachment = 0,
        .layout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
    };

    var subpass_description = c.VkSubpassDescription{
        .pipelineBindPoint = c.VK_PIPELINE_BIND_POINT_GRAPHICS,
        .colorAttachmentCount = 1,
        .pColorAttachments = &color_attachment_reference,
    };

    var subpass_dependency = c.VkSubpassDependency{
        .srcSubpass = c.VK_SUBPASS_EXTERNAL,
        .dstSubpass = 0,
        .srcStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        .srcAccessMask = 0,
        .dstStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        .dstAccessMask = c.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
    };

    var render_pass_create_info = c.VkRenderPassCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
        .attachmentCount = 1,
        .pAttachments = &color_attachment_description,
        .subpassCount = 1,
        .pSubpasses = &subpass_description,
        .dependencyCount = 1,
        .pDependencies = &subpass_dependency,
    };

    err = c.vkCreateRenderPass(device, &render_pass_create_info, null, &render_pass);

    try create_framebuffers();

    if (err != c.VK_SUCCESS) {
        std.debug.print("Failed to create render pass. error code: {}", .{err});
    }

    var shader_stages = [_]c.VkPipelineShaderStageCreateInfo{ vertex_shader_stage_info, fragment_shader_stage_info };

    var pipeline_create_info = c.VkGraphicsPipelineCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
        .stageCount = 2,
        .pStages = @ptrCast(&shader_stages),
        .pVertexInputState = &vertex_input_state_create_info,
        .pInputAssemblyState = &input_assembly_state_create_info,
        .pViewportState = &viewport_state_create_info,
        .pRasterizationState = &rasterization_state_create_info,
        .pMultisampleState = &multisample_state_create_info,
        .pDepthStencilState = null,
        .pColorBlendState = &color_blend_state_create_info,
        .pDynamicState = &dynamic_state_create_info,
        .layout = pipeline_layout,
        .renderPass = render_pass,
        .subpass = 0,
        .basePipelineHandle = null,
        .basePipelineIndex = -1,
    };

    var graphics_pipeline: c.VkPipeline = undefined;
    err = c.vkCreateGraphicsPipelines(device, null, 1, &pipeline_create_info, null, &graphics_pipeline);

    if (err != c.VK_SUCCESS) {
        std.debug.print("Failed to create graphics pipeline. error code: {}", .{err});
    }

    var command_pool: c.VkCommandPool = undefined;
    var command_pool_create_info = c.VkCommandPoolCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .flags = c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
        .queueFamilyIndex = graphics_queue_family.?,
    };

    err = c.vkCreateCommandPool(device, &command_pool_create_info, null, &command_pool);

    if (err != c.VK_SUCCESS) {
        std.debug.print("Failed to create command pool. error code: {}", .{err});
    }

    var command_buffers: []c.VkCommandBuffer = try alloc.alloc(c.VkCommandBuffer, max_frames_in_flight);
    var command_buffer_allocate_info = c.VkCommandBufferAllocateInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = command_pool,
        .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = 1,
    };

    for (0..max_frames_in_flight) |i| {
        err = c.vkAllocateCommandBuffers(device, &command_buffer_allocate_info, &command_buffers[i]);

        if (err != c.VK_SUCCESS) {
            std.debug.print("Failed to allocate command buffer. error code: {}", .{err});
        }
    }

    var semaphore_create_info = c.VkSemaphoreCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
    };

    var fence_create_info = c.VkFenceCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
        .flags = c.VK_FENCE_CREATE_SIGNALED_BIT,
    };

    render_finished_semaphores = try alloc.alloc(c.VkSemaphore, max_frames_in_flight);
    image_available_semaphores = try alloc.alloc(c.VkSemaphore, max_frames_in_flight);
    rendering_fences = try alloc.alloc(c.VkFence, max_frames_in_flight);

    for (0..max_frames_in_flight) |i| {
        err |= c.vkCreateSemaphore(device, &semaphore_create_info, null, &render_finished_semaphores[i]);
        err |= c.vkCreateSemaphore(device, &semaphore_create_info, null, &image_available_semaphores[i]);
        err |= c.vkCreateFence(device, &fence_create_info, null, &rendering_fences[i]);

        if (err != c.VK_SUCCESS) {
            std.debug.print("Error when making semaphores.", .{});
        }
    }

    // var vertex_data = [_]vec2{
    //     .{ .x = 0, .y = -0.5 },
    //     .{ .x = 0.5, .y = 0.5 },
    //     .{ .x = -0.5, .y = 0.5 },
    //     .{ .x = 0, .y = 0.5 },
    //     .{ .x = -0.5, .y = -0.5 },
    //     .{ .x = 0.5, .y = -0.5 },
    // };
    var object = try Obj.load(alloc);

    var matrix = mat4.rotationY(0.0).multiply(mat4.rotationX(0)).multiply(mat4.rotationZ(0));
    _ = matrix;
    var model = &object.models.items[0];
    var vertex_data_len = model.position_indices.items.len;
    var vertex_data: []vec3 = try alloc.alloc(vec3, vertex_data_len);
    for (model.position_indices.items, 0..) |index, i| {
        vertex_data[i] = object.positions.items[index].muls(40); //.multiply_m4(matrix);
    }
    // if (index >= object.positions.items.len) {
    //     std.debug.print("index {} > len {}", .{ index, object.positions.items.len });
    // } else {
    // }

    var vertex_colors_len = model.normal_indices.items.len;
    var vertex_colors: []vec3 = try alloc.alloc(vec3, vertex_colors_len);
    for (model.normal_indices.items, 0..) |index, i| {
        vertex_colors[i] = object.normals.items[index];
    }

    // var vertex_colors = [_]vec3{
    //     .{ .x = 1, .y = 0, .z = 1 },
    //     .{ .x = 1, .y = 0.1, .z = 0.8 },
    //     .{ .x = 0.8, .y = 0.1, .z = 1 },
    //     .{ .x = 0, .y = 1, .z = 1 },
    //     .{ .x = 0.1, .y = 0.8, .z = 1 },
    //     .{ .x = 0.1, .y = 1, .z = 0.8 },
    // };

    var positions = try create_vertex_buffer(@sizeOf(vec3) * vertex_data.len, graphics_queue_family.?);
    var vertex_buffer = positions.buffer;
    var vertex_buffer_memory = positions.memory;

    var colors = try create_vertex_buffer(@sizeOf(vec3) * vertex_colors.len, graphics_queue_family.?);
    var vertex_color_buffer = colors.buffer;
    var vertex_color_buffer_memory = colors.memory;

    var data: [*c]vec3 = undefined;
    var data_vec3: [*c]vec3 = undefined;

    err = c.vkBindBufferMemory(device, vertex_buffer, vertex_buffer_memory, 0);

    if (err != c.VK_SUCCESS) {
        std.debug.panic("bind buffer memory error: {}", .{err});
    }

    err = c.vkMapMemory(device, vertex_buffer_memory, 0, @sizeOf(vec3) * vertex_data_len, 0, @alignCast(@ptrCast(&data)));

    if (err != c.VK_SUCCESS) {
        std.debug.panic("vulkan map memory error: {}", .{err});
    }

    // @memcpy(data[0..vertex_data_len], vertex_data[0..vertex_data_len]);
    for (0..vertex_data_len) |i| {
        data[i] = vertex_data[i];
    }

    c.vkUnmapMemory(device, vertex_buffer_memory);

    //colors

    err = c.vkBindBufferMemory(device, vertex_color_buffer, vertex_color_buffer_memory, 0);

    if (err != c.VK_SUCCESS) {
        std.debug.panic("bind buffer memory error: {}", .{err});
    }

    err = c.vkMapMemory(device, vertex_color_buffer_memory, 0, @sizeOf(vec3) * vertex_colors.len, 0, @alignCast(@ptrCast(&data_vec3)));
    if (err != c.VK_SUCCESS) {
        std.debug.panic("vulkan map memory error: {}", .{err});
    }
    @memcpy(data_vec3[0..vertex_colors.len], vertex_colors[0..vertex_colors.len]);
    c.vkUnmapMemory(device, vertex_color_buffer_memory);
    var command_buffer_image_index: u32 = 0;

    var last_fps: usize = 0;
    var last_fps_time: f64 = 0;
    var fps_counter: usize = 0;

    var current_frame: u32 = 0;

    while (c.glfwWindowShouldClose(window) == 0) {
        c.glfwPollEvents();
        //c.glfwSwapBuffers(window);

        if (c.glfwGetTime() - last_fps_time > 1) {
            last_fps = fps_counter;
            fps_counter = 0;
            last_fps_time = c.glfwGetTime();
            std.debug.print("FPS: {}\n", .{last_fps});
        }

        var f = current_frame % max_frames_in_flight;
        current_frame += 1;
        _ = c.vkWaitForFences(device, 1, &rendering_fences[f], c.VK_TRUE, c.UINT64_MAX);

        var acquire_err = c.vkAcquireNextImageKHR(device, swapchain, c.UINT64_MAX, image_available_semaphores[f], null, &command_buffer_image_index);
        _ = c.vkResetCommandBuffer(command_buffers[f], 0);

        if (acquire_err == c.VK_ERROR_OUT_OF_DATE_KHR or acquire_err == c.VK_SUBOPTIMAL_KHR) {
            c.vkDestroySemaphore(device, image_available_semaphores[f], null);
            _ = c.vkCreateSemaphore(device, &semaphore_create_info, null, &image_available_semaphores[f]);
            try recreate_swapchain();
            continue;
        } else if (acquire_err != c.VK_SUCCESS) {
            std.debug.print("acquire error: {}\n", .{acquire_err});
        }

        _ = c.vkResetFences(device, 1, &rendering_fences[f]);

        var command_buffer_begin_info = c.VkCommandBufferBeginInfo{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
            .flags = 0,
            .pInheritanceInfo = null,
        };

        err = c.vkBeginCommandBuffer(command_buffers[f], &command_buffer_begin_info);
        if (err != c.VK_SUCCESS) {
            std.debug.print("Failed to begin recording command buffer. error code: {}", .{err});
        }

        var clear_color = c.VkClearValue{
            .color = c.VkClearColorValue{
                .float32 = [4]f32{ 0, 0, 1, 1 },
            },
        };
        var render_pass_begin_info = c.VkRenderPassBeginInfo{
            .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
            .renderPass = render_pass,
            .framebuffer = swapchain_framebuffers[command_buffer_image_index],
            .renderArea = c.VkRect2D{
                .offset = .{ .x = 0, .y = 0 },
                .extent = swapchain_extent,
            },
            .clearValueCount = 1,
            .pClearValues = &clear_color,
        };
        c.vkCmdBeginRenderPass(command_buffers[f], &render_pass_begin_info, c.VK_SUBPASS_CONTENTS_INLINE);

        c.vkCmdBindPipeline(command_buffers[f], c.VK_PIPELINE_BIND_POINT_GRAPHICS, graphics_pipeline);

        c.vkCmdSetViewport(
            command_buffers[f],
            0,
            1,
            &viewport,
        );
        c.vkCmdSetScissor(
            command_buffers[f],
            0,
            1,
            &scissor,
        );

        var buffers = [_]c.VkBuffer{
            vertex_buffer,
            vertex_color_buffer,
        };

        var buffer_offsets = [_]u64{
            0,
            0,
        };
        c.vkCmdBindVertexBuffers(
            command_buffers[f],
            0,
            2,
            &buffers,
            @ptrCast(&buffer_offsets),
        );

        c.vkCmdDraw(
            command_buffers[f],
            @intCast(vertex_data.len),
            1,
            0,
            0,
        );

        c.vkCmdEndRenderPass(command_buffers[f]);
        err = c.vkEndCommandBuffer(command_buffers[f]);

        if (err != c.VK_SUCCESS) {
            std.debug.print("Error on command buffer end. Error code: {}", .{err});
        }

        var submit_info = c.VkSubmitInfo{
            .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
            .waitSemaphoreCount = 1,
            .pWaitSemaphores = &image_available_semaphores[f],
            .pWaitDstStageMask = &[_]c.VkPipelineStageFlags{c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT},
            .commandBufferCount = 1,
            .pCommandBuffers = &command_buffers[f],
            .signalSemaphoreCount = 1,
            .pSignalSemaphores = &render_finished_semaphores[f],
        };

        err = c.vkQueueSubmit(graphics_queue, 1, &submit_info, rendering_fences[f]);

        if (err != c.VK_SUCCESS) {
            std.debug.print("failed to submit queue. error code: {} ", .{err});
        }

        var present_info = c.VkPresentInfoKHR{
            .sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
            .waitSemaphoreCount = 1,
            .pWaitSemaphores = &render_finished_semaphores[f],
            .swapchainCount = 1,
            .pSwapchains = &swapchain,
            .pImageIndices = &command_buffer_image_index,
            .pResults = null,
        };

        var present_err = c.vkQueuePresentKHR(surface_queue, &present_info);
        if (present_err == c.VK_ERROR_OUT_OF_DATE_KHR) {
            try recreate_swapchain();
            continue;
        } else if (present_err != c.VK_SUCCESS) {
            std.debug.print("present_error: {}", .{present_err});
        }

        fps_counter += 1;
    }

    // cleanup

    clean_sync();

    _ = c.vkDeviceWaitIdle(device);

    clean_framebuffers();

    c.vkDestroyCommandPool(device, command_pool, null);

    c.vkDestroyRenderPass(device, render_pass, null);
    c.vkDestroyPipeline(device, graphics_pipeline, null);
    c.vkDestroyPipelineLayout(device, pipeline_layout, null);

    c.vkDestroyShaderModule(device, vertex_shader_module, null);
    c.vkDestroyShaderModule(device, fragment_shader_module, null);

    clean_swapchain();

    c.vkDestroyDevice(device, null);
    c.vkDestroySurfaceKHR(instance, surface, null);
    c.vkDestroyInstance(instance, null);
    c.glfwDestroyWindow(window);
    c.glfwTerminate();
}

fn create_vertex_buffer(size: u64, graphics_queue_family: u32) !struct { buffer: c.VkBuffer, memory: c.VkDeviceMemory } {
    var vertex_buffer: c.VkBuffer = undefined;

    var create_info = c.VkBufferCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .pQueueFamilyIndices = @ptrCast(&graphics_queue_family),
        .queueFamilyIndexCount = 1,
        .sharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
        .size = size,
        .usage = c.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
    };

    _ = c.vkCreateBuffer(device, &create_info, null, &vertex_buffer);
    var memory_requirements: c.VkMemoryRequirements = undefined;
    c.vkGetBufferMemoryRequirements(device, vertex_buffer, &memory_requirements);

    var memory_properties: c.VkPhysicalDeviceMemoryProperties = undefined;
    c.vkGetPhysicalDeviceMemoryProperties(physical_device, &memory_properties);

    var preferred_memory_type_index: ?u32 = null;
    var property_flags: u32 = c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT;
    std.debug.print("memoryTypeBits={b}\n", .{memory_requirements.memoryTypeBits});
    for (0..memory_properties.memoryTypeCount) |i| {
        var bit = (@as(u32, 1) << @as(u5, @intCast(i)));
        std.debug.print("{}={b}, ", .{ i, bit });
        if (memory_requirements.memoryTypeBits & bit > 0) {
            if (memory_properties.memoryTypes[i].propertyFlags & property_flags == property_flags) {
                preferred_memory_type_index = @intCast(i);
            }
        }
    }

    if (preferred_memory_type_index == null) {
        std.debug.panic("Couldn't find memory index with the desired properties", .{});
    }

    var alloc_info = c.VkMemoryAllocateInfo{
        .sType = c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .allocationSize = memory_requirements.size,
        .memoryTypeIndex = preferred_memory_type_index.?,
    };

    var vertex_buffer_memory: c.VkDeviceMemory = undefined;
    var err = c.vkAllocateMemory(device, &alloc_info, null, &vertex_buffer_memory);
    if (err != c.VK_SUCCESS) {
        std.debug.panic("vulkan allocate memory error: {}", .{err});
    }

    return .{
        .buffer = vertex_buffer,
        .memory = vertex_buffer_memory,
    };
}

fn clean_framebuffers() void {
    for (swapchain_framebuffers) |framebuffer| {
        c.vkDestroyFramebuffer(device, framebuffer, null);
    }
    alloc.free(swapchain_framebuffers);
}

fn clean_swapchain() void {
    for (swapchain_image_views) |swapchain_image_view| {
        c.vkDestroyImageView(device, swapchain_image_view, null);
    }
    alloc.free(swapchain_image_views);
    c.vkDestroySwapchainKHR(device, swapchain, null);
}

fn clean_sync() void {
    for (0..max_frames_in_flight) |i| {
        c.vkDestroySemaphore(device, render_finished_semaphores[i], null);
        c.vkDestroySemaphore(device, image_available_semaphores[i], null);
        c.vkDestroyFence(device, rendering_fences[i], null);
    }
}

fn create_swapchain() !void {
    var glfw_width: i32 = 0;
    var glfw_height: i32 = 0;

    c.glfwGetFramebufferSize(window, &glfw_width, &glfw_height);

    var width: u32 = @intCast(glfw_width);
    var height: u32 = @intCast(glfw_height);
    std.debug.print("w: {} h: {}\n", .{ width, height });

    _ = c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(physical_device, surface, &surface_capabilities);

    width = @min(@max(width, surface_capabilities.minImageExtent.width), surface_capabilities.maxImageExtent.width);
    height = @min(@max(width, surface_capabilities.minImageExtent.height), surface_capabilities.maxImageExtent.height);

    var swapchain_image_count: u32 = surface_capabilities.minImageCount + 2;
    if (surface_capabilities.maxImageCount > 0 and swapchain_image_count > surface_capabilities.maxImageCount) {
        swapchain_image_count = surface_capabilities.maxImageCount;
    }

    swapchain_extent = c.VkExtent2D{ .width = width, .height = height };

    viewport = c.VkViewport{
        .x = 0,
        .y = 0,
        .width = @floatFromInt(swapchain_extent.width),
        .height = @floatFromInt(swapchain_extent.height),
        .minDepth = 0,
        .maxDepth = 1,
    };

    scissor = c.VkRect2D{
        .offset = .{ .x = 0, .y = 0 },
        .extent = swapchain_extent,
    };

    // create swap chain
    var swapchain_create_info = std.mem.zeroes(c.VkSwapchainCreateInfoKHR);
    swapchain_create_info.sType = c.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR;
    swapchain_create_info.surface = surface;

    swapchain_create_info.imageColorSpace = surface_format.colorSpace;
    swapchain_create_info.imageFormat = surface_format.format;
    swapchain_create_info.presentMode = surface_present_mode;
    swapchain_create_info.clipped = c.VK_TRUE;

    swapchain_create_info.imageExtent = swapchain_extent;
    swapchain_create_info.imageUsage = c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
    swapchain_create_info.minImageCount = swapchain_image_count;
    swapchain_create_info.imageArrayLayers = 1;

    swapchain_create_info.queueFamilyIndexCount = 0;
    swapchain_create_info.pQueueFamilyIndices = null;
    swapchain_create_info.imageSharingMode = c.VK_SHARING_MODE_EXCLUSIVE; // fix

    swapchain_create_info.preTransform = surface_capabilities.currentTransform;

    swapchain_create_info.compositeAlpha = c.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;

    swapchain_create_info.oldSwapchain = null;

    var err = c.vkCreateSwapchainKHR(device, &swapchain_create_info, null, &swapchain);
    if (err != c.VK_SUCCESS) {
        std.debug.print("Failed to create swapchain.\n", .{});
        return;
    }

    _ = c.vkGetSwapchainImagesKHR(device, swapchain, &swapchain_image_count, null);
    swapchain_images = try alloc.alloc(c.VkImage, swapchain_image_count);
    _ = c.vkGetSwapchainImagesKHR(device, swapchain, &swapchain_image_count, @ptrCast(swapchain_images));

    //image views

    swapchain_image_views = try alloc.alloc(c.VkImageView, swapchain_images.len);
    for (swapchain_image_views, swapchain_images) |*swapchain_image_view, swapchain_image| {
        var image_view_create_info = std.mem.zeroes(c.VkImageViewCreateInfo);
        image_view_create_info.sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
        image_view_create_info.image = swapchain_image;

        image_view_create_info.viewType = c.VK_IMAGE_VIEW_TYPE_2D;
        image_view_create_info.format = surface_format.format;

        image_view_create_info.components = c.VkComponentMapping{
            .r = c.VK_COMPONENT_SWIZZLE_IDENTITY,
            .g = c.VK_COMPONENT_SWIZZLE_IDENTITY,
            .b = c.VK_COMPONENT_SWIZZLE_IDENTITY,
            .a = c.VK_COMPONENT_SWIZZLE_IDENTITY,
        };

        image_view_create_info.subresourceRange = c.VkImageSubresourceRange{
            .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        };

        err = c.vkCreateImageView(device, &image_view_create_info, null, swapchain_image_view);

        if (err != c.VK_SUCCESS) {
            std.debug.print("Failed to create image view.\n", .{});
            return;
        }
    }
}

//depends on swapchain, swapchain image views, and render pass
fn create_framebuffers() !void {
    swapchain_framebuffers = try alloc.alloc(c.VkFramebuffer, swapchain_image_views.len);

    for (swapchain_framebuffers, swapchain_image_views) |*framebuffer, swapchain_image_view| {
        var framebuffer_create_info = c.VkFramebufferCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
            .renderPass = render_pass,
            .attachmentCount = 1,
            .pAttachments = &swapchain_image_view,
            .width = swapchain_extent.width,
            .height = swapchain_extent.height,
            .layers = 1,
        };

        var err = c.vkCreateFramebuffer(device, &framebuffer_create_info, null, framebuffer);

        if (err != c.VK_SUCCESS) {
            std.debug.print("Failed to create framebuffer. error code: {}", .{err});
        }
    }
}

fn recreate_swapchain() !void {
    _ = c.vkDeviceWaitIdle(device);
    clean_framebuffers();
    clean_swapchain();
    try create_swapchain();
    try create_framebuffers();
}

fn on_window_resize(_: ?*c.GLFWwindow, _: c_int, _: c_int) callconv(.C) void {
    //recreate_swapchain() catch unreachable;
    std.debug.print("resized", .{});
}

fn u32_array_duct_tape(bytecode: []const u8) ![]u32 {
    var bytecode_out = try alloc.alloc(u32, bytecode.len / 4);
    for (0..bytecode_out.len) |u| {
        var b = u * 4;
        var bytes: [4]u8 = [4]u8{
            bytecode[b],
            bytecode[b + 1],
            bytecode[b + 2],
            bytecode[b + 3],
        };

        bytecode_out[u] = std.mem.readIntNative(u32, &bytes);
    }

    return bytecode_out;
}

fn create_shader_module(bytecode: []const u8) !c.VkShaderModule {
    var create_info = std.mem.zeroes(c.VkShaderModuleCreateInfo);
    create_info.sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
    create_info.codeSize = bytecode.len;
    var bytecode2 = try u32_array_duct_tape(bytecode);
    create_info.pCode = @ptrCast(bytecode2);

    var shader_module: c.VkShaderModule = undefined;
    var err = c.vkCreateShaderModule(device, &create_info, null, &shader_module);

    if (err != c.VK_SUCCESS) {
        std.debug.print("Failed to create shader module - error code: {}", .{err});
        return error.Failure;
    }

    return shader_module;
}

const Model = struct {
    name: [256]u8,
    position_indices: std.ArrayList(u32),
    texcoord_indices: std.ArrayList(u32),
    normal_indices: std.ArrayList(u32),

    fn init(allocator: std.mem.Allocator) !Model {
        return Model{
            .name = undefined,
            .position_indices = try std.ArrayList(u32).initCapacity(allocator, 1024 * 16),
            .texcoord_indices = try std.ArrayList(u32).initCapacity(allocator, 1024 * 16),
            .normal_indices = try std.ArrayList(u32).initCapacity(allocator, 1024 * 16),
        };
    }

    fn deinit(self: *Model) void {
        self.positions.deinit();
        self.position_indices.deinit();
        self.texcoords.deinit();
        self.texcoord_indices.deinit();
        self.normals.deinit();
        self.normal_indices.deinit();
    }
};

test "obj" {
    var timer = try std.time.Timer.start();
    var object = try Obj.load(std.testing.allocator);
    std.debug.print("\n\nObject read time elapsed: {}ms\n\n", .{timer.lap() / std.time.ns_per_ms});
    object.deinit();
}

const Obj = struct {
    models: std.ArrayList(Model),

    positions: std.ArrayList(vec3),
    texcoords: std.ArrayList(vec2),
    normals: std.ArrayList(vec3),

    //materials: std.StringHashMap(Material),

    fn load(allocator: std.mem.Allocator) !Obj {
        var object = Obj{
            .models = std.ArrayList(Model).init(allocator),
            .positions = try std.ArrayList(vec3).initCapacity(allocator, 1024 * 16),
            .texcoords = try std.ArrayList(vec2).initCapacity(allocator, 1024 * 16),
            .normals = try std.ArrayList(vec3).initCapacity(allocator, 1024 * 16),
        };

        var file = try std.fs.cwd().openFile("../models/test/test.obj", .{});
        defer file.close();

        var buffered_reader = std.io.bufferedReader(file.reader());
        var reader = buffered_reader.reader();
        //var reader = file.reader();
        var buffer: [1024]u8 = undefined;

        //state

        var model: ?Model = null;
        while (try reader.readUntilDelimiterOrEof(&buffer, '\n')) |line| {
            var spaces = std.mem.split(u8, line, " ");

            var char = spaces.next().?;

            if (std.mem.eql(u8, char, "o")) {
                if (model != null) {
                    try object.models.append(model.?);
                    // std.debug.print("M{} -- P {},PI {} T{}, TI{}, N{}, NI{},\n", .{
                    //     obj.models.items.len,
                    //     model.?.positions.items.len,
                    //     model.?.position_indices.items.len,
                    //     model.?.texcoords.items.len,
                    //     model.?.texcoord_indices.items.len,
                    //     model.?.normals.items.len,
                    //     model.?.normal_indices.items.len,
                    // });
                }

                model = try Model.init(allocator);
                var name = spaces.next().?;
                @memcpy(model.?.name[0..name.len], name);
            }

            if (std.mem.eql(u8, char, "v")) {
                var vec: vec3 = .{
                    .x = try std.fmt.parseFloat(f32, spaces.next().?),
                    .y = try std.fmt.parseFloat(f32, spaces.next().?),
                    .z = try std.fmt.parseFloat(f32, spaces.next().?),
                };

                try object.positions.append(vec);
            }

            if (std.mem.eql(u8, char, "vn")) {
                var vec: vec3 = .{
                    .x = try std.fmt.parseFloat(f32, spaces.next().?),
                    .y = try std.fmt.parseFloat(f32, spaces.next().?),
                    .z = try std.fmt.parseFloat(f32, spaces.next().?),
                };

                try object.normals.append(vec);
            }

            if (std.mem.eql(u8, char, "vt")) {
                var vec: vec2 = .{
                    .x = try std.fmt.parseFloat(f32, spaces.next().?),
                    .y = try std.fmt.parseFloat(f32, spaces.next().?),
                };

                try object.texcoords.append(vec);
            }

            if (std.mem.eql(u8, char, "f")) {
                for (0..3) |v| {
                    _ = v;
                    var vertex_indices_str = spaces.next().?;
                    var vertex_indices = std.mem.split(u8, vertex_indices_str, "/");

                    var position_index = try std.fmt.parseInt(u32, vertex_indices.next().?, 10) - 1;
                    var texcoord_index = try std.fmt.parseInt(u32, vertex_indices.next().?, 10) - 1;
                    var normals_index = try std.fmt.parseInt(u32, vertex_indices.next().?, 10) - 1;

                    try model.?.position_indices.append(position_index);
                    try model.?.texcoord_indices.append(texcoord_index);
                    try model.?.normal_indices.append(normals_index);
                }
            }
        }

        if (model != null) {
            try object.models.append(model.?);
        }

        return object;
    }

    fn deinit(self: *Obj) void {
        for (self.models.items) |*model| {
            model.deinit();
        }

        self.positions.deinit();
        self.texcoords.deinit();
        self.normals.deinit();
        self.models.deinit();
    }
};
