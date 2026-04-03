const std = @import("std");
const model = @import("model.zig");
const aegis = @import("thirdparty/aegis.zig");
const authy = @import("thirdparty/authy.zig");
const otpauth_parser = @import("thirdparty/otpauth.zig");
const normalize = @import("thirdparty/normalize.zig");
const twofas = @import("thirdparty/twofas.zig");
const andotp = @import("thirdparty/andotp.zig");
const bitwarden_mod = @import("thirdparty/bitwarden.zig");
const proton_mod = @import("thirdparty/proton_authenticator.zig");
const ente_mod = @import("thirdparty/ente_auth.zig");

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
        if (fields.len >= 15) {
            try entries.append(allocator, .{
                .id = try dup(allocator, fields[0]),
                .issuer = try dup(allocator, fields[1]),
                .account_name = try dup(allocator, fields[2]),
                .secret = try dup(allocator, fields[3]),
                .kind = model.EntryKind.fromString(fields[4]) orelse .totp,
                .digits = try std.fmt.parseInt(u8, fields[5], 10),
                .period = try std.fmt.parseInt(u32, fields[6], 10),
                .counter = if (fields[7].len == 0) null else try std.fmt.parseInt(u64, fields[7], 10),
                .algorithm = model.Algorithm.fromString(fields[8]) orelse return error.InvalidAlgorithm,
                .tags = try tags_list.toOwnedSlice(allocator),
                .note = if (fields[10].len == 0) null else try dup(allocator, fields[10]),
                .readonly_reason = if (fields[11].len == 0) null else try dup(allocator, fields[11]),
                .source_format = if (fields[12].len == 0) null else try dup(allocator, fields[12]),
                .created_at = try std.fmt.parseInt(i64, fields[13], 10),
                .updated_at = try std.fmt.parseInt(i64, fields[14], 10),
            });
        } else {
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
    }
    return entries.toOwnedSlice(allocator);
}

pub fn otpauth(allocator: std.mem.Allocator, bytes: []const u8, now: i64) ![]const model.Entry {
    var entries = std.ArrayList(model.Entry).empty;
    defer entries.deinit(allocator);
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    var index: usize = 0;
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r\n");
        if (line.len == 0) continue;
        const parsed = try otpauth_parser.parseUri(allocator, line);
        defer parsed.deinit(allocator);
        const entry = try normalize.entryAlloc(allocator, parsed.input, now, index);
        try entries.append(allocator, entry);
        index += 1;
    }
    return entries.toOwnedSlice(allocator);
}

pub const third_party = struct {
    pub const aegis_plain = aegis.importPlain;
    pub const aegis_encrypted = aegis.importEncrypted;
    pub const authy_backup = authy.importBackup;
    pub const twofas_plain = twofas.importPlain;
    pub const twofas_encrypted = twofas.importEncrypted;
    pub const andotp_plain = andotp.importPlain;
    pub const andotp_encrypted = andotp.importEncrypted;
    pub const andotp_encrypted_old = andotp.importEncryptedOld;
    pub const bitwarden = bitwarden_mod.importAlloc;
    pub const proton_authenticator = proton_mod.importAlloc;
    pub const ente_auth = ente_mod.importAlloc;
};

fn readFixtureAlloc(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    return std.Io.Dir.cwd().readFileAlloc(std.Io.Threaded.init_single_threaded, path, allocator, .limited(std.math.maxInt(usize)));
}

test "imports supported otpauth entries from public sample" {
    const testing = std.testing;
    const bytes = try readFixtureAlloc(testing.allocator, "testdata/otpauth_plain.txt");
    defer testing.allocator.free(bytes);
    const entries = try otpauth(testing.allocator, bytes, 0);
    try testing.expectEqual(@as(usize, 7), entries.len);
    try testing.expectEqualStrings("Deno", entries[0].issuer);
    try testing.expectEqual(@as(u8, 7), entries[1].digits);
    try testing.expectEqual(@as(u32, 50), entries[2].period);
    try testing.expectEqual(model.EntryKind.hotp, entries[3].kind);
    try testing.expect(entries[3].isReadonly());
    try testing.expectEqual(model.EntryKind.steam, entries[6].kind);
}
