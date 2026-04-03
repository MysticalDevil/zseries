const std = @import("std");

fn writeAll(fd: std.posix.fd_t, bytes: []const u8) !void {
    if (@import("builtin").os.tag != .linux) return error.UnsupportedPlatform;
    const linux = std.os.linux;
    var start: usize = 0;
    while (start < bytes.len) {
        const rc = linux.write(fd, bytes[start..].ptr, bytes[start..].len);
        switch (linux.errno(rc)) {
            .SUCCESS => start += rc,
            .INTR => continue,
            else => return error.WriteFailed,
        }
    }
}

pub fn writeStdout(bytes: []const u8) !void {
    try writeAll(std.posix.STDOUT_FILENO, bytes);
}
pub fn enterScreen() !void {
    try writeAll(std.posix.STDOUT_FILENO, "\x1b[?1049h\x1b[?25l\x1b[2J\x1b[H");
}
pub fn restoreScreen() !void {
    try writeAll(std.posix.STDOUT_FILENO, "\x1b[?25h\x1b[?1049l");
}

test "terminal helper symbols are available" {
    const testing = std.testing;
    try testing.expect(@TypeOf(writeStdout) == fn ([]const u8) anyerror!void);
    try testing.expect(@TypeOf(enterScreen) == fn () anyerror!void);
    try testing.expect(@TypeOf(restoreScreen) == fn () anyerror!void);
}
