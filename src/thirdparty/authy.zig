const std = @import("std");
const base32 = @import("../base32.zig");
const model = @import("../model.zig");
const shared = @import("shared.zig");

const Backup = struct {
    tokens: TokensResponse,
    apps: AppsResponse,
};

const TokensResponse = struct {
    message: []const u8 = "",
    authenticator_tokens: []const Token = &.{},
    deleted: []const Token = &.{},
    success: bool = true,
};

const Token = struct {
    account_type: []const u8 = "",
    digits: u8,
    encrypted_seed: []const u8,
    key_derivation_iterations: u32,
    name: []const u8,
    original_name: []const u8 = "",
    password_timestamp: u64 = 0,
    salt: []const u8,
    unique_id: []const u8,
};

const AppsResponse = struct {
    message: []const u8 = "",
    apps: []const App = &.{},
    deleted: []const App = &.{},
    success: bool = true,
};

const App = struct {
    _id: []const u8,
    name: []const u8,
    serial_id: u32,
    version: u32,
    assets_group: []const u8,
    authy_id: u64,
    secret_seed: []const u8,
    digits: u8,
};

fn tokenDescription(token: Token) []const u8 {
    if (token.original_name.len > 0) return token.original_name;
    if (token.name.len > 0) return token.name;
    return token.unique_id;
}

fn decryptToken(allocator: std.mem.Allocator, token: Token, password: []const u8) ![]u8 {
    var key: [32]u8 = undefined;
    try std.crypto.pwhash.pbkdf2(&key, password, token.salt, token.key_derivation_iterations, std.crypto.auth.hmac.HmacSha1);
    const ciphertext = try shared.base64DecodeAlloc(allocator, token.encrypted_seed);
    defer allocator.free(ciphertext);
    const plaintext = try shared.aes256CbcDecryptAlloc(allocator, ciphertext, key);
    return std.ascii.allocUpperString(allocator, plaintext);
}

fn encryptToken(allocator: std.mem.Allocator, entry: model.Entry, password: []const u8, io: std.Io, index: usize) !Token {
    const salt = try shared.randomHexAlloc(allocator, io, 8);
    var key: [32]u8 = undefined;
    try std.crypto.pwhash.pbkdf2(&key, password, salt, 1000, std.crypto.auth.hmac.HmacSha1);
    const lower = try std.ascii.allocLowerString(allocator, entry.secret);
    defer allocator.free(lower);
    const ciphertext = try shared.aes256CbcEncryptAlloc(allocator, lower, key);
    defer allocator.free(ciphertext);
    return .{
        .digits = entry.digits,
        .encrypted_seed = try shared.base64EncodeAlloc(allocator, ciphertext),
        .key_derivation_iterations = 1000,
        .name = try shared.dup(allocator, entry.account_name),
        .original_name = if (entry.issuer.len > 0) try std.fmt.allocPrint(allocator, "{s} ({s})", .{ entry.issuer, entry.account_name }) else "",
        .salt = salt,
        .unique_id = try std.fmt.allocPrint(allocator, "token-{d}", .{index}),
    };
}

pub fn importBackup(allocator: std.mem.Allocator, bytes: []const u8, password: []const u8, now: i64) ![]const model.Entry {
    const backup = try std.json.parseFromSliceLeaky(Backup, allocator, bytes, .{ .allocate = .alloc_always });
    var entries = std.ArrayList(model.Entry).empty;
    defer entries.deinit(allocator);
    for (backup.tokens.authenticator_tokens, 0..) |token, i| {
        try entries.append(allocator, .{
            .id = try std.fmt.allocPrint(allocator, "authy-token-{d}", .{i}),
            .issuer = "Authy",
            .account_name = try shared.dup(allocator, tokenDescription(token)),
            .secret = try decryptToken(allocator, token, password),
            .kind = .totp,
            .digits = token.digits,
            .period = 30,
            .algorithm = .sha1,
            .source_format = "authy",
            .created_at = now,
            .updated_at = now,
        });
    }
    for (backup.apps.apps, 0..) |app, i| {
        const seed_bytes = try shared.hexDecodeAlloc(allocator, app.secret_seed);
        defer allocator.free(seed_bytes);
        try entries.append(allocator, .{
            .id = try std.fmt.allocPrint(allocator, "authy-app-{d}", .{i}),
            .issuer = "Authy",
            .account_name = try shared.dup(allocator, app.name),
            .secret = try base32.encodeAlloc(allocator, seed_bytes),
            .kind = .totp,
            .digits = app.digits,
            .period = 10,
            .algorithm = .sha1,
            .source_format = "authy",
            .created_at = now,
            .updated_at = now,
        });
    }
    return entries.toOwnedSlice(allocator);
}

pub fn exportBackup(allocator: std.mem.Allocator, io: std.Io, entries: []const model.Entry, password: []const u8) ![]u8 {
    var tokens = std.ArrayList(Token).empty;
    defer tokens.deinit(allocator);
    var apps = std.ArrayList(App).empty;
    defer apps.deinit(allocator);
    for (entries, 0..) |entry, i| {
        if (entry.kind != .totp) return error.UnsupportedEntryKind;
        if (entry.period == 10 and entry.digits == 7 and entry.algorithm == .sha1) {
            const secret_seed = try base32.decodeAlloc(allocator, entry.secret);
            defer allocator.free(secret_seed);
            try apps.append(allocator, .{
                ._id = try std.fmt.allocPrint(allocator, "app-{d}", .{i}),
                .name = try shared.dup(allocator, entry.account_name),
                .serial_id = @intCast(i + 1),
                .version = 1,
                .assets_group = "default",
                .authy_id = 0,
                .secret_seed = try shared.hexEncodeAlloc(allocator, secret_seed),
                .digits = entry.digits,
            });
        } else {
            try tokens.append(allocator, try encryptToken(allocator, entry, password, io, i));
        }
    }
    return std.fmt.allocPrint(allocator, "{f}\n", .{std.json.fmt(Backup{
        .tokens = .{ .authenticator_tokens = try tokens.toOwnedSlice(allocator) },
        .apps = .{ .apps = try apps.toOwnedSlice(allocator) },
    }, .{ .whitespace = .indent_2 })});
}

test "authy backup export import roundtrip" {
    const testing = std.testing;
    const entries = [_]model.Entry{
        .{
            .id = "one",
            .issuer = "Deno",
            .account_name = "Mason",
            .secret = "4SJHB4GSD43FZBAI7C2HLRJGPQ",
            .digits = 6,
            .period = 30,
            .algorithm = .sha1,
            .created_at = 0,
            .updated_at = 0,
        },
    };
    const exported = try exportBackup(testing.allocator, std.Io.Threaded.init_single_threaded, &entries, "authy-pass");
    defer testing.allocator.free(exported);
    const imported = try importBackup(testing.allocator, exported, "authy-pass", 0);
    try testing.expectEqual(@as(usize, 1), imported.len);
    try testing.expectEqualStrings("Authy", imported[0].issuer);
    try testing.expectEqualStrings("Deno (Mason)", imported[0].account_name);
    try testing.expectEqual(model.EntryKind.totp, imported[0].kind);
}
