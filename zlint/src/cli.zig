const std = @import("std");
const zcli = @import("zcli");

/// CLI options
pub const Options = struct {
    file: ?[]const u8 = null,
    format: Format = .text,
    config_path: ?[]const u8 = null,
    root_path: []const u8 = ".",
    no_compile_check: bool = false,
    no_build: bool = false,
    quiet: bool = false,

    pub const Format = enum {
        text,
        json,
    };
};

/// Command definition for zcli help generation
const cmd_def: zcli.help.Command = .{
    .name = "zlint",
    .summary = "Zig project linter for enforcing code quality rules",
    .flags = &.{
        .{ .name = "--file", .value_name = "PATH", .description = "Single file to lint (skips directory scanning)" },
        .{ .name = "--format", .short = "-f", .value_name = "FORMAT", .description = "Output format: text or json (default: text)" },
        .{ .name = "--config", .short = "-c", .value_name = "PATH", .description = "Config file path (default: zlint.toml)" },
        .{ .name = "--root", .short = "-r", .value_name = "PATH", .description = "Project root path (default: .)" },
        .{ .name = "--no-compile-check", .description = "Skip compile check" },
        .{ .name = "--no-build", .description = "Skip auto zig build if build.zig exists" },
        .{ .name = "--quiet", .short = "-q", .description = "Suppress output" },
        .{ .name = "--help", .short = "-h", .description = "Show this help" },
    },
};

/// Print help text
fn printHelp() !void {
    const help =
        \\zlint - Zig project linter
        \\
        \\Usage: zlint [options]
        \\
        \\Options:
        \\  -f, --format <FORMAT>   Output format: text or json (default: text)
        \\  -c, --config <PATH>     Config file path (default: zlint.toml)
        \\  -r, --root <PATH>       Project root path (default: .)
        \\      --no-compile-check  Skip compile check
        \\      --no-build          Skip auto zig build if build.zig exists
        \\  -q, --quiet             Suppress output
        \\  -h, --help              Show this help
        \\
        \\Exit codes:
        \\  0  No diagnostics or only warnings
        \\  1  At least one error
        \\  2  Compile check failed
        \\  3  Config or CLI error
        \\  4  Build failed
        \\
    ;
    std.debug.print("{s}", .{help});
}

/// Parse command line arguments using zcli
pub fn parseArgs(args: []const []const u8) !Options {
    // Check for help first
    if (zcli.args.hasFlag(args, "--help") or zcli.args.hasFlag(args, "-h")) {
        try printHelp();
        std.process.exit(0);
    }

    var options = Options{};

    // Parse single file
    if (zcli.args.flagValue(args, "--file")) |value| {
        options.file = value;
    }

    // Parse format
    if (zcli.args.flagValue(args, "--format") orelse zcli.args.flagValue(args, "-f")) |value| {
        if (std.mem.eql(u8, value, "text")) {
            options.format = .text;
        } else if (std.mem.eql(u8, value, "json")) {
            options.format = .json;
        } else {
            return error.InvalidFormat;
        }
    }

    // Parse config path
    if (zcli.args.flagValue(args, "--config") orelse zcli.args.flagValue(args, "-c")) |value| {
        options.config_path = value;
    }

    // Parse root path
    if (zcli.args.flagValue(args, "--root") orelse zcli.args.flagValue(args, "-r")) |value| {
        options.root_path = value;
    }

    // Parse flags
    options.no_compile_check = zcli.args.hasFlag(args, "--no-compile-check");
    options.no_build = zcli.args.hasFlag(args, "--no-build");
    options.quiet = zcli.args.hasFlag(args, "--quiet") or zcli.args.hasFlag(args, "-q");

    return options;
}

/// Exit codes as per PLAN.md
pub const ExitCode = enum(u8) {
    ok = 0,
    has_errors = 1,
    compile_failed = 2,
    config_error = 3,
    build_failed = 4,
};

/// Log level for styled output
pub const LogLevel = enum {
    error_level,
    warning_level,
    info_level,
    success_level,
};

/// Generic styled print function
fn printStyled(writer: anytype, level: LogLevel, comptime fmt: []const u8, args: anytype) !void {
    const style: zcli.color.Style = switch (level) {
        .error_level => .title,
        .warning_level => .flag,
        .info_level => .heading,
        .success_level => .command,
    };
    const prefix = switch (level) {
        .error_level => "error: ",
        .warning_level => "warning: ",
        .info_level => "info: ",
        .success_level => "success: ",
    };

    try zcli.color.writeStyled(writer, true, style, prefix);
    try writer.print(fmt, args);
    try writer.writeByte('\n');
}

/// Print styled error message
pub fn printError(writer: anytype, comptime fmt: []const u8, args: anytype) !void {
    try printStyled(writer, .error_level, fmt, args);
}

/// Print styled warning message
pub fn printWarning(writer: anytype, comptime fmt: []const u8, args: anytype) !void {
    try printStyled(writer, .warning_level, fmt, args);
}

/// Print styled info message
pub fn printInfo(writer: anytype, comptime fmt: []const u8, args: anytype) !void {
    try printStyled(writer, .info_level, fmt, args);
}

/// Print styled success message
pub fn printSuccess(writer: anytype, comptime fmt: []const u8, args: anytype) !void {
    try printStyled(writer, .success_level, fmt, args);
}
