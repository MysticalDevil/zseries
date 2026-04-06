const std = @import("std");
const normalize = @import("normalize.zig");
const model = @import("../model.zig");
const shared = @import("shared.zig");

const Entry = struct {
    secret: []const u8,
    issuer: ?[]const u8 = null,
    label: []const u8,
    digits: u8,
    type: []const u8,
    algorithm: []const u8,
    period: ?u32 = null,
    counter: ?u64 = null,
    tags: []const []const u8 = &.{},
};

fn toKind(value: []const u8) model.EntryKind {
    return model.EntryKind.fromString(value) orelse .unknown;
}

fn toEntries(allocator: std.mem.Allocator, entries_in: []const Entry, now: i64) ![]const model.Entry {
    var entries = std.ArrayList(model.Entry).empty;
    defer entries.deinit(allocator);
    for (entries_in, 0..) |entry, i| {
        var issuer = entry.issuer;
        var account = entry.label;
        if (issuer == null) {
            var parts = std.mem.splitSequence(u8, entry.label, " - ");
            const first = parts.next() orelse entry.label;
            if (parts.next()) |second| {
                issuer = first;
                account = second;
            }
        }
        const kind = toKind(entry.type);
        try entries.append(allocator, try normalize.entryAlloc(allocator, .{
            .issuer = issuer,
            .account_name = account,
            .secret = std.mem.trim(u8, entry.secret, "="),
            .kind = kind,
            .digits = entry.digits,
            .period = entry.period orelse 30,
            .counter = entry.counter,
            .algorithm = model.Algorithm.fromString(entry.algorithm) orelse .sha1,
            .tags = entry.tags,
            .source_format = "andotp",
        }, now, i));
    }
    return entries.toOwnedSlice(allocator);
}

pub fn importPlain(allocator: std.mem.Allocator, bytes: []const u8, now: i64) ![]const model.Entry {
    const parsed = try std.json.parseFromSliceLeaky([]const Entry, allocator, bytes, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
    return toEntries(allocator, parsed, now);
}

fn decryptNew(allocator: std.mem.Allocator, bytes: []const u8, password: []const u8) ![]u8 {
    if (bytes.len < 4 + 12 + 12 + 16) return error.InvalidAndOtpBackup;
    const iterations = std.mem.readInt(i32, bytes[0..4], .big);
    if (iterations < 1 or iterations > 10_000_000) return error.InvalidAndOtpBackup;
    const salt = bytes[4..16];
    const nonce = bytes[16..28];
    const tag = bytes[bytes.len - 16 ..];
    const ciphertext = bytes[28 .. bytes.len - 16];
    const key = try shared.pbkdf2Sha1(password, salt, @intCast(iterations));
    return shared.aes256GcmDecryptAlloc(allocator, ciphertext, nonce, tag, key);
}

fn decryptOld(allocator: std.mem.Allocator, bytes: []const u8, password: []const u8) ![]u8 {
    if (bytes.len < 12 + 16) return error.InvalidAndOtpBackup;
    const nonce = bytes[0..12];
    const tag = bytes[bytes.len - 16 ..];
    const ciphertext = bytes[12 .. bytes.len - 16];
    const key = shared.sha256Bytes(password);
    return shared.aes256GcmDecryptAlloc(allocator, ciphertext, nonce, tag, key);
}

pub fn importEncrypted(allocator: std.mem.Allocator, bytes: []const u8, password: []const u8, now: i64) ![]const model.Entry {
    const plaintext = try decryptNew(allocator, bytes, password);
    defer allocator.free(plaintext);
    return importPlain(allocator, plaintext, now);
}

pub fn importEncryptedOld(allocator: std.mem.Allocator, bytes: []const u8, password: []const u8, now: i64) ![]const model.Entry {
    const plaintext = try decryptOld(allocator, bytes, password);
    defer allocator.free(plaintext);
    return importPlain(allocator, plaintext, now);
}
