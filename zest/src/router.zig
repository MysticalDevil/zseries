const std = @import("std");

pub const Route = struct {
    handler: Handler,
    params: []const ParamDef,
};

pub const ParamDef = struct {
    name: []const u8,
    index: usize,
};

pub const Handler = *const fn (*anyopaque) anyerror!void;

pub const MatchResult = struct {
    route: Route,
    params: PathParams,
};

pub const PathParams = struct {
    items: []const Item,

    pub const Item = struct {
        name: []const u8,
        value: []const u8,
    };

    pub fn get(self: PathParams, name: []const u8) ?[]const u8 {
        for (self.items) |item| {
            if (std.mem.eql(u8, item.name, name)) {
                return item.value;
            }
        }
        return null;
    }

    pub fn getInt(self: PathParams, name: []const u8, comptime T: type) ?T {
        const value = self.get(name) orelse return null;
        return std.fmt.parseInt(T, value, 10) catch null;
    }
};

pub const Node = struct {
    allocator: std.mem.Allocator,
    prefix: []const u8,
    children: std.ArrayList(*Node),
    route: ?Route,
    param_child: ?*Node,
    param_name: []const u8,

    pub fn init(allocator: std.mem.Allocator, prefix: []const u8) !*Node {
        const node = try allocator.create(Node);
        node.* = .{
            .allocator = allocator,
            .prefix = try allocator.dupe(u8, prefix),
            .children = std.ArrayList(*Node).init(allocator),
            .route = null,
            .param_child = null,
            .param_name = "",
        };
        return node;
    }

    pub fn deinit(self: *Node) void {
        for (self.children.items) |child| {
            child.deinit();
        }
        self.children.deinit();
        if (self.param_child) |param| {
            param.deinit();
        }
        self.allocator.free(self.prefix);
        self.allocator.destroy(self);
    }

    fn findCommonPrefixLen(a: []const u8, b: []const u8) usize {
        var i: usize = 0;
        while (i < a.len and i < b.len and a[i] == b[i]) : (i += 1) {}
        return i;
    }

    fn isParam(segment: []const u8) bool {
        return segment.len > 0 and segment[0] == ':';
    }

    fn getParamName(segment: []const u8) []const u8 {
        if (isParam(segment)) {
            return segment[1..];
        }
        return segment;
    }

    pub fn insert(self: *Node, path: []const u8, route: Route) !void {
        if (path.len == 0) {
            self.route = route;
            return;
        }

        const segment = self.getFirstSegment(path);

        if (isParam(segment)) {
            if (self.param_child) |param| {
                const rest = path[segment.len..];
                if (rest.len == 0) {
                    param.route = route;
                } else {
                    try param.insert(rest, route);
                }
            } else {
                const param_name = getParamName(segment);
                const rest = path[segment.len..];
                const param = try Node.init(self.allocator, "");
                param.param_name = param_name;
                self.param_child = param;

                if (rest.len == 0) {
                    param.route = route;
                } else {
                    try param.insert(rest, route);
                }
            }
        } else {
            for (self.children.items) |child| {
                const common = findCommonPrefixLen(child.prefix, segment);
                if (common > 0) {
                    if (common < child.prefix.len) {
                        const new_child = try Node.init(self.allocator, child.prefix[common..]);
                        new_child.children = child.children;
                        new_child.route = child.route;
                        new_child.param_child = child.param_child;

                        child.prefix = try self.allocator.realloc(
                            @constCast(child.prefix),
                            common,
                        );
                        child.children = std.ArrayList(*Node).init(self.allocator);
                        try child.children.append(new_child);
                        child.route = null;
                        child.param_child = null;
                    }

                    if (common < segment.len) {
                        try child.insert(path[common..], route);
                    } else {
                        child.route = route;
                    }
                    return;
                }
            }

            const new_node = try Node.init(self.allocator, segment);
            try self.children.append(new_node);
            const rest = path[segment.len..];
            if (rest.len == 0) {
                new_node.route = route;
            } else {
                try new_node.insert(rest, route);
            }
        }
    }

    fn getFirstSegment(path: []const u8) []const u8 {
        if (path.len == 0) return path;
        if (path[0] == '/') {
            const end = std.mem.indexOfScalar(u8, path[1..], '/') orelse path.len - 1;
            return path[0 .. end + 1];
        }
        const end = std.mem.indexOfScalar(u8, path, '/') orelse path.len;
        return path[0..end];
    }

    pub fn search(self: *Node, path: []const u8, params: *std.ArrayList(PathParams.Item)) !?MatchResult {
        if (path.len == 0) {
            if (self.route) |route| {
                return MatchResult{
                    .route = route,
                    .params = .{ .items = params.items },
                };
            }
            return null;
        }

        for (self.children.items) |child| {
            if (path.len >= child.prefix.len and
                std.mem.eql(u8, path[0..child.prefix.len], child.prefix))
            {
                const result = try child.search(path[child.prefix.len..], params);
                if (result != null) return result;
            }
        }

        if (self.param_child) |param| {
            const segment = self.getFirstSegment(path);
            const rest = path[segment.len..];

            try params.append(.{
                .name = param.param_name,
                .value = segment,
            });

            const result = try param.search(rest, params);
            if (result != null) return result;

            params.items = params.items[0..params.items.len];
        }

        return null;
    }
};

