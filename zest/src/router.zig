const std = @import("std");
const Context = @import("context.zig").Context;
const Handler = @import("middleware.zig").Handler;

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
    handler: Handler,
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
        for (self.routes.items) |route| {
            self.allocator.free(route.path);
        }
        self.routes.deinit(self.allocator);
    }

    pub fn add(self: *Router, path: []const u8, handler: Handler) !void {
        try self.routes.append(self.allocator, .{
            .path = try self.allocator.dupe(u8, path),
            .handler = handler,
        });
    }

    pub fn get(self: *Router, target: []const u8, params: *std.ArrayList(PathParams.Item)) !?MatchResult {
        const path = stripQuery(target);
        for (self.routes.items) |*route| {
            params.clearRetainingCapacity();
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

    try router.add("/users/:id", handler);
    try router.add("/users/:id/posts/:postId", handler);

    var params = std.ArrayList(PathParams.Item).empty;
    defer params.deinit(allocator);

    const match1 = try router.get("/users/123", &params);
    try testing.expect(match1 != null);
    const m1 = match1 orelse return error.TestUnexpectedResult;
    const id1 = m1.params.get("id") orelse return error.TestUnexpectedResult;
    try testing.expectEqualStrings("123", id1);

    params.clearRetainingCapacity();
    const match2 = try router.get("/users/456/posts/789", &params);
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

    try router.add("/items/:id", handler);

    var params = std.ArrayList(PathParams.Item).empty;
    defer params.deinit(allocator);

    const match = try router.get("/items/42", &params);
    try testing.expect(match != null);
    const m = match orelse return error.TestUnexpectedResult;
    const id = m.params.getInt("id", u32) orelse return error.TestUnexpectedResult;
    try testing.expectEqual(@as(u32, 42), id);
}
