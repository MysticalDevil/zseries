const std = @import("std");
const color = @import("color.zig");

pub fn writeHeader(writer: *std.Io.Writer, use_color: bool, title: []const u8, subtitle: []const u8) !void {
    try color.writeStyled(writer, use_color, .title, title);
    try writer.writeAll("\n");
    try color.writeStyled(writer, use_color, .muted, subtitle);
    try writer.writeAll("\n\n");
}

pub fn writeHeading(writer: *std.Io.Writer, use_color: bool, name: []const u8) !void {
    try color.writeStyled(writer, use_color, .heading, name);
    try writer.writeAll("\n");
}

pub fn writeCommandRow(writer: *std.Io.Writer, use_color: bool, name: []const u8, summary: []const u8) !void {
    try writer.writeAll("  ");
    try color.writeStyled(writer, use_color, .command, name);
    if (name.len < 8) {
        for (0..8 - name.len) |_| try writer.writeByte(' ');
    }
    try writer.writeAll("  ");
    try writer.writeAll(summary);
    try writer.writeAll("\n");
}

pub fn writeBullet(writer: *std.Io.Writer, use_color: bool, label: []const u8, value: []const u8) !void {
    try writer.writeAll("  ");
    try color.writeStyled(writer, use_color, .flag, label);
    try writer.writeAll("  ");
    try writer.writeAll(value);
    try writer.writeAll("\n");
}

pub fn writeExample(writer: *std.Io.Writer, use_color: bool, example: []const u8) !void {
    try writer.writeAll("  ");
    try color.writeStyled(writer, use_color, .accent, "$ ");
    try color.writeStyled(writer, use_color, .value, example);
    try writer.writeAll("\n");
}

test "writeCommandRow aligns short command names" {
    const testing = std.testing;
    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    try writeCommandRow(&out.writer, false, "add", "Add a TOTP entry");
    const text = try out.toOwnedSlice();
    defer testing.allocator.free(text);
    try testing.expectEqualStrings("  add       Add a TOTP entry\n", text);
}

test "writeHeader emits title subtitle spacing" {
    const testing = std.testing;
    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    try writeHeader(&out.writer, false, "ztotp", "subtitle");
    const text = try out.toOwnedSlice();
    defer testing.allocator.free(text);
    try testing.expectEqualStrings("ztotp\nsubtitle\n\n", text);
}

test "writeExample prefixes shell marker" {
    const testing = std.testing;
    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    try writeExample(&out.writer, false, "ztotp init");
    const text = try out.toOwnedSlice();
    defer testing.allocator.free(text);
    try testing.expectEqualStrings("  $ ztotp init\n", text);
}
