const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zcli_dep = b.dependency("zcli", .{});
    const ztui_dep = b.dependency("ztui", .{});
    const zlog_dep = b.dependency("zlog", .{});
    const ztmpfile_dep = b.dependency("ztmpfile", .{});

    const zcli_module = zcli_dep.module("zcli");
    const ztui_module = ztui_dep.module("ztui");
    const zlog_module = zlog_dep.module("zlog");
    const ztmpfile_module = ztmpfile_dep.module("ztmpfile");

    const mod = b.addModule("ztotp", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "zcli", .module = zcli_module },
            .{ .name = "ztui", .module = ztui_module },
            .{ .name = "zlog", .module = zlog_module },
            .{ .name = "ztmpfile", .module = ztmpfile_module },
        },
    });

    const exe = b.addExecutable(.{
        .name = "ztotp",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "ztotp", .module = mod },
                .{ .name = "zcli", .module = zcli_module },
                .{ .name = "ztui", .module = ztui_module },
                .{ .name = "zlog", .module = zlog_module },
                .{ .name = "ztmpfile", .module = ztmpfile_module },
            },
        }),
    });

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);
    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });
    const run_exe_tests = b.addRunArtifact(exe_tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
