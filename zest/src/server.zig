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
        self.server_socket = try net.IpAddress.listen(address, self.io, .{});
        self.running.store(true, .seq_cst);

        std.log.info("zest server listening on {any}", .{address});

        while (self.running.load(.seq_cst)) {
            const socket = if (self.server_socket) |server_socket|
                server_socket
            else
                break;
            const conn = socket.accept(self.io) catch |err| switch (err) {
                error.SocketNotListening => break,
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
                error.EndOfStream => return,
                else => {
                    std.log.err("http receive error: {any}", .{err});
                    return;
                },
            };

            try self.handleRequest(&request);

            if (!request.head.keep_alive) {
                return;
            }
        }
    }

    fn handleRequest(self: *Server, request: *http.Server.Request) !void {
        const target = request.head.target;
        const method = request.head.method;

        var params_buf = std.ArrayList(router.PathParams.Item).init(self.allocator);
        defer params_buf.deinit();

        const match_result = try self.router.get(target, &params_buf);

        var ctx = try Context.init(
            self.allocator,
            self.io,
            method,
            target,
            if (match_result) |m| m.params else .{ .items = &.{} },
        );
        defer ctx.deinit();

        if (match_result) |match| {
            try self.middleware.execute(&ctx, match.route.handler);
        } else {
            try ctx.status(404);
            try ctx.text(404, "Not Found");
        }

        try self.sendResponse(request, &ctx);
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

        const status = @as(http.Status, @enumFromInt(ctx.response_status));

        try request.respond(body, .{
            .status = status,
            .extra_headers = extra_headers[0..header_count],
        });
    }
};
