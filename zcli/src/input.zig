const std = @import("std");

const ParseError = error{InvalidInput};

pub fn promptLine(allocator: std.mem.Allocator, io: std.Io, prompt: []const u8) ![]const u8 {
    std.debug.print("{s}", .{prompt});
    var buffer: [1024]u8 = undefined;
    var reader = std.Io.File.stdin().reader(io, &buffer);
    const line = (try reader.interface.takeDelimiter('\n')) orelse return error.EndOfStream;
    return try allocator.dupe(u8, std.mem.trim(u8, line, "\r"));
}

fn canHidePassword() bool {
    const term = std.posix.tcgetattr(std.posix.STDIN_FILENO) catch return false;
    return term.lflag.ECHO or !term.lflag.ECHO;
}

pub fn promptPassword(allocator: std.mem.Allocator, io: std.Io, prompt: []const u8) ![]const u8 {
    if (!canHidePassword()) return promptLine(allocator, io, prompt);

    const fd = std.posix.STDIN_FILENO;
    const original = try std.posix.tcgetattr(fd);
    var hidden = original;
    hidden.lflag.ECHO = false;
    try std.posix.tcsetattr(fd, .FLUSH, hidden);
    defer std.posix.tcsetattr(fd, .FLUSH, original) catch {};

    std.debug.print("{s}", .{prompt});
    const value = try promptLine(allocator, io, "");
    std.debug.print("\n", .{});
    return value;
}

pub fn chooseIndex(allocator: std.mem.Allocator, io: std.Io, count: usize, prompt: []const u8) !usize {
    while (true) {
        const line = try promptLine(allocator, io, prompt);
        defer allocator.free(line);
        const parsed = parseChoiceIndex(line, count) catch {
            std.debug.print("Please enter a number between 1 and {d}.\n", .{count});
            continue;
        };
        return parsed;
    }
}

pub fn confirm(allocator: std.mem.Allocator, io: std.Io, prompt: []const u8, default: bool) !bool {
    while (true) {
        const line = try promptLine(allocator, io, prompt);
        defer allocator.free(line);
        return parseConfirm(line, default) catch {
            std.debug.print("Please enter y or n.\n", .{});
            continue;
        };
    }
}

pub fn selectMultiple(allocator: std.mem.Allocator, io: std.Io, count: usize, prompt: []const u8) ![]const usize {
    while (true) {
        const line = try promptLine(allocator, io, prompt);
        defer allocator.free(line);
        return parseMultipleSelection(allocator, line, count) catch {
            std.debug.print("Please enter numbers between 1 and {d}, separated by commas.\n", .{count});
            continue;
        };
    }
}

fn parseChoiceIndex(line: []const u8, count: usize) ParseError!usize {
    const trimmed = std.mem.trim(u8, line, " \t\r\n");
    const parsed = std.fmt.parseInt(usize, trimmed, 10) catch return error.InvalidInput;
    if (parsed == 0 or parsed > count) return error.InvalidInput;
    return parsed - 1;
}

fn parseConfirm(line: []const u8, default: bool) ParseError!bool {
    const trimmed = std.mem.trim(u8, line, " \t\r\n");
    if (trimmed.len == 0) return default;
    if (std.ascii.eqlIgnoreCase(trimmed, "y") or std.ascii.eqlIgnoreCase(trimmed, "yes")) return true;
    if (std.ascii.eqlIgnoreCase(trimmed, "n") or std.ascii.eqlIgnoreCase(trimmed, "no")) return false;
    return error.InvalidInput;
}

fn parseMultipleSelection(allocator: std.mem.Allocator, line: []const u8, count: usize) (ParseError || std.mem.Allocator.Error)![]const usize {
    const trimmed = std.mem.trim(u8, line, " \t\r\n");
    if (trimmed.len == 0) return error.InvalidInput;

    var selected = std.ArrayList(usize).empty;
    errdefer selected.deinit(allocator);

    var iter = std.mem.splitAny(u8, trimmed, ",");
    while (iter.next()) |part| {
        const num_str = std.mem.trim(u8, part, " \t");
        const parsed = std.fmt.parseInt(usize, num_str, 10) catch return error.InvalidInput;
        if (parsed == 0 or parsed > count) return error.InvalidInput;
        try selected.append(allocator, parsed - 1);
    }

    if (selected.items.len == 0) return error.InvalidInput;
    return selected.toOwnedSlice(allocator);
}

test "parseChoiceIndex accepts one-based values" {
    try std.testing.expectEqual(@as(usize, 0), try parseChoiceIndex("1", 3));
    try std.testing.expectEqual(@as(usize, 2), try parseChoiceIndex(" 3 \n", 3));
}

test "parseChoiceIndex rejects invalid values" {
    try std.testing.expectError(error.InvalidInput, parseChoiceIndex("0", 3));
    try std.testing.expectError(error.InvalidInput, parseChoiceIndex("4", 3));
    try std.testing.expectError(error.InvalidInput, parseChoiceIndex("abc", 3));
}

test "parseConfirm handles defaults and common answers" {
    try std.testing.expectEqual(true, try parseConfirm("", true));
    try std.testing.expectEqual(false, try parseConfirm("", false));
    try std.testing.expectEqual(true, try parseConfirm("YeS", false));
    try std.testing.expectEqual(false, try parseConfirm(" n ", true));
}

test "parseConfirm rejects invalid answers" {
    try std.testing.expectError(error.InvalidInput, parseConfirm("maybe", true));
}

test "parseMultipleSelection parses comma-separated indexes" {
    const selected = try parseMultipleSelection(std.testing.allocator, "1, 3,2", 4);
    defer std.testing.allocator.free(selected);

    try std.testing.expectEqualSlices(usize, &.{ 0, 2, 1 }, selected);
}

test "parseMultipleSelection rejects empty or invalid tokens" {
    try std.testing.expectError(error.InvalidInput, parseMultipleSelection(std.testing.allocator, "", 4));
    try std.testing.expectError(error.InvalidInput, parseMultipleSelection(std.testing.allocator, "1,0", 4));
    try std.testing.expectError(error.InvalidInput, parseMultipleSelection(std.testing.allocator, "1,nope", 4));
    try std.testing.expectError(error.InvalidInput, parseMultipleSelection(std.testing.allocator, "5", 4));
}
