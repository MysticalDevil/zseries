const std = @import("std");
const testing = std.testing;
const Router = @import("router.zig").Router;
const PathParams = @import("router.zig").PathParams;

test "radix tree basic matching" {
    const allocator = testing.allocator;
    var router = try Router.init(allocator);
    defer router.deinit();

    const handler = struct {
        fn h(_: *anyopaque) !void {}
    }.h;

    try router.add("/users/:id", handler);
    try router.add("/users/:id/posts/:postId", handler);

    var params = std.ArrayList(PathParams.Item).init(allocator);
    defer params.deinit();

    const match1 = try router.get("/users/123", &params);
    try testing.expect(match1 != null);
    const m1 = match1.?;
    const id1 = m1.params.get("id") orelse return error.TestFailed;
    try testing.expectEqualStrings("123", id1);

    params.clearRetainingCapacity();
    const match2 = try router.get("/users/456/posts/789", &params);
    try testing.expect(match2 != null);
    const m2 = match2.?;
    const id2 = m2.params.get("id") orelse return error.TestFailed;
    try testing.expectEqualStrings("456", id2);
    const postId = m2.params.get("postId") orelse return error.TestFailed;
    try testing.expectEqualStrings("789", postId);
}

test "radix tree param int parsing" {
    const allocator = testing.allocator;
    var router = try Router.init(allocator);
    defer router.deinit();

    const handler = struct {
        fn h(_: *anyopaque) !void {}
    }.h;

    try router.add("/items/:id", handler);

    var params = std.ArrayList(PathParams.Item).init(allocator);
    defer params.deinit();

    const match = try router.get("/items/42", &params);
    try testing.expect(match != null);
    const m = match.?;
    const id = m.params.getInt("id", u32) orelse return error.TestFailed;
    try testing.expectEqual(@as(u32, 42), id);
}