pub const Router = struct {
    allocator: std.mem.Allocator,
    root: *Node,

    pub fn init(allocator: std.mem.Allocator) !Router {
        return .{
            .allocator = allocator,
            .root = try Node.init(allocator, ""),
        };
    }

    pub fn deinit(self: *Router) void {
        self.root.deinit();
    }

    pub fn add(self: *Router, path: []const u8, handler: Handler) !void {
        const route = Route{
            .handler = handler,
            .params = &.{},
        };
        try self.root.insert(path, route);
    }

    pub fn get(self: *Router, path: []const u8, params_buf: *std.ArrayList(PathParams.Item)) !?MatchResult {
        params_buf.clearRetainingCapacity();
        return try self.root.search(path, params_buf);
    }
};

const testing = std.testing;

test "radix tree exact match" {
    const allocator = testing.allocator;
    var router = try Router.init(allocator);
    defer router.deinit();

    const handler = struct {
        fn h(_: *anyopaque) !void {}
    }.h;

    try router.add("/users", handler);
    try router.add("/users/profile", handler);

    var params = std.ArrayList(PathParams.Item).init(allocator);
    defer params.deinit();

    const match1 = try router.get("/users", &params);
    try testing.expect(match1 != null);

    const match2 = try router.get("/users/profile", &params);
    try testing.expect(match2 != null);

    const match3 = try router.get("/notfound", &params);
    try testing.expect(match3 == null);
}

test "radix tree with params" {
    const allocator = testing.allocator;
    var router = try Router.init(allocator);
    defer router.deinit();

    const handler = struct {
        fn h(_: *anyopaque) !void {}
    }.h;

    try router.add("/users/:id", handler);
    try router.add("/users/:id/posts/:postId", handler);

    var params = std.ArrayList(PathParams.Item).init(allocator);
    defer params.deinit();

    const match1 = try router.get("/users/123", &params);
    try testing.expect(match1 != null);
    try testing.expectEqualStrings("123", match1.?.params.get("id").?);

    params.clearRetainingCapacity();
    const match2 = try router.get("/users/456/posts/789", &params);
    try testing.expect(match2 != null);
    try testing.expectEqualStrings("456", match2.?.params.get("id").?);
    try testing.expectEqualStrings("789", match2.?.params.get("postId").?);
}

test "radix tree param int parsing" {
    const allocator = testing.allocator;
    var router = try Router.init(allocator);
    defer router.deinit();

    const handler = struct {
        fn h(_: *anyopaque) !void {}
    }.h;

    try router.add("/items/:id", handler);

    var params = std.ArrayList(PathParams.Item).init(allocator);
    defer params.deinit();

    const match = try router.get("/items/42", &params);
    try testing.expect(match != null);
    const id = match.?.params.getInt("id", u32) orelse return error.TestFailed;
    try testing.expectEqual(@as(u32, 42), id);
}
