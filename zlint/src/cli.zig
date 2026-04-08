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
    color: ColorMode = .auto,
    no_collapse: bool = false,
    max_per_group: usize = 3,
    context_lines: usize = 1,

    pub const Format = enum {
        text,
        json,
    };

    pub const ColorMode = enum {
        auto,
        always,
        never,
    };
};

/// Print compact colorful help text
fn printHelp(io: std.Io, use_color: bool) !void {
    var buffer: [4096]u8 = undefined;
    var file_writer: std.Io.File.Writer = .init(.stdout(), io, &buffer);
    const writer = &file_writer.interface;

    // Title
    try zcli.color.writeStyled(writer, use_color, .command, "zlint");
    try writer.writeAll(" - Zig project linter\n\n");

    // Usage
    try zcli.color.writeStyled(writer, use_color, .heading, "USAGE\n");
    try writer.writeAll("  zlint [options] [file]\n\n");

    // Options
    try zcli.color.writeStyled(writer, use_color, .heading, "OPTIONS\n");

    try writer.writeAll("  ");
    try zcli.color.writeStyled(writer, use_color, .flag, "[file]");
    try writer.writeAll("                     File to lint (optional)\n");

    try writer.writeAll("  ");
    try zcli.color.writeStyled(writer, use_color, .flag, "-f, --format");
    try writer.writeAll(" ");
    try zcli.color.writeStyled(writer, use_color, .value, "<FORMAT>");
    try writer.writeAll("      Output: text or json (default: text)\n");

    try writer.writeAll("  ");
    try zcli.color.writeStyled(writer, use_color, .flag, "-c, --config");
    try writer.writeAll(" ");
    try zcli.color.writeStyled(writer, use_color, .value, "<PATH>");
    try writer.writeAll("      Config file (default: zlint.toml)\n");

    try writer.writeAll("  ");
    try zcli.color.writeStyled(writer, use_color, .flag, "-r, --root");
    try writer.writeAll(" ");
    try zcli.color.writeStyled(writer, use_color, .value, "<PATH>");
    try writer.writeAll("        Project root (default: .)\n");

    try writer.writeAll("  ");
    try zcli.color.writeStyled(writer, use_color, .flag, "    --no-compile-check");
    try writer.writeAll("     Skip compile check\n");

    try writer.writeAll("  ");
    try zcli.color.writeStyled(writer, use_color, .flag, "    --no-build");
    try writer.writeAll("           Skip auto zig build\n");

    try writer.writeAll("  ");
    try zcli.color.writeStyled(writer, use_color, .flag, "-q, --quiet");
    try writer.writeAll("              Suppress output\n");

    try writer.writeAll("  ");
    try zcli.color.writeStyled(writer, use_color, .flag, "    --color");
    try writer.writeAll(" ");
    try zcli.color.writeStyled(writer, use_color, .value, "<MODE>");
    try writer.writeAll("      Color: auto|always|never (default: auto)\n");

    try writer.writeAll("  ");
    try zcli.color.writeStyled(writer, use_color, .flag, "    --no-collapse");
    try writer.writeAll("       Show all diagnostics without grouping\n");

    try writer.writeAll("  ");
    try zcli.color.writeStyled(writer, use_color, .flag, "    --max-per-group");
    try writer.writeAll(" ");
    try zcli.color.writeStyled(writer, use_color, .value, "<N>");
    try writer.writeAll("   Max diagnostics per group (default: 3)\n");

    try writer.writeAll("  ");
    try zcli.color.writeStyled(writer, use_color, .flag, "    --context-lines");
    try writer.writeAll(" ");
    try zcli.color.writeStyled(writer, use_color, .value, "<N>");
    try writer.writeAll("   Context lines around target (default: 1)\n");

    try writer.writeAll("  ");
    try zcli.color.writeStyled(writer, use_color, .flag, "-h, --help");
    try writer.writeAll("               Show this help\n\n");

    // Exit codes
    try zcli.color.writeStyled(writer, use_color, .heading, "EXIT CODES\n");
    try writer.writeAll("  0  No issues or only warnings\n");
    try writer.writeAll("  1  At least one error\n");
    try writer.writeAll("  2  Compile/build gate failed\n");
    try writer.writeAll("  3  Config or CLI error\n");
    try writer.writeAll("  4  Build failed (strict_exit mode)\n\n");

    // Examples
    try zcli.color.writeStyled(writer, use_color, .heading, "EXAMPLES\n");
    try writer.writeAll("  zlint                    Lint current directory\n");
    try writer.writeAll("  zlint -r ./my-project    Lint specific project\n");
    try writer.writeAll("  zlint main.zig           Lint single file\n");
    try writer.writeAll("  zlint --file main.zig    Lint single file (explicit)\n");
    try writer.writeAll("  zlint -f json            Output as JSON\n");

    try file_writer.flush();
}

