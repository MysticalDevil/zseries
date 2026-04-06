const std = @import("std");

pub const Algorithm = enum {
    HS256,
    HS384,
    HS512,
    RS256,
    RS384,
    RS512,
    ES256,
    ES384,
    ES512,

    pub fn isHmac(self: Algorithm) bool {
        return switch (self) {
            .HS256, .HS384, .HS512 => true,
            else => false,
        };
    }

    pub fn isRsa(self: Algorithm) bool {
        return switch (self) {
            .RS256, .RS384, .RS512 => true,
            else => false,
        };
    }

    pub fn isEcdsa(self: Algorithm) bool {
        return switch (self) {
            .ES256, .ES384, .ES512 => true,
            else => false,
        };
    }

    pub fn jwtName(self: Algorithm) []const u8 {
        return switch (self) {
            .HS256 => "HS256",
            .HS384 => "HS384",
            .HS512 => "HS512",
            .RS256 => "RS256",
            .RS384 => "RS384",
            .RS512 => "RS512",
            .ES256 => "ES256",
            .ES384 => "ES384",
            .ES512 => "ES512",
        };
    }

    pub fn fromString(name: []const u8) ?Algorithm {
        const map = std.StaticStringMap(Algorithm).initComptime(.{
            .{ "HS256", .HS256 },
            .{ "HS384", .HS384 },
            .{ "HS512", .HS512 },
            .{ "RS256", .RS256 },
            .{ "RS384", .RS384 },
            .{ "RS512", .RS512 },
            .{ "ES256", .ES256 },
            .{ "ES384", .ES384 },
            .{ "ES512", .ES512 },
        });
        return map.get(name);
    }

    pub fn hashLength(self: Algorithm) usize {
        return switch (self) {
            .HS256, .RS256, .ES256 => 32,
            .HS384, .RS384, .ES384 => 48,
            .HS512, .RS512, .ES512 => 64,
        };
    }
};

const testing = std.testing;

test "algorithm type checks" {
    try testing.expect(Algorithm.HS256.isHmac());
    try testing.expect(!Algorithm.HS256.isRsa());
    try testing.expect(!Algorithm.HS256.isEcdsa());

    try testing.expect(Algorithm.RS256.isRsa());
    try testing.expect(!Algorithm.RS256.isHmac());

    try testing.expect(Algorithm.ES256.isEcdsa());
    try testing.expect(!Algorithm.ES256.isHmac());
}

test "algorithm name conversion" {
    try testing.expectEqualStrings("HS256", Algorithm.HS256.jwtName());
    try testing.expectEqualStrings("RS256", Algorithm.RS256.jwtName());
    try testing.expectEqualStrings("ES256", Algorithm.ES256.jwtName());
}

test "algorithm from string" {
    try testing.expectEqual(Algorithm.HS256, Algorithm.fromString("HS256").?);
    try testing.expectEqual(Algorithm.RS256, Algorithm.fromString("RS256").?);
    try testing.expectEqual(null, Algorithm.fromString("INVALID"));
}

test "hash lengths" {
    try testing.expectEqual(@as(usize, 32), Algorithm.HS256.hashLength());
    try testing.expectEqual(@as(usize, 48), Algorithm.HS384.hashLength());
    try testing.expectEqual(@as(usize, 64), Algorithm.HS512.hashLength());
}
