const std = @import("std");
const http = std.http;
const net = std.Io.net;
const Server = @import("server.zig").Server;
const Context = @import("context.zig").Context;
const Handler = @import("middleware.zig").Handler;
const BeforeHook = @import("middleware.zig").BeforeHook;
const AfterHook = @import("middleware.zig").AfterHook;

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

    fn addRoute(self: *App, path: []const u8, handler: Handler) !void {
        try self.server.router.add(path, handler);
    }

    pub fn get(self: *App, path: []const u8, handler: Handler) !void {
        try self.addRoute(path, handler);
    }

    pub fn post(self: *App, path: []const u8, handler: Handler) !void {
        try self.addRoute(path, handler);
    }

    pub fn put(self: *App, path: []const u8, handler: Handler) !void {
        try self.addRoute(path, handler);
    }

    pub fn delete(self: *App, path: []const u8, handler: Handler) !void {
        try self.addRoute(path, handler);
    }

    pub fn patch(self: *App, path: []const u8, handler: Handler) !void {
        try self.addRoute(path, handler);
    }

    pub fn head(self: *App, path: []const u8, handler: Handler) !void {
        try self.addRoute(path, handler);
    }

    pub fn options(self: *App, path: []const u8, handler: Handler) !void {
        try self.addRoute(path, handler);
    }

    pub fn listen(self: *App, address: net.IpAddress) !void {
        try self.server.listen(address);
    }

    pub fn stop(self: *App) void {
        self.server.stop();
    }
};
