const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Get artemis-engine dependency
    const artemis_engine = b.dependency("artemis_engine", .{
        .target = target,
        .optimize = optimize,
    });

    // Create GUI module
    const artemis_gui = b.addModule("artemis-gui", .{
        .root_source_file = b.path("src/gui.zig"),
    });
    artemis_gui.addImport("artemis-engine", artemis_engine.module("artemis-engine"));

    // Tests
    const gui_tests = b.addTest(.{
        .root_source_file = b.path("src/gui.zig"),
        .target = target,
        .optimize = optimize,
    });
    gui_tests.root_module.addImport("artemis-engine", artemis_engine.module("artemis-engine"));

    const test_step = b.step("test", "Run tests");
    const run_tests = b.addRunArtifact(gui_tests);
    test_step.dependOn(&run_tests.step);

    // Example
    const example = b.addExecutable(.{
        .name = "gui-example",
        .root_source_file = b.path("examples/basic.zig"),
        .target = target,
        .optimize = optimize,
    });
    example.root_module.addImport("artemis-gui", artemis_gui);

    const example_run = b.addRunArtifact(example);
    const example_step = b.step("example", "Run basic example");
    example_step.dependOn(&example_run.step);
}