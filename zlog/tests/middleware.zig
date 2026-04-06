const std = @import("std");
const zlog = @import("zlog");
const middleware = zlog.middleware;
const MiddlewareConfig = zlog.MiddlewareConfig;
const LogField = zlog.LogField;
const Logger = zlog.Logger;
const Level = zlog.Level;
const Sink = zlog.Sink;

const TestSink = struct {
    logs: std.ArrayList([]const u8),

    pub fn init(allocator: std.mem.Allocator) TestSink {
        return .{ .logs = std.ArrayList([]const u8).init(allocator) };
    }

    pub fn deinit(self: *TestSink) void {
        for (self.logs.items) |log| {
            self.logs.allocator.free(log);
        }
        self.logs.deinit();
    }

    pub fn sink(self: *TestSink) Sink {
        return Sink{
            .ptr = self,
            .kind = .stdout,
            .writeFn = writeFn,
            .flushFn = flushFn,
            .deinitFn = deinitFn,
        };
    }

    fn writeFn(ptr: *anyopaque, data: []const u8) anyerror!void {
        const self = @as(*TestSink, @ptrCast(@alignCast(ptr)));
        const copy = try self.logs.allocator.dupe(u8, data);
        try self.logs.append(copy);
    }

    fn flushFn(ptr: *anyopaque) anyerror!void {
        const self = @as(*TestSink, @ptrCast(@alignCast(ptr)));
        std.mem.doNotOptimizeAway(self);
    }

    fn deinitFn(ptr: *anyopaque) void {
        const self = @as(*TestSink, @ptrCast(@alignCast(ptr)));
        self.deinit();
    }
};

test "middleware logs request and response" {
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    var test_sink = TestSink.init(allocator);
    defer test_sink.deinit();

    var logger = Logger.init(allocator, io, Level.info);
    defer logger.deinit();
    try logger.addSink(test_sink.sink());

    const config = MiddlewareConfig{
        .fields = &[_]LogField{ .method, .path, .status, .duration },
        .json_format = true,
    };

    const mw = middleware.LoggingMiddleware.init(allocator, &logger, config);

    var headers = std.StringHashMap([]const u8).init(allocator);
    defer headers.deinit();

    const req = middleware.RequestContext{
        .method = "GET",
        .path = "/api/users",
        .headers = headers,
        .remote_addr = "127.0.0.1",
        .body = null,
        .allocator = allocator,
    };

    mw.logRequest(req);

    try std.testing.expectEqual(@as(usize, 1), test_sink.logs.items.len);

    const log_entry = test_sink.logs.items[0];
    try std.testing.expect(std.mem.indexOf(u8, log_entry, "method=GET") != null);
    try std.testing.expect(std.mem.indexOf(u8, log_entry, "path=/api/users") != null);
}

test "middleware extracts request_id from header" {
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    var test_sink = TestSink.init(allocator);
    defer test_sink.deinit();

    var logger = Logger.init(allocator, io, Level.info);
    defer logger.deinit();
    try logger.addSink(test_sink.sink());

    const config = MiddlewareConfig{
        .fields = &[_]LogField{ .method, .path, .status, .request_id },
        .request_id_header = "X-Request-Id",
        .json_format = true,
    };

    const mw = middleware.LoggingMiddleware.init(allocator, &logger, config);

    var headers = std.StringHashMap([]const u8).init(allocator);
    defer headers.deinit();
    try headers.put("X-Request-Id", "req-12345");

    const req = middleware.RequestContext{
        .method = "POST",
        .path = "/api/login",
        .headers = headers,
        .remote_addr = "192.168.1.1",
        .body = null,
        .allocator = allocator,
    };

    var resp_headers = std.StringHashMap([]const u8).init(allocator);
    defer resp_headers.deinit();

    var resp = middleware.ResponseContext{
        .status = 200,
        .headers = resp_headers,
        .body = null,
        .allocator = allocator,
    };
    defer resp.deinit();

    mw.logResponse(req, resp, std.time.milliTimestamp() - 100);

    try std.testing.expectEqual(@as(usize, 1), test_sink.logs.items.len);

    const log_entry = test_sink.logs.items[0];
    try std.testing.expect(std.mem.indexOf(u8, log_entry, "request_id=req-12345") != null);
}
