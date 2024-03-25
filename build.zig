const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "city",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    exe.linkLibC ();

    // zglfw
    const zglfw = b.dependency ("zglfw", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport ("zglfw", zglfw.module ("root"));
    exe.linkLibrary (zglfw.artifact ("glfw"));

    // zgui
    const zgui = b.dependency ("zgui", .{
        .target = target,
        .optimize = optimize,
        .backend = .glfw_opengl3,
    });
    exe.root_module.addImport ("zgui", zgui.module ("root"));
    exe.linkLibrary (zgui.artifact ("imgui"));

    // zflecs
    const zflecs = b.dependency ("zflecs", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport ("zflecs", zflecs.module ("root"));
    exe.linkLibrary (zflecs.artifact ("zflecs"));

    // ztracy
    const ztracy = b.dependency ("ztracy", .{
        .target = target,
        .optimize = optimize,
        .enable_ztracy = true,
    });
    exe.root_module.addImport ("ztracy", ztracy.module ("root"));
    exe.linkLibrary (ztracy.artifact ("ztracy"));

    // zopengl
    const zopengl = b.dependency ("zopengl", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport ("zopengl", zopengl.module ("root"));

    // zmath
    const zmath = b.dependency ("zmath", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport ("zmath", zmath.module ("root"));

    // zstbi
    const zstbi = b.dependency ("zstbi", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport ("zstbi", zstbi.module ("root"));
    exe.linkLibrary (zstbi.artifact ("zstbi"));

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
