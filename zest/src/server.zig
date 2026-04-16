const std = @import("std");
const http = std.http;
const net = std.Io.net;
const router = @import("router.zig");
const Router = router.Router;
const MatchResult = router.MatchResult;
const Context = @import("context.zig").Context;
const middleware_mod = @import("middleware.zig");
const Middleware = middleware_mod.Middleware;
const Handler = middleware_mod.Handler;

pub const Server = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    router: Router,
    middleware: Middleware,
    server_socket: ?net.Server,
    running: std.atomic.Value(bool),

    pub fn init(allocator: std.mem.Allocator, io: std.Io) !Server {
        return .{
            .allocator = allocator,
            .io = io,
            .router = try Router.init(allocator),
            .middleware = Middleware.init(allocator),
            .server_socket = null,
            .running = std.atomic.Value(bool).init(false),
        };
    }

    pub fn deinit(self: *Server) void {
        self.stop();
        self.router.deinit();
        self.middleware.deinit();
    }

    pub fn stop(self: *Server) void {
        self.running.store(false, .seq_cst);
        if (self.server_socket) |*socket| {
            socket.deinit(self.io);
            self.server_socket = null;
        }
    }

    pub fn listen(self: *Server, address: net.IpAddress) !void {
        self.server_socket = try net.IpAddress.listen(&address, self.io, .{ .reuse_address = true });
        self.running.store(true, .seq_cst);

        std.log.info("zest server listening on {any}", .{address});

        while (self.running.load(.seq_cst)) {
            const socket = if (self.server_socket) |*server_socket|
                server_socket
            else
                break;
            const conn = socket.accept(self.io) catch |err| switch (err) {
                error.SocketNotListening => break,
                error.Canceled => break,
                else => {
                    std.log.err("accept error: {any}", .{err});
                    continue;
                },
            };

            try self.handleConnection(conn);
        }
    }

    fn handleConnection(self: *Server, stream: net.Stream) !void {
        defer stream.close(self.io);

        var read_buffer: [4096]u8 = undefined;
        var write_buffer: [4096]u8 = undefined;

        var reader = stream.reader(self.io, &read_buffer);
        var writer = stream.writer(self.io, &write_buffer);

        var http_server = http.Server.init(&reader.interface, &writer.interface);

        while (true) {
            var request = http_server.receiveHead() catch |err| switch (err) {
                error.HttpConnectionClosing => return,
                else => {
                    std.log.err("http receive error: {any}", .{err});
                    return;
                },
            };

            try self.handleRequest(&request);

            // Single-threaded server: close connection after each request
            // to avoid blocking the accept loop on idle keep-alive connections.
            return;
        }
    }

    fn handleRequest(self: *Server, request: *http.Server.Request) !void {
        const target = request.head.target;
        const method = request.head.method;

        var params_buf = std.ArrayList(router.PathParams.Item).empty;
        defer params_buf.deinit(self.allocator);

        const match_result = try self.router.match(target, method, &params_buf);

        var ctx = try Context.init(
            self.allocator,
            self.io,
            method,
            target,
            if (match_result) |m| m.params else .{ .items = &.{} },
        );
        defer ctx.deinit();

        try populateRequestContext(self, request, &ctx);

        if (match_result) |match| {
            self.middleware.execute(&ctx, match.route, match.route.handler) catch |err| {
                const already_responded = ctx.response_status != .ok or
                    ctx.response_headers.count() > 0 or
                    ctx.response_body.items.len > 0;
                if (!already_responded) {
                    std.log.err("request handler error: {any}", .{err});
                    ctx.status(500);
                    ctx.text(500, "Internal Server Error") catch {};
                }
            };
        } else if (method == .OPTIONS) {
            const noopHandler = struct {
                fn h(_: *Context) !void {}
            }.h;
            self.middleware.execute(&ctx, null, noopHandler) catch |err| {
                const already_responded = ctx.response_status != .ok or
                    ctx.response_headers.count() > 0 or
                    ctx.response_body.items.len > 0;
                if (!already_responded) {
                    std.log.err("request handler error: {any}", .{err});
                    ctx.status(500);
                    ctx.text(500, "Internal Server Error") catch {};
                }
            };
        } else {
            ctx.status(404);
            try ctx.text(404, "Not Found");
        }

        try self.sendResponse(request, &ctx);
    }

    fn populateRequestContext(self: *Server, request: *http.Server.Request, ctx: *Context) !void {
        var headers = request.iterateHeaders();
        while (headers.next()) |header| {
            try ctx.headers.put(
                try self.allocator.dupe(u8, header.name),
                try self.allocator.dupe(u8, header.value),
            );
        }

        if (!request.head.method.requestHasBody()) return;

        var read_buffer: [512]u8 = undefined;
        const reader = try request.readerExpectContinue(&read_buffer);
        var body_writer: std.Io.Writer.Allocating = .init(self.allocator);
        errdefer body_writer.deinit();
        const streamed_len = reader.streamRemaining(&body_writer.writer) catch |err| switch (err) {
            error.ReadFailed => return err,
            else => |e| return e,
        };
        std.debug.assert(streamed_len == body_writer.writer.end);
        ctx.request_body = try body_writer.toOwnedSlice();
    }

    fn sendResponse(_: *Server, request: *http.Server.Request, ctx: *Context) !void {
        const body = ctx.response_body.items;

        var extra_headers: [32]http.Header = undefined;
        var header_count: usize = 0;

        var iter = ctx.response_headers.iterator();
        while (iter.next()) |entry| {
            if (header_count >= extra_headers.len) break;
            extra_headers[header_count] = .{
                .name = entry.key_ptr.*,
                .value = entry.value_ptr.*,
            };
            header_count += 1;
        }

        try request.respond(body, .{
            .status = ctx.response_status,
            .extra_headers = extra_headers[0..header_count],
        });
    }
};
