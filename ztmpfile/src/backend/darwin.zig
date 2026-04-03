const std = @import("std");

const Io = std.Io;
const CreateOptions = @import("../options.zig").CreateOptions;
const posix = @import("posix_core.zig");

pub const CreatedDir = posix.CreatedDir;
pub const CreatedFile = posix.CreatedFile;

pub fn defaultTempRoot(allocator: std.mem.Allocator, _: Io) ![]u8 {
    // macOS keeps TMPDIR in launchd environment; use /tmp as reliable fallback root.
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
