const std = @import("std");

pub const Level = enum(u8) {
    trace,
    debug,
    info,
    warn,
    err,

    pub fn stdLevel(self: Level) ?std.log.Level {
        return switch (self) {
            .trace => null,
            .debug => .debug,
            .info => .info,
            .warn => .warn,
            .err => .err,
        };
    }

    pub fn fromStdLevel(level: std.log.Level) Level {
        return switch (level) {
            .debug => .debug,
            .info => .info,
            .warn => .warn,
            .err => .err,
        };
    }

    pub fn asString(self: Level) []const u8 {
        if (self.stdLevel()) |level| {
            return switch (level) {
                .debug => "DEBUG",
                .info => "INFO",
                .warn => "WARN",
                .err => "ERROR",
            };
        }
        return switch (self) {
            .trace => "TRACE",
            else => unreachable,
        };
    }

    pub fn fromString(text: []const u8) ?Level {
        if (std.ascii.eqlIgnoreCase(text, "trace")) return .trace;
        if (std.ascii.eqlIgnoreCase(text, "debug")) return .debug;
        if (std.ascii.eqlIgnoreCase(text, "info")) return .info;
        if (std.ascii.eqlIgnoreCase(text, "warn")) return .warn;
        if (std.ascii.eqlIgnoreCase(text, "warning")) return .warn;
        if (std.ascii.eqlIgnoreCase(text, "error")) return .err;
        return null;
    }
};

test "level parsing and display" {
    const testing = std.testing;
    try testing.expectEqual(Level.trace, Level.fromString("trace").?);
    try testing.expectEqual(Level.err, Level.fromString("ERROR").?);
    try testing.expectEqual(Level.warn, Level.fromString("warning").?);
    try testing.expectEqualStrings("WARN", Level.warn.asString());
    try testing.expectEqual(@as(?std.log.Level, .info), Level.info.stdLevel());
    try testing.expectEqual(Level.warn, Level.fromStdLevel(.warn));
}
