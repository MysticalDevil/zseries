const std = @import("std");
const style = @import("style.zig");

pub const Cell = struct {
    bytes: [4]u8 = [_]u8{' '} ** 4,
    len: u8 = 1,
    style_id: style.StyleId = .normal,
};

pub const Buffer = struct {
    allocator: std.mem.Allocator,
    width: usize,
    height: usize,
    cells: []Cell,

    pub fn init(allocator: std.mem.Allocator, width: usize, height: usize) !Buffer {
        const cells = try allocator.alloc(Cell, width * height);
        var buffer = Buffer{ .allocator = allocator, .width = width, .height = height, .cells = cells };
        buffer.clear(.normal);
        return buffer;
    }

    pub fn deinit(self: *Buffer) void {
        self.allocator.free(self.cells);
    }

    pub fn clear(self: *Buffer, style_id: style.StyleId) void {
        for (self.cells) |*cell| cell.* = .{ .style_id = style_id };
    }

    fn index(self: Buffer, x: usize, y: usize) usize {
        return y * self.width + x;
    }

    pub fn putRune(self: *Buffer, x: usize, y: usize, rune: u21, style_id: style.StyleId) void {
        if (x >= self.width or y >= self.height) return;
        var encoded: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(rune, &encoded) catch return;
        self.cells[self.index(x, y)] = .{ .bytes = encoded, .len = @intCast(len), .style_id = style_id };
    }

    pub fn putText(self: *Buffer, x: usize, y: usize, text: []const u8, style_id: style.StyleId) void {
        var column = x;
        var iter = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
        while (iter.nextCodepoint()) |rune| {
            if (column >= self.width) break;
            self.putRune(column, y, rune, style_id);
            column += 1;
        }
    }

    pub fn putTextClipped(self: *Buffer, x: usize, y: usize, width: usize, text: []const u8, style_id: style.StyleId) void {
        var column: usize = 0;
        var iter = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
        while (iter.nextCodepoint()) |rune| {
            if (column >= width) break;
            self.putRune(x + column, y, rune, style_id);
            column += 1;
        }
        if (column == width and text.len > width and width > 0) self.putRune(x + width - 1, y, '…', style_id);
    }

    pub fn fillRect(self: *Buffer, x: usize, y: usize, width: usize, height: usize, rune: u21, style_id: style.StyleId) void {
        for (0..height) |dy| for (0..width) |dx| self.putRune(x + dx, y + dy, rune, style_id);
    }

    pub fn renderAlloc(self: Buffer) ![]u8 {
        var out: std.Io.Writer.Allocating = .init(self.allocator);
        errdefer out.deinit();
        const writer = &out.writer;
        var last_style: ?style.StyleId = null;
        for (0..self.height) |y| {
            for (0..self.width) |x| {
                const cell = self.cells[self.index(x, y)];
                if (last_style == null or last_style.? != cell.style_id) {
                    try writer.writeAll(style.ansi(cell.style_id));
                    last_style = cell.style_id;
                }
                try writer.writeAll(cell.bytes[0..cell.len]);
            }
            try writer.writeAll(style.reset);
            last_style = null;
            if (y + 1 < self.height) try writer.writeByte('\n');
        }
        return out.toOwnedSlice();
    }
};

test "buffer fillRect fills area" {
    const testing = std.testing;
    var buf = try Buffer.init(testing.allocator, 4, 2);
    defer buf.deinit();
    buf.fillRect(1, 0, 2, 2, '█', .code);
    const rendered = try buf.renderAlloc();
    defer testing.allocator.free(rendered);
    try testing.expect(std.mem.indexOf(u8, rendered, "██") != null);
}

test "putTextClipped adds ellipsis when clipped" {
    const testing = std.testing;
    var buf = try Buffer.init(testing.allocator, 5, 1);
    defer buf.deinit();
    buf.putTextClipped(0, 0, 4, "Internal", .normal);
    const rendered = try buf.renderAlloc();
    defer testing.allocator.free(rendered);
    try testing.expect(std.mem.indexOf(u8, rendered, "Int…") != null);
}
