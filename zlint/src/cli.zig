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

/// Print compact colorful help text
fn printHelp() !void {
    var out: std.Io.Writer.Allocating = .init(std.heap.page_allocator);
    defer out.deinit();
    const writer = &out.writer;

    // Title
    try zcli.color.writeStyled(writer, true, .command, "zlint");
    try writer.writeAll(" - Zig project linter\n\n");

    // Usage
    try zcli.color.writeStyled(writer, true, .heading, "USAGE\n");
    try writer.writeAll("  zlint [options]\n\n");

    // Options
    try zcli.color.writeStyled(writer, true, .heading, "OPTIONS\n");

    try writer.writeAll("  ");
    try zcli.color.writeStyled(writer, true, .flag, "-f, --format");
    try writer.writeAll(" ");
    try zcli.color.writeStyled(writer, true, .value, "<FORMAT>");
    try writer.writeAll("      Output: text or json (default: text)\n");

    try writer.writeAll("  ");
    try zcli.color.writeStyled(writer, true, .flag, "-c, --config");
    try writer.writeAll(" ");
    try zcli.color.writeStyled(writer, true, .value, "<PATH>");
    try writer.writeAll("      Config file (default: zlint.toml)\n");

    try writer.writeAll("  ");
    try zcli.color.writeStyled(writer, true, .flag, "-r, --root");
    try writer.writeAll(" ");
    try zcli.color.writeStyled(writer, true, .value, "<PATH>");
    try writer.writeAll("        Project root (default: .)\n");

    try writer.writeAll("  ");
    try zcli.color.writeStyled(writer, true, .flag, "    --file");
    try writer.writeAll(" ");
    try zcli.color.writeStyled(writer, true, .value, "<PATH>");
    try writer.writeAll("        Lint single file only\n");

    try writer.writeAll("  ");
    try zcli.color.writeStyled(writer, true, .flag, "    --no-compile-check");
    try writer.writeAll("     Skip compile check\n");

    try writer.writeAll("  ");
    try zcli.color.writeStyled(writer, true, .flag, "    --no-build");
    try writer.writeAll("           Skip auto zig build\n");

    try writer.writeAll("  ");
    try zcli.color.writeStyled(writer, true, .flag, "-q, --quiet");
    try writer.writeAll("              Suppress output\n");

    try writer.writeAll("  ");
    try zcli.color.writeStyled(writer, true, .flag, "-h, --help");
    try writer.writeAll("               Show this help\n\n");

    // Exit codes
    try zcli.color.writeStyled(writer, true, .heading, "EXIT CODES\n");
    try writer.writeAll("  0  No issues or only warnings\n");
    try writer.writeAll("  1  At least one error\n");
    try writer.writeAll("  2  Compile check failed\n");
    try writer.writeAll("  3  Config or CLI error\n");
    try writer.writeAll("  4  Build failed\n\n");

    // Examples
    try zcli.color.writeStyled(writer, true, .heading, "EXAMPLES\n");
    try writer.writeAll("  zlint                    Lint current directory\n");
    try writer.writeAll("  zlint -r ./my-project    Lint specific project\n");
    try writer.writeAll("  zlint --file main.zig    Lint single file\n");
    try writer.writeAll("  zlint -f json            Output as JSON\n");

    const help_text = try out.toOwnedSlice();
    defer std.heap.page_allocator.free(help_text);
    std.debug.print("{s}", .{help_text});
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
