const std = @import("std");
const http = std.http;
const Context = @import("context.zig").Context;
const middleware = @import("middleware.zig");
const Handler = middleware.Handler;
const BeforeHook = middleware.BeforeHook;
const AfterHook = middleware.AfterHook;

pub const PathParams = struct {
    items: []Item,

    pub const Item = struct {
        name: []const u8,
        value: []const u8,
    };

    pub fn get(self: PathParams, name: []const u8) ?[]const u8 {
        for (self.items) |item| {
            if (std.mem.eql(u8, item.name, name)) return item.value;
        }
        return null;
    }

    pub fn getInt(self: PathParams, name: []const u8, comptime T: type) ?T {
        const value = self.get(name) orelse return null;
        return std.fmt.parseInt(T, value, 10) catch null;
    }
};

pub const Route = struct {
    path: []const u8,
    method: http.Method,
    handler: Handler,
    before_hooks: std.ArrayList(BeforeHook),
    after_hooks: std.ArrayList(AfterHook),

    pub fn init(allocator: std.mem.Allocator, path: []const u8, method: http.Method, handler: Handler) !Route {
        return .{
            .path = try allocator.dupe(u8, path),
            .method = method,
            .handler = handler,
            .before_hooks = .empty,
            .after_hooks = .empty,
        };
    }

    pub fn deinit(self: *Route, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
        self.before_hooks.deinit(allocator);
        self.after_hooks.deinit(allocator);
    }

    pub fn before(self: *Route, allocator: std.mem.Allocator, hook: BeforeHook) !void {
        try self.before_hooks.append(allocator, hook);
    }

    pub fn after(self: *Route, allocator: std.mem.Allocator, hook: AfterHook) !void {
        try self.after_hooks.append(allocator, hook);
    }
};

pub const MatchResult = struct {
    route: *const Route,
    params: PathParams,
};

pub const Router = struct {
    allocator: std.mem.Allocator,
    routes: std.ArrayList(Route),

    pub fn init(allocator: std.mem.Allocator) !Router {
        return .{
            .allocator = allocator,
            .routes = .empty,
        };
    }

    pub fn deinit(self: *Router) void {
        for (self.routes.items) |*route| {
            route.deinit(self.allocator);
        }
        self.routes.deinit(self.allocator);
    }

    pub fn add(self: *Router, path: []const u8, method: http.Method, handler: Handler) !*Route {
        const route = try Route.init(self.allocator, path, method, handler);
        try self.routes.append(self.allocator, route);
        return &self.routes.items[self.routes.items.len - 1];
    }

    pub fn match(self: *Router, target: []const u8, method: http.Method, params: *std.ArrayList(PathParams.Item)) !?MatchResult {
        const path = stripQuery(target);
        for (self.routes.items) |*route| {
            params.clearRetainingCapacity();
            if (route.method != method) continue;
            if (matchRoute(self.allocator, route.path, path, params)) {
                return .{
                    .route = route,
                    .params = .{ .items = params.items },
                };
            }
        }
        return null;
    }
};

fn stripQuery(target: []const u8) []const u8 {
    const query_index = std.mem.indexOfScalar(u8, target, '?') orelse return target;
    return target[0..query_index];
}

fn trimSlashes(path: []const u8) []const u8 {
    return std.mem.trim(u8, path, "/");
}

fn matchRoute(allocator: std.mem.Allocator, route_path: []const u8, request_path: []const u8, params: *std.ArrayList(PathParams.Item)) bool {
    var route_iter = std.mem.splitScalar(u8, trimSlashes(route_path), '/');
    var request_iter = std.mem.splitScalar(u8, trimSlashes(request_path), '/');

    while (true) {
        const route_segment = route_iter.next();
        const request_segment = request_iter.next();

        if (route_segment == null and request_segment == null) return true;
        if (route_segment == null or request_segment == null) return false;

        const route_value = route_segment orelse unreachable;
        const request_value = request_segment orelse unreachable;
        if (route_value.len > 0 and route_value[0] == ':') {
            params.append(allocator, .{
                .name = route_value[1..],
                .value = request_value,
            }) catch return false;
            continue;
        }
        if (!std.mem.eql(u8, route_value, request_value)) return false;
    }
}

const testing = std.testing;

test "radix tree basic matching" {
    const allocator = testing.allocator;
    var router = try Router.init(allocator);
    defer router.deinit();

    const handler = struct {
        fn h(_: *Context) !void {}
    }.h;

    const r1 = try router.add("/users/:id", .GET, handler);
    _ = r1;
    const r2 = try router.add("/users/:id/posts/:postId", .GET, handler);
    _ = r2;

    var params = std.ArrayList(PathParams.Item).empty;
    defer params.deinit(allocator);

    const match1 = try router.match("/users/123", .GET, &params);
    try testing.expect(match1 != null);
    const m1 = match1 orelse return error.TestUnexpectedResult;
    const id1 = m1.params.get("id") orelse return error.TestUnexpectedResult;
    try testing.expectEqualStrings("123", id1);

    params.clearRetainingCapacity();
    const match2 = try router.match("/users/456/posts/789", .GET, &params);
    try testing.expect(match2 != null);
    const m2 = match2 orelse return error.TestUnexpectedResult;
    const id2 = m2.params.get("id") orelse return error.TestUnexpectedResult;
    try testing.expectEqualStrings("456", id2);
    const post_id = m2.params.get("postId") orelse return error.TestUnexpectedResult;
    try testing.expectEqualStrings("789", post_id);
}

test "radix tree param int parsing" {
    const allocator = testing.allocator;
    var router = try Router.init(allocator);
    defer router.deinit();

    const handler = struct {
        fn h(_: *Context) !void {}
    }.h;

    const r = try router.add("/items/:id", .GET, handler);
    _ = r;

    var params = std.ArrayList(PathParams.Item).empty;
    defer params.deinit(allocator);

    const match = try router.match("/items/42", .GET, &params);
    try testing.expect(match != null);
    const m = match orelse return error.TestUnexpectedResult;
    const id = m.params.getInt("id", u32) orelse return error.TestUnexpectedResult;
    try testing.expectEqual(@as(u32, 42), id);
}

test "router discriminates by method" {
    const allocator = testing.allocator;
    var router = try Router.init(allocator);
    defer router.deinit();

    const get_handler = struct {
        fn h(_: *Context) !void {}
    }.h;
    const post_handler = struct {
        fn h(_: *Context) !void {}
    }.h;

    const r1 = try router.add("/items", .GET, get_handler);
    _ = r1;
    const r2 = try router.add("/items", .POST, post_handler);
    _ = r2;

    var params = std.ArrayList(PathParams.Item).empty;
    defer params.deinit(allocator);

    const get_match = try router.match("/items", .GET, &params);
    try testing.expect(get_match != null);

    const post_match = try router.match("/items", .POST, &params);
    try testing.expect(post_match != null);

    const delete_match = try router.match("/items", .DELETE, &params);
    try testing.expect(delete_match == null);
}
