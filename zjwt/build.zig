const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zjwt_module = b.addModule("zjwt", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const unit_tests = b.addTest(.{
        .name = "zjwt_unit_tests",
        .root_module = zjwt_module,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);

    const basic_tests = b.createModule(.{
        .root_source_file = b.path("tests/basic.zig"),
        .target = target,
        .optimize = optimize,
    });
    basic_tests.addImport("zjwt", zjwt_module);

    const basic_tests_artifact = b.addTest(.{
        .name = "zjwt_basic_tests",
        .root_module = basic_tests,
    });
    const run_basic_tests = b.addRunArtifact(basic_tests_artifact);

    const test_step = b.step("test", "Run zjwt tests");
    test_step.dependOn(&run_unit_tests.step);
    test_step.dependOn(&run_basic_tests.step);
}
