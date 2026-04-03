const std = @import("std");
const model = @import("model.zig");
const aegis = @import("thirdparty/aegis.zig");
const authy = @import("thirdparty/authy.zig");

fn dup(allocator: std.mem.Allocator, value: []const u8) ![]const u8 {
    return try allocator.dupe(u8, value);
}

fn trimDup(allocator: std.mem.Allocator, value: []const u8) ![]const u8 {
    return dup(allocator, std.mem.trim(u8, value, " \t\r\n"));
}

pub fn json(allocator: std.mem.Allocator, bytes: []const u8) ![]const model.Entry {
    const parsed = try std.json.parseFromSliceLeaky(model.ExportBundle, allocator, bytes, .{ .allocate = .alloc_always });
    return parsed.entries;
}

fn parseCsvLine(allocator: std.mem.Allocator, line: []const u8) ![][]const u8 {
    var fields = std.ArrayList([]const u8).empty;
    defer fields.deinit(allocator);
    var current = std.ArrayList(u8).empty;
    defer current.deinit(allocator);
    var i: usize = 0;
    var quoted = false;
    while (i < line.len) : (i += 1) {
        const ch = line[i];
        if (quoted) {
            if (ch == '"') {
                if (i + 1 < line.len and line[i + 1] == '"') {
                    try current.append(allocator, '"');
                    i += 1;
                } else quoted = false;
            } else try current.append(allocator, ch);
        } else switch (ch) {
            '"' => quoted = true,
            ',' => {
                try fields.append(allocator, try current.toOwnedSlice(allocator));
                current = .empty;
            },
            else => try current.append(allocator, ch),
        }
    }
    try fields.append(allocator, try current.toOwnedSlice(allocator));
    return fields.toOwnedSlice(allocator);
}

pub fn csv(allocator: std.mem.Allocator, bytes: []const u8) ![]const model.Entry {
    var entries = std.ArrayList(model.Entry).empty;
    defer entries.deinit(allocator);
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    const header = lines.next() orelse return entries.toOwnedSlice(allocator);
    if (!std.mem.startsWith(u8, header, "id,")) return error.InvalidCsv;
    while (lines.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, "\r");
        if (line.len == 0) continue;
        const fields = try parseCsvLine(allocator, line);
        defer {
            for (fields) |field| allocator.free(field);
            allocator.free(fields);
        }
        var tags_list = std.ArrayList([]const u8).empty;
        defer tags_list.deinit(allocator);
        var tags_iter = std.mem.splitScalar(u8, fields[7], ';');
        while (tags_iter.next()) |tag| {
            if (tag.len == 0) continue;
            try tags_list.append(allocator, try trimDup(allocator, tag));
        }
        try entries.append(allocator, .{
            .id = try dup(allocator, fields[0]),
            .issuer = try dup(allocator, fields[1]),
            .account_name = try dup(allocator, fields[2]),
            .secret = try dup(allocator, fields[3]),
            .digits = try std.fmt.parseInt(u8, fields[4], 10),
            .period = try std.fmt.parseInt(u32, fields[5], 10),
            .algorithm = model.Algorithm.fromString(fields[6]) orelse return error.InvalidAlgorithm,
            .tags = try tags_list.toOwnedSlice(allocator),
            .note = if (fields[8].len == 0) null else try dup(allocator, fields[8]),
            .created_at = try std.fmt.parseInt(i64, fields[9], 10),
            .updated_at = try std.fmt.parseInt(i64, fields[10], 10),
        });
    }
    return entries.toOwnedSlice(allocator);
}

fn decodeUriComponentAlloc(allocator: std.mem.Allocator, component: std.Uri.Component) ![]const u8 {
    return try component.toRawMaybeAlloc(allocator);
}

fn queryValue(query: []const u8, key: []const u8) ?[]const u8 {
    var iter = std.mem.splitScalar(u8, query, '&');
    while (iter.next()) |part| {
        var pair_iter = std.mem.splitScalar(u8, part, '=');
        const current_key = pair_iter.next() orelse continue;
        const current_value = pair_iter.next() orelse "";
        if (std.mem.eql(u8, current_key, key)) return current_value;
    }
    return null;
}

fn parseOtpAuthUri(allocator: std.mem.Allocator, line: []const u8, now: i64, id_hint: usize) !model.Entry {
    const uri = try std.Uri.parse(line);
    if (!std.ascii.eqlIgnoreCase(uri.scheme, "otpauth")) return error.InvalidOtpAuth;
    const host = try uri.getHostAlloc(allocator);
    if (!std.ascii.eqlIgnoreCase(host.bytes, "totp")) return error.InvalidOtpAuth;
    const raw_path = try decodeUriComponentAlloc(allocator, uri.path);
    defer allocator.free(raw_path);
    const label = std.mem.trim(u8, raw_path, "/");
    const query_component = uri.query orelse return error.MissingSecret;
    const query = try decodeUriComponentAlloc(allocator, query_component);
    defer allocator.free(query);
    const secret_value = queryValue(query, "secret") orelse return error.MissingSecret;
    var issuer = queryValue(query, "issuer") orelse "";
    var account = label;
    if (std.mem.indexOfScalar(u8, label, ':')) |idx| {
        issuer = std.mem.trim(u8, label[0..idx], " ");
        account = std.mem.trim(u8, label[idx + 1 ..], " ");
    }
    return .{
        .id = try std.fmt.allocPrint(allocator, "import-{d}", .{id_hint}),
        .issuer = try dup(allocator, issuer),
        .account_name = try dup(allocator, account),
        .secret = try dup(allocator, secret_value),
        .digits = if (queryValue(query, "digits")) |value| try std.fmt.parseInt(u8, value, 10) else 6,
        .period = if (queryValue(query, "period")) |value| try std.fmt.parseInt(u32, value, 10) else 30,
        .algorithm = if (queryValue(query, "algorithm")) |value| model.Algorithm.fromString(value) orelse .sha1 else .sha1,
        .created_at = now,
        .updated_at = now,
    };
}

pub fn otpauth(allocator: std.mem.Allocator, bytes: []const u8, now: i64) ![]const model.Entry {
    var entries = std.ArrayList(model.Entry).empty;
    defer entries.deinit(allocator);
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    var index: usize = 0;
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r\n");
        if (line.len == 0) continue;
        try entries.append(allocator, try parseOtpAuthUri(allocator, line, now, index));
        index += 1;
    }
    return entries.toOwnedSlice(allocator);
}

pub const third_party = struct {
    pub const aegis_plain = aegis.importPlain;
    pub const aegis_encrypted = aegis.importEncrypted;
    pub const authy_backup = authy.importBackup;
};
