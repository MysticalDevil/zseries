const std = @import("std");

pub fn main() !void {
    const cwd = std.fs.cwd();
    const dir = try cwd.openDir("./.", .{ .iterate = true });
    defer dir.close();

    var count: usize = 0;
    var walker = try dir.walk(std.heap.page_allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.basename, ".zig")) {
            std.debug.print("Found: {s}\n", .{entry.path});
            count += 1;
        }
    }

    std.debug.print("Total .zig files: {d}\n", .{count});
}
