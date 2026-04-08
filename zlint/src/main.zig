const std = @import("std");
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

fn shouldUseColor(io: std.Io, mode: cli.Options.ColorMode) bool {
    return switch (mode) {
        .always => true,
        .never => false,
        .auto => std.Io.File.stdout().supportsAnsiEscapeCodes(io) catch false,
    };
}

fn hasBuildZig(io: std.Io, root_path: []const u8) bool {
    const cwd = std.Io.Dir.cwd();
    cwd.access(io, root_path, .{}) catch return false;

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const joined = std.fmt.bufPrint(&path_buf, "{s}/build.zig", .{root_path}) catch return false;
    cwd.access(io, joined, .{}) catch return false;
    return true;
}

fn emitCheckOutput(writer: *std.Io.Writer, stderr_writer: *std.Io.Writer, result: compile_check.CheckResult) !void {
    if (result.stdout.len > 0) try writer.writeAll(result.stdout);
    if (result.stderr.len > 0) try stderr_writer.writeAll(result.stderr);
}

fn verboseLevel(options: cli.Options) u8 {
    if (options.format != .text) return 0;
    return options.verbose;
}

fn emitVerbose(
    writer: *std.Io.Writer,
    use_color: bool,
    options: cli.Options,
    level: u8,
    comptime fmt: []const u8,
    args: anytype,
) !void {
    if (verboseLevel(options) < level) return;
    try cli.emit(writer, use_color, .info, fmt, args);
}

fn emitBestEffort(
    writer: *std.Io.Writer,
    use_color: bool,
    level: cli.LogLevel,
    comptime fmt: []const u8,
    args: anytype,
) void {
    cli.emit(writer, use_color, level, fmt, args) catch |err| {
        std.debug.print("zlint: failed to emit terminal output: {}\n", .{err});
    };
}

fn writeBestEffort(writer: *std.Io.Writer, text: []const u8) void {
    writer.writeAll(text) catch |err| {
        std.debug.print("zlint: failed to write terminal output: {}\n", .{err});
    };
}

fn flushBestEffort(writer: *std.Io.Writer) void {
    writer.flush() catch |err| {
        std.debug.print("zlint: failed to flush terminal output: {}\n", .{err});
    };
}

fn emitFailureAndExit(
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
    use_color: bool,
    format: cli.Options.Format,
    exit_code: cli.ExitCode,
    code: []const u8,
    message: []const u8,
    stdout_text: ?[]const u8,
    stderr_text: ?[]const u8,
) noreturn {
    if (format == .json) {
        json_reporter.writeFailureJson(stdout, code, message, stdout_text, stderr_text) catch |err| {
            std.debug.print("zlint: failed to emit JSON failure output: {}\n", .{err});
        };
        flushBestEffort(stdout);
    } else {
        emitBestEffort(stderr, use_color, .err, "{s}", .{message});
        if (stdout_text) |text| {
            if (text.len > 0) writeBestEffort(stdout, text);
        }
        if (stderr_text) |text| {
            if (text.len > 0) writeBestEffort(stderr, text);
        }
        flushBestEffort(stderr);
    }
    std.process.exit(@intFromEnum(exit_code));
}

fn shouldFail(summary: diagnostic.Summary, cfg: config.Config) bool {
    if (summary.errors > 0) return true;
    if (cfg.fail_on_warning and summary.warnings > 0) return true;
    return false;
}

fn resolveConfigPath(allocator: std.mem.Allocator, root_path: []const u8, maybe_cfg_path: ?[]const u8) ![]const u8 {
    const cfg_path = maybe_cfg_path orelse "zlint.toml";
    if (std.fs.path.isAbsolute(cfg_path)) return allocator.dupe(u8, cfg_path);
    return std.fs.path.join(allocator, &.{ root_path, cfg_path });
}

