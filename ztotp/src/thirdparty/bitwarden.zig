const std = @import("std");
const model = @import("../model.zig");
const otpauth = @import("otpauth.zig");
const normalize = @import("normalize.zig");

const JsonExport = struct {
    items: []const Item,
};

const Item = struct {
    id: ?[]const u8 = null,
    name: ?[]const u8 = null,
    notes: ?[]const u8 = null,
    login: ?struct {
        totp: ?[]const u8 = null,
    } = null,
};

pub fn importAlloc(allocator: std.mem.Allocator, bytes: []const u8, now: i64) ![]const model.Entry {
    const trimmed = std.mem.trim(u8, bytes, " \t\r\n");
    if (trimmed.len == 0) return &.{};
    if (trimmed[0] == '{') return importJson(allocator, bytes, now);
    return importCsv(allocator, bytes, now);
}

fn importJson(allocator: std.mem.Allocator, bytes: []const u8, now: i64) ![]const model.Entry {
    const parsed = try std.json.parseFromSliceLeaky(JsonExport, allocator, bytes, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
    var entries = std.ArrayList(model.Entry).empty;
    defer entries.deinit(allocator);
    for (parsed.items, 0..) |item, i| {
        const totp_uri = if (item.login) |login| login.totp else null;
        const uri = totp_uri orelse continue;
        if (uri.len == 0) continue;
        const parsed_uri = try otpauth.parseUri(allocator, uri);
        defer parsed_uri.deinit(allocator);
        var input = parsed_uri.input;
        input.id = item.id;
        input.note = item.notes;
        input.source_format = "bitwarden";
        try entries.append(allocator, try normalize.entryAlloc(allocator, input, now, i));
    }
    return entries.toOwnedSlice(allocator);
}

fn importCsv(allocator: std.mem.Allocator, bytes: []const u8, now: i64) ![]const model.Entry {
    var entries = std.ArrayList(model.Entry).empty;
    defer entries.deinit(allocator);
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    const header = lines.next() orelse return &.{};
    var header_index: ?usize = null;
    var cols = std.mem.splitScalar(u8, std.mem.trim(u8, header, "\r"), ',');
    var idx: usize = 0;
    while (cols.next()) |col| : (idx += 1) {
        if (std.mem.eql(u8, col, "login_totp")) header_index = idx;
    }
    const totp_index = header_index orelse return error.InvalidBitwardenCsv;
    var row_index: usize = 0;
    while (lines.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, "\r");
        if (line.len == 0) continue;
        var fields = std.mem.splitScalar(u8, line, ',');
        var col_index: usize = 0;
        var totp_uri: ?[]const u8 = null;
        while (fields.next()) |field| : (col_index += 1) {
            if (col_index == totp_index) {
                if (field.len > 0) totp_uri = field;
                break;
            }
        }
        if (totp_uri) |uri| {
            const parsed_uri = try otpauth.parseUri(allocator, uri);
            defer parsed_uri.deinit(allocator);
            var input = parsed_uri.input;
            input.source_format = "bitwarden";
            try entries.append(allocator, try normalize.entryAlloc(allocator, input, now, row_index));
            row_index += 1;
        }
    }
    return entries.toOwnedSlice(allocator);
}
