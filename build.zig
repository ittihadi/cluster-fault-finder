const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/main.zig"),
    });

    const raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
        .raudio = false,
        .rmodels = false,
    });

    const raylib = raylib_dep.module("raylib"); // main raylib module
    const raygui = raylib_dep.module("raygui"); // main raygui module
    const raylib_artifact = raylib_dep.artifact("raylib"); // raylib C library

    mod.linkLibrary(raylib_artifact);
    mod.addImport("raylib", raylib);
    mod.addImport("raygui", raygui);

    const exe = b.addExecutable(.{
        .name = if (target.result.os.tag == .windows) "ClusterFaultFinder" else "cluster-fault-finder",
        .root_module = mod,
    });
    b.installArtifact(exe);

    const exe_check = b.addExecutable(.{ .name = "cluster-fault-finder", .root_module = mod });

    // Add run step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_cmd.step);

    // Add check step
    const check = b.step("check", "Check if program compiles");
    check.dependOn(&exe_check.step);

    // Creates unit test
    const exe_unit_tests = b.addTest(.{
        .root_module = mod,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    // Add test step
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
