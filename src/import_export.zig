const std = @import("std");
const model = @import("model.zig");

pub const ImportFormat = enum { otpauth, json, csv };
pub const ExportFormat = enum { otpauth, json, csv };

fn dup(allocator: std.mem.Allocator, value: []const u8) ![]const u8 {
    return try allocator.dupe(u8, value);
}

fn trimDup(allocator: std.mem.Allocator, value: []const u8) ![]const u8 {
    return dup(allocator, std.mem.trim(u8, value, " \t\r\n"));
}

pub fn importJson(allocator: std.mem.Allocator, bytes: []const u8) ![]const model.Entry {
    const parsed = try std.json.parseFromSliceLeaky(model.ExportBundle, allocator, bytes, .{ .allocate = .alloc_always });
    return parsed.entries;
}

pub fn exportJson(allocator: std.mem.Allocator, entries: []const model.Entry, now: i64) ![]u8 {
    return std.fmt.allocPrint(allocator, "{f}\n", .{std.json.fmt(model.ExportBundle{
        .exported_at = now,
        .entries = entries,
    }, .{ .whitespace = .indent_2 })});
}

fn escapeCsvField(writer: anytype, field: []const u8) !void {
    const needs_quotes = std.mem.indexOfAny(u8, field, ",\n\r\"") != null;
    if (!needs_quotes) {
        try writer.writeAll(field);
        return;
    }

    try writer.writeByte('"');
    for (field) |ch| {
        if (ch == '"') try writer.writeByte('"');
        try writer.writeByte(ch);
    }
    try writer.writeByte('"');
}

pub fn exportCsv(allocator: std.mem.Allocator, entries: []const model.Entry) ![]u8 {
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
        try writer.writeByte(',');
        try writer.print("{d},{d},{s},", .{ entry.digits, entry.period, entry.algorithm.asString() });
        try escapeCsvField(writer, tags);
        try writer.writeByte(',');
        try escapeCsvField(writer, note);
        try writer.print(",{d},{d}\n", .{ entry.created_at, entry.updated_at });
    }
    return out.toOwnedSlice();
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
                } else {
                    quoted = false;
                }
            } else {
                try current.append(allocator, ch);
            }
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

pub fn importCsv(allocator: std.mem.Allocator, bytes: []const u8) ![]const model.Entry {
    var entries = std.ArrayList(model.Entry).empty;
    defer entries.deinit(allocator);

    var lines = std.mem.splitScalar(u8, bytes, '\n');
    _ = lines.next();
    while (lines.next()) |line_raw| {
        const line = std.mem.trim(u8, line_raw, "\r");
        if (line.len == 0) continue;
        const fields = try parseCsvLine(allocator, line);
        defer {
            for (fields) |field| allocator.free(field);
            allocator.free(fields);
        }
        if (fields.len < 11) return error.InvalidCsv;

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
        const pair = std.mem.splitScalar(u8, part, '=');
        var pair_iter = pair;
        const current_key = pair_iter.next() orelse continue;
        const current_value = pair_iter.next() orelse "";
        if (std.mem.eql(u8, current_key, key)) return current_value;
    }
    return null;
}

pub fn parseOtpAuthUri(allocator: std.mem.Allocator, line: []const u8, now: i64, id_hint: usize) !model.Entry {
    const uri = try std.Uri.parse(line);
    if (!std.ascii.eqlIgnoreCase(uri.scheme, "otpauth")) return error.InvalidOtpAuth;
    const host = try uri.getHostAlloc(allocator);
    if (!std.ascii.eqlIgnoreCase(host.bytes, "totp")) return error.InvalidOtpAuth;
    const raw_path = try decodeUriComponentAlloc(allocator, uri.path);
    defer allocator.free(raw_path);
    const label = std.mem.trim(u8, raw_path, "/");

    const secret = uri.query orelse return error.MissingSecret;
    const query = try decodeUriComponentAlloc(allocator, secret);
    defer allocator.free(query);

    const secret_value = queryValue(query, "secret") orelse return error.MissingSecret;
    const issuer_q = queryValue(query, "issuer");
    const digits_q = queryValue(query, "digits");
    const period_q = queryValue(query, "period");
    const algorithm_q = queryValue(query, "algorithm");

    var issuer = issuer_q orelse "";
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
        .digits = if (digits_q) |value| try std.fmt.parseInt(u8, value, 10) else 6,
        .period = if (period_q) |value| try std.fmt.parseInt(u32, value, 10) else 30,
        .algorithm = if (algorithm_q) |value| model.Algorithm.fromString(value) orelse .sha1 else .sha1,
        .tags = &.{},
        .note = null,
        .created_at = now,
        .updated_at = now,
    };
}

pub fn importOtpAuth(allocator: std.mem.Allocator, bytes: []const u8, now: i64) ![]const model.Entry {
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

pub fn exportOtpAuth(allocator: std.mem.Allocator, entries: []const model.Entry) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();
    const writer = &out.writer;
    for (entries) |entry| {
        const label = if (entry.issuer.len > 0)
            try std.fmt.allocPrint(allocator, "{s}:{s}", .{ entry.issuer, entry.account_name })
        else
            try dup(allocator, entry.account_name);
        defer allocator.free(label);
        try writer.print(
            "otpauth://totp/{f}?secret={s}&issuer={s}&algorithm={s}&digits={d}&period={d}\n",
            .{ std.fmt.alt(std.Uri.Component{ .raw = label }, .formatEscaped), entry.secret, entry.issuer, entry.algorithm.asString(), entry.digits, entry.period },
        );
    }
    return out.toOwnedSlice();
}
