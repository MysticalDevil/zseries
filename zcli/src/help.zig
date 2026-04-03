const std = @import("std");
const color = @import("color.zig");

pub const Flag = struct {
    name: []const u8,
    short: ?[]const u8 = null,
    value_name: ?[]const u8 = null,
    description: []const u8,
    required: bool = false,
};

pub const Arg = struct {
    name: []const u8,
    description: []const u8,
    required: bool = true,
};

pub const Command = struct {
    name: []const u8,
    summary: []const u8,
    description: ?[]const u8 = null,
    flags: []const Flag = &.{},
    args: []const Arg = &.{},
    subcommands: []const Command = &.{},
    examples: []const []const u8 = &.{},
};

pub const Options = struct {
    use_color: bool = true,
    prog_name: []const u8 = "program",
};

pub fn writeHelp(writer: *std.Io.Writer, cmd: Command, opts: Options) !void {
    try writeHeader(writer, opts.use_color, opts.prog_name, cmd.name, cmd.summary);

    if (cmd.description) |desc| {
        try writer.writeAll("\n");
        try writer.writeAll(desc);
        try writer.writeAll("\n");
    }

    if (cmd.args.len > 0) {
        try writeSection(writer, opts.use_color, "Arguments");
        for (cmd.args) |arg| {
            try writer.writeAll("  ");
            if (opts.use_color) {
                try color.writeStyled(writer, true, .value, arg.name);
            } else {
                try writer.writeAll(arg.name);
            }
            try writer.writeAll("  ");
            try writer.writeAll(arg.description);
            if (!arg.required) try writer.writeAll(" (optional)");
            try writer.writeAll("\n");
        }
    }

    if (cmd.flags.len > 0) {
        try writeSection(writer, opts.use_color, "Options");
        for (cmd.flags) |flag| {
            try writer.writeAll("  ");
            if (flag.short) |short| {
                if (opts.use_color) {
                    try color.writeStyled(writer, true, .flag, short);
                } else {
                    try writer.writeAll(short);
                }
                try writer.writeAll(", ");
            } else {
                try writer.writeAll("    ");
            }
            if (opts.use_color) {
                try color.writeStyled(writer, true, .flag, flag.name);
            } else {
                try writer.writeAll(flag.name);
            }
            if (flag.value_name) |vn| {
                try writer.writeAll("=");
                try writer.writeAll(vn);
            }
            try writer.writeAll("  ");
            try writer.writeAll(flag.description);
            if (flag.required) try writer.writeAll(" (required)");
            try writer.writeAll("\n");
        }
    }

    if (cmd.subcommands.len > 0) {
        try writeSection(writer, opts.use_color, "Commands");
        for (cmd.subcommands) |sub| {
            try writer.writeAll("  ");
            if (opts.use_color) {
                try color.writeStyled(writer, true, .command, sub.name);
            } else {
                try writer.writeAll(sub.name);
            }
            const name_len = sub.name.len;
            if (name_len < 12) {
                try writer.writeByteNTimes(' ', 12 - name_len);
            }
            try writer.writeAll("  ");
            try writer.writeAll(sub.summary);
            try writer.writeAll("\n");
        }
    }

    if (cmd.examples.len > 0) {
        try writeSection(writer, opts.use_color, "Examples");
        for (cmd.examples) |example| {
            try writer.writeAll("  $ ");
            if (opts.use_color) {
                try color.writeStyled(writer, true, .value, example);
            } else {
                try writer.writeAll(example);
            }
            try writer.writeAll("\n");
        }
    }
}

fn writeHeader(writer: *std.Io.Writer, use_color: bool, prog_name: []const u8, cmd_name: []const u8, summary: []const u8) !void {
    if (use_color) {
        try color.writeStyled(writer, true, .title, prog_name);
    } else {
        try writer.writeAll(prog_name);
    }
    try writer.writeAll(" ");
    if (use_color) {
        try color.writeStyled(writer, true, .command, cmd_name);
    } else {
        try writer.writeAll(cmd_name);
    }
    try writer.writeAll(" — ");
    try writer.writeAll(summary);
    try writer.writeAll("\n\n");
}

fn writeSection(writer: *std.Io.Writer, use_color: bool, name: []const u8) !void {
    if (use_color) {
        try color.writeStyled(writer, true, .heading, name);
    } else {
        try writer.writeAll(name);
    }
    try writer.writeAll(":\n");
}

test "writeHelp generates formatted help" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const cmd = Command{
        .name = "init",
        .summary = "Initialize a new vault",
        .flags = &.{
            .{ .name = "--password", .short = "-p", .value_name = "VALUE", .description = "Master password" },
        },
        .args = &.{
            .{ .name = "path", .description = "Vault path", .required = false },
        },
    };

    var out: std.Io.Writer.Allocating = .init(arena.allocator());
    defer out.deinit();
    try writeHelp(&out.writer, cmd, .{ .use_color = false, .prog_name = "ztotp" });

    const text = try out.toOwnedSlice();
    defer testing.allocator.free(text);
    try testing.expect(std.mem.indexOf(u8, text, "init") != null);
    try testing.expect(std.mem.indexOf(u8, text, "--password") != null);
}
