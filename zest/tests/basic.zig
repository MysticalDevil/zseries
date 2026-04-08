const std = @import("std");
const zest = @import("zest");

const testing = std.testing;

test "app creates server" {
    const io = std.Io.Threaded.global_single_threaded.io();
    const allocator = testing.allocator;

    var app = try zest.App.init(allocator, io);
    defer app.deinit();

    const handler = struct {
        fn h(ctx: *zest.Context) !void {
            try ctx.textStatus(zest.Status.ok, "Hello");
        }
    }.h;

    try app.get("/hello", handler);
}

test "router matches exact paths" {
    const allocator = testing.allocator;

    var router = try zest.Router.init(allocator);
    defer router.deinit();

    const handler = struct {
        fn h(_: *anyopaque) !void {}
    }.h;

    try router.add("/api/users", handler);

    var params = std.ArrayList(zest.PathParams.Item).init(allocator);
    defer params.deinit();

    const match = try router.get("/api/users", &params);
    try testing.expect(match != null);
}

test "context response building" {
    const io = std.Io.Threaded.global_single_threaded.io();
    const allocator = testing.allocator;

    var ctx = try zest.Context.init(
        allocator,
        io,
        .GET,
        "/test",
        .{ .items = &.{} },
    );
    defer ctx.deinit();

    try ctx.textStatus(zest.Status.ok, "Hello, World!");
    try testing.expectEqual(@as(u16, 200), @intFromEnum(ctx.response_status));
    try testing.expectEqualStrings("Hello, World!", ctx.response_body.items);
}

test "context json response" {
    const io = std.Io.Threaded.global_single_threaded.io();
    const allocator = testing.allocator;

    var ctx = try zest.Context.init(
        allocator,
        io,
        .GET,
        "/api/data",
        .{ .items = &.{} },
    );
    defer ctx.deinit();

    const data = .{
        .name = "test",
        .value = 42,
    };

    try ctx.jsonStatus(zest.Status.ok, data);
    try testing.expectEqual(@as(u16, 200), @intFromEnum(ctx.response_status));
    try testing.expect(std.mem.indexOf(u8, ctx.response_body.items, "\"name\":\"test\"") != null);
}

test "middleware executes hooks" {
    const allocator = testing.allocator;

    var mw = zest.middleware.Middleware.init(allocator);
    defer mw.deinit();

    const before_hook = struct {
        fn h(ctx: *zest.Context) !void {
            try ctx.statusCode(zest.Status.ok);
        }
    }.h;

    const after_hook = struct {
        fn h(ctx: *zest.Context) !void {
            const status = ctx.response_status;
            std.mem.doNotOptimizeAway(&status);
        }
    }.h;

    const io = std.Io.Threaded.global_single_threaded.io();
    var ctx = try zest.Context.init(
        allocator,
        io,
        .GET,
        "/",
        .{ .items = &.{} },
    );
    defer ctx.deinit();

    try mw.before(before_hook);
    try mw.after(after_hook);

    const handler = struct {
        fn h(_: *zest.Context) !void {}
    }.h;

    try mw.execute(&ctx, handler);
}

test "status enum values" {
    try testing.expectEqual(@as(u16, 200), @intFromEnum(zest.Status.ok));
    try testing.expectEqual(@as(u16, 404), @intFromEnum(zest.Status.not_found));
    try testing.expectEqual(@as(u16, 500), @intFromEnum(zest.Status.internal_server_error));
}

test "status category checks" {
    try testing.expectEqual(std.http.Status.Class.success, zest.Status.ok.class());
    try testing.expectEqual(std.http.Status.Class.client_error, zest.Status.not_found.class());
    try testing.expectEqual(std.http.Status.Class.server_error, zest.Status.internal_server_error.class());
}
