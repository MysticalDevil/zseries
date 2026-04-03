const std = @import("std");

pub const Level = enum(u8) {
    trace,
    debug,
    info,
    warn,
    err,

    pub fn asString(self: Level) []const u8 {
        return switch (self) {
            .trace => "TRACE",
            .debug => "DEBUG",
            .info => "INFO",
            .warn => "WARN",
            .err => "ERROR",
        };
    }

    pub fn fromString(text: []const u8) ?Level {
        if (std.ascii.eqlIgnoreCase(text, "trace")) return .trace;
        if (std.ascii.eqlIgnoreCase(text, "debug")) return .debug;
        if (std.ascii.eqlIgnoreCase(text, "info")) return .info;
        if (std.ascii.eqlIgnoreCase(text, "warn")) return .warn;
        if (std.ascii.eqlIgnoreCase(text, "error")) return .err;
        return null;
    }
};

test "level parsing and display" {
    const testing = std.testing;
    try testing.expectEqual(Level.trace, Level.fromString("trace").?);
    try testing.expectEqual(Level.err, Level.fromString("ERROR").?);
    try testing.expectEqualStrings("WARN", Level.warn.asString());
}
