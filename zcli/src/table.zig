const std = @import("std");
const color = @import("color.zig");

pub const Column = struct {
    name: []const u8,
    width: usize = 0,
    align_left: bool = true,
};

pub const TableOptions = struct {
    use_color: bool = true,
    show_header: bool = true,
    padding: usize = 2,
};

pub const Table = struct {
    columns: []const Column,
    options: TableOptions,
    rows: std.ArrayList([]const []const u8),

    pub fn init(columns: []const Column, options: TableOptions) Table {
        return .{
            .columns = columns,
            .options = options,
            .rows = std.ArrayList([]const []const u8).empty,
        };
    }

    pub fn deinit(self: *Table, allocator: std.mem.Allocator) void {
        for (self.rows.items) |row| {
            for (row) |cell| allocator.free(cell);
            allocator.free(row);
        }
        self.rows.deinit(allocator);
    }

    pub fn addRow(self: *Table, allocator: std.mem.Allocator, cells: []const []const u8) !void {
        var row = try allocator.alloc([]const u8, cells.len);
        for (cells, 0..) |cell, i| {
            row[i] = try allocator.dupe(u8, cell);
        }
        try self.rows.append(allocator, row);
    }

    pub fn render(self: *const Table, allocator: std.mem.Allocator, writer: *std.Io.Writer) !void {
        var widths = try allocator.alloc(usize, self.columns.len);
        defer allocator.free(widths);

        for (self.columns, 0..) |col, i| {
            widths[i] = col.width;
            if (widths[i] == 0) widths[i] = col.name.len;
        }

        for (self.rows.items) |row| {
            for (row, 0..) |cell, i| {
                if (cell.len > widths[i]) widths[i] = cell.len;
            }
        }

        if (self.options.show_header) {
            for (self.columns, 0..) |col, i| {
                if (self.options.use_color) {
                    try color.writeStyled(writer, true, .heading, col.name);
                } else {
                    try writer.writeAll(col.name);
                }
                if (i < self.columns.len - 1) {
                    const pad = widths[i] - col.name.len + self.options.padding;
                    try writer.writeByteNTimes(' ', pad);
                }
            }
            try writer.writeAll("\n");
        }

        for (self.rows.items) |row| {
            for (row, 0..) |cell, i| {
                try writer.writeAll(cell);
                if (i < row.len - 1) {
                    const pad = widths[i] - cell.len + self.options.padding;
                    try writer.writeByteNTimes(' ', pad);
                }
            }
            try writer.writeAll("\n");
        }
    }
};

pub fn writeKeyValue(writer: *std.Io.Writer, use_color: bool, key: []const u8, value: []const u8) !void {
    if (use_color) {
        try color.writeStyled(writer, true, .flag, key);
    } else {
        try writer.writeAll(key);
    }
    try writer.writeAll(": ");
    try writer.writeAll(value);
    try writer.writeAll("\n");
}

pub fn writeBulletList(writer: *std.Io.Writer, use_color: bool, items: []const []const u8) !void {
    for (items) |item| {
        try writer.writeAll("  • ");
        if (use_color) {
            try color.writeStyled(writer, true, .value, item);
        } else {
            try writer.writeAll(item);
        }
        try writer.writeAll("\n");
    }
}

test "Table renders with header and rows" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const columns = [_]Column{
        .{ .name = "Name" },
        .{ .name = "Value" },
    };

    var table = Table.init(allocator, &columns, .{ .use_color = false });
    defer table.deinit(allocator);

    try table.addRow(allocator, &[_][]const u8{ "alpha", "100" });
    try table.addRow(allocator, &[_][]const u8{ "beta", "200" });

    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();
    try table.render(allocator, &out.writer);

    const text = try out.toOwnedSlice();
    defer testing.allocator.free(text);
    try testing.expect(std.mem.indexOf(u8, text, "Name") != null);
    try testing.expect(std.mem.indexOf(u8, text, "alpha") != null);
    try testing.expect(std.mem.indexOf(u8, text, "beta") != null);
}
