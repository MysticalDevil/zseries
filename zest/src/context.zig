const std = @import("std");
const http = std.http;
const router = @import("router.zig");
const PathParams = router.PathParams;
const Status = @import("status.zig").Status;

pub const Context = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    method: http.Method,
    path: []const u8,
    params: PathParams,
    headers: std.StringHashMap([]const u8),
    request_body: ?[]const u8,

    response_status: http.Status,
    response_headers: std.StringHashMap([]const u8),
    response_body: std.ArrayList(u8),

    context_data: std.StringHashMap(*anyopaque),

    pub fn init(
        allocator: std.mem.Allocator,
        io: std.Io,
        method: http.Method,
        path: []const u8,
        params: PathParams,
    ) !Context {
        return .{
            .allocator = allocator,
            .io = io,
            .method = method,
            .path = path,
            .params = params,
            .headers = std.StringHashMap([]const u8).init(allocator),
            .request_body = null,
            .response_status = .ok,
            .response_headers = std.StringHashMap([]const u8).init(allocator),
            .response_body = std.ArrayList(u8).init(allocator),
            .context_data = std.StringHashMap(*anyopaque).init(allocator),
        };
    }

    pub fn deinit(self: *Context) void {
        self.headers.deinit();
        if (self.request_body) |body| {
            self.allocator.free(body);
        }
        self.response_headers.deinit();
        self.response_body.deinit();
        self.context_data.deinit();
    }

    pub fn set(self: *Context, key: []const u8, value: *anyopaque) !void {
        try self.context_data.put(key, value);
    }

    pub fn get(self: *Context, key: []const u8) ?*anyopaque {
        return self.context_data.get(key);
    }

    pub fn param(self: *Context, name: []const u8) ?[]const u8 {
        return self.params.get(name);
    }

    pub fn paramInt(self: *Context, name: []const u8, comptime T: type) ?T {
        return self.params.getInt(name, T);
    }

    pub fn header(self: *Context, name: []const u8) ?[]const u8 {
        return self.headers.get(name);
    }

    pub fn status(self: *Context, code: u16) void {
        self.response_status = @enumFromInt(code);
    }

    pub fn statusCode(self: *Context, status_code: Status) void {
        self.response_status = status_code;
    }

    pub fn setHeader(self: *Context, name: []const u8, value: []const u8) !void {
        try self.response_headers.put(name, value);
    }

    pub fn text(self: *Context, code: u16, content: []const u8) !void {
        self.response_status = @enumFromInt(code);
        try self.setHeader("Content-Type", "text/plain; charset=utf-8");
        try self.response_body.appendSlice(content);
    }

    pub fn textStatus(self: *Context, status_code: Status, content: []const u8) !void {
        self.response_status = status_code;
        try self.setHeader("Content-Type", "text/plain; charset=utf-8");
        try self.response_body.appendSlice(content);
    }

    pub fn json(self: *Context, code: u16, value: anytype) !void {
        self.response_status = @enumFromInt(code);
        try self.setHeader("Content-Type", "application/json");
        try std.json.stringify(value, .{}, self.response_body.writer());
    }

    pub fn jsonStatus(self: *Context, status_code: Status, value: anytype) !void {
        self.response_status = status_code;
        try self.setHeader("Content-Type", "application/json");
        try std.json.stringify(value, .{}, self.response_body.writer());
    }

    pub fn html(self: *Context, code: u16, content: []const u8) !void {
        self.response_status = @enumFromInt(code);
        try self.setHeader("Content-Type", "text/html; charset=utf-8");
        try self.response_body.appendSlice(content);
    }

    pub fn htmlStatus(self: *Context, status_code: Status, content: []const u8) !void {
        self.response_status = status_code;
        try self.setHeader("Content-Type", "text/html; charset=utf-8");
        try self.response_body.appendSlice(content);
    }

    pub fn redirect(self: *Context, location: []const u8, code: u16) !void {
        self.response_status = @enumFromInt(code);
        try self.setHeader("Location", location);
    }

    pub fn redirectStatus(self: *Context, location: []const u8, status_code: Status) !void {
        self.response_status = status_code;
        try self.setHeader("Location", location);
    }

    pub fn bodyReader(self: *Context) ?[]const u8 {
        return self.request_body;
    }

    pub fn bodyText(self: *Context) ?[]const u8 {
        return self.request_body;
    }

    pub fn bodyJson(self: *Context, comptime T: type) !?T {
        const body = self.request_body orelse return null;
        return try std.json.parseFromSlice(T, self.allocator, body, .{});
    }
};
