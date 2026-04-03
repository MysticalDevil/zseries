const std = @import("std");
const base32 = @import("base32.zig");
const model = @import("model.zig");

pub const TotpCode = struct {
    code: [8]u8,
    len: usize,
    remaining_seconds: u32,
};

fn writeCounter(counter: u64) [8]u8 {
    var out: [8]u8 = undefined;
    std.mem.writeInt(u64, &out, counter, .big);
    return out;
}

fn truncateHmac(hash: []const u8, digits: u8) u32 {
    const offset = hash[hash.len - 1] & 0x0f;
    const binary = (@as(u32, hash[offset] & 0x7f) << 24) |
        (@as(u32, hash[offset + 1]) << 16) |
        (@as(u32, hash[offset + 2]) << 8) |
        @as(u32, hash[offset + 3]);

    var modulus: u32 = 1;
    for (0..digits) |_| modulus *= 10;
    return binary % modulus;
}

fn hotp(secret: []const u8, counter: u64, algorithm: model.Algorithm, digits: u8) [8]u8 {
    const message = writeCounter(counter);
    var digest: [64]u8 = undefined;
    const digest_len: usize = switch (algorithm) {
        .sha1 => len: {
            std.crypto.auth.hmac.HmacSha1.create(digest[0..20], &message, secret);
            break :len 20;
        },
        .sha256 => len: {
            std.crypto.auth.hmac.sha2.HmacSha256.create(digest[0..32], &message, secret);
            break :len 32;
        },
        .sha512 => len: {
            std.crypto.auth.hmac.sha2.HmacSha512.create(digest[0..64], &message, secret);
            break :len 64;
        },
    };

    const binary = truncateHmac(digest[0..digest_len], digits);
    var buf: [8]u8 = [_]u8{'0'} ** 8;
    const formatted = std.fmt.bufPrint(&buf, "{d:0>8}", .{binary}) catch unreachable;
    var result: [8]u8 = [_]u8{'0'} ** 8;
    const start = buf.len - formatted.len;
    @memcpy(result[start..], formatted);
    return result;
}

pub fn generate(allocator: std.mem.Allocator, entry: model.Entry, timestamp: i64) !TotpCode {
    if (entry.digits == 0 or entry.digits > 8) return error.InvalidDigits;
    if (entry.period == 0) return error.InvalidPeriod;
    if (timestamp < 0) return error.InvalidTimestamp;

    const secret = try base32.decodeAlloc(allocator, entry.secret);
    defer allocator.free(secret);

    const ts: u64 = @intCast(timestamp);
    const counter = ts / entry.period;
    const remaining: u32 = entry.period - @as(u32, @intCast(ts % entry.period));
    const padded = hotp(secret, counter, entry.algorithm, entry.digits);
    return .{
        .code = padded,
        .len = entry.digits,
        .remaining_seconds = remaining,
    };
}

test "base32 decode" {
    const testing = std.testing;
    const decoded = try base32.decodeAlloc(testing.allocator, "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ");
    defer testing.allocator.free(decoded);
    try testing.expectEqualStrings("12345678901234567890", decoded);
}

fn expectVector(algorithm: model.Algorithm, ts: i64, expected: []const u8) !void {
    const testing = std.testing;
    const entry = model.Entry{
        .id = "rfc",
        .issuer = "RFC",
        .account_name = "vector",
        .secret = switch (algorithm) {
            .sha1 => "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ",
            .sha256 => "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZA====",
            .sha512 => "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNA=",
        },
        .digits = 8,
        .period = 30,
        .algorithm = algorithm,
        .created_at = 0,
        .updated_at = 0,
    };
    const code = try generate(testing.allocator, entry, ts);
    try testing.expectEqualStrings(expected, code.code[8 - code.len ..]);
}

test "rfc6238 sha1 vectors" {
    try expectVector(.sha1, 59, "94287082");
    try expectVector(.sha1, 1111111109, "07081804");
    try expectVector(.sha1, 2000000000, "69279037");
}
