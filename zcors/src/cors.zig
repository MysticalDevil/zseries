const std = @import("std");

pub const Config = struct {
    /// Allowed origins. Empty slice means allow any origin (`*`).
    origins: []const []const u8 = &.{},
    /// Allowed methods for preflight (e.g. `GET,POST,PUT`).
    methods: []const []const u8 = &.{ "GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS" },
    /// Allowed headers for preflight (e.g. `Content-Type,Authorization`).
    headers: []const []const u8 = &.{},
    /// Whether to allow credentials.
    credentials: bool = false,
    /// Max-Age for preflight cache in seconds.
    max_age: ?u32 = null,
};

/// Returns a `BeforeHook` that handles CORS preflight (`OPTIONS`) requests.
/// Requires `Context` to provide `.method` (std.http.Method) in addition to
/// the minimum middleware interface (`header`, `status`, `setHeader`).
pub fn beforeHook(comptime Context: type, config: Config) *const fn (*Context) anyerror!void {
    const Closure = struct {
        var c: Config = undefined;

        fn hook(ctx: *Context) !void {
            if (ctx.method != .OPTIONS) return;

            const origin = ctx.header("Origin") orelse return;
            if (!isOriginAllowed(origin, c.origins)) {
                return error.CorsOriginNotAllowed;
            }

            try ctx.setHeader("Access-Control-Allow-Origin", origin);

            if (c.credentials) {
                try ctx.setHeader("Access-Control-Allow-Credentials", "true");
            }

            if (c.methods.len > 0) {
                const methods = try joinSlice(ctx.allocator, ",", c.methods);
                defer ctx.allocator.free(methods);
                try ctx.setHeader("Access-Control-Allow-Methods", methods);
            }

            if (c.headers.len > 0) {
                const headers = try joinSlice(ctx.allocator, ",", c.headers);
                defer ctx.allocator.free(headers);
                try ctx.setHeader("Access-Control-Allow-Headers", headers);
            }

            if (c.max_age) |age| {
                var buf: [32]u8 = undefined;
                const text = try std.fmt.bufPrint(&buf, "{d}", .{age});
                try ctx.setHeader("Access-Control-Max-Age", text);
            }

            ctx.status(204);
            return error.CorsPreflight;
        }
    };

    Closure.c = config;
    return Closure.hook;
}

/// Returns an `AfterHook` that adds CORS headers to the response.
/// Only requires `Context` to provide `header` and `setHeader`.
pub fn afterHook(comptime Context: type, config: Config) *const fn (*Context) anyerror!void {
    const Closure = struct {
        var c: Config = undefined;

        fn hook(ctx: *Context) !void {
            const origin = ctx.header("Origin") orelse return;
            if (!isOriginAllowed(origin, c.origins)) return;

            try ctx.setHeader("Access-Control-Allow-Origin", origin);

            if (c.credentials) {
                try ctx.setHeader("Access-Control-Allow-Credentials", "true");
            }
        }
    };

    Closure.c = config;
    return Closure.hook;
}

fn isOriginAllowed(origin: []const u8, allowed: []const []const u8) bool {
    if (allowed.len == 0) return true;
    for (allowed) |a| {
        if (std.mem.eql(u8, origin, a)) return true;
    }
    return false;
}

fn joinSlice(allocator: std.mem.Allocator, sep: []const u8, items: []const []const u8) ![]u8 {
    if (items.len == 0) return allocator.dupe(u8, "");
    var len: usize = items.len - 1;
    for (items) |it| len += it.len;
    const buf = try allocator.alloc(u8, len);
    errdefer allocator.free(buf);
    var pos: usize = 0;
    for (items, 0..) |it, i| {
        @memcpy(buf[pos..][0..it.len], it);
        pos += it.len;
        if (i < items.len - 1) {
            @memcpy(buf[pos..][0..sep.len], sep);
            pos += sep.len;
        }
    }
    return buf;
}

// ------------------------------------------------------------------
// Tests
// ------------------------------------------------------------------

