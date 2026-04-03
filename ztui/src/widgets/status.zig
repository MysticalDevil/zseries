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

fn cellText(buf: *const buffer.Buffer, x: usize, y: usize) []const u8 {
    const cell = buf.cells[y * buf.width + x];
    return cell.bytes[0..cell.len];
}

test "StatusBar draws segments with separators" {
    const testing = std.testing;

    var bar = StatusBar.init(.{ .width = 14, .style_id = .heading });
    defer bar.deinit(testing.allocator);
    try bar.addSegment(testing.allocator, "ONE");
    try bar.addSegment(testing.allocator, "TWO");

    var buf = try buffer.Buffer.init(testing.allocator, 14, 1);
    defer buf.deinit();

    bar.draw(&buf);

    try testing.expectEqualStrings("O", cellText(&buf, 0, 0));
    try testing.expectEqualStrings("E", cellText(&buf, 2, 0));
    try testing.expectEqualStrings("│", cellText(&buf, 4, 0));
    try testing.expectEqualStrings("T", cellText(&buf, 5, 0));
    try testing.expectEqualStrings("O", cellText(&buf, 7, 0));
}

test "StatusBar stops before overflowing width" {
    const testing = std.testing;

    var bar = StatusBar.init(.{ .width = 6, .style_id = .heading });
    defer bar.deinit(testing.allocator);
    try bar.addSegment(testing.allocator, "abc");
    try bar.addSegment(testing.allocator, "toolong");

    var buf = try buffer.Buffer.init(testing.allocator, 6, 1);
    defer buf.deinit();

    bar.draw(&buf);

    try testing.expectEqualStrings("a", cellText(&buf, 0, 0));
    try testing.expectEqualStrings("c", cellText(&buf, 2, 0));
    try testing.expectEqualStrings("│", cellText(&buf, 4, 0));
    try testing.expectEqualStrings(" ", cellText(&buf, 5, 0));
}

test "StatusBar clear removes all segments" {
    const testing = std.testing;

    var bar = StatusBar.init(.{});
    defer bar.deinit(testing.allocator);
    try bar.addSegment(testing.allocator, "left");
    try bar.addSegment(testing.allocator, "right");

    bar.clear(testing.allocator);

    try testing.expectEqual(@as(usize, 0), bar.segments.items.len);
}

test "drawTextLine supports left center and right alignment" {
    const testing = std.testing;

    var buf = try buffer.Buffer.init(testing.allocator, 7, 3);
    defer buf.deinit();

    drawTextLine(&buf, 0, 7, "abc", .left, .normal);
    drawTextLine(&buf, 1, 7, "abc", .center, .normal);
    drawTextLine(&buf, 2, 7, "abc", .right, .normal);

    try testing.expectEqualStrings("a", cellText(&buf, 0, 0));
    try testing.expectEqualStrings("a", cellText(&buf, 2, 1));
    try testing.expectEqualStrings("c", cellText(&buf, 4, 1));
    try testing.expectEqualStrings("a", cellText(&buf, 4, 2));
    try testing.expectEqualStrings("c", cellText(&buf, 6, 2));
}

test "drawTextLine clips long text" {
    const testing = std.testing;

    var buf = try buffer.Buffer.init(testing.allocator, 4, 1);
    defer buf.deinit();

    drawTextLine(&buf, 0, 4, "status-long", .left, .normal);

    try testing.expectEqualStrings("s", cellText(&buf, 0, 0));
    try testing.expectEqualStrings("…", cellText(&buf, 3, 0));
}

test "drawDivider fills full width with requested rune" {
    const testing = std.testing;

    var buf = try buffer.Buffer.init(testing.allocator, 5, 1);
    defer buf.deinit();

    drawDivider(&buf, 0, 5, '─', .muted);

    for (0..5) |x| {
        try testing.expectEqualStrings("─", cellText(&buf, x, 0));
    }
}
