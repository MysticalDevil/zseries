const std = @import("std");

const builder = @import("builder.zig");
const temp_dir_mod = @import("temp_dir.zig");
const named_temp_file_mod = @import("named_temp_file.zig");
const options_mod = @import("options.zig");

pub const version = "0.1.0";

pub const Builder = builder.Builder;
pub const CreateOptions = options_mod.CreateOptions;
pub const TempDir = temp_dir_mod.TempDir;
pub const NamedTempFile = named_temp_file_mod.NamedTempFile;

pub const tempdir = builder.tempdir;
pub const tempdirIn = builder.tempdirIn;
pub const tempfile = builder.tempfile;
pub const tempfileIn = builder.tempfileIn;

pub const compat = @import("compat/root.zig");

test "tempdir lifecycle deletes directory" {
    const io = std.Io.Threaded.global_single_threaded.io();
    var dir = try tempdir(std.testing.allocator);
    const path_copy = try std.testing.allocator.dupe(u8, dir.path());
    defer std.testing.allocator.free(path_copy);

    {
        const opened = try std.Io.Dir.openDirAbsolute(io, dir.path(), .{});
        opened.close(io);
    }

    dir.deinit();

    try std.testing.expectError(error.FileNotFound, std.Io.Dir.openDirAbsolute(io, path_copy, .{}));
}

test "tempdir persist keeps directory" {
    const io = std.Io.Threaded.global_single_threaded.io();
    var dir = try tempdir(std.testing.allocator);
    const kept = dir.persist();
    defer std.testing.allocator.free(kept);

    {
        const opened = try std.Io.Dir.openDirAbsolute(io, kept, .{});
        opened.close(io);
    }

    try compat.deletePath(kept);
}

test "named tempfile lifecycle and reopen" {
    const io = std.Io.Threaded.global_single_threaded.io();
    var tmp = try tempfile(std.testing.allocator);
    defer tmp.deinit();

    var write_buffer: [128]u8 = undefined;
    var writer = tmp.file().writer(io, &write_buffer);
    try writer.interface.writeAll("hello");
    try writer.interface.flush();

    var reopened = try tmp.reopen();
    defer reopened.close(io);

    var read_buffer: [128]u8 = undefined;
    var reader = reopened.reader(io, &read_buffer);
    try reader.seekTo(0);
    var out: [5]u8 = undefined;
    const got = try reader.interface.readSliceShort(&out);
    try std.testing.expectEqual(@as(usize, 5), got);
    try std.testing.expectEqualSlices(u8, "hello", &out);
}

test "named tempfile persist renames and keeps file" {
    const io = std.Io.Threaded.global_single_threaded.io();
    var tmp = try tempfile(std.testing.allocator);
    const original = try std.testing.allocator.dupe(u8, tmp.path());
    defer std.testing.allocator.free(original);

    const target = try std.fmt.allocPrint(std.testing.allocator, "{s}.kept", .{tmp.path()});
    defer std.testing.allocator.free(target);

    const kept = try tmp.persist(target);
    defer std.testing.allocator.free(kept);

    try std.testing.expectEqualStrings(target, kept);
    try std.testing.expectError(error.FileNotFound, std.Io.Dir.openFileAbsolute(io, original, .{ .mode = .read_only }));

    const reopened = try std.Io.Dir.openFileAbsolute(io, kept, .{ .mode = .read_only });
    reopened.close(io);
    try std.Io.Dir.deleteFileAbsolute(io, kept);
}

test "compat createPath and deletePath" {
    const io = std.Io.Threaded.global_single_threaded.io();
    const path = try compat.createPath(std.testing.allocator, "compat-");
    defer std.testing.allocator.free(path);

    {
        const opened = try std.Io.Dir.openDirAbsolute(io, path, .{});
        opened.close(io);
    }

    try compat.deletePath(path);
    try std.testing.expectError(error.FileNotFound, std.Io.Dir.openDirAbsolute(io, path, .{}));
}
