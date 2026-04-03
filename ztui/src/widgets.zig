const buffer = @import("buffer.zig");
const style = @import("style.zig");

pub const Rect = struct { x: usize, y: usize, width: usize, height: usize };

pub fn boxSingle(buf: *buffer.Buffer, rect: Rect, border_style: style.StyleId) void {
    if (rect.width < 2 or rect.height < 2) return;
    buf.putRune(rect.x, rect.y, '╭', border_style);
    buf.putRune(rect.x + rect.width - 1, rect.y, '╮', border_style);
    buf.putRune(rect.x, rect.y + rect.height - 1, '╰', border_style);
    buf.putRune(rect.x + rect.width - 1, rect.y + rect.height - 1, '╯', border_style);
    for (1..rect.width - 1) |dx| {
        buf.putRune(rect.x + dx, rect.y, '─', border_style);
        buf.putRune(rect.x + dx, rect.y + rect.height - 1, '─', border_style);
    }
    for (1..rect.height - 1) |dy| {
        buf.putRune(rect.x, rect.y + dy, '│', border_style);
        buf.putRune(rect.x + rect.width - 1, rect.y + dy, '│', border_style);
    }
}

pub fn label(buf: *buffer.Buffer, x: usize, y: usize, width: usize, text: []const u8, text_style: style.StyleId) void {
    buf.putTextClipped(x, y, width, text, text_style);
}

pub fn progressBar(buf: *buffer.Buffer, x: usize, y: usize, width: usize, filled: usize, bar_style: style.StyleId, empty_style: style.StyleId) void {
    for (0..width) |i| if (i < filled) buf.putRune(x + i, y, '█', bar_style) else buf.putRune(x + i, y, '░', empty_style);
}

test "boxSingle draws unicode corners" {
    const testing = @import("std").testing;
    var buf = try buffer.Buffer.init(testing.allocator, 8, 4);
    defer buf.deinit();
    boxSingle(&buf, .{ .x = 0, .y = 0, .width = 8, .height = 4 }, .heading);
    const rendered = try buf.renderAlloc();
    defer testing.allocator.free(rendered);
    try testing.expect(@import("std").mem.indexOf(u8, rendered, "╭") != null);
    try testing.expect(@import("std").mem.indexOf(u8, rendered, "╯") != null);
}

test "progressBar uses filled and empty runes" {
    const testing = @import("std").testing;
    var buf = try buffer.Buffer.init(testing.allocator, 6, 1);
    defer buf.deinit();
    progressBar(&buf, 0, 0, 6, 3, .code, .muted);
    const rendered = try buf.renderAlloc();
    defer testing.allocator.free(rendered);
    try testing.expect(@import("std").mem.indexOf(u8, rendered, "███") != null);
    try testing.expect(@import("std").mem.indexOf(u8, rendered, "░") != null);
}
