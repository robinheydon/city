const std = @import("std");

const zglfw = @import ("zglfw");
const zgui = @import ("zgui");
const zmath = @import ("zmath");
const zopengl = @import ("zopengl");
const ztracy = @import ("ztracy");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "city",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const zglfw_pkg = zglfw.package (b, target, optimize, .{});
    const zgui_pkg = zgui.package (b, target, optimize, .{
            .options = .{
                .backend = .glfw_opengl3,
            },
        }
    );
    const zmath_pkg = zmath.package (b, target, optimize, .{});
    const zopengl_pkg = zopengl.package (b, target, optimize, .{});
    const ztracy_pkg = ztracy.package (b, target, optimize, .{
        .options = .{
            .enable_ztracy = true,
        },
    });

    zglfw_pkg.link (exe);
    zgui_pkg.link (exe);
    zmath_pkg.link (exe);
    zopengl_pkg.link (exe);
    ztracy_pkg.link (exe);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
