const std = @import("std");
const ztmpfile = @import("ztmpfile");

test "builder applies prefix suffix and randLen lower bound" {
    const io = std.Io.Threaded.global_single_threaded.io();
    const parent = try ztmpfile.compat.createPath(std.testing.allocator, "unit-parent-");
    defer std.testing.allocator.free(parent);
    defer ztmpfile.compat.deletePath(parent) catch {};

    var b = ztmpfile.Builder.init();
    _ = b.inDir(parent).prefix("pre-").suffix("-suf").randLen(1);

    var dir = try b.tempDir(std.testing.allocator);
    defer dir.deinit();

    const base = std.fs.path.basename(dir.path());
    try std.testing.expect(std.mem.startsWith(u8, base, "pre-"));
    try std.testing.expect(std.mem.endsWith(u8, base, "-suf"));

    const rand_len = base.len - "pre-".len - "-suf".len;
    try std.testing.expectEqual(@as(usize, 4), rand_len);

    {
        const opened = try std.Io.Dir.openDirAbsolute(io, dir.path(), .{});
        opened.close(io);
    }
}

test "tempdirIn returns error for missing parent directory" {
    const missing = "/tmp/ztmpfile-missing-parent-unit";
    try std.testing.expectError(error.FileNotFound, ztmpfile.tempdirIn(std.testing.allocator, missing));
}

test "tempfileIn returns error for missing parent directory" {
    const missing = "/tmp/ztmpfile-missing-parent-file-unit";
    try std.testing.expectError(error.FileNotFound, ztmpfile.tempfileIn(std.testing.allocator, missing));
}

test "tempdir cleanup is idempotent" {
    const io = std.Io.Threaded.global_single_threaded.io();
    var dir = try ztmpfile.tempdir(std.testing.allocator);
    const p = try std.testing.allocator.dupe(u8, dir.path());
    defer std.testing.allocator.free(p);

    dir.cleanup();
    dir.cleanup();
    dir.deinit();

    try std.testing.expectError(error.FileNotFound, std.Io.Dir.openDirAbsolute(io, p, .{}));
}

test "named tempfile cleanup is idempotent" {
    const io = std.Io.Threaded.global_single_threaded.io();
    var file = try ztmpfile.tempfile(std.testing.allocator);
    const p = try std.testing.allocator.dupe(u8, file.path());
    defer std.testing.allocator.free(p);

    file.cleanup();
    file.cleanup();
    file.deinit();

    try std.testing.expectError(error.FileNotFound, std.Io.Dir.openFileAbsolute(io, p, .{ .mode = .read_only }));
}

test "named tempfile persist then second persist returns AlreadyClosed" {
    const io = std.Io.Threaded.global_single_threaded.io();
    var file = try ztmpfile.tempfile(std.testing.allocator);
    const target = try std.fmt.allocPrint(std.testing.allocator, "{s}.persisted", .{file.path()});
    defer std.testing.allocator.free(target);

    const kept = try file.persist(target);
    defer std.testing.allocator.free(kept);
    defer std.Io.Dir.deleteFileAbsolute(io, kept) catch {};

    try std.testing.expectError(error.AlreadyClosed, file.persist(target));
}
