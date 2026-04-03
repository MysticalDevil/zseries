pub const reset = "\x1b[0m";

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

pub fn ansi(style_id: StyleId) []const u8 {
    return switch (style_id) {
        .normal => reset,
        .title => "\x1b[1;96m",
        .heading => "\x1b[1;94m",
        .code => "\x1b[1;92m",
        .muted => "\x1b[2;37m",
        .accent => "\x1b[1;95m",
        .readonly => "\x1b[1;93m",
        .source => "\x1b[36m",
        .badge => "\x1b[1;97;44m",
    };
}

test "ansi returns distinct sequences" {
    const testing = @import("std").testing;
    try testing.expectEqualStrings("\x1b[1;96m", ansi(.title));
    try testing.expectEqualStrings("\x1b[1;92m", ansi(.code));
    try testing.expectEqualStrings("\x1b[0m", ansi(.normal));
}
