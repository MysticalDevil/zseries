const std = @import("std");

pub fn nowMillis(io: std.Io) i64 {
    const ts = std.Io.Clock.Timestamp.now(io, .real);
    return @intCast(@divFloor(ts.raw.nanoseconds, std.time.ns_per_ms));
}
