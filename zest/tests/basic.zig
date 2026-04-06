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
    try testing.expectEqual(@as(u16, 200), ctx.response_status);
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
    try testing.expectEqual(@as(u16, 200), ctx.response_status);
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
    try testing.expectEqual(@as(u16, 200), zest.Status.ok.code());
    try testing.expectEqual(@as(u16, 404), zest.Status.not_found.code());
    try testing.expectEqual(@as(u16, 500), zest.Status.internal_server_error.code());
}

test "status category checks" {
    try testing.expect(zest.Status.ok.isSuccess());
    try testing.expect(!zest.Status.ok.isError());

    try testing.expect(zest.Status.not_found.isClientError());
    try testing.expect(zest.Status.not_found.isError());

    try testing.expect(zest.Status.internal_server_error.isServerError());
    try testing.expect(zest.Status.internal_server_error.isError());
}
