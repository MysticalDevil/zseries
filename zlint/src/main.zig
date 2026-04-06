const std = @import("std");
const zcli = @import("zcli");
const cli = @import("cli.zig");
const config = @import("config.zig");
const compile_check = @import("compile_check.zig");
const fs_walk = @import("fs_walk.zig");
const source_file = @import("source_file.zig");
const ignore_directives = @import("ignore_directives.zig");
const diagnostic = @import("diagnostic.zig");
const rules = @import("rules/root.zig");
const text_reporter = @import("reporter/text.zig");
const json_reporter = @import("reporter/json.zig");

/// Check if build.zig exists in the given directory
fn hasBuildZig(allocator: std.mem.Allocator, io: std.Io, root_path: []const u8) bool {
    const cwd = std.Io.Dir.cwd();
    const build_zig_path = std.fs.path.join(allocator, &.{ root_path, "build.zig" }) catch return false;
    defer allocator.free(build_zig_path);

    // Try to open build.zig and immediately close it
    const file = cwd.openFile(io, build_zig_path, .{}) catch return false;
    file.close(io);
    return true;
}

/// Run zig build in the given directory
fn runZigBuild(io: std.Io, root_path: []const u8, quiet: bool, stdout: anytype, stderr: anytype) !bool {
    if (!quiet) {
        cli.printInfo(stdout, "Auto-building project (build.zig detected)...", .{}) catch {};
    }

    var child = std.process.spawn(io, .{
        .argv = &.{ "zig", "build" },
        .cwd = .{ .path = root_path },
        .stdout = .inherit,
        .stderr = .inherit,
    }) catch |err| {
        if (!quiet) {
            cli.printError(stderr, "Failed to spawn zig build: {}", .{err}) catch {};
        }
        return false;
    };

    // Wait for process to complete
    const term = child.wait(io) catch |err| {
        if (!quiet) {
            cli.printError(stderr, "Failed to wait for zig build: {}", .{err}) catch {};
        }
        return false;
    };

    const success = switch (term) {
        .exited => |code| code == 0,
        else => false,
    };

    if (!success and !quiet) {
        cli.printError(stderr, "Build failed. Fix build errors before linting.", .{}) catch {};
    } else if (success and !quiet) {
        cli.printSuccess(stdout, "Build completed successfully", .{}) catch {};
    }

    return success;
}

