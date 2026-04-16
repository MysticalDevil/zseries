const std = @import("std");
const algorithm_zig = @import("algorithm.zig");
const claims_zig = @import("claims.zig");
const token_zig = @import("token.zig");
const key_zig = @import("key.zig");
const encoder_zig = @import("encoder.zig");
const Algorithm = algorithm_zig.Algorithm;
const Claims = claims_zig.Claims;
const Header = token_zig.Header;
const Key = key_zig.Key;
const base64UrlDecode = token_zig.base64UrlDecode;
const Encoder = encoder_zig.Encoder;

pub const Verifier = struct {
    allocator: std.mem.Allocator,
    algorithm: Algorithm,
    key: Key,
    options: VerifyOptions,

    pub const VerifyOptions = struct {
        clock_skew: i64 = 60,
        issuer: ?[]const u8 = null,
        audience: ?[]const u8 = null,
        sliding_expiration: bool = true,
        sliding_window: i64 = 300,
    };

    pub fn init(allocator: std.mem.Allocator, algorithm: Algorithm, key: Key, options: VerifyOptions) Verifier {
        return .{
            .allocator = allocator,
            .algorithm = algorithm,
            .key = key,
            .options = options,
        };
    }

    pub fn verify(self: *Verifier, token_str: []const u8) !VerifiedToken {
        var parts = std.mem.splitScalar(u8, token_str, '.');
        const header_b64 = parts.next() orelse return error.InvalidToken;
        const claims_b64 = parts.next() orelse return error.InvalidToken;
        const signature_b64 = parts.next() orelse return error.InvalidToken;

        if (parts.next() != null) return error.InvalidToken;

        const header_json = try base64UrlDecode(self.allocator, header_b64);
        defer self.allocator.free(header_json);

        const header = try parseHeader(self.allocator, header_json);

        if (header.alg != self.algorithm) {
            return error.AlgorithmMismatch;
        }

        const claims_json = try base64UrlDecode(self.allocator, claims_b64);
        defer self.allocator.free(claims_json);

        var claims = try parseClaims(self.allocator, claims_json);

        const signing_input_len = header_b64.len + 1 + claims_b64.len;
        const signing_input = try self.allocator.alloc(u8, signing_input_len);
        defer self.allocator.free(signing_input);

        @memcpy(signing_input[0..header_b64.len], header_b64);
        signing_input[header_b64.len] = '.';
        @memcpy(signing_input[header_b64.len + 1 ..], claims_b64);

        const signature = try base64UrlDecode(self.allocator, signature_b64);
        defer self.allocator.free(signature);

        const valid = try self.verifySignature(signing_input, signature);
        if (!valid) {
            return error.InvalidSignature;
        }

        const now = std.time.timestamp();
        try claims.validate(now, .{
            .clock_skew = self.options.clock_skew,
            .issuer = self.options.issuer,
            .audience = self.options.audience,
        });

        var new_token: ?[]const u8 = null;
        if (self.options.sliding_expiration) {
            if (claims.exp) |exp| {
                const time_remaining = exp - now;

                if (time_remaining < self.options.sliding_window) {
                    if (claims.iat) |iat| {
                        claims.exp = now + (exp - iat);

                        var encoder = Encoder.init(self.allocator, self.algorithm, self.key);
                        new_token = try encoder.encode(claims);
                    }
                }
            }
        }

        const raw_copy = try self.allocator.dupe(u8, token_str);

        return VerifiedToken{
            .allocator = self.allocator,
            .header = header,
            .claims = claims,
            .signature = signature,
            .raw = raw_copy,
            .new_token = new_token,
        };
    }

    fn verifySignature(self: *Verifier, data: []const u8, signature: []const u8) !bool {
        return switch (self.algorithm) {
            .HS256 => try verifyHmac(data, signature, self.key.hmac, .sha256),
            .HS384 => try verifyHmac(data, signature, self.key.hmac, .sha384),
            .HS512 => try verifyHmac(data, signature, self.key.hmac, .sha512),
            else => error.UnsupportedAlgorithm,
        };
    }

    fn verifyHmac(data: []const u8, signature: []const u8, secret: []const u8, comptime hash_type: enum { sha256, sha384, sha512 }) !bool {
        const Hmac = switch (hash_type) {
            .sha256 => std.crypto.auth.hmac.sha2.HmacSha256,
            .sha384 => std.crypto.auth.hmac.sha2.HmacSha384,
            .sha512 => std.crypto.auth.hmac.sha2.HmacSha512,
        };

        if (signature.len != Hmac.mac_length) return false;

        var expected: [Hmac.mac_length]u8 = undefined;
        Hmac.create(&expected, data, secret);

        return std.crypto.timing_safe.eql([Hmac.mac_length]u8, expected, signature[0..Hmac.mac_length]);
    }
};

pub const VerifiedToken = struct {
    allocator: std.mem.Allocator,
    header: Header,
    claims: Claims,
    signature: []const u8,
    raw: []const u8,
    new_token: ?[]const u8,

    pub fn deinit(self: *VerifiedToken) void {
        self.claims.deinit();
        self.allocator.free(self.signature);
        self.allocator.free(self.raw);
        if (self.new_token) |token| {
            self.allocator.free(token);
        }
    }
};

fn parseHeader(allocator: std.mem.Allocator, json: []const u8) !Header {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();

    const root = parsed.value;

    const alg_str = root.object.get("alg") orelse return error.MissingAlgorithm;
    const alg = Algorithm.fromString(alg_str.string) orelse return error.InvalidAlgorithm;

    const typ = root.object.get("typ");
    const kid = root.object.get("kid");

    return Header{
        .alg = alg,
        .typ = if (typ) |t| t.string else "JWT",
        .kid = if (kid) |k| k.string else null,
    };
}

fn parseClaims(allocator: std.mem.Allocator, json: []const u8) !Claims {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();

    const root = parsed.value;
    var claims = Claims.init(allocator);

    if (root.object.get("iss")) |v| claims.iss = try allocator.dupe(u8, v.string);
    if (root.object.get("sub")) |v| claims.sub = try allocator.dupe(u8, v.string);
    if (root.object.get("aud")) |v| claims.aud = try allocator.dupe(u8, v.string);
    if (root.object.get("exp")) |v| claims.exp = v.integer;
    if (root.object.get("nbf")) |v| claims.nbf = v.integer;
    if (root.object.get("iat")) |v| claims.iat = v.integer;
    if (root.object.get("jti")) |v| claims.jti = try allocator.dupe(u8, v.string);

    var iter = root.object.iterator();
    while (iter.next()) |entry| {
        const key = entry.key_ptr.*;
        if (std.mem.eql(u8, key, "iss") or
            std.mem.eql(u8, key, "sub") or
            std.mem.eql(u8, key, "aud") or
            std.mem.eql(u8, key, "exp") or
            std.mem.eql(u8, key, "nbf") or
            std.mem.eql(u8, key, "iat") or
            std.mem.eql(u8, key, "jti"))
        {
            continue;
        }
        try claims.custom.put(key, entry.value_ptr.*);
    }

    return claims;
}
