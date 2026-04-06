const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const ztmpfile_module = b.addModule("ztmpfile", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const unit_test_module = b.createModule(.{
        .root_source_file = b.path("tests/unit.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "ztmpfile", .module = ztmpfile_module },
        },
    });
    const integration_test_module = b.createModule(.{
        .root_source_file = b.path("tests/integration_fs.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "ztmpfile", .module = ztmpfile_module },
        },
    });
    const compat_test_module = b.createModule(.{
        .root_source_file = b.path("tests/compat.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "ztmpfile", .module = ztmpfile_module },
        },
    });

    const unit_tests = b.addTest(.{
        .name = "ztmpfile_unit_tests",
        .root_module = unit_test_module,
    });
    const integration_tests = b.addTest(.{
        .name = "ztmpfile_integration_tests",
        .root_module = integration_test_module,
    });
    const compat_tests = b.addTest(.{
        .name = "ztmpfile_compat_tests",
        .root_module = compat_test_module,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const run_integration_tests = b.addRunArtifact(integration_tests);
    const run_compat_tests = b.addRunArtifact(compat_tests);

    const test_unit_step = b.step("test-unit", "Run unit tests");
    test_unit_step.dependOn(&run_unit_tests.step);

    const test_integration_step = b.step("test-integration", "Run integration tests");
    test_integration_step.dependOn(&run_integration_tests.step);
    test_integration_step.dependOn(&run_compat_tests.step);

    const test_cross_step = b.step("test-cross", "Cross-target compile-only test checks");
    addCrossCompileChecks(b, test_cross_step, optimize);

    const test_wine_step = b.step("test-wine", "Run Windows runtime smoke tests via Wine (optional)");
    addWineRuntimeChecks(b, test_wine_step, optimize);

    const test_wasm_step = b.step("test-wasm", "Run WASI runtime smoke tests via wasmtime/wasmer (optional)");
    addWasmRuntimeChecks(b, test_wasm_step, optimize);

    const test_runtime_step = b.step("test-runtime", "Run optional runtime smoke checks");
    test_runtime_step.dependOn(test_wine_step);
    test_runtime_step.dependOn(test_wasm_step);

    const test_step = b.step("test", "Run ztmpfile tests");
    test_step.dependOn(test_unit_step);
    test_step.dependOn(test_integration_step);
    test_step.dependOn(test_cross_step);

    const test_all_step = b.step("test-all", "Run full suite including optional runtime checks");
    test_all_step.dependOn(test_step);
    test_all_step.dependOn(test_runtime_step);
}

fn addCrossCompileChecks(b: *std.Build, step: *std.Build.Step, optimize: std.builtin.OptimizeMode) void {
    const targets = [_]std.Target.Query{
        .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu },
        .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .gnu },
        .{ .cpu_arch = .aarch64, .os_tag = .macos },
        .{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .gnu },
        .{ .cpu_arch = .aarch64, .os_tag = .windows, .abi = .gnu },
        .{ .cpu_arch = .wasm32, .os_tag = .wasi },
    };

    inline for (targets) |query| {
        const target = b.resolveTargetQuery(query);
        const ztmpfile_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        });

        const unit_test_module = b.createModule(.{
            .root_source_file = b.path("tests/unit.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "ztmpfile", .module = ztmpfile_module },
            },
        });
        const integration_test_module = b.createModule(.{
            .root_source_file = b.path("tests/integration_fs.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "ztmpfile", .module = ztmpfile_module },
            },
        });

        const unit_compile = b.addTest(.{
            .name = b.fmt("cross_unit_{s}", .{target.result.zigTriple(b.allocator) catch "unknown"}),
            .root_module = unit_test_module,
        });
        const integration_compile = b.addTest(.{
            .name = b.fmt("cross_integration_{s}", .{target.result.zigTriple(b.allocator) catch "unknown"}),
            .root_module = integration_test_module,
        });

        step.dependOn(&unit_compile.step);
        step.dependOn(&integration_compile.step);
    }
}

fn addWineRuntimeChecks(b: *std.Build, step: *std.Build.Step, optimize: std.builtin.OptimizeMode) void {
    const wine = b.findProgram(&.{ "wine64", "wine" }, &.{}) catch {
        addSkipStep(b, step, "SKIP test-wine: wine runner not found");
        return;
    };

    const target = b.resolveTargetQuery(.{
        .cpu_arch = .x86_64,
        .os_tag = .windows,
        .abi = .gnu,
    });

    const ztmpfile_module = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const smoke_module = b.createModule(.{
        .root_source_file = b.path("tests/runtime_windows.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "ztmpfile", .module = ztmpfile_module },
        },
    });
    const smoke_test = b.addTest(.{
        .name = "runtime_windows_smoke",
        .root_module = smoke_module,
    });
    const run = b.addSystemCommand(&.{wine});
    run.addFileArg(smoke_test.getEmittedBin());
    run.step.dependOn(&smoke_test.step);
    step.dependOn(&run.step);
}

fn addWasmRuntimeChecks(b: *std.Build, step: *std.Build.Step, optimize: std.builtin.OptimizeMode) void {
    const runner_path, const runner_kind = blk: {
        const wasmtime = b.findProgram(&.{"wasmtime"}, &.{}) catch null;
        if (wasmtime) |r| break :blk .{ r, RunnerKind.wasmtime };
        const wasmer = b.findProgram(&.{"wasmer"}, &.{}) catch null;
        if (wasmer) |r| break :blk .{ r, RunnerKind.wasmer };
        break :blk .{ null, null };
    };

    if (runner_path == null or runner_kind == null) {
        addSkipStep(b, step, "SKIP test-wasm: wasmtime/wasmer runner not found");
        return;
    }

    const target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .wasi,
    });

    const ztmpfile_module = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const smoke_module = b.createModule(.{
        .root_source_file = b.path("tests/runtime_wasi.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "ztmpfile", .module = ztmpfile_module },
        },
    });
    const smoke_test = b.addTest(.{
        .name = "runtime_wasi_smoke",
        .root_module = smoke_module,
    });

    const run = switch (runner_kind.?) {
        .wasmtime => b.addSystemCommand(&.{ runner_path.?, "--dir=." }),
        .wasmer => b.addSystemCommand(&.{ runner_path.?, "run", "--dir=." }),
    };
    run.addFileArg(smoke_test.getEmittedBin());
    run.step.dependOn(&smoke_test.step);
    step.dependOn(&run.step);
}

const RunnerKind = enum {
    wasmtime,
    wasmer,
};

fn addSkipStep(b: *std.Build, step: *std.Build.Step, msg: []const u8) void {
    const run = b.addSystemCommand(&.{ "/bin/sh", "-c", b.fmt("printf '%s\\n' \"{s}\"", .{msg}) });
    step.dependOn(&run.step);
}
