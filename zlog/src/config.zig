const std = @import("std");
const level = @import("level.zig");

pub const Config = struct {
    level_value: level.Level = .info,
    file_path: ?[]const u8 = null,
    stdout_enabled: bool = false,
    stderr_enabled: bool = false,
};

pub fn fromEnv(allocator: std.mem.Allocator, env: *const std.process.Environ.Map) !Config {
    var cfg = Config{};
    if (env.get("ZLOG_LEVEL")) |value| {
        cfg.level_value = level.Level.fromString(value) orelse .info;
    }
    if (env.get("ZLOG_FILE")) |value| {
        cfg.file_path = try allocator.dupe(u8, value);
    }
    if (env.get("ZLOG_STDOUT")) |value| {
        cfg.stdout_enabled = std.mem.eql(u8, value, "1") or std.ascii.eqlIgnoreCase(value, "true");
    }
    if (env.get("ZLOG_STDERR")) |value| {
        cfg.stderr_enabled = std.mem.eql(u8, value, "1") or std.ascii.eqlIgnoreCase(value, "true");
    }
    return cfg;
}

test "config parses environment" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var env = std.process.Environ.Map.init(arena.allocator());
    defer env.deinit(arena.allocator());
    try env.put(arena.allocator(), "ZLOG_LEVEL", "trace");
    try env.put(arena.allocator(), "ZLOG_FILE", "/tmp/test.log");
    try env.put(arena.allocator(), "ZLOG_STDERR", "1");
    const cfg = try fromEnv(arena.allocator(), &env);
    try testing.expectEqual(level.Level.trace, cfg.level_value);
    try testing.expectEqualStrings("/tmp/test.log", cfg.file_path.?);
    try testing.expect(cfg.stderr_enabled);
}

test "config falls back on invalid values and keeps defaults" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var env = std.process.Environ.Map.init(arena.allocator());
    defer env.deinit(arena.allocator());
    try env.put(arena.allocator(), "ZLOG_LEVEL", "verbose-ish");
    try env.put(arena.allocator(), "ZLOG_STDOUT", "TRUE");
    try env.put(arena.allocator(), "ZLOG_STDERR", "0");

    const cfg = try fromEnv(arena.allocator(), &env);

    try testing.expectEqual(level.Level.info, cfg.level_value);
    try testing.expect(cfg.stdout_enabled);
    try testing.expect(!cfg.stderr_enabled);
    try testing.expectEqual(@as(?[]const u8, null), cfg.file_path);
}
