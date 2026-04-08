const std = @import("std");
const Terminal = std.Io.Terminal;

pub const Style = enum {
    plain,
    title,
    heading,
    command,
    flag,
    value,
    muted,
    accent,
};

pub fn enabled(env: *const std.process.Environ.Map) bool {
    if (env.get("NO_COLOR")) |value| return value.len == 0;
    if (env.get("CLICOLOR_FORCE")) |value| return value.len != 0;
    return true;
}

fn terminalColor(style: Style) ?Terminal.Color {
    return switch (style) {
        .plain => null,
        .title => .bright_cyan,
        .heading => .bright_blue,
        .command => .bright_green,
        .flag => .bright_yellow,
        .value => .cyan,
        .muted => .dim,
        .accent => .bright_magenta,
    };
}

fn ansiCode(color: Terminal.Color) []const u8 {
    return switch (color) {
        .black => "\x1b[30m",
        .red => "\x1b[31m",
        .green => "\x1b[32m",
        .yellow => "\x1b[33m",
        .blue => "\x1b[34m",
        .magenta => "\x1b[35m",
        .cyan => "\x1b[36m",
        .white => "\x1b[37m",
        .bright_black => "\x1b[90m",
        .bright_red => "\x1b[91m",
        .bright_green => "\x1b[92m",
        .bright_yellow => "\x1b[93m",
        .bright_blue => "\x1b[94m",
        .bright_magenta => "\x1b[95m",
        .bright_cyan => "\x1b[96m",
        .bright_white => "\x1b[97m",
        .dim => "\x1b[2m",
        .bold => "\x1b[1m",
        .reset => "\x1b[0m",
    };
}

pub fn writeStyled(writer: *std.Io.Writer, use_color: bool, style: Style, text: []const u8) !void {
    const color = terminalColor(style) orelse {
        try writer.writeAll(text);
        return;
    };
    if (!use_color) {
        try writer.writeAll(text);
        return;
    }
    try writer.writeAll(ansiCode(color));
    try writer.writeAll(text);
    try writer.writeAll(ansiCode(.reset));
}

test "enabled respects NO_COLOR" {
    const testing = std.testing;

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var map = std.process.Environ.Map.init(arena.allocator());
    defer map.deinit(arena.allocator());

    try testing.expect(enabled(&map));
    try map.put(arena.allocator(), "NO_COLOR", "1");
    try testing.expect(!enabled(&map));
}

test "writeStyled writes plain text without color" {
    const testing = std.testing;
    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    try writeStyled(&out.writer, false, .title, "ztotp");
    const text = try out.toOwnedSlice();
    defer testing.allocator.free(text);
    try testing.expectEqualStrings("ztotp", text);
}

test "writeStyled wraps text with ansi color" {
    const testing = std.testing;
    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    try writeStyled(&out.writer, true, .heading, "Usage");
    const text = try out.toOwnedSlice();
    defer testing.allocator.free(text);
    try testing.expect(std.mem.startsWith(u8, text, "\x1b[1;94m"));
    try testing.expect(std.mem.endsWith(u8, text, "\x1b[0m"));
    try testing.expect(std.mem.indexOf(u8, text, "Usage") != null);
}
