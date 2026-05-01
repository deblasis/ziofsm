const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    _ = b.addModule("ziofsm", .{
        .root_source_file = b.path("src/ziofsm.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addStaticLibrary(.{
        .name = "ziofsm",
        .root_source_file = b.path("src/ziofsm.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(lib);

    const tests = b.addTest(.{
        .root_source_file = b.path("src/ziofsm.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_tests.step);
}

    // Example
    const exe = b.addExecutable(.{
        .name = "example",
        .root_source_file = b.path("examples/example.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("ziofsm", b.addModule("ziofsm", .{
        .root_source_file = b.path("src/ziofsm.zig"),
        .target = target,
        .optimize = optimize,
    }));
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run-example", "Run the example");
    run_step.dependOn(&run_cmd.step);
