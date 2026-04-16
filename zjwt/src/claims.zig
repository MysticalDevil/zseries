const std = @import("std");
const time = @import("time.zig");

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
        if (self.iss) |s| self.allocator.free(s);
        if (self.sub) |s| self.allocator.free(s);
        if (self.aud) |s| self.allocator.free(s);
        if (self.jti) |s| self.allocator.free(s);
        var it = self.custom.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            freeJsonValue(self.allocator, entry.value_ptr.*);
        }
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
        const k = try self.allocator.dupe(u8, key);
        errdefer self.allocator.free(k);
        const v = try cloneJsonValue(self.allocator, value);
        try self.custom.put(k, v);
    }

    pub fn setString(self: *Claims, key: []const u8, value: []const u8) !void {
        const k = try self.allocator.dupe(u8, key);
        errdefer self.allocator.free(k);
        const v = try self.allocator.dupe(u8, value);
        try self.custom.put(k, .{ .string = v });
    }

    pub fn setInt(self: *Claims, key: []const u8, value: i64) !void {
        const k = try self.allocator.dupe(u8, key);
        errdefer self.allocator.free(k);
        try self.custom.put(k, .{ .integer = value });
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

pub fn cloneJsonValue(allocator: std.mem.Allocator, v: std.json.Value) !std.json.Value {
    switch (v) {
        .null => return .null,
        .bool => |b| return .{ .bool = b },
        .integer => |i| return .{ .integer = i },
        .float => |f| return .{ .float = f },
        .number_string => |s| return .{ .number_string = try allocator.dupe(u8, s) },
        .string => |s| return .{ .string = try allocator.dupe(u8, s) },
        .array => |arr| {
            var new = std.json.Array.init(allocator);
            errdefer new.deinit();
            for (arr.items) |item| {
                try new.append(try cloneJsonValue(allocator, item));
            }
            return .{ .array = new };
        },
        .object => {
            var new = try std.json.ObjectMap.init(allocator, &.{}, &.{});
            errdefer {
                var it = new.iterator();
                while (it.next()) |entry| {
                    allocator.free(entry.key_ptr.*);
                    freeJsonValue(allocator, entry.value_ptr.*);
                }
                new.deinit(allocator);
            }
            var it = v.object.iterator();
            while (it.next()) |entry| {
                const k = try allocator.dupe(u8, entry.key_ptr.*);
                errdefer allocator.free(k);
                const val = try cloneJsonValue(allocator, entry.value_ptr.*);
                try new.put(allocator, k, val);
            }
            return .{ .object = new };
        },
    }
}

pub fn freeJsonValue(allocator: std.mem.Allocator, v: std.json.Value) void {
    switch (v) {
        .number_string => |s| allocator.free(s),
        .string => |s| allocator.free(s),
        .array => |arr| {
            for (arr.items) |item| freeJsonValue(allocator, item);
            arr.deinit();
        },
        .object => {
            var obj = v.object;
            var it = obj.iterator();
            while (it.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                freeJsonValue(allocator, entry.value_ptr.*);
            }
            obj.deinit(allocator);
        },
        .null, .bool, .integer, .float => {},
    }
}

const testing = std.testing;

fn testIo() std.Io {
    return std.Io.Threaded.global_single_threaded.io();
}

test "claims expiration check" {
    var claims = Claims.init(testing.allocator);
    defer claims.deinit();

    const io = testIo();
    claims.exp = time.nowSeconds(io) + 3600; // 1 hour from now

    const now = time.nowSeconds(io);
    try testing.expect(!claims.isExpired(now, 60));

    claims.exp = now - 1; // 1 second ago
    try testing.expect(claims.isExpired(now, 0));
}

test "claims validation" {
    var claims = Claims.init(testing.allocator);
    defer claims.deinit();

    const io = testIo();
    claims.iss = try testing.allocator.dupe(u8, "test-issuer");
    claims.aud = try testing.allocator.dupe(u8, "test-audience");
    claims.exp = time.nowSeconds(io) + 3600;

    const now = time.nowSeconds(io);
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
