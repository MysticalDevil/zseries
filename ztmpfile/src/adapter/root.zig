const std = @import("std");
const builtin = @import("builtin");
const CreateOptions = @import("../options.zig").CreateOptions;

const Backend = switch (builtin.os.tag) {
    .linux => @import("../backend/linux.zig"),
    .macos, .ios, .watchos, .tvos, .visionos => @import("../backend/darwin.zig"),
    .windows => @import("../backend/windows.zig"),
    .wasi => @import("../backend/wasi.zig"),
    else => @import("../backend/unsupported.zig"),
};

pub const CreatedDir = Backend.CreatedDir;
pub const CreatedFile = Backend.CreatedFile;

pub fn defaultTempRoot(allocator: std.mem.Allocator, io: std.Io) ![]u8 {
    return Backend.defaultTempRoot(allocator, io);
}

pub fn createUniqueDir(allocator: std.mem.Allocator, io: std.Io, parent_path: []const u8, options: CreateOptions) !CreatedDir {
    return Backend.createUniqueDir(allocator, io, parent_path, options);
}

pub fn createUniqueFile(allocator: std.mem.Allocator, io: std.Io, parent_path: []const u8, options: CreateOptions) !CreatedFile {
    return Backend.createUniqueFile(allocator, io, parent_path, options);
}

pub fn deleteTree(io: std.Io, parent_path: []const u8, name: []const u8) !void {
    return Backend.deleteTree(io, parent_path, name);
}

pub fn deleteFile(io: std.Io, parent_path: []const u8, name: []const u8) !void {
    return Backend.deleteFile(io, parent_path, name);
}
