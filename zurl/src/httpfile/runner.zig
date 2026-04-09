const std = @import("std");
const model = @import("model.zig");

pub const ResponseHeader = struct {
    name: []const u8,
    value: []const u8,

    pub fn deinit(self: ResponseHeader, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.value);
    }
};

pub const Response = struct {
    status: std.http.Status,
    headers: []ResponseHeader,
    body: []const u8,

    pub fn deinit(self: Response, allocator: std.mem.Allocator) void {
        for (self.headers) |header| header.deinit(allocator);
        allocator.free(self.headers);
        allocator.free(self.body);
    }
};

const Cookie = struct {
    name: []const u8,
    value: []const u8,

    fn deinit(self: Cookie, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.value);
    }
};

pub const Session = struct {
    allocator: std.mem.Allocator,
    client: std.http.Client,
    cookies: std.ArrayList(Cookie),

    pub fn init(allocator: std.mem.Allocator, io: std.Io) Session {
        return .{
            .allocator = allocator,
            .client = .{ .allocator = allocator, .io = io },
            .cookies = .empty,
        };
    }

    pub fn deinit(self: *Session) void {
        for (self.cookies.items) |cookie| cookie.deinit(self.allocator);
        self.cookies.deinit(self.allocator);
        self.client.deinit();
    }

    pub fn execute(self: *Session, request: *const model.ResolvedRequest) !Response {
        const uri = try std.Uri.parse(request.target);

        var extra_headers = std.ArrayList(std.http.Header).empty;
        defer extra_headers.deinit(self.allocator);

        for (request.headers) |header| {
            if (std.ascii.eqlIgnoreCase(header.name, "host")) continue;
            if (std.ascii.eqlIgnoreCase(header.name, "content-length")) continue;
            try extra_headers.append(self.allocator, .{ .name = header.name, .value = header.value });
        }

        const cookie_value = try self.buildCookieHeader();
        defer if (cookie_value) |value| self.allocator.free(value);
        if (cookie_value) |value| {
            try extra_headers.append(self.allocator, .{ .name = "Cookie", .value = value });
        }

        var req = try self.client.request(request.method, uri, .{
            .redirect_behavior = .unhandled,
            .extra_headers = extra_headers.items,
        });
        defer req.deinit();

        if (request.body) |body| {
            req.transfer_encoding = .{ .content_length = body.len };
            const owned_body = try self.allocator.dupe(u8, body);
            defer self.allocator.free(owned_body);
            try req.sendBodyComplete(owned_body);
        } else if (request.method.requestHasBody()) {
            req.transfer_encoding = .{ .content_length = 0 };
            try req.sendBodyComplete(&.{});
        } else {
            try req.sendBodiless();
        }

        var redirect_buffer: [8192]u8 = undefined;
        var response = try req.receiveHead(&redirect_buffer);

        const headers = try self.captureHeaders(response.head);
        errdefer {
            for (headers) |header| header.deinit(self.allocator);
            self.allocator.free(headers);
        }
        try self.updateCookies(headers);

        var body_writer: std.Io.Writer.Allocating = .init(self.allocator);
        errdefer body_writer.deinit();
        var transfer_buffer: [512]u8 = undefined;
        var decompress: std.http.Decompress = undefined;
        var decompress_buffer: [8192]u8 = undefined;
        const body_reader = response.readerDecompressing(&transfer_buffer, &decompress, &decompress_buffer);
        const streamed_len = body_reader.streamRemaining(&body_writer.writer) catch |err| switch (err) {
            error.ReadFailed => return response.bodyErr() orelse err,
            else => |e| return e,
        };
        std.debug.assert(streamed_len == body_writer.writer.end);

        return .{
            .status = response.head.status,
            .headers = headers,
            .body = try body_writer.toOwnedSlice(),
        };
    }

    fn buildCookieHeader(self: *Session) !?[]u8 {
        if (self.cookies.items.len == 0) return null;

        var writer: std.Io.Writer.Allocating = .init(self.allocator);
        defer writer.deinit();
        for (self.cookies.items, 0..) |cookie, idx| {
            if (idx > 0) try writer.writer.writeAll("; ");
            try writer.writer.writeAll(cookie.name);
            try writer.writer.writeByte('=');
            try writer.writer.writeAll(cookie.value);
        }
        return try writer.toOwnedSlice();
    }

    fn captureHeaders(self: *Session, head: std.http.Client.Response.Head) ![]ResponseHeader {
        var headers = std.ArrayList(ResponseHeader).empty;
        defer headers.deinit(self.allocator);

        var iterator = head.iterateHeaders();
        while (iterator.next()) |header| {
            try headers.append(self.allocator, .{
                .name = try self.allocator.dupe(u8, header.name),
                .value = try self.allocator.dupe(u8, header.value),
            });
        }
        return headers.toOwnedSlice(self.allocator);
    }

    fn updateCookies(self: *Session, headers: []const ResponseHeader) !void {
        for (headers) |header| {
            if (!std.ascii.eqlIgnoreCase(header.name, "set-cookie")) continue;
            try self.applySetCookie(header.value);
        }
    }

    fn applySetCookie(self: *Session, set_cookie: []const u8) !void {
        const first = std.mem.indexOfScalar(u8, set_cookie, ';') orelse set_cookie.len;
        const pair = set_cookie[0..first];
        const equals = std.mem.indexOfScalar(u8, pair, '=') orelse return;
        const name = std.mem.trim(u8, pair[0..equals], " \t");
        const value = std.mem.trim(u8, pair[equals + 1 ..], " \t");
        if (name.len == 0) return;

        for (self.cookies.items) |*cookie| {
            if (!std.mem.eql(u8, cookie.name, name)) continue;
            self.allocator.free(cookie.value);
            cookie.value = try self.allocator.dupe(u8, value);
            return;
        }

        try self.cookies.append(self.allocator, .{
            .name = try self.allocator.dupe(u8, name),
            .value = try self.allocator.dupe(u8, value),
        });
    }
};
