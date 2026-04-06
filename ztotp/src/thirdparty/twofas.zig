const std = @import("std");
const normalize = @import("normalize.zig");
const otpauth = @import("otpauth.zig");
const model = @import("../model.zig");
const shared = @import("shared.zig");

const TwoFas = struct {
    services: ?[]const Service = null,
    servicesEncrypted: ?[]const u8 = null,
    schemaVersion: ?u32 = null,
};

const Service = struct {
    name: ?[]const u8 = null,
    secret: []const u8,
    otp: Otp,
};

const Otp = struct {
    link: ?[]const u8 = null,
    label: ?[]const u8 = null,
    account: ?[]const u8 = null,
    issuer: ?[]const u8 = null,
    digits: ?u8 = null,
    period: ?u32 = null,
    algorithm: ?[]const u8 = null,
    counter: ?u64 = null,
    tokenType: ?[]const u8 = null,
};

fn kindFromTokenType(value: ?[]const u8) model.EntryKind {
    const token_type = value orelse return .totp;
    if (std.ascii.eqlIgnoreCase(token_type, "TOTP")) return .totp;
    if (std.ascii.eqlIgnoreCase(token_type, "HOTP")) return .hotp;
    if (std.ascii.eqlIgnoreCase(token_type, "STEAM")) return .steam;
    return .unknown;
}

fn toEntries(allocator: std.mem.Allocator, services: []const Service, now: i64) ![]const model.Entry {
    var entries = std.ArrayList(model.Entry).empty;
    defer entries.deinit(allocator);
    for (services, 0..) |service, i| {
        if (service.otp.link) |link| {
            const parsed = try otpauth.parseUri(allocator, link);
            defer parsed.deinit(allocator);
            var input = parsed.input;
            input.source_format = "2fas";
            try entries.append(allocator, try normalize.entryAlloc(allocator, input, now, i));
            continue;
        }

        const input = normalize.NormalizedInput{
            .issuer = service.otp.issuer orelse service.name,
            .account_name = service.otp.account orelse service.otp.label orelse service.name orelse "",
            .secret = service.secret,
            .kind = kindFromTokenType(service.otp.tokenType),
            .digits = service.otp.digits orelse if (kindFromTokenType(service.otp.tokenType) == .steam) 5 else 6,
            .period = service.otp.period orelse 30,
            .counter = service.otp.counter,
            .algorithm = if (service.otp.algorithm) |algorithm| model.Algorithm.fromString(algorithm) orelse .sha1 else .sha1,
            .source_format = "2fas",
        };
        if (input.secret.len == 0) continue;
        try entries.append(allocator, try normalize.entryAlloc(allocator, input, now, i));
    }
    return entries.toOwnedSlice(allocator);
}

pub fn importPlain(allocator: std.mem.Allocator, bytes: []const u8, now: i64) ![]const model.Entry {
    const trimmed = std.mem.trim(u8, bytes, " \t\r\n");
    const services = if (trimmed.len > 0 and trimmed[0] == '[')
        try std.json.parseFromSliceLeaky([]const Service, allocator, bytes, .{ .allocate = .alloc_always, .ignore_unknown_fields = true })
    else blk: {
        const parsed = try std.json.parseFromSliceLeaky(TwoFas, allocator, bytes, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
        break :blk parsed.services orelse return error.InvalidTwoFasBackup;
    };
    return toEntries(allocator, services, now);
}

pub fn importEncrypted(allocator: std.mem.Allocator, bytes: []const u8, password: []const u8, now: i64) ![]const model.Entry {
    const parsed = try std.json.parseFromSliceLeaky(TwoFas, allocator, bytes, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
    const encrypted = parsed.servicesEncrypted orelse return error.InvalidTwoFasBackup;
    var parts = std.mem.splitScalar(u8, encrypted, ':');
    const data_b64 = parts.next() orelse return error.InvalidTwoFasBackup;
    const salt_b64 = parts.next() orelse return error.InvalidTwoFasBackup;
    const iv_b64 = parts.next() orelse return error.InvalidTwoFasBackup;
    const ciphertext = try shared.base64DecodeAlloc(allocator, data_b64);
    defer allocator.free(ciphertext);
    const salt = try shared.base64DecodeAlloc(allocator, salt_b64);
    defer allocator.free(salt);
    const iv = try shared.base64DecodeAlloc(allocator, iv_b64);
    defer allocator.free(iv);
    const key = try shared.pbkdf2Sha256(password, salt, 10_000);
    const tag_offset = ciphertext.len - 16;
    const plaintext = try shared.aes256GcmDecryptAlloc(allocator, ciphertext[0..tag_offset], iv, ciphertext[tag_offset..], key);
    defer allocator.free(plaintext);
    return importPlain(allocator, plaintext, now);
}
