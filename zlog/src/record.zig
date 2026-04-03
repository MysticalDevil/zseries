const std = @import("std");
const level = @import("level.zig");
const field = @import("field.zig");

pub const Record = struct {
    timestamp: i64,
    level_value: level.Level,
    message: []const u8,
    fields: []const field.Field = &.{},

    pub fn formatAlloc(self: Record, allocator: std.mem.Allocator) ![]u8 {
        var out: std.Io.Writer.Allocating = .init(allocator);
        defer out.deinit();
        try out.writer.print("ts={d} level={s} ", .{ self.timestamp, self.level_value.asString() });
        try field.appendField(&out.writer, field.Field.string("msg", self.message));
        for (self.fields) |entry| {
            try out.writer.writeByte(' ');
            try field.appendField(&out.writer, entry);
        }
        try out.writer.writeByte('\n');
        return out.toOwnedSlice();
    }
};

test "record formatting includes message and fields" {
    const testing = std.testing;
    const record = Record{
        .timestamp = 123,
        .level_value = .info,
        .message = "frame rendered",
        .fields = &.{ field.Field.uint("frame", 7), field.Field.boolean("changed", true) },
    };
    const text = try record.formatAlloc(testing.allocator);
    defer testing.allocator.free(text);
    try testing.expect(std.mem.indexOf(u8, text, "ts=123 level=INFO") != null);
    try testing.expect(std.mem.indexOf(u8, text, "msg=\"frame rendered\"") != null);
    try testing.expect(std.mem.indexOf(u8, text, "frame=7") != null);
}
