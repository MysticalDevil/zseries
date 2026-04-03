const std = @import("std");
const buffer = @import("../buffer.zig");
const style = @import("../style.zig");

pub const StatusBarConfig = struct {
    x: usize = 0,
    y: usize = 0,
    width: usize = 80,
    style_id: style.StyleId = .heading,
};

pub const StatusBar = struct {
    config: StatusBarConfig,
    segments: std.ArrayList([]const u8),

    pub fn init(config: StatusBarConfig) StatusBar {
        return .{
            .config = config,
            .segments = .empty,
        };
    }

    pub fn deinit(self: *StatusBar, allocator: std.mem.Allocator) void {
        for (self.segments.items) |seg| allocator.free(seg);
        self.segments.deinit(allocator);
    }

    pub fn addSegment(self: *StatusBar, allocator: std.mem.Allocator, text: []const u8) !void {
        try self.segments.append(allocator, try allocator.dupe(u8, text));
    }

    pub fn draw(self: StatusBar, buf: *buffer.Buffer) void {
        buf.fillRect(self.config.x, self.config.y, self.config.width, 1, ' ', self.config.style_id);
        var x: usize = self.config.x;
        for (self.segments.items) |seg| {
            if (x + seg.len > self.config.width) break;
            buf.putTextClipped(x, self.config.y, self.config.width - x, seg, self.config.style_id);
            x += seg.len + 1;
            if (x < self.config.width) {
                buf.putRune(x, self.config.y, '│', self.config.style_id);
                x += 1;
            }
        }
    }

    pub fn clear(self: *StatusBar, allocator: std.mem.Allocator) void {
        for (self.segments.items) |seg| allocator.free(seg);
        self.segments.clearRetainingCapacity();
    }
};

pub const TextAlign = enum {
    left,
    center,
    right,
};

pub fn drawTextLine(buf: *buffer.Buffer, y: usize, width: usize, text: []const u8, text_align: TextAlign, style_id: style.StyleId) void {
    const x = switch (text_align) {
        .left => 0,
        .center => if (text.len < width) (width - text.len) / 2 else 0,
        .right => if (text.len < width) width - text.len else 0,
    };
    buf.putTextClipped(x, y, width, text, style_id);
}

pub fn drawDivider(buf: *buffer.Buffer, y: usize, width: usize, char: u21, style_id: style.StyleId) void {
    buf.fillRect(0, y, width, 1, char, style_id);
}
