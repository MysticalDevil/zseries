const color = @import("color.zig");

pub fn writeHeader(writer: anytype, use_color: bool, title: []const u8, subtitle: []const u8) !void {
    try color.writeStyled(writer, use_color, .title, title);
    try writer.writeAll("\n");
    try color.writeStyled(writer, use_color, .muted, subtitle);
    try writer.writeAll("\n\n");
}

pub fn writeHeading(writer: anytype, use_color: bool, name: []const u8) !void {
    try color.writeStyled(writer, use_color, .heading, name);
    try writer.writeAll("\n");
}

pub fn writeCommandRow(writer: anytype, use_color: bool, name: []const u8, summary: []const u8) !void {
    try writer.writeAll("  ");
    try color.writeStyled(writer, use_color, .command, name);
    if (name.len < 8) {
        for (0..8 - name.len) |_| try writer.writeByte(' ');
    }
    try writer.writeAll("  ");
    try writer.writeAll(summary);
    try writer.writeAll("\n");
}

pub fn writeBullet(writer: anytype, use_color: bool, label: []const u8, value: []const u8) !void {
    try writer.writeAll("  ");
    try color.writeStyled(writer, use_color, .flag, label);
    try writer.writeAll("  ");
    try writer.writeAll(value);
    try writer.writeAll("\n");
}

pub fn writeExample(writer: anytype, use_color: bool, example: []const u8) !void {
    try writer.writeAll("  ");
    try color.writeStyled(writer, use_color, .accent, "$ ");
    try color.writeStyled(writer, use_color, .value, example);
    try writer.writeAll("\n");
}