fn isDirectoryPath(io: std.Io, path: []const u8) bool {
    const cwd = std.Io.Dir.cwd();
    var dir = cwd.openDir(io, path, .{}) catch return false;
    defer dir.close(io);
    return true;
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_file_writer: std.Io.File.Writer = .init(.stdout(), init.io, &stdout_buffer);
    const stdout = &stdout_file_writer.interface;

    var stderr_buffer: [4096]u8 = undefined;
    var stderr_file_writer: std.Io.File.Writer = .init(.stderr(), init.io, &stderr_buffer);
    const stderr = &stderr_file_writer.interface;

    const startup_color = shouldUseColor(init.io, .auto);
    const args = try init.minimal.args.toSlice(allocator);
    const options = cli.parseArgs(init.io, args, startup_color) catch |err| {
        const msg = switch (err) {
            error.InvalidFormat => "Invalid format. Use 'text' or 'json'.",
            error.InvalidOption => "Invalid CLI option, missing option value, or conflicting flags (-q and -v).",
            else => "Failed to parse command line arguments.",
        };
        emitFailureAndExit(
            stdout,
            stderr,
            startup_color,
            .text,
            .config_error,
            "config_error",
            msg,
            null,
            null,
        );
    };

    const use_color = shouldUseColor(init.io, options.color);

    var run_root = options.root_path;
    var run_file = options.file;

    var owned_root: ?[]const u8 = null;
    defer if (owned_root) |p| allocator.free(p);

    var owned_file: ?[]const u8 = null;
    defer if (owned_file) |p| allocator.free(p);

    if (options.file) |input_path| {
        const candidate = if (std.fs.path.isAbsolute(input_path))
            input_path
        else blk: {
            const joined = try std.fs.path.join(allocator, &.{ options.root_path, input_path });
            break :blk joined;
        };

        if (isDirectoryPath(init.io, candidate)) {
            run_root = candidate;
            run_file = null;
            if (!std.fs.path.isAbsolute(input_path)) owned_root = candidate;
        } else if (!std.fs.path.isAbsolute(input_path)) {
            run_file = candidate;
            owned_file = candidate;
        }
    }

    const cfg_path = try resolveConfigPath(allocator, run_root, options.config_path);
    try emitVerbose(stdout, use_color, options, 1, "Resolved run root: {s}", .{run_root});
    try emitVerbose(stdout, use_color, options, 1, "Resolved config path: {s}", .{cfg_path});
    const cfg = config.loadConfig(allocator, init.io, cfg_path) catch {
        const msg = std.fmt.allocPrint(allocator, "Failed to load configuration: {s}", .{cfg_path}) catch "Failed to load configuration";
        defer if (msg.ptr != "Failed to load configuration".ptr) allocator.free(msg);
        emitFailureAndExit(
            stdout,
            stderr,
            use_color,
            options.format,
            .config_error,
            "config_error",
            msg,
            null,
            null,
        );
    };

    const has_build_zig = hasBuildZig(init.io, run_root);
    try emitVerbose(stdout, use_color, options, 1, "Build gate candidate: has_build_zig={any}, run_file={s}", .{
        has_build_zig,
        if (run_file) |file| file else "<none>",
    });

    if (!options.no_build and run_file == null and has_build_zig) {
        if (options.format != .json and !options.quiet) {
            try cli.emit(stdout, use_color, .info, "Running build gate (zig build)...", .{});
        }

        var result = try compile_check.runBuild(allocator, init.io, run_root);
        defer result.deinit(allocator);

        if (!result.ok) {
            const code: cli.ExitCode = if (cfg.strict_exit) .build_failed else .compile_failed;
            const error_code = if (cfg.strict_exit) "build_failed" else "compile_failed";
            const message = if (cfg.strict_exit)
                "Build gate failed and strict_exit is enabled."
            else
                "Build gate failed.";
            emitFailureAndExit(
                stdout,
                stderr,
                use_color,
                options.format,
                code,
                error_code,
                message,
                result.stdout,
                result.stderr,
            );
        }
    } else if (!options.no_compile_check and run_file == null and !has_build_zig) {
        if (options.format != .json and !options.quiet) {
            try cli.emit(stdout, use_color, .info, "No build.zig found; skipping build gate", .{});
        }
    } else if (verboseLevel(options) >= 1) {
        try emitVerbose(stdout, use_color, options, 1, "Skipping build gate: no_build={any}, no_compile_check={any}", .{
            options.no_build,
            options.no_compile_check,
        });
    }

    const files = if (run_file) |single_file|
        &[_][]const u8{single_file}
    else
        try fs_walk.collectFiles(allocator, init.io, run_root, cfg);
    try emitVerbose(stdout, use_color, options, 1, "Collected {d} file(s) for linting", .{files.len});

    var all_diagnostics = diagnostic.DiagnosticCollection.init(allocator);
    defer all_diagnostics.deinit();

    const enabled_rules = rules.getEnabledRules(cfg, allocator) catch {
        emitFailureAndExit(
            stdout,
            stderr,
            use_color,
            options.format,
            .config_error,
            "config_error",
            "Failed to build enabled rule list",
            null,
            null,
        );
    };
    try emitVerbose(stdout, use_color, options, 1, "Enabled {d} rule(s)", .{enabled_rules.len});
    if (verboseLevel(options) >= 1) {
        for (enabled_rules) |rule| {
            try emitVerbose(stdout, use_color, options, 1, "Rule enabled: {s}", .{rule.name});
        }
    }

    var files_linted: usize = 0;
    for (files) |file_path| {
        try emitVerbose(stdout, use_color, options, 1, "Linting file: {s}", .{file_path});
        var src_file = source_file.SourceFile.init(allocator, init.io, file_path) catch {
            try emitVerbose(stdout, use_color, options, 1, "Skipping unreadable file: {s}", .{file_path});
            continue;
        };
        defer src_file.deinit();

        var scratch_arena = std.heap.ArenaAllocator.init(allocator);
        defer scratch_arena.deinit();
        const scratch_alloc = scratch_arena.allocator();

        const ignores = ignore_directives.IgnoreDirectives.parse(scratch_alloc, src_file.content) catch |err| switch (err) {
            error.UnknownRuleId => {
                const msg = std.fmt.allocPrint(allocator, "Unknown suppression rule id in file: {s}", .{file_path}) catch "Unknown suppression rule id in file";
                defer if (msg.ptr != "Unknown suppression rule id in file".ptr) allocator.free(msg);
                emitFailureAndExit(
                    stdout,
                    stderr,
                    use_color,
                    options.format,
                    .config_error,
                    "config_error",
                    msg,
                    null,
                    null,
                );
            },
            error.OutOfMemory => return err,
        };

        var ctx = rules.RuleContext{
            .allocator = allocator,
            .file = &src_file,
            .config = cfg,
            .ignores = &ignores,
            .diagnostics = &all_diagnostics,
            .trace_writer = stdout,
            .trace_use_color = use_color,
            .verbose_level = verboseLevel(options),
        };

        const before_count = all_diagnostics.items.items.len;
        for (enabled_rules) |rule| {
            ctx.current_rule_name = rule.name;
            try emitVerbose(stdout, use_color, options, 1, "Running rule '{s}' on {s}", .{ rule.name, file_path });
            rule.run(&ctx) catch |rule_err| {
                if (options.format != .json and !options.quiet) {
                    try cli.emit(stderr, use_color, .warning, "Rule '{s}' failed on {s}: {}", .{ rule.name, file_path, rule_err });
                }
            };
        }
        const after_count = all_diagnostics.items.items.len;
        try emitVerbose(stdout, use_color, options, 1, "Finished file: {s} ({d} new diagnostic(s))", .{
            file_path,
            after_count - before_count,
        });

        files_linted += 1;
    }

    var summary = all_diagnostics.getSummary();
    summary.files_scanned = files_linted;
    try emitVerbose(stdout, use_color, options, 1, "Lint complete: files={d}, diagnostics={d}", .{
        summary.files_scanned,
        summary.diagnostics,
    });

    switch (options.format) {
        .text => try text_reporter.writeText(allocator, init.io, stdout, all_diagnostics.items.items, summary, .{
            .use_color = use_color,
            .collapse_duplicates = !options.no_collapse,
            .max_per_group = options.max_per_group,
            .context_lines = options.context_lines,
        }),
        .json => try json_reporter.writeJson(allocator, stdout, all_diagnostics.items.items, summary),
    }
    try stdout.flush();

    const exit_code: cli.ExitCode = if (shouldFail(summary, cfg)) .has_errors else .ok;
    std.process.exit(@intFromEnum(exit_code));
}
