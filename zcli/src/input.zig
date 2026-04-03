const std = @import("std");

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
        const parsed = std.fmt.parseInt(usize, line, 10) catch {
            std.debug.print("Please enter a number between 1 and {d}.\n", .{count});
            continue;
        };
        if (parsed == 0 or parsed > count) {
            std.debug.print("Please enter a number between 1 and {d}.\n", .{count});
            continue;
        }
        return parsed - 1;
    }
}

pub fn confirm(allocator: std.mem.Allocator, io: std.Io, prompt: []const u8, default: bool) !bool {
    while (true) {
        const line = try promptLine(allocator, io, prompt);
        defer allocator.free(line);
        const trimmed = std.mem.trim(u8, line, " \t\r\n");
        if (trimmed.len == 0) return default;
        if (std.ascii.eqlIgnoreCase(trimmed, "y") or std.ascii.eqlIgnoreCase(trimmed, "yes")) return true;
        if (std.ascii.eqlIgnoreCase(trimmed, "n") or std.ascii.eqlIgnoreCase(trimmed, "no")) return false;
        std.debug.print("Please enter y or n.\n", .{});
    }
}

pub fn selectMultiple(allocator: std.mem.Allocator, io: std.Io, count: usize, prompt: []const u8) ![]const usize {
    var selected = std.ArrayList(usize).empty;
    errdefer selected.deinit(allocator);

    while (true) {
        const line = try promptLine(allocator, io, prompt);
        defer allocator.free(line);
        const trimmed = std.mem.trim(u8, line, " \t\r\n");

        if (trimmed.len == 0) {
            std.debug.print("Please enter one or more numbers separated by commas.\n", .{});
            continue;
        }

        var valid = true;
        var iter = std.mem.splitAny(u8, trimmed, ",");
        while (iter.next()) |part| {
            const num_str = std.mem.trim(u8, part, " \t");
            const parsed = std.fmt.parseInt(usize, num_str, 10) catch {
                valid = false;
                break;
            };
            if (parsed == 0 or parsed > count) {
                valid = false;
                break;
            }
            try selected.append(allocator, parsed - 1);
        }

        if (valid and selected.items.len > 0) {
            return selected.toOwnedSlice(allocator);
        }

        std.debug.print("Please enter numbers between 1 and {d}, separated by commas.\n", .{count});
        selected.clearRetainingCapacity();
    }
}
