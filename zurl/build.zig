const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zcli_dep = b.dependency("zcli", .{
        .target = target,
        .optimize = optimize,
    });
    const zcli_module = zcli_dep.module("zcli");
    const zest_dep = b.dependency("zest", .{
        .target = target,
        .optimize = optimize,
    });
    const zest_module = zest_dep.module("zest");

    const mod = b.addModule("zurl", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "zcli", .module = zcli_module },
            .{ .name = "zest", .module = zest_module },
        },
    });

    const exe = b.addExecutable(.{
        .name = "zurl",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zurl", .module = mod },
                .{ .name = "zcli", .module = zcli_module },
                .{ .name = "zest", .module = zest_module },
            },
        }),
    });
    b.installArtifact(exe);

    const test_server_exe = b.addExecutable(.{
        .name = "zurl-test-server",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/test_server.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zest", .module = zest_module },
            },
        }),
    });
    b.installArtifact(test_server_exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run zurl");
    run_step.dependOn(&run_cmd.step);

    const run_test_server_cmd = b.addRunArtifact(test_server_exe);
    if (b.args) |args| {
        run_test_server_cmd.addArgs(args);
    }
    const run_test_server_step = b.step("run-test-server", "Run zurl integration test server");
    run_test_server_step.dependOn(&run_test_server_cmd.step);

    const mod_tests = b.addTest(.{ .root_module = mod });
    const run_mod_tests = b.addRunArtifact(mod_tests);
    const exe_tests = b.addTest(.{ .root_module = exe.root_module });
    const run_exe_tests = b.addRunArtifact(exe_tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(b.getInstallStep());
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
