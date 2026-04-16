const std = @import("std");
const zest = @import("zest");
const zlog = @import("zlog");
const zcors = @import("zcors");
const Db = @import("db.zig").Db;
const AuthState = @import("auth.zig").AuthState;
const handlers = @import("handlers.zig");
const time = @import("time.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    var db = try Db.init(allocator, "memos.db");
    defer db.deinit();

    var auth_state = AuthState.init(allocator, &db, io);
    defer {
        // encoder and verifier hold no heap data for HMAC keys in this example
    }

    var logger = zlog.Logger.init(allocator, io, .info);
    defer logger.deinit();
    try logger.addStdoutSink();

    var app = try zest.App.init(allocator, io);
    defer app.deinit();

    // Inject shared state into every request context via a global before hook
    const InjectStruct = struct {
        var auth_ptr: *AuthState = undefined;
        fn hook(ctx: *zest.Context) !void {
            try ctx.set("auth_state", @ptrCast(auth_ptr));
        }
    };
    InjectStruct.auth_ptr = &auth_state;
    try app.before(InjectStruct.hook);

    // Logging middleware
    const LogBeforeStruct = struct {
        var log: *zlog.Logger = undefined;
        var io_val: std.Io = undefined;
        fn hook(ctx: *zest.Context) !void {
            const start = time.nowMillis(io_val);
            try ctx.set("start_time", @ptrFromInt(@as(usize, @intCast(start))));
            try log.log(.info, "request_started", &.{
                zlog.Field.string("method", @tagName(ctx.method)),
                zlog.Field.string("path", ctx.path),
            });
        }
    };
    LogBeforeStruct.log = &logger;
    LogBeforeStruct.io_val = io;
    try app.before(LogBeforeStruct.hook);

    const LogAfterStruct = struct {
        var log: *zlog.Logger = undefined;
        var io_val: std.Io = undefined;
        fn hook(ctx: *zest.Context) !void {
            const start_ptr = ctx.get("start_time");
            const start: i64 = if (start_ptr) |p| @intCast(@intFromPtr(p)) else 0;
            const duration = time.nowMillis(io_val) - start;
            try log.log(.info, "request_completed", &.{
                zlog.Field.string("method", @tagName(ctx.method)),
                zlog.Field.string("path", ctx.path),
                zlog.Field.uint("status", @intFromEnum(ctx.response_status)),
                zlog.Field.int("duration_ms", duration),
            });
        }
    };
    LogAfterStruct.log = &logger;
    LogAfterStruct.io_val = io;
    try app.after(LogAfterStruct.hook);

    // CORS middleware
    const cors_config = zcors.Config{
        .origins = &.{"http://localhost:5173"},
        .methods = &.{ "GET", "POST", "PUT", "DELETE", "OPTIONS" },
        .headers = &.{"Content-Type", "Authorization"},
        .credentials = true,
        .max_age = 86400,
    };
    try app.before(zcors.cors.beforeHook(zest.Context, cors_config));
    try app.after(zcors.cors.afterHook(zest.Context, cors_config));

    // Auth routes (no JWT required)
    _ = try app.post("/api/auth/register", handlers.registerHandler);
    _ = try app.post("/api/auth/login", handlers.loginHandler);

    // API group (JWT required)
    var api = try app.group("/api");
    defer api.deinit();
    try api.before(AuthState.authMiddleware(zest.Context, &auth_state));
    _ = try api.get("/memos", handlers.listMemosHandler);
    _ = try api.post("/memos", handlers.createMemoHandler);
    _ = try api.put("/memos/:id", handlers.updateMemoHandler);
    _ = try api.delete("/memos/:id", handlers.deleteMemoHandler);

    // Static files / SPA fallback
    _ = try app.get("/*", handlers.staticFileHandler);

    const addr = std.Io.net.IpAddress{ .ip4 = std.Io.net.Ip4Address.loopback(8082) };
    std.log.info("memos backend listening on http://localhost:8082", .{});
    try app.listen(addr);
}
