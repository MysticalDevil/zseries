const std = @import("std");
const ztmpfile = @import("ztmpfile");

test "tempdirIn creates under explicit parent and cleans up" {
    const io = std.Io.Threaded.global_single_threaded.io();
    const parent = try ztmpfile.compat.createPath(std.testing.allocator, "it-parent-");
    defer std.testing.allocator.free(parent);
    defer ztmpfile.compat.deletePath(parent) catch {};

    var dir = try ztmpfile.tempdirIn(std.testing.allocator, parent);
    const path_copy = try std.testing.allocator.dupe(u8, dir.path());
    defer std.testing.allocator.free(path_copy);

    try std.testing.expect(std.mem.startsWith(u8, dir.path(), parent));
    dir.deinit();
    try std.testing.expectError(error.FileNotFound, std.Io.Dir.openDirAbsolute(io, path_copy, .{}));
}

test "tempfileIn writes reopens persists with same content" {
    const io = std.Io.Threaded.global_single_threaded.io();
    const parent = try ztmpfile.compat.createPath(std.testing.allocator, "it-parent-file-");
    defer std.testing.allocator.free(parent);
    defer ztmpfile.compat.deletePath(parent) catch {};

    var file = try ztmpfile.tempfileIn(std.testing.allocator, parent);
    var write_buffer: [256]u8 = undefined;
    var writer = file.file().writer(io, &write_buffer);
    try writer.interface.writeAll("integration-content");
    try writer.interface.flush();

    var reopened = try file.reopen();
    defer reopened.close(io);
    var read_buffer: [256]u8 = undefined;
    var reader = reopened.reader(io, &read_buffer);
    try reader.seekTo(0);
    var content: [19]u8 = undefined;
    const got = try reader.interface.readSliceShort(&content);
    try std.testing.expectEqual(@as(usize, 19), got);
    try std.testing.expectEqualStrings("integration-content", &content);

    const target = try std.fmt.allocPrint(std.testing.allocator, "{s}/saved.bin", .{parent});
    defer std.testing.allocator.free(target);
    const kept = try file.persist(target);
    defer std.testing.allocator.free(kept);

    const persisted = try std.Io.Dir.openFileAbsolute(io, kept, .{ .mode = .read_only });
    defer persisted.close(io);
}

test "batch creation produces unique paths" {
    var seen = std.StringHashMap(void).init(std.testing.allocator);
    defer {
        var it = seen.keyIterator();
        while (it.next()) |key_ptr| {
            std.testing.allocator.free(key_ptr.*);
        }
        seen.deinit();
    }

    var files: [24]ztmpfile.NamedTempFile = undefined;
    var i: usize = 0;
    errdefer {
        var j: usize = 0;
        while (j < i) : (j += 1) files[j].deinit();
    }

    while (i < files.len) : (i += 1) {
        files[i] = try ztmpfile.tempfile(std.testing.allocator);
        const path_copy = try std.testing.allocator.dupe(u8, files[i].path());
        if (seen.get(path_copy) != null) return error.DuplicatePath;
        try seen.put(path_copy, {});
    }

    for (&files) |*f| {
        f.deinit();
    }
}
