const std = @import("std");

const Io = std.Io;
const CreateOptions = @import("../options.zig").CreateOptions;
const posix = @import("posix_core.zig");

pub const CreatedDir = posix.CreatedDir;
pub const CreatedFile = posix.CreatedFile;

pub fn defaultTempRoot(allocator: std.mem.Allocator, io: Io) ![]u8 {
    if (try readEnvironValue(allocator, io, "TMPDIR")) |v| return v;
    if (try readEnvironValue(allocator, io, "TEMP")) |v| return v;
    if (try readEnvironValue(allocator, io, "TMP")) |v| return v;
    if (try readEnvironValue(allocator, io, "XDG_RUNTIME_DIR")) |v| return v;
    return allocator.dupe(u8, "/tmp");
}

pub fn createUniqueDir(allocator: std.mem.Allocator, io: Io, parent_path: []const u8, options: CreateOptions) !CreatedDir {
    return posix.createUniqueDir(allocator, io, parent_path, options);
}

pub fn createUniqueFile(allocator: std.mem.Allocator, io: Io, parent_path: []const u8, options: CreateOptions) !CreatedFile {
    return posix.createUniqueFile(allocator, io, parent_path, options);
}

pub fn deleteTree(io: Io, parent_path: []const u8, name: []const u8) !void {
    return posix.deleteTree(io, parent_path, name);
}

pub fn deleteFile(io: Io, parent_path: []const u8, name: []const u8) !void {
    return posix.deleteFile(io, parent_path, name);
}

fn readEnvironValue(allocator: std.mem.Allocator, io: Io, key: []const u8) !?[]u8 {
    const env_file = std.Io.Dir.openFileAbsolute(io, "/proc/self/environ", .{ .mode = .read_only }) catch return null;
    defer env_file.close(io);

    var read_buffer: [8192]u8 = undefined;
    var file_reader = env_file.reader(io, &read_buffer);
    const got = file_reader.interface.readSliceShort(&read_buffer) catch return null;
    const data = read_buffer[0..got];

    var it = std.mem.splitScalar(u8, data, 0);
    while (it.next()) |entry| {
        if (entry.len <= key.len + 1) continue;
        if (std.mem.startsWith(u8, entry, key) and entry[key.len] == '=') {
            const value = entry[key.len + 1 ..];
            if (value.len == 0) return null;
            return try allocator.dupe(u8, value);
        }
    }
    return null;
}
