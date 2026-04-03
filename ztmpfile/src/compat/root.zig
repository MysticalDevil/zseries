const std = @import("std");
const builder = @import("../builder.zig");
const adapter = @import("../adapter/root.zig");

pub fn createPath(allocator: std.mem.Allocator, prefix: []const u8) ![]u8 {
    var b = builder.Builder.init();
    _ = b.prefix(prefix);

    var dir = try b.tempDir(allocator);
    return dir.persist();
}

pub fn deletePath(path: []const u8) !void {
    const io = std.Io.Threaded.global_single_threaded.io();
    const sep_idx = std.mem.lastIndexOfScalar(u8, path, std.fs.path.sep) orelse return error.InvalidPath;
    if (sep_idx == 0 or sep_idx + 1 >= path.len) return error.InvalidPath;

    const parent = path[0..sep_idx];
    const child = path[sep_idx + 1 ..];
    try adapter.deleteTree(io, parent, child);
}
