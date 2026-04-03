const std = @import("std");

pub fn hasFlag(args: []const []const u8, flag: []const u8) bool {
    for (args) |arg| {
        if (std.mem.eql(u8, arg, flag)) return true;
    }
    return false;
}

pub fn flagValue(args: []const []const u8, flag: []const u8) ?[]const u8 {
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], flag)) {
            if (i + 1 < args.len) return args[i + 1];
            return null;
        }
    }
    return null;
}

pub fn flagValueInt(args: []const []const u8, flag: []const u8, default: anytype) @TypeOf(default) {
    const value = flagValue(args, flag) orelse return default;
    return std.fmt.parseInt(@TypeOf(default), value, 10) catch return default;
}

pub fn repeatedFlags(allocator: std.mem.Allocator, args: []const []const u8, flag: []const u8) ![]const []const u8 {
    var list = std.ArrayList([]const u8).empty;
    defer list.deinit(allocator);
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], flag) and i + 1 < args.len) {
            try list.append(allocator, try allocator.dupe(u8, args[i + 1]));
        }
    }
    return list.toOwnedSlice(allocator);
}

pub fn positionalArg(args: []const []const u8, index: usize) ?[]const u8 {
    var count: usize = 0;
    for (args) |arg| {
        if (std.mem.startsWith(u8, arg, "-")) continue;
        if (count == index) return arg;
        count += 1;
    }
    return null;
}

pub const Subcommand = struct {
    name: []const u8,
    handler: *const fn (allocator: std.mem.Allocator, io: std.Io, env: *const std.process.Environ.Map, args: []const []const u8) anyerror!void,
};

pub fn routeSubcommand(args: []const []const u8, commands: []const Subcommand, default: ?*const fn (allocator: std.mem.Allocator, io: std.Io, env: *const std.process.Environ.Map, args: []const []const u8) anyerror!void) ?*const fn (allocator: std.mem.Allocator, io: std.Io, env: *const std.process.Environ.Map, args: []const []const u8) anyerror!void {
    if (args.len == 0) {
        if (default) |handler| return handler;
        return null;
    }
    const command = args[0];
    for (commands) |cmd| {
        if (std.mem.eql(u8, command, cmd.name)) return cmd.handler;
    }
    return null;
}

test "hasFlag detects presence" {
    const args = [_][]const u8{ "--verbose", "file.txt" };
    try std.testing.expect(hasFlag(&args, "--verbose"));
    try std.testing.expect(!hasFlag(&args, "--quiet"));
}

test "flagValue extracts value" {
    const args = [_][]const u8{ "--name", "value", "--other", "data" };
    try std.testing.expectEqualStrings("value", flagValue(&args, "--name").?);
    try std.testing.expectEqualStrings("data", flagValue(&args, "--other").?);
    try std.testing.expect(flagValue(&args, "--missing") == null);
}

test "flagValueInt parses integers" {
    const args = [_][]const u8{ "--count", "42", "--port", "8080" };
    try std.testing.expectEqual(@as(u32, 42), flagValueInt(&args, "--count", @as(u32, 0)));
    try std.testing.expectEqual(@as(u16, 8080), flagValueInt(&args, "--port", @as(u16, 0)));
    try std.testing.expectEqual(@as(i32, -1), flagValueInt(&args, "--missing", @as(i32, -1)));
}

test "positionalArg skips flags" {
    const args = [_][]const u8{ "--flag", "value", "file1.txt", "-v", "file2.txt" };
    try std.testing.expectEqualStrings("value", positionalArg(&args, 0).?);
    try std.testing.expectEqualStrings("file1.txt", positionalArg(&args, 1).?);
    try std.testing.expectEqualStrings("file2.txt", positionalArg(&args, 2).?);
    try std.testing.expect(positionalArg(&args, 3) == null);
}
