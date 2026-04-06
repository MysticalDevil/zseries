const std = @import("std");

pub const Claims = struct {
    allocator: std.mem.Allocator,

    // Registered claims (RFC 7519)
    iss: ?[]const u8 = null, // Issuer
    sub: ?[]const u8 = null, // Subject
    aud: ?[]const u8 = null, // Audience
    exp: ?i64 = null, // Expiration Time
    nbf: ?i64 = null, // Not Before
    iat: ?i64 = null, // Issued At
    jti: ?[]const u8 = null, // JWT ID

    // Custom claims
    custom: std.StringHashMap(std.json.Value),

    pub fn init(allocator: std.mem.Allocator) Claims {
        return .{
            .allocator = allocator,
            .custom = std.StringHashMap(std.json.Value).init(allocator),
        };
    }

    pub fn deinit(self: *Claims) void {
        self.custom.deinit();
    }

    pub fn get(self: *const Claims, key: []const u8) ?std.json.Value {
        return self.custom.get(key);
    }

    pub fn getString(self: *const Claims, key: []const u8) ?[]const u8 {
        const val = self.custom.get(key) orelse return null;
        return switch (val) {
            .string => |s| s,
            else => null,
        };
    }

    pub fn getInt(self: *const Claims, key: []const u8) ?i64 {
        const val = self.custom.get(key) orelse return null;
        return switch (val) {
            .integer => |i| i,
            else => null,
        };
    }

    pub fn getArray(self: *const Claims, key: []const u8) ?[]std.json.Value {
        const val = self.custom.get(key) orelse return null;
        return switch (val) {
            .array => |arr| arr.items,
            else => null,
        };
    }

    pub fn set(self: *Claims, key: []const u8, value: std.json.Value) !void {
        try self.custom.put(key, value);
    }

    pub fn setString(self: *Claims, key: []const u8, value: []const u8) !void {
        try self.custom.put(key, .{ .string = value });
    }

    pub fn setInt(self: *Claims, key: []const u8, value: i64) !void {
        try self.custom.put(key, .{ .integer = value });
    }

    pub fn isExpired(self: *const Claims, now: i64, clock_skew: i64) bool {
        const exp = self.exp orelse return false;
        return now > exp + clock_skew;
    }

    pub fn isNotBefore(self: *const Claims, now: i64, clock_skew: i64) bool {
        const nbf = self.nbf orelse return false;
        return now < nbf - clock_skew;
    }

    pub fn validate(self: *const Claims, now: i64, options: ValidateOptions) !void {
        if (self.isExpired(now, options.clock_skew)) {
            return error.TokenExpired;
        }

        if (self.isNotBefore(now, options.clock_skew)) {
            return error.TokenNotYetValid;
        }

        if (options.issuer) |issuer| {
            const iss = self.iss orelse return error.InvalidIssuer;
            if (!std.mem.eql(u8, iss, issuer)) {
                return error.InvalidIssuer;
            }
        }

        if (options.audience) |audience| {
            const aud = self.aud orelse return error.InvalidAudience;
            if (!std.mem.eql(u8, aud, audience)) {
                return error.InvalidAudience;
            }
        }
    }
};

pub const ValidateOptions = struct {
    clock_skew: i64 = 60, // seconds
    issuer: ?[]const u8 = null,
    audience: ?[]const u8 = null,
};

const testing = std.testing;

test "claims expiration check" {
    var claims = Claims.init(testing.allocator);
    defer claims.deinit();

    claims.exp = std.time.timestamp() + 3600; // 1 hour from now

    const now = std.time.timestamp();
    try testing.expect(!claims.isExpired(now, 60));

    claims.exp = now - 1; // 1 second ago
    try testing.expect(claims.isExpired(now, 0));
}

test "claims validation" {
    var claims = Claims.init(testing.allocator);
    defer claims.deinit();

    claims.iss = "test-issuer";
    claims.aud = "test-audience";
    claims.exp = std.time.timestamp() + 3600;

    const now = std.time.timestamp();
    try claims.validate(now, .{ .issuer = "test-issuer", .audience = "test-audience" });

    const result = claims.validate(now, .{ .issuer = "wrong-issuer" });
    try testing.expectError(error.InvalidIssuer, result);
}

test "claims custom fields" {
    var claims = Claims.init(testing.allocator);
    defer claims.deinit();

    try claims.setString("role", "admin");
    try claims.setInt("user_id", 42);

    try testing.expectEqualStrings("admin", claims.getString("role").?);
    try testing.expectEqual(@as(i64, 42), claims.getInt("user_id").?);
}
