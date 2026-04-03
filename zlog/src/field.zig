const std = @import("std");

pub const Value = union(enum) {
    string: []const u8,
    int: i64,
    uint: u64,
    boolean: bool,
};

pub const Field = struct {
    key: []const u8,
    value: Value,

    pub fn string(key: []const u8, value: []const u8) Field {
        return .{ .key = key, .value = .{ .string = value } };
    }

    pub fn int(key: []const u8, value: i64) Field {
        return .{ .key = key, .value = .{ .int = value } };
    }

    pub fn uint(key: []const u8, value: u64) Field {
        return .{ .key = key, .value = .{ .uint = value } };
    }

    pub fn boolean(key: []const u8, value: bool) Field {
        return .{ .key = key, .value = .{ .boolean = value } };
    }
};

fn needsQuoting(text: []const u8) bool {
    return std.mem.indexOfAny(u8, text, " \t\n\r=\"") != null;
}

fn appendEscapedString(writer: *std.Io.Writer, text: []const u8) !void {
    const quote = needsQuoting(text);
    if (quote) try writer.writeByte('"');
    for (text) |ch| {
        switch (ch) {
            '"' => try writer.writeAll("\\\""),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => try writer.writeByte(ch),
        }
    }
    if (quote) try writer.writeByte('"');
}

pub fn appendField(writer: *std.Io.Writer, field: Field) !void {
    try writer.print("{s}=", .{field.key});
    switch (field.value) {
        .string => |value| try appendEscapedString(writer, value),
        .int => |value| try writer.print("{d}", .{value}),
        .uint => |value| try writer.print("{d}", .{value}),
        .boolean => |value| try writer.writeAll(if (value) "true" else "false"),
    }
}

test "field formatting emits escaped key value pairs" {
    const testing = std.testing;
    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    try appendField(&out.writer, Field.string("msg", "hello world"));
    try out.writer.writeByte(' ');
    try appendField(&out.writer, Field.boolean("changed", true));
    const text = try out.toOwnedSlice();
    defer testing.allocator.free(text);
    try testing.expectEqualStrings("msg=\"hello world\" changed=true", text);
}
