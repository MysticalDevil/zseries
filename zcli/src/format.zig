const std = @import("std");
const color = @import("color.zig");

pub const JsonOptions = struct {
    use_color: bool = false,
    indent: ?[]const u8 = "  ",
};

pub fn writeJson(writer: *std.Io.Writer, value: anytype, options: JsonOptions) !void {
    const fmt_options: std.json.StringifyOptions = .{
        .whitespace = if (options.indent) |indent| .{ .indent_level = 1, .indent = indent } else null,
    };
    if (options.use_color) {
        try writer.writeAll("\x1b[36m");
        try std.json.stringify(value, fmt_options, writer);
        try writer.writeAll("\x1b[0m");
    } else {
        try std.json.stringify(value, fmt_options, writer);
    }
}

pub fn writeJsonToAlloc(allocator: std.mem.Allocator, value: anytype, options: JsonOptions) ![]u8 {
    var buf: std.Io.Writer.Allocating = .init(allocator);
    defer buf.deinit();
    try writeJson(&buf.writer, value, options);
    return try buf.toOwnedSlice();
}

pub fn writeYaml(writer: *std.Io.Writer, value: anytype) !void {
    try writeYamlValue(writer, value, 0);
}

fn writeYamlValue(writer: *std.Io.Writer, value: anytype, indent: usize) !void {
    const T = @TypeOf(value);
    switch (@typeInfo(T)) {
        .null => try writer.writeAll("null"),
        .bool => try writer.writeAll(if (value) "true" else "false"),
        .int, .comptime_int => try writer.print("{d}", .{value}),
        .float, .comptime_float => try writer.print("{d}", .{value}),
        .pointer => |ptr| switch (ptr.size) {
            .slice => {
                if (@typeInfo(ptr.child) == .array and @typeInfo(ptr.child).child == .u8) {
                    try writer.print("\"{s}\"", .{value});
                } else {
                    for (value, 0..) |item, i| {
                        if (i > 0) try writer.writeAll("\n");
                        try writer.writeByteNTimes(' ', indent);
                        try writer.writeAll("- ");
                        try writeYamlValue(writer, item, indent + 2);
                    }
                }
            },
            else => @compileError("Unsupported pointer type for YAML"),
        },
        .array => |arr| {
            if (arr.child == u8) {
                try writer.print("\"{s}\"", .{value});
            } else {
                for (value, 0..) |item, i| {
                    if (i > 0) try writer.writeAll("\n");
                    try writer.writeByteNTimes(' ', indent);
                    try writer.writeAll("- ");
                    try writeYamlValue(writer, item, indent + 2);
                }
            }
        },
        .@"struct" => |struct_info| {
            const has_fields = struct_info.fields.len > 0;
            if (has_fields) {
                var first = true;
                inline for (struct_info.fields) |field| {
                    const field_value = @field(value, field.name);
                    if (!first) try writer.writeAll("\n");
                    first = false;
                    try writer.writeByteNTimes(' ', indent);
                    try writer.print("{s}: ", .{field.name});
                    try writeYamlValue(writer, field_value, indent + 2);
                }
            }
        },
        .optional => if (value) |v| try writeYamlValue(writer, v, indent) else try writer.writeAll("null"),
        else => @compileError("Unsupported type for YAML: " ++ @typeName(T)),
    }
}

test "writeJson produces valid JSON" {
    const testing = std.testing;
    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();

    const data = .{ .name = "test", .value = 42 };
    try writeJson(&out.writer, data, .{});

    const text = try out.toOwnedSlice();
    defer testing.allocator.free(text);
    try testing.expect(std.mem.indexOf(u8, text, "\"name\"") != null);
    try testing.expect(std.mem.indexOf(u8, text, "\"test\"") != null);
}
