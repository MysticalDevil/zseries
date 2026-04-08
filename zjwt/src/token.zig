const std = @import("std");
const Algorithm = @import("algorithm.zig").Algorithm;
const Claims = @import("claims.zig").Claims;

pub const Header = struct {
    alg: Algorithm,
    typ: []const u8 = "JWT",
    kid: ?[]const u8 = null, // Key ID

    pub fn toJson(self: Header, allocator: std.mem.Allocator) ![]const u8 {
        var map = std.StringHashMap(std.json.Value).init(allocator);
        defer map.deinit();

        try map.put("alg", .{ .string = self.alg.jwtName() });
        try map.put("typ", .{ .string = self.typ });

        if (self.kid) |kid| {
            try map.put("kid", .{ .string = kid });
        }

        var json = std.ArrayList(u8).init(allocator);
        try std.json.stringify(map, .{}, json.writer());
        return json.toOwnedSlice();
    }
};

pub const Token = struct {
    allocator: std.mem.Allocator,
    header: Header,
    claims: Claims,
    signature: []const u8,
    raw: []const u8, // Original JWT string

    pub fn deinit(self: *Token) void {
        self.claims.deinit();
        self.allocator.free(self.signature);
        self.allocator.free(self.raw);
    }

    pub fn parts(self: *const Token) Parts {
        var iter = std.mem.splitScalar(u8, self.raw, '.');
        return Parts{
            .header = iter.next() orelse "",
            .payload = iter.next() orelse "",
            .signature = iter.next() orelse "",
        };
    }
};

pub const Parts = struct {
    header: []const u8,
    payload: []const u8,
    signature: []const u8,
};

pub fn base64UrlEncode(allocator: std.mem.Allocator, data: []const u8) ![]const u8 {
    const encoded = try allocator.alloc(u8, std.base64.url_safe_no_pad.Encoder.calcSize(data.len));
    const written = std.base64.url_safe_no_pad.Encoder.encode(encoded, data);
    if (written.len != encoded.len) return error.EncodingFailed;
    return encoded;
}

pub fn base64UrlDecode(allocator: std.mem.Allocator, data: []const u8) ![]const u8 {
    const decoded_len = try std.base64.url_safe_no_pad.Decoder.calcSizeForSlice(data);
    const decoded = try allocator.alloc(u8, decoded_len);
    try std.base64.url_safe_no_pad.Decoder.decode(decoded, data);

    return decoded;
}

const testing = std.testing;

test "base64url encoding" {
    const allocator = testing.allocator;

    const data = "hello+world/test";
    const encoded = try base64UrlEncode(allocator, data);
    defer allocator.free(encoded);

    const decoded = try base64UrlDecode(allocator, encoded);
    defer allocator.free(decoded);

    try testing.expectEqualStrings(data, decoded);
}

test "header to json" {
    const header = Header{
        .alg = .HS256,
        .typ = "JWT",
    };

    const json = try header.toJson(testing.allocator);
    defer testing.allocator.free(json);

    try testing.expect(std.mem.indexOf(u8, json, "\"alg\":\"HS256\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"typ\":\"JWT\"") != null);
}
