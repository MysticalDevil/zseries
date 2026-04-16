const std = @import("std");
const time = @import("time.zig");
const algorithm_zig = @import("algorithm.zig");
const claims_zig = @import("claims.zig");
const token_zig = @import("token.zig");
const key_zig = @import("key.zig");
const Algorithm = algorithm_zig.Algorithm;
const Claims = claims_zig.Claims;
const Header = token_zig.Header;
const Token = token_zig.Token;
const Key = key_zig.Key;
const base64UrlEncode = token_zig.base64UrlEncode;

pub const Encoder = struct {
    allocator: std.mem.Allocator,
    algorithm: Algorithm,
    key: Key,
    io: std.Io,

    pub fn init(allocator: std.mem.Allocator, algorithm: Algorithm, key: Key, io: std.Io) Encoder {
        return .{
            .allocator = allocator,
            .algorithm = algorithm,
            .key = key,
            .io = io,
        };
    }

    pub fn encode(self: *Encoder, claims: Claims) ![]const u8 {
        const header = Header{
            .alg = self.algorithm,
            .typ = "JWT",
        };

        return self.encodeWithHeader(header, claims);
    }

    pub fn encodeWithHeader(self: *Encoder, header: Header, claims: Claims) ![]const u8 {
        // Encode header
        const header_json = try header.toJson(self.allocator);
        defer self.allocator.free(header_json);

        const header_b64 = try base64UrlEncode(self.allocator, header_json);
        defer self.allocator.free(header_b64);

        // Encode claims
        const claims_json = try claimsToJson(self.allocator, claims);
        defer self.allocator.free(claims_json);

        const claims_b64 = try base64UrlEncode(self.allocator, claims_json);
        defer self.allocator.free(claims_b64);

        // Create signing input
        const signing_input_len = header_b64.len + 1 + claims_b64.len;
        const signing_input = try self.allocator.alloc(u8, signing_input_len);
        defer self.allocator.free(signing_input);

        @memcpy(signing_input[0..header_b64.len], header_b64);
        signing_input[header_b64.len] = '.';
        @memcpy(signing_input[header_b64.len + 1 ..], claims_b64);

        // Sign
        const signature = try self.sign(signing_input);
        defer self.allocator.free(signature);

        const signature_b64 = try base64UrlEncode(self.allocator, signature);
        defer self.allocator.free(signature_b64);

        // Combine all parts
        const token_len = signing_input_len + 1 + signature_b64.len;
        const token = try self.allocator.alloc(u8, token_len);

        @memcpy(token[0..signing_input_len], signing_input);
        token[signing_input_len] = '.';
        @memcpy(token[signing_input_len + 1 ..], signature_b64);

        return token;
    }

    fn sign(self: *Encoder, data: []const u8) ![]const u8 {
        return switch (self.algorithm) {
            .HS256 => try signHmac(self.allocator, data, self.key.hmac, .sha256),
            .HS384 => try signHmac(self.allocator, data, self.key.hmac, .sha384),
            .HS512 => try signHmac(self.allocator, data, self.key.hmac, .sha512),
            else => error.UnsupportedAlgorithm,
        };
    }

    fn signHmac(allocator: std.mem.Allocator, data: []const u8, secret: []const u8, comptime hash_type: enum { sha256, sha384, sha512 }) ![]const u8 {
        const Hmac = switch (hash_type) {
            .sha256 => std.crypto.auth.hmac.sha2.HmacSha256,
            .sha384 => std.crypto.auth.hmac.sha2.HmacSha384,
            .sha512 => std.crypto.auth.hmac.sha2.HmacSha512,
        };

        const sig = try allocator.alloc(u8, Hmac.mac_length);
        Hmac.create(sig[0..Hmac.mac_length], data, secret);
        return sig;
    }
};

fn claimsToJson(allocator: std.mem.Allocator, claims: Claims) ![]const u8 {
    var obj: std.json.ObjectMap = .{};
    defer {
        var it = obj.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            claims_zig.freeJsonValue(allocator, entry.value_ptr.*);
        }
        obj.deinit(allocator);
    }

    // Add registered claims (deep copy values so obj fully owns them)
    if (claims.iss) |iss| {
        const k = try allocator.dupe(u8, "iss");
        errdefer allocator.free(k);
        const v = try allocator.dupe(u8, iss);
        try obj.put(allocator, k, .{ .string = v });
    }
    if (claims.sub) |sub| {
        const k = try allocator.dupe(u8, "sub");
        errdefer allocator.free(k);
        const v = try allocator.dupe(u8, sub);
        try obj.put(allocator, k, .{ .string = v });
    }
    if (claims.aud) |aud| {
        const k = try allocator.dupe(u8, "aud");
        errdefer allocator.free(k);
        const v = try allocator.dupe(u8, aud);
        try obj.put(allocator, k, .{ .string = v });
    }
    if (claims.exp) |exp| {
        const k = try allocator.dupe(u8, "exp");
        errdefer allocator.free(k);
        try obj.put(allocator, k, .{ .integer = exp });
    }
    if (claims.nbf) |nbf| {
        const k = try allocator.dupe(u8, "nbf");
        errdefer allocator.free(k);
        try obj.put(allocator, k, .{ .integer = nbf });
    }
    if (claims.iat) |iat| {
        const k = try allocator.dupe(u8, "iat");
        errdefer allocator.free(k);
        try obj.put(allocator, k, .{ .integer = iat });
    }
    if (claims.jti) |jti| {
        const k = try allocator.dupe(u8, "jti");
        errdefer allocator.free(k);
        const v = try allocator.dupe(u8, jti);
        try obj.put(allocator, k, .{ .string = v });
    }

    // Add custom claims
    var iter = claims.custom.iterator();
    while (iter.next()) |entry| {
        const k = try allocator.dupe(u8, entry.key_ptr.*);
        errdefer allocator.free(k);
        const v = try claims_zig.cloneJsonValue(allocator, entry.value_ptr.*);
        try obj.put(allocator, k, v);
    }

    const value = std.json.Value{ .object = obj };
    var writer: std.Io.Writer.Allocating = .init(allocator);
    defer writer.deinit();
    try std.json.Stringify.value(value, .{}, &writer.writer);
    return writer.toOwnedSlice();
}

const testing = std.testing;

test "encode and verify hmac token" {
    const allocator = testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    var claims = Claims.init(allocator);
    defer claims.deinit();

    claims.sub = try allocator.dupe(u8, "user123");
    claims.exp = time.nowSeconds(io) + 3600;
    try claims.setString("role", "admin");

    const secret = "my-secret-key";
    var encoder = Encoder.init(allocator, .HS256, Key.fromHmacSecret(secret), io);

    const token = try encoder.encode(claims);
    defer allocator.free(token);

    try testing.expect(std.mem.indexOf(u8, token, ".") != null);
    try testing.expectEqual(@as(usize, 2), std.mem.count(u8, token, "."));
}
