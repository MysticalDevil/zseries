const std = @import("std");
const ztmpfile = @import("ztmpfile");

test "windows runtime smoke: tempfile lifecycle in relative dir" {
    const io = std.Io.Threaded.global_single_threaded.io();
    const cwd = std.Io.Dir.cwd();
    const parent_name = "wine-smoke-parent";

    cwd.createDir(io, parent_name, .default_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    defer cwd.deleteTree(io, parent_name) catch |err| switch (err) {
        error.FileNotFound => {},
        else => std.debug.panic("failed to remove {s}: {}", .{ parent_name, err }),
    };

    var file = try ztmpfile.tempfileIn(std.testing.allocator, parent_name);

    var write_buffer: [128]u8 = undefined;
    var writer = file.file().writer(io, &write_buffer);
    try writer.interface.writeAll("wine-ok");
    try writer.interface.flush();

    var reopened = try file.reopen();
    defer reopened.close(io);
    var read_buffer: [128]u8 = undefined;
    var reader = reopened.reader(io, &read_buffer);
    try reader.seekTo(0);
    var out: [7]u8 = undefined;
    const got = try reader.interface.readSliceShort(&out);
    try std.testing.expectEqual(@as(usize, 7), got);
    try std.testing.expectEqualSlices(u8, "wine-ok", &out);

    file.deinit();
}
