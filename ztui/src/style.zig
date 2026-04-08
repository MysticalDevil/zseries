const std = @import("std");

pub const reset = "\x1b[0m";
const Terminal = std.Io.Terminal;

pub const StyleId = enum {
    normal,
    title,
    heading,
    code,
    muted,
    accent,
    readonly,
    source,
    badge,
};

pub fn terminalColor(style_id: StyleId) Terminal.Color {
    return switch (style_id) {
        .normal => .reset,
        .title => .bright_cyan,
        .heading => .bright_blue,
        .code => .bright_green,
        .muted => .dim,
        .accent => .bright_magenta,
        .readonly => .bright_yellow,
        .source => .cyan,
        .badge => .bright_white,
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
        .reset => reset,
    };
}

pub fn ansi(style_id: StyleId) []const u8 {
    return switch (style_id) {
        .badge => "\x1b[1;97;44m",
        else => ansiCode(terminalColor(style_id)),
    };
}

test "ansi returns distinct sequences" {
    const testing = @import("std").testing;
    try testing.expectEqualStrings("\x1b[1;96m", ansi(.title));
    try testing.expectEqualStrings("\x1b[1;92m", ansi(.code));
    try testing.expectEqualStrings("\x1b[0m", ansi(.normal));
}