pub fn main(init: std.process.Init) u8 {
    const allocator = init.arena.allocator();

    // Setup stdout/stderr writers
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_file_writer: std.Io.File.Writer = .init(.stdout(), init.io, &stdout_buffer);
    const stdout = &stdout_file_writer.interface;

    var stderr_buffer: [4096]u8 = undefined;
    var stderr_file_writer: std.Io.File.Writer = .init(.stderr(), init.io, &stderr_buffer);
    const stderr = &stderr_file_writer.interface;

    const args = init.minimal.args.toSlice(allocator) catch |err| {
        cli.printError(stderr, "Failed to parse arguments: {}", .{err}) catch {};
        stderr.flush() catch {};
        return @intFromEnum(cli.ExitCode.config_error);
    };

    // Parse CLI arguments
    const options = cli.parseArgs(args) catch {
        cli.printError(stderr, "Invalid format. Use 'text' or 'json'.", .{}) catch {};
        stderr.flush() catch {};
        return @intFromEnum(cli.ExitCode.config_error);
    };

    // Load configuration
    const cfg_path = options.config_path orelse "zlint.toml";
    const cfg = config.loadConfig(allocator, cfg_path) catch |err| {
        cli.printError(stderr, "Failed to load config: {}", .{err}) catch {};
        stderr.flush() catch {};
        return @intFromEnum(cli.ExitCode.config_error);
    };

    // Auto-build if build.zig exists and not disabled
    if (!options.no_build and options.file == null) {
        if (hasBuildZig(allocator, init.io, options.root_path)) {
            const build_success = runZigBuild(init.io, options.root_path, options.quiet, stdout, stderr) catch false;
            if (!build_success) {
                stderr.flush() catch {};
                return @intFromEnum(cli.ExitCode.build_failed);
            }
            if (!options.quiet) {
                stdout.writeAll("\n") catch {};
                stdout.flush() catch {};
            }
        }
    }

    // Compile check
    if (!options.no_compile_check) {
        if (!options.quiet) {
            cli.printInfo(stdout, "Running compile check...", .{}) catch {};
        }

        const compiled = compile_check.checkCompile(allocator, options.root_path) catch |err| {
            cli.printError(stderr, "Compile check failed: {}", .{err}) catch {};
            stderr.flush() catch {};
            return @intFromEnum(cli.ExitCode.compile_failed);
        };

        if (!compiled) {
            cli.printError(stderr, "Compile check failed. Fix compilation errors before linting.", .{}) catch {};
            stderr.flush() catch {};
            return @intFromEnum(cli.ExitCode.compile_failed);
        }

        if (!options.quiet) {
            cli.printSuccess(stdout, "Compile check passed", .{}) catch {};
            stdout.writeAll("\n") catch {};
            stdout.flush() catch {};
        }
    }

    // Collect files to scan
    const files = if (options.file) |single_file|
        &[_][]const u8{single_file}
    else
        fs_walk.collectFiles(allocator, init.io, options.root_path, cfg) catch |err| {
            cli.printError(stderr, "Failed to collect files: {}", .{err}) catch {};
            stderr.flush() catch {};
            return @intFromEnum(cli.ExitCode.config_error);
        };

    if (!options.quiet) {
        cli.printInfo(stdout, "Found {d} files to scan", .{files.len}) catch {};
        stdout.writeAll("\n") catch {};
        stdout.flush() catch {};
    }

    // Run linting
    var all_diagnostics = diagnostic.DiagnosticCollection.init(allocator);

    for (files) |file_path| {
        var src_file = source_file.SourceFile.init(allocator, init.io, file_path) catch |err| {
            if (!options.quiet) {
                cli.printWarning(stderr, "Failed to parse {s}: {}", .{ file_path, err }) catch {};
            }
            continue;
        };

        // Parse ignore directives
        const ignores = ignore_directives.IgnoreDirectives.parse(allocator, src_file.content) catch |err| {
            if (!options.quiet) {
                cli.printWarning(stderr, "Failed to parse ignore directives in {s}: {}", .{ file_path, err }) catch {};
            }
            continue;
        };

        // Create rule context
        var ctx = rules.RuleContext{
            .allocator = allocator,
            .file = &src_file,
            .config = cfg,
            .ignores = &ignores,
            .diagnostics = &all_diagnostics.items,
        };

        // Get enabled rules and run them
        const enabled_rules = rules.getEnabledRules(cfg, allocator) catch |err| {
            if (!options.quiet) {
                cli.printWarning(stderr, "Failed to get enabled rules: {}", .{err}) catch {};
            }
            continue;
        };

        for (enabled_rules) |rule| {
            rule.run(&ctx) catch |err| {
                if (!options.quiet) {
                    cli.printWarning(stderr, "Rule '{s}' failed on {s}: {}", .{ rule.name, file_path, err }) catch {};
                }
            };
        }
    }

    // Get summary
    var summary = all_diagnostics.getSummary();
    summary.files_scanned = files.len;

    // Output results
    switch (options.format) {
        .text => {
            text_reporter.writeText(stdout, all_diagnostics.items.items, summary, true) catch {};
        },
        .json => {
            json_reporter.writeJson(stdout, all_diagnostics.items.items, summary) catch {};
        },
    }
    stdout.flush() catch {};

    // Return appropriate exit code
    if (summary.errors > 0) {
        return @intFromEnum(cli.ExitCode.has_errors);
    }
    return @intFromEnum(cli.ExitCode.ok);
}
