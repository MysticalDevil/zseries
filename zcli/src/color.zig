const std = @import("std");

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
    return env.get("NO_COLOR") == null;
}

fn prefix(style: Style) []const u8 {
    return switch (style) {
        .plain => "",
        .title => "\x1b[1;96m",
        .heading => "\x1b[1;94m",
        .command => "\x1b[1;92m",
        .flag => "\x1b[1;93m",
        .value => "\x1b[36m",
        .muted => "\x1b[2;37m",
        .accent => "\x1b[1;95m",
    };
}

pub fn writeStyled(writer: *std.Io.Writer, use_color: bool, style: Style, text: []const u8) !void {
    if (!use_color or style == .plain) {
        try writer.writeAll(text);
        return;
    }
    try writer.writeAll(prefix(style));
    try writer.writeAll(text);
    try writer.writeAll("\x1b[0m");
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