const MockContext = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    method: std.http.Method,
    headers: std.StringHashMap([]const u8),
    response_status: u16,
    response_headers: std.StringHashMap([]const u8),

    fn init(allocator: std.mem.Allocator, method: std.http.Method) !Self {
        return .{
            .allocator = allocator,
            .method = method,
            .headers = std.StringHashMap([]const u8).init(allocator),
            .response_status = 200,
            .response_headers = std.StringHashMap([]const u8).init(allocator),
        };
    }

    fn deinit(self: *Self) void {
        self.headers.deinit();
        var iter = self.response_headers.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.response_headers.deinit();
    }

    fn addRequestHeader(self: *Self, name: []const u8, value: []const u8) !void {
        try self.headers.put(name, value);
    }

    fn header(self: *Self, name: []const u8) ?[]const u8 {
        return self.headers.get(name);
    }

    fn status(self: *Self, code: u16) void {
        self.response_status = code;
    }

    fn setHeader(self: *Self, name: []const u8, value: []const u8) !void {
        try self.response_headers.put(try self.allocator.dupe(u8, name), try self.allocator.dupe(u8, value));
    }
};

test "beforeHook handles preflight request" {
    const allocator = std.testing.allocator;
    var ctx = try MockContext.init(allocator, .OPTIONS);
    defer ctx.deinit();
    try ctx.addRequestHeader("Origin", "https://example.com");

    const config = Config{
        .origins = &.{"https://example.com"},
        .methods = &.{ "GET", "POST" },
        .headers = &.{"Content-Type"},
        .max_age = 86400,
    };

    const hook = beforeHook(MockContext, config);
    const err = hook(&ctx);
    try std.testing.expectError(error.CorsPreflight, err);
    try std.testing.expectEqual(@as(u16, 204), ctx.response_status);
    try std.testing.expectEqualStrings("https://example.com", ctx.response_headers.get("Access-Control-Allow-Origin").?);
    try std.testing.expectEqualStrings("GET,POST", ctx.response_headers.get("Access-Control-Allow-Methods").?);
    try std.testing.expectEqualStrings("Content-Type", ctx.response_headers.get("Access-Control-Allow-Headers").?);
    try std.testing.expectEqualStrings("86400", ctx.response_headers.get("Access-Control-Max-Age").?);
}

test "beforeHook skips non-preflight requests" {
    const allocator = std.testing.allocator;
    var ctx = try MockContext.init(allocator, .GET);
    defer ctx.deinit();
    try ctx.addRequestHeader("Origin", "https://example.com");

    const config = Config{ .origins = &.{"https://example.com"} };
    const hook = beforeHook(MockContext, config);
    try hook(&ctx);
    try std.testing.expectEqual(@as(u16, 200), ctx.response_status);
    try std.testing.expect(ctx.response_headers.get("Access-Control-Allow-Origin") == null);
}

test "beforeHook rejects disallowed origin" {
    const allocator = std.testing.allocator;
    var ctx = try MockContext.init(allocator, .OPTIONS);
    defer ctx.deinit();
    try ctx.addRequestHeader("Origin", "https://evil.com");

    const config = Config{ .origins = &.{"https://example.com"} };
    const hook = beforeHook(MockContext, config);
    const err = hook(&ctx);
    try std.testing.expectError(error.CorsOriginNotAllowed, err);
}

test "afterHook adds CORS headers to simple request" {
    const allocator = std.testing.allocator;
    var ctx = try MockContext.init(allocator, .GET);
    defer ctx.deinit();
    try ctx.addRequestHeader("Origin", "https://example.com");

    const config = Config{
        .origins = &.{"https://example.com"},
        .credentials = true,
    };

    const hook = afterHook(MockContext, config);
    try hook(&ctx);
    try std.testing.expectEqualStrings("https://example.com", ctx.response_headers.get("Access-Control-Allow-Origin").?);
    try std.testing.expectEqualStrings("true", ctx.response_headers.get("Access-Control-Allow-Credentials").?);
}

test "afterHook ignores requests without Origin" {
    const allocator = std.testing.allocator;
    var ctx = try MockContext.init(allocator, .GET);
    defer ctx.deinit();

    const config = Config{ .origins = &.{"https://example.com"} };
    const hook = afterHook(MockContext, config);
    try hook(&ctx);
    try std.testing.expect(ctx.response_headers.get("Access-Control-Allow-Origin") == null);
}

test "afterHook allows any origin when origins is empty" {
    const allocator = std.testing.allocator;
    var ctx = try MockContext.init(allocator, .GET);
    defer ctx.deinit();
    try ctx.addRequestHeader("Origin", "https://anything.com");

    const config = Config{};
    const hook = afterHook(MockContext, config);
    try hook(&ctx);
    try std.testing.expectEqualStrings("https://anything.com", ctx.response_headers.get("Access-Control-Allow-Origin").?);
}
