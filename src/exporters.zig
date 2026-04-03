const std = @import("std");
const model = @import("model.zig");
const aegis = @import("thirdparty/aegis.zig");
const authy = @import("thirdparty/authy.zig");

fn dup(allocator: std.mem.Allocator, value: []const u8) ![]const u8 {
    return try allocator.dupe(u8, value);
}

fn escapeCsvField(writer: anytype, field: []const u8) !void {
    const needs_quotes = std.mem.indexOfAny(u8, field, ",\n\r\"") != null;
    if (!needs_quotes) return writer.writeAll(field);
    try writer.writeByte('"');
    for (field) |ch| {
        if (ch == '"') try writer.writeByte('"');
        try writer.writeByte(ch);
    }
    try writer.writeByte('"');
}

pub fn json(allocator: std.mem.Allocator, entries: []const model.Entry, now: i64) ![]u8 {
    return std.fmt.allocPrint(allocator, "{f}\n", .{std.json.fmt(model.ExportBundle{ .exported_at = now, .entries = entries }, .{ .whitespace = .indent_2 })});
}

pub fn csv(allocator: std.mem.Allocator, entries: []const model.Entry) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();
    const writer = &out.writer;
    try writer.writeAll("id,issuer,account_name,secret,digits,period,algorithm,tags,note,created_at,updated_at\n");
    for (entries) |entry| {
        const tags = try std.mem.join(allocator, ";", entry.tags);
        defer allocator.free(tags);
        const note = entry.note orelse "";
        try escapeCsvField(writer, entry.id);
        try writer.writeByte(',');
        try escapeCsvField(writer, entry.issuer);
        try writer.writeByte(',');
        try escapeCsvField(writer, entry.account_name);
        try writer.writeByte(',');
        try escapeCsvField(writer, entry.secret);
        try writer.print(",{d},{d},{s},", .{ entry.digits, entry.period, entry.algorithm.asString() });
        try escapeCsvField(writer, tags);
        try writer.writeByte(',');
        try escapeCsvField(writer, note);
        try writer.print(",{d},{d}\n", .{ entry.created_at, entry.updated_at });
    }
    return out.toOwnedSlice();
}

pub fn otpauth(allocator: std.mem.Allocator, entries: []const model.Entry) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();
    const writer = &out.writer;
    for (entries) |entry| {
        const label = if (entry.issuer.len > 0) try std.fmt.allocPrint(allocator, "{s}:{s}", .{ entry.issuer, entry.account_name }) else try dup(allocator, entry.account_name);
        defer allocator.free(label);
        try writer.print(
            "otpauth://totp/{f}?secret={s}&issuer={s}&algorithm={s}&digits={d}&period={d}\n",
            .{ std.fmt.alt(std.Uri.Component{ .raw = label }, .formatEscaped), entry.secret, entry.issuer, entry.algorithm.asString(), entry.digits, entry.period },
        );
    }
    return out.toOwnedSlice();
}

pub const third_party = struct {
    pub const aegis_plain = aegis.exportPlain;
    pub const aegis_encrypted = aegis.exportEncrypted;
    pub const authy_backup = authy.exportBackup;
};
