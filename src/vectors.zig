const std = @import("std");

//prelude

// const vectors = @import("vectors.zig");

// const vec2 = vectors.vec2;
// const ivec2 = vectors.ivec2;
// const iivec2 = vectors.iivec2;

// const vec3 = vectors.vec3;
// const ivec3 = vectors.ivec3;
// const iivec3 = vectors.iivec3;

// const vec4 = vectors.vec4;
// const ivec4 = vectors.ivec4;
// const iivec4 = vectors.iivec4;

// const mat4 = vectors.mat4;

//vec2

pub const vec2 = extern struct {
    x: f32,
    y: f32,
};

pub const ivec2 = extern struct {
    x: i32,
    y: i32,
};

pub const iivec2 = extern struct {
    x: i64,
    y: i64,
};

//vec4

pub const vec4 = extern struct {
    x: f32,
    y: f32,
    z: f32,
    w: f32,
};

pub const ivec4 = extern struct {
    x: i32,
    y: i32,
    z: i32,
    w: i32,
};

pub const iivec4 = extern struct {
    x: i64,
    y: i64,
    z: i64,
    w: i64,
};

//vec3

pub const ivec3 = extern struct {
    x: i32,
    y: i32,
    z: i32,
};

pub const iivec3 = extern struct {
    x: i64,
    y: i64,
    z: i64,
};

pub const vec3 = extern struct {
    x: f32,
    y: f32,
    z: f32,

    pub fn init(x: f32, y: f32, z: f32) vec3 {
        return .{ .x = x, .y = y, .z = z };
    }

    pub fn from_angle(pitch: f32, yaw: f32) vec3 {
        return .{
            .x = @sin(pitch) * @cos(yaw),
            .y = @cos(pitch),
            .z = @sin(pitch) * @sin(yaw),
        };
    }

    pub fn from_scalar(scalar: f32) vec3 {
        return .{ .x = scalar, .y = scalar, .z = scalar };
    }

    pub fn from_zero() vec3 {
        return .{ .x = 0, .y = 0, .z = 0 };
    }

    pub fn from_one() vec3 {
        return .{ .x = 1, .y = 1, .z = 1 };
    }

    pub fn add(self: vec3, other: vec3) vec3 {
        return .{
            .x = self.x + other.x,
            .y = self.y + other.y,
            .z = self.z + other.z,
        };
    }

    pub fn sub(self: vec3, other: vec3) vec3 {
        return .{
            .x = self.x - other.x,
            .y = self.y - other.y,
            .z = self.z - other.z,
        };
    }

    pub fn mul(self: vec3, other: vec3) vec3 {
        return .{
            .x = self.x * other.x,
            .y = self.y * other.y,
            .z = self.z * other.z,
        };
    }

    pub fn muls(self: vec3, scalar: f32) vec3 {
        return .{
            .x = self.x * scalar,
            .y = self.y * scalar,
            .z = self.z * scalar,
        };
    }

    pub fn divs(self: vec3, scalar: f32) vec3 {
        return .{
            .x = self.x / scalar,
            .y = self.y / scalar,
            .z = self.z / scalar,
        };
    }

    pub fn about_equals(self: vec3, other: vec3) bool {
        return equals(self, other, 0.001);
    }

    pub fn equals(self: vec3, other: vec3, t: f32) bool {
        return std.math.approxEqAbs(f32, self.x, other.x, t) and std.math.approxEqAbs(f32, self.y, other.y, t) and std.math.approxEqAbs(f32, self.z, other.z, t);
    }

    pub fn magnitude(self: vec3) f32 {
        return @sqrt((self.x * self.x) + (self.y * self.y) + (self.z * self.z));
    }

    pub fn distance(self: vec3, other: vec3) f32 {
        return magnitude(self.sub(other));
    }

    pub fn normalize(self: vec3) vec3 {
        return self.div(self.magnitude());
    }

    pub fn to_ivec3(self: vec3) ivec3 {
        return .{ self.x, self.y, self.z };
    }

    pub fn to_iivec3(self: vec3) @Vector(3, i64) {
        return .{
            @as(i64, @intFromFloat(@floor(self.x))),
            @as(i64, @intFromFloat(@floor(self.y))),
            @as(i64, @intFromFloat(@floor(self.z))),
        };
    }

    pub fn increment_voxelwise(self: vec3, dir: vec3) vec3 {
        var face_x: f32 = undefined;
        var face_y: f32 = undefined;
        var face_z: f32 = undefined;

        if (dir.x < 0) {
            face_x = @ceil(self.x) - 1;
        } else {
            face_x = @floor(self.x) + 1;
        }

        if (dir.y < 0) {
            face_y = @ceil(self.y) - 1;
        } else {
            face_y = @floor(self.y) + 1;
        }

        if (dir.z < 0) {
            face_z = @ceil(self.z) - 1;
        } else {
            face_z = @floor(self.z) + 1;
        }

        var face_x_dis = (face_x - self.x) / dir.x;
        var face_y_dis = (face_y - self.y) / dir.y;
        var face_z_dis = (face_z - self.z) / dir.z;

        var dis: f32 = undefined;
        if (face_x_dis < face_y_dis and face_x_dis < face_z_dis) {
            dis = face_x_dis;
        } else if (face_y_dis < face_x_dis and face_y_dis < face_z_dis) {
            dis = face_y_dis;
        } else {
            dis = face_z_dis;
        }

        return self.add(dir.mul(dis));
    }
};

