const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Get dependencies
    const ztoml_dep = b.dependency("ztoml", .{
        .target = target,
        .optimize = optimize,
    });
    const zcli_dep = b.dependency("zcli", .{
        .target = target,
        .optimize = optimize,
    });

    // Create module
    const mod = b.addModule("zlint", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });
    mod.addImport("ztoml", ztoml_dep.module("ztoml"));
    mod.addImport("zcli", zcli_dep.module("zcli"));

    // Main executable
    const exe = b.addExecutable(.{
        .name = "zlint",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zlint", .module = mod },
                .{ .name = "zcli", .module = zcli_dep.module("zcli") },
            },
        }),
    });
    b.installArtifact(exe);

    // Run command
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run zlint");
    run_step.dependOn(&run_cmd.step);

    // Tests
    const mod_tests = b.addTest(.{
        .root_module = mod,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("test", "Run zlint tests");
    test_step.dependOn(&run_mod_tests.step);
}
