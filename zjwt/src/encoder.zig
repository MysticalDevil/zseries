const std = @import("std");
const Algorithm = @import("algorithm.zig").Algorithm;
const Claims = @import("claims.zig").Claims;
const Header = @import("token.zig").Header;
const Token = @import("token.zig").Token;
const Key = @import("key.zig").Key;
const base64UrlEncode = @import("token.zig").base64UrlEncode;

pub const Encoder = struct {
    allocator: std.mem.Allocator,
    algorithm: Algorithm,
    key: Key,

    pub fn init(allocator: std.mem.Allocator, algorithm: Algorithm, key: Key) Encoder {
        return .{
            .allocator = allocator,
            .algorithm = algorithm,
            .key = key,
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
        Hmac.create(sig, data, secret);
        return sig;
    }
};

fn claimsToJson(allocator: std.mem.Allocator, claims: Claims) ![]const u8 {
    var map = std.StringHashMap(std.json.Value).init(allocator);
    defer map.deinit();

    // Add registered claims
    if (claims.iss) |iss| try map.put("iss", .{ .string = iss });
    if (claims.sub) |sub| try map.put("sub", .{ .string = sub });
    if (claims.aud) |aud| try map.put("aud", .{ .string = aud });
    if (claims.exp) |exp| try map.put("exp", .{ .integer = exp });
    if (claims.nbf) |nbf| try map.put("nbf", .{ .integer = nbf });
    if (claims.iat) |iat| try map.put("iat", .{ .integer = iat });
    if (claims.jti) |jti| try map.put("jti", .{ .string = jti });

    // Add custom claims
    var iter = claims.custom.iterator();
    while (iter.next()) |entry| {
        try map.put(entry.key_ptr.*, entry.value_ptr.*);
    }

    var json = std.ArrayList(u8).init(allocator);
    try std.json.stringify(map, .{}, json.writer());
    return json.toOwnedSlice();
}

const testing = std.testing;

test "encode and verify hmac token" {
    const allocator = testing.allocator;

    var claims = Claims.init(allocator);
    defer claims.deinit();

    claims.sub = "user123";
    claims.exp = std.time.timestamp() + 3600;
    try claims.setString("role", "admin");

    const secret = "my-secret-key";
    var encoder = Encoder.init(allocator, .HS256, Key.fromHmacSecret(secret));

    const token = try encoder.encode(claims);
    defer allocator.free(token);

    try testing.expect(std.mem.indexOf(u8, token, ".") != null);
    try testing.expectEqual(@as(usize, 2), std.mem.count(u8, token, "."));
}
