const std = @import("std");
const buffer = @import("../buffer.zig");
const style = @import("../style.zig");

pub const ListConfig = struct {
    x: usize = 0,
    y: usize = 0,
    width: usize = 40,
    selected: usize = 0,
    style_normal: style.StyleId = .normal,
    style_selected: style.StyleId = .heading,
};

pub const List = struct {
    config: ListConfig,
    items: []const []const u8,

    pub fn draw(self: List, buf: *buffer.Buffer) void {
        for (self.items, 0..) |item, i| {
            const item_style: style.StyleId = if (i == self.config.selected) self.config.style_selected else self.config.style_normal;
            const prefix: []const u8 = if (i == self.config.selected) "> " else "  ";
            buf.putText(self.config.x, self.config.y + i, prefix, item_style);
            buf.putTextClipped(self.config.x + 2, self.config.y + i, self.config.width - 2, item, item_style);
        }
    }

    pub fn up(self: *List) void {
        if (self.config.selected > 0) self.config.selected -= 1;
    }

    pub fn down(self: *List) void {
        if (self.config.selected + 1 < self.items.len) self.config.selected += 1;
    }

    pub fn selected(self: List) ?[]const u8 {
        if (self.items.len == 0) return null;
        return self.items[self.config.selected];
    }
};

test "List draws selected item with style" {
    const testing = std.testing;
    var buf = try buffer.Buffer.init(testing.allocator, 20, 3);
    defer buf.deinit();

    const items = [_][]const u8{ "one", "two", "three" };
    var list = List{ .config = .{ .selected = 1 }, .items = &items };
    list.draw(&buf);

    const text = try buf.renderAlloc();
    defer testing.allocator.free(text);
    try testing.expect(std.mem.indexOf(u8, text, "> two") != null);
}
