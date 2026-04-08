const std = @import("std");

pub const Status = std.http.Status;

const testing = std.testing;

test "status enum values" {
    try testing.expectEqual(@as(u16, 200), @intFromEnum(Status.ok));
    try testing.expectEqual(@as(u16, 404), @intFromEnum(Status.not_found));
    try testing.expectEqual(@as(u16, 500), @intFromEnum(Status.internal_server_error));
}

test "status phrase and class" {
    try testing.expectEqualStrings("OK", Status.ok.phrase().?);
    try testing.expectEqualStrings("I'm a teapot", Status.teapot.phrase().?);
    try testing.expectEqual(std.http.Status.Class.success, Status.ok.class());
    try testing.expectEqual(std.http.Status.Class.client_error, Status.not_found.class());
    try testing.expectEqual(std.http.Status.Class.server_error, Status.internal_server_error.class());
}
