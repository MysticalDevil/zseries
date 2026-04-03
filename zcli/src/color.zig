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

pub fn writeStyled(writer: anytype, use_color: bool, style: Style, text: []const u8) !void {
    if (!use_color or style == .plain) {
        try writer.writeAll(text);
        return;
    }
    try writer.writeAll(prefix(style));
    try writer.writeAll(text);
    try writer.writeAll("\x1b[0m");
}
