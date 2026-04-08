const std = @import("std");
const ztmpfile = @import("ztmpfile");

test "compat deletePath rejects invalid paths" {
    try std.testing.expectError(error.InvalidPath, ztmpfile.compat.deletePath("noslash"));
    try std.testing.expectError(error.InvalidPath, ztmpfile.compat.deletePath("/"));
}

test "compat deletePath removes non-empty directory tree" {
    const io = std.Io.Threaded.global_single_threaded.io();
    const path = try ztmpfile.compat.createPath(std.testing.allocator, "compat-tree-");
    defer std.testing.allocator.free(path);

    const nested = try std.fmt.allocPrint(std.testing.allocator, "{s}/nested", .{path});
    defer std.testing.allocator.free(nested);
    try std.Io.Dir.createDirAbsolute(io, nested, .default_dir);

    const file_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/nested/child.txt", .{path});
    defer std.testing.allocator.free(file_path);
    const f = try std.Io.Dir.createFileAbsolute(io, file_path, .{
        .read = false,
        .truncate = true,
    });
    f.close(io);

    try ztmpfile.compat.deletePath(path);
    try std.testing.expectError(error.FileNotFound, std.Io.Dir.openDirAbsolute(io, path, .{}));
}

test "compat createPath honors prefix and returns absolute path" {
    const io = std.Io.Threaded.global_single_threaded.io();
    const path = try ztmpfile.compat.createPath(std.testing.allocator, "compat-prefix-");
    defer std.testing.allocator.free(path);
    defer ztmpfile.compat.deletePath(path) catch |err| switch (err) {
        error.FileNotFound => {},
        else => std.debug.panic("failed to cleanup {s}: {}", .{ path, err }),
    };

    try std.testing.expect(std.fs.path.isAbsolute(path));
    const base = std.fs.path.basename(path);
    try std.testing.expect(std.mem.startsWith(u8, base, "compat-prefix-"));

    const opened = try std.Io.Dir.openDirAbsolute(io, path, .{});
    opened.close(io);
}
