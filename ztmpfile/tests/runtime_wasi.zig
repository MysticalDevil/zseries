const std = @import("std");
const ztmpfile = @import("ztmpfile");

test "wasi runtime smoke: tempdir may succeed or return fs capability error" {
    var dir_or_err = ztmpfile.tempdir(std.testing.allocator);
    if (dir_or_err) |*dir| {
        const kept = dir.persist();
        defer std.testing.allocator.free(kept);
        ztmpfile.compat.deletePath(kept) catch |err| switch (err) {
            error.FileNotFound => {},
            else => std.debug.panic("failed to cleanup wasi tempdir {s}: {}", .{ kept, err }),
        };
    } else |err| switch (err) {
        error.AccessDenied,
        error.PermissionDenied,
        error.FileNotFound,
        error.NoDevice,
        => {},
        else => return err,
    }
}

test "wasi runtime smoke: tempfile may succeed or return fs capability error" {
    var file_or_err = ztmpfile.tempfile(std.testing.allocator);
    if (file_or_err) |*file| {
        file.deinit();
    } else |err| switch (err) {
        error.AccessDenied,
        error.PermissionDenied,
        error.FileNotFound,
        error.NoDevice,
        => {},
        else => return err,
    }
}
