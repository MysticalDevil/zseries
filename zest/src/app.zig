const std = @import("std");
const http = std.http;
const net = std.Io.net;
const Server = server.Server;
const Context = context.Context;
const mw = @import("middleware.zig");
const server = @import("server.zig");
const context = @import("context.zig");
const router = @import("router.zig");
const Handler = mw.Handler;
const BeforeHook = mw.BeforeHook;
const AfterHook = mw.AfterHook;
const Route = router.Route;

pub const RouteBuilder = struct {
    route: *Route,
    allocator: std.mem.Allocator,

    pub fn before(self: RouteBuilder, hook: BeforeHook) !RouteBuilder {
        try self.route.before(self.allocator, hook);
        return self;
    }

    pub fn after(self: RouteBuilder, hook: AfterHook) !RouteBuilder {
        try self.route.after(self.allocator, hook);
        return self;
    }
};

pub const Group = struct {
    app: *App,
    prefix: []const u8,
    before_hooks: std.ArrayList(BeforeHook),
    after_hooks: std.ArrayList(AfterHook),

    pub fn init(app: *App, prefix: []const u8) !Group {
        var group = Group{
            .app = app,
            .prefix = try app.allocator.dupe(u8, prefix),
            .before_hooks = .empty,
            .after_hooks = .empty,
        };

        if (group.prefix.len > 1 and std.mem.endsWith(u8, group.prefix, "/")) {
            group.prefix = std.mem.trimRight(u8, group.prefix, "/");
        }
        return group;
    }

    pub fn deinit(self: *Group) void {
        self.app.allocator.free(self.prefix);
        self.before_hooks.deinit(self.app.allocator);
        self.after_hooks.deinit(self.app.allocator);
    }

    pub fn before(self: *Group, hook: BeforeHook) !void {
        try self.before_hooks.append(self.app.allocator, hook);
    }

    pub fn after(self: *Group, hook: AfterHook) !void {
        try self.after_hooks.append(self.app.allocator, hook);
    }

    fn joinPath(self: *Group, path: []const u8) ![]const u8 {
        if (std.mem.eql(u8, path, "/")) {
            return self.app.allocator.dupe(u8, self.prefix);
        }
        return std.fmt.allocPrint(self.app.allocator, "{s}{s}", .{ self.prefix, path });
    }

    fn addRoute(self: *Group, method: http.Method, path: []const u8, handler: Handler) !RouteBuilder {
        const full_path = try self.joinPath(path);
        defer self.app.allocator.free(full_path);
        const builder = try self.app.addRouteInternal(full_path, method, handler);
        for (self.before_hooks.items) |hook| {
            try builder.route.before(self.app.allocator, hook);
        }
        for (self.after_hooks.items) |hook| {
            try builder.route.after(self.app.allocator, hook);
        }
        return builder;
    }

    pub fn get(self: *Group, path: []const u8, handler: Handler) !RouteBuilder {
        return try self.addRoute(.GET, path, handler);
    }

    pub fn post(self: *Group, path: []const u8, handler: Handler) !RouteBuilder {
        return try self.addRoute(.POST, path, handler);
    }

    pub fn put(self: *Group, path: []const u8, handler: Handler) !RouteBuilder {
        return try self.addRoute(.PUT, path, handler);
    }

    pub fn delete(self: *Group, path: []const u8, handler: Handler) !RouteBuilder {
        return try self.addRoute(.DELETE, path, handler);
    }

    pub fn patch(self: *Group, path: []const u8, handler: Handler) !RouteBuilder {
        return try self.addRoute(.PATCH, path, handler);
    }

    pub fn head(self: *Group, path: []const u8, handler: Handler) !RouteBuilder {
        return try self.addRoute(.HEAD, path, handler);
    }

    pub fn options(self: *Group, path: []const u8, handler: Handler) !RouteBuilder {
        return try self.addRoute(.OPTIONS, path, handler);
    }
};

pub const App = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    server: Server,

    pub fn init(allocator: std.mem.Allocator, io: std.Io) !App {
        return .{
            .allocator = allocator,
            .io = io,
            .server = try Server.init(allocator, io),
        };
    }

    pub fn deinit(self: *App) void {
        self.server.deinit();
    }

    pub fn before(self: *App, hook: BeforeHook) !void {
        try self.server.middleware.before(hook);
    }

    pub fn after(self: *App, hook: AfterHook) !void {
        try self.server.middleware.after(hook);
    }

    pub fn group(self: *App, prefix: []const u8) !Group {
        return try Group.init(self, prefix);
    }

    fn addRouteInternal(self: *App, path: []const u8, method: http.Method, handler: Handler) !RouteBuilder {
        const route = try self.server.router.add(path, method, handler);
        return .{
            .route = route,
            .allocator = self.allocator,
        };
    }

    pub fn get(self: *App, path: []const u8, handler: Handler) !RouteBuilder {
        return try self.addRouteInternal(path, .GET, handler);
    }

    pub fn post(self: *App, path: []const u8, handler: Handler) !RouteBuilder {
        return try self.addRouteInternal(path, .POST, handler);
    }

    pub fn put(self: *App, path: []const u8, handler: Handler) !RouteBuilder {
        return try self.addRouteInternal(path, .PUT, handler);
    }

    pub fn delete(self: *App, path: []const u8, handler: Handler) !RouteBuilder {
        return try self.addRouteInternal(path, .DELETE, handler);
    }

    pub fn patch(self: *App, path: []const u8, handler: Handler) !RouteBuilder {
        return try self.addRouteInternal(path, .PATCH, handler);
    }

    pub fn head(self: *App, path: []const u8, handler: Handler) !RouteBuilder {
        return try self.addRouteInternal(path, .HEAD, handler);
    }

    pub fn options(self: *App, path: []const u8, handler: Handler) !RouteBuilder {
        return try self.addRouteInternal(path, .OPTIONS, handler);
    }

    pub fn listen(self: *App, address: net.IpAddress) !void {
        try self.server.listen(address);
    }

    pub fn stop(self: *App) void {
        self.server.stop();
    }
};
