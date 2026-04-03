const std = @import("std");

pub const Event = union(enum) {
    none,
    quit,
    clear_search,
    backspace,
    character: u8,
};

pub const RawMode = struct {
    original: std.posix.termios,

    pub fn enter() !RawMode {
        const original = try std.posix.tcgetattr(std.posix.STDIN_FILENO);
        var raw = original;
        raw.lflag.ECHO = false;
        raw.lflag.ICANON = false;
        raw.lflag.IEXTEN = false;
        raw.iflag.ICRNL = false;
        raw.cc[@intFromEnum(std.posix.V.MIN)] = 0;
        raw.cc[@intFromEnum(std.posix.V.TIME)] = 0;
        try std.posix.tcsetattr(std.posix.STDIN_FILENO, .FLUSH, raw);
        return .{ .original = original };
    }

    pub fn leave(self: RawMode) void {
        std.posix.tcsetattr(std.posix.STDIN_FILENO, .FLUSH, self.original) catch {};
    }
};

pub fn readEvent(timeout_ms: i32) !Event {
    var fds = [_]std.posix.pollfd{.{ .fd = std.posix.STDIN_FILENO, .events = std.posix.POLL.IN, .revents = 0 }};
    const ready = try std.posix.poll(&fds, timeout_ms);
    if (ready == 0 or (fds[0].revents & std.posix.POLL.IN) == 0) return .none;
    var buf: [1]u8 = undefined;
    const read_len = try std.posix.read(std.posix.STDIN_FILENO, &buf);
    if (read_len == 0) return .none;
    const ch = buf[0];
    if (ch == 'q' or ch == 0x03) return .quit;
    if (ch == 0x1b) return .clear_search;
    if (ch == 0x7f or ch == 0x08) return .backspace;
    if (ch == 0x0d or ch == 0x0a) return .none;
    if (ch >= 0x20 and ch <= 0x7e) return .{ .character = ch };
    return .none;
}