/// Parse command line arguments using zcli
pub fn parseArgs(io: std.Io, args: []const []const u8, use_color: bool) !Options {
    // Check for help first
    if (zcli.args.hasFlag(args, "--help") or zcli.args.hasFlag(args, "-h")) {
        try printHelp(io, use_color);
        std.process.exit(0);
    }

    var options = Options{};

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (matchesOption(arg, "--format", "-f")) {
            const value = try takeValue(args, &i, error.InvalidFormat);
            options.format = parseFormat(value) orelse return error.InvalidFormat;
            continue;
        }

        if (matchesOption(arg, "--config", "-c")) {
            options.config_path = try takeValue(args, &i, error.InvalidOption);
            continue;
        }

        if (matchesOption(arg, "--root", "-r")) {
            options.root_path = try takeValue(args, &i, error.InvalidOption);
            continue;
        }

        if (std.mem.eql(u8, arg, "--file")) {
            options.file = try takeValue(args, &i, error.InvalidOption);
            continue;
        }

        if (std.mem.eql(u8, arg, "--no-compile-check")) {
            options.no_compile_check = true;
            continue;
        }

        if (std.mem.eql(u8, arg, "--no-build")) {
            options.no_build = true;
            continue;
        }

        if (std.mem.eql(u8, arg, "--quiet") or std.mem.eql(u8, arg, "-q")) {
            options.quiet = true;
            continue;
        }

        if (std.mem.eql(u8, arg, "--color")) {
            const value = try takeValue(args, &i, error.InvalidOption);
            options.color = std.meta.stringToEnum(Options.ColorMode, value) orelse return error.InvalidOption;
            continue;
        }

        if (std.mem.eql(u8, arg, "--no-collapse")) {
            options.no_collapse = true;
            continue;
        }

        if (std.mem.eql(u8, arg, "--max-per-group") or std.mem.eql(u8, arg, "--context-lines")) {
            const value = try takeValue(args, &i, error.InvalidOption);
            const parsed = std.fmt.parseInt(usize, value, 10) catch return error.InvalidOption;
            if (std.mem.eql(u8, arg, "--max-per-group")) {
                options.max_per_group = parsed;
            } else {
                options.context_lines = parsed;
            }
            continue;
        }

        if (!std.mem.startsWith(u8, arg, "-") and options.file == null) {
            options.file = arg;
            continue;
        }

        return error.InvalidOption;
    }

    return options;
}

fn matchesOption(arg: []const u8, long: []const u8, short: []const u8) bool {
    return std.mem.eql(u8, arg, long) or std.mem.eql(u8, arg, short);
}

fn parseFormat(value: []const u8) ?Options.Format {
    if (std.mem.eql(u8, value, "text")) return .text;
    if (std.mem.eql(u8, value, "json")) return .json;
    return null;
}

fn takeValue(args: []const []const u8, i: *usize, comptime err: anyerror) ![]const u8 {
    if (i.* + 1 >= args.len) return err;
    i.* += 1;
    return args[i.*];
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
    err,
    warning,
    info,
    success,
};

/// Emit a styled message
pub fn emit(writer: *std.Io.Writer, use_color: bool, level: LogLevel, comptime fmt: []const u8, args: anytype) !void {
    const style: zcli.color.Style = switch (level) {
        .err => .title,
        .warning => .flag,
        .info => .heading,
        .success => .command,
    };
    const prefix = switch (level) {
        .err => "error: ",
        .warning => "warning: ",
        .info => "info: ",
        .success => "success: ",
    };

    try zcli.color.writeStyled(writer, use_color, style, prefix);
    try writer.print(fmt, args);
    try writer.writeByte('\n');
}