//Column Major Ordering
const mat4 = struct {
    values: @Vector(4 * 4, f32),

    fn zeroes() mat4 {
        return mat4{
            .values = @splat(0),
        };
    }

    fn identity() mat4 {
        return mat4{
            .values = .{ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 },
        };
    }

    fn scale(x: f32, y: f32, z: f32) mat4 {
        return mat4{
            .values = .{ x, 0, 0, 0, 0, y, 0, 0, 0, 0, z, 0, 0, 0, 0, 1 },
        };
    }

    fn translation(x: f32, y: f32, z: f32) mat4 {
        return mat4{
            .values = .{ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, x, y, z, 1 },
        };
    }

    fn rotationY(angle: f32) mat4 {
        return mat4{
            .values = .{ @cos(angle), 0, @sin(angle), 0, 0, 1, 0, 0, -@sin(angle), 0, @cos(angle), 0, 0, 0, 0, 1 },
        };
    }

    fn rotationX(angle: f32) mat4 {
        return mat4{
            .values = .{ 1, 0, 0, 0, 0, @cos(angle), -@sin(angle), 0, 0, @sin(angle), @cos(angle), 0, 0, 0, 0, 1 },
        };
    }

    fn rotationZ(angle: f32) mat4 {
        return mat4{
            .values = .{ @cos(angle), @sin(angle), 0, 0, -@sin(angle), @cos(angle), 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 },
        };
    }

    fn perspective(fov: f32, aspect_ratio: f32, near: f32, far: f32) mat4 {
        var t = @tan(fov / 2);
        return mat4{
            .values = .{ 1 / (t * aspect_ratio), 0, 0, 0, 0, 1 / t, 0, 0, 0, 0, -(far + near) / (far - near), -1, 0, 0, -(2 * far * near) / (far - near), 1 },
        };
    }

    fn multiply(self: mat4, other: mat4) mat4 {
        var result: mat4 = mat4.zeroes();

        for (0..4) |res_col| {
            for (0..4) |res_row| {
                var value: f32 = 0;
                for (0..4) |self_col_other_row| {
                    value += self.values[self_col_other_row * 4 + res_row] * other.values[self_col_other_row + res_col * 4];
                }
                result.values[res_col * 4 + res_row] = value;
            }
        }

        return result;
    }

    fn approx_equals(self: mat4, other: mat4) bool {
        return equals(self, other, 0.001);
    }

    fn equals(self: mat4, other: mat4, tolerance: f32) bool {
        for (0..16) |i| {
            if (!std.math.approxEqAbs(f32, self.values[i], other.values[i], tolerance))
                return false;
        }

        return true;
    }

    fn print(self: mat4) void {
        std.debug.print("\n", .{});
        for (0..4) |row| {
            std.debug.print("[ ", .{});
            for (0..4) |col| {
                std.debug.print("{d:.3}, ", .{self.values[col * 4 + row]});
            }
            std.debug.print("]\n", .{});
        }
    }
};

test "matrix" {
    const assert = std.debug.assert;

    var scale = mat4.scale(2, 2, 2);
    var translate = mat4.translation(0, 5, 0);
    var identity = mat4.identity();
    identity.multiply(translate).print();
    identity.multiply(identity.multiply(translate)).print();
    identity.multiply(scale.multiply(translate)).print();
    identity.multiply(scale.multiply(scale)).print();
    assert(identity.multiply(translate).approx_equals(translate));
    assert(identity.multiply(translate).approx_equals(identity.multiply(translate)));
}
