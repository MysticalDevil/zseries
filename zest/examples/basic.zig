const std = @import("std");
const zest = @import("zest");
const zlog = @import("zlog");

pub fn main() !void {
    const io = std.Io.Threaded.global_single_threaded.io();
    const allocator = std.heap.page_allocator;

    var logger = zlog.Logger.init(allocator, io, .info);
    defer logger.deinit();
    try logger.addStdoutSink();

    var app = try zest.App.init(allocator, io);
    defer app.deinit();

    const beforeHook = struct {
        var log: *zlog.Logger = undefined;
        fn hook(ctx: *zest.Context) !void {
            const start_time = std.time.milliTimestamp();
            const ptr: *anyopaque = @ptrFromInt(@as(usize, @intCast(start_time)));
            try ctx.set("start_time", ptr);

            log.log(.info, "request_started", &.{
                zlog.Field.string("method", @tagName(ctx.method)),
                zlog.Field.string("path", ctx.path),
            });
        }
    }.hook;
    beforeHook.log = &logger;
    try app.before(beforeHook);

    const afterHook = struct {
        var log: *zlog.Logger = undefined;
        fn hook(ctx: *zest.Context) !void {
            const start_ptr = ctx.get("start_time");
            if (start_ptr == null) return;
            const start_time: i64 = @intCast(@intFromPtr(start_ptr.?));
            const duration = std.time.milliTimestamp() - start_time;

            log.log(.info, "request_completed", &.{
                zlog.Field.string("method", @tagName(ctx.method)),
                zlog.Field.string("path", ctx.path),
                zlog.Field.uint("status", @intFromEnum(ctx.response_status)),
                zlog.Field.int("duration_ms", duration),
            });
        }
    }.hook;
    afterHook.log = &logger;
    try app.after(afterHook);

    const index = try app.get("/", indexHandler);
    _ = index;
    const health = try app.get("/health", healthHandler);
    _ = health;

    // API group with its own prefix and hooks
    var api = try app.group("/api");
    defer api.deinit();

    const apiAuthHook = struct {
        fn hook(ctx: *zest.Context) !void {
            // Stub authentication check for the API group
            if (ctx.header("Authorization") == null) {
                try ctx.jsonStatus(zest.Status.unauthorized, .{ .@"error" = "missing auth" });
                return error.Unauthorized;
            }
        }
    }.hook;
    try api.before(apiAuthHook);

    const user_builder = try api.get("/users/:id", getUserHandler);
    _ = user_builder;
    const create_builder = try api.post("/users", createUserHandler);
    _ = create_builder;

    // Per-route middleware example: add a custom header on a single route
    const admin_builder = try api.get("/admin", adminHandler);
    const admin_with_hook = try admin_builder.after(struct {
        fn hook(ctx: *zest.Context) !void {
            try ctx.setHeader("X-Admin-Route", "true");
        }
    }.hook);
    _ = admin_with_hook;

    const addr = std.Io.net.Ip4Address.loopback(8080);
    try app.listen(addr);
}

fn indexHandler(ctx: *zest.Context) !void {
    try ctx.jsonStatus(zest.Status.ok, .{
        .message = "Welcome to zest!",
        .version = zest.version,
    });
}

fn healthHandler(ctx: *zest.Context) !void {
    try ctx.jsonStatus(zest.Status.ok, .{
        .status = "healthy",
        .timestamp = std.time.milliTimestamp(),
    });
}

fn getUserHandler(ctx: *zest.Context) !void {
    const user_id_opt = ctx.param("id");
    if (user_id_opt == null) {
        const ErrorResponse = struct {
            @"error": []const u8,
        };
        try ctx.jsonStatus(zest.Status.bad_request, ErrorResponse{ .@"error" = "Missing user id" });
        return;
    }
    const user_id = user_id_opt.?;

    var name_buf: [64]u8 = undefined;
    const name = try std.fmt.bufPrint(&name_buf, "User {s}", .{user_id});

    const UserResponse = struct {
        id: []const u8,
        name: []const u8,
        email: []const u8,
    };

    const resp = UserResponse{
        .id = user_id,
        .name = name,
        .email = "user@example.com",
    };

    try ctx.jsonStatus(zest.Status.ok, resp);
}

fn createUserHandler(ctx: *zest.Context) !void {
    const User = struct {
        name: []const u8,
        email: []const u8,
    };

    const user = try ctx.bodyJson(User) orelse {
        try ctx.jsonStatus(zest.Status.bad_request, .{ .@"error" = "Invalid JSON body" });
        return;
    };

    try ctx.jsonStatus(zest.Status.created, .{
        .id = "12345",
        .name = user.name,
        .email = user.email,
    });
}

fn adminHandler(ctx: *zest.Context) !void {
    try ctx.jsonStatus(zest.Status.ok, .{ .admin = true });
}
