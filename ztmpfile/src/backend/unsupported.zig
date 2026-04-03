const std = @import("std");

const Io = std.Io;
const CreateOptions = @import("../options.zig").CreateOptions;

pub const CreatedDir = struct {
    parent_path: []u8,
    name: []u8,
    full_path: []u8,
};

pub const CreatedFile = struct {
    parent_path: []u8,
    name: []u8,
    full_path: []u8,
    file: std.Io.File,
};

pub fn defaultTempRoot(_: std.mem.Allocator, _: Io) ![]u8 {
    return error.UnsupportedPlatform;
}

pub fn createUniqueDir(_: std.mem.Allocator, _: Io, _: []const u8, _: CreateOptions) !CreatedDir {
    return error.UnsupportedPlatform;
}

pub fn createUniqueFile(_: std.mem.Allocator, _: Io, _: []const u8, _: CreateOptions) !CreatedFile {
    return error.UnsupportedPlatform;
}

pub fn deleteTree(_: Io, _: []const u8, _: []const u8) !void {
    return error.UnsupportedPlatform;
}

pub fn deleteFile(_: Io, _: []const u8, _: []const u8) !void {
    return error.UnsupportedPlatform;
}
