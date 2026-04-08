const std = @import("std");

const Io = std.Io;
const Dir = std.Io.Dir;
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

pub fn createUniqueDir(allocator: std.mem.Allocator, io: Io, parent_path: []const u8, options: CreateOptions) !CreatedDir {
    const created = try createUniqueResource(void, allocator, io, parent_path, options, createDirEntry, noopCleanup);
    return .{
        .parent_path = created.parts.parent_path,
        .name = created.parts.name,
        .full_path = created.parts.full_path,
    };
}

pub fn createUniqueFile(allocator: std.mem.Allocator, io: Io, parent_path: []const u8, options: CreateOptions) !CreatedFile {
    const created = try createUniqueResource(std.Io.File, allocator, io, parent_path, options, createFileEntry, closeFileCleanup);
    return .{
        .parent_path = created.parts.parent_path,
        .name = created.parts.name,
        .full_path = created.parts.full_path,
        .file = created.payload,
    };
}

const CreatedPathParts = struct {
    parent_path: []u8,
    name: []u8,
    full_path: []u8,
};

fn CreatedResource(comptime Payload: type) type {
    return struct {
        parts: CreatedPathParts,
        payload: Payload,
    };
}

fn createUniqueResource(
    comptime Payload: type,
    allocator: std.mem.Allocator,
    io: Io,
    parent_path: []const u8,
    options: CreateOptions,
    creator: *const fn (Dir, Io, []const u8) anyerror!Payload,
    cleanup: *const fn (Io, Payload) void,
) !CreatedResource(Payload) {
    var parent_dir = try openParent(io, parent_path);
    defer parent_dir.close(io);

    var attempt: usize = 0;
    while (attempt < options.max_attempts) : (attempt += 1) {
        const name = try makeName(allocator, io, options);
        errdefer allocator.free(name);

        const payload = creator(parent_dir, io, name) catch |err| switch (err) {
            error.PathAlreadyExists => {
                allocator.free(name);
                continue;
            },
            else => return err,
        };

        const parts = try createPathParts(allocator, parent_path, name);
        errdefer {
            cleanup(io, payload);
            freePathParts(allocator, parts);
        }

        return .{ .parts = parts, .payload = payload };
    }

    return error.PathAlreadyExists;
}

pub fn deleteTree(io: Io, parent_path: []const u8, name: []const u8) !void {
    var parent_dir = try openParent(io, parent_path);
    defer parent_dir.close(io);
    try parent_dir.deleteTree(io, name);
}

pub fn deleteFile(io: Io, parent_path: []const u8, name: []const u8) !void {
    var parent_dir = try openParent(io, parent_path);
    defer parent_dir.close(io);
    try parent_dir.deleteFile(io, name);
}

pub fn openParent(io: Io, parent_path: []const u8) !Dir {
    if (std.fs.path.isAbsolute(parent_path)) {
        return Dir.openDirAbsolute(io, parent_path, .{});
    }
    return Dir.cwd().openDir(io, parent_path, .{});
}

fn makeName(allocator: std.mem.Allocator, io: Io, options: CreateOptions) ![]u8 {
    const entropy = try randomAlphaNum(allocator, io, options.rand_len);
    defer allocator.free(entropy);

    return std.fmt.allocPrint(allocator, "{s}{s}{s}", .{ options.prefix, entropy, options.suffix });
}

fn randomAlphaNum(allocator: std.mem.Allocator, io: Io, len: usize) ![]u8 {
    const alphabet = "0123456789abcdefghijklmnopqrstuvwxyz";
    const random = try allocator.alloc(u8, len);
    errdefer allocator.free(random);

    const bytes = try allocator.alloc(u8, len);
    defer allocator.free(bytes);
    io.random(bytes);

    for (bytes, 0..) |b, idx| {
        random[idx] = alphabet[b % alphabet.len];
    }
    return random;
}

fn createDirEntry(parent_dir: Dir, io: Io, name: []const u8) !void {
    try parent_dir.createDir(io, name, .default_dir);
}

fn createFileEntry(parent_dir: Dir, io: Io, name: []const u8) !std.Io.File {
    return parent_dir.createFile(io, name, .{
        .read = true,
        .truncate = false,
        .exclusive = true,
    });
}

fn createPathParts(allocator: std.mem.Allocator, parent_path: []const u8, name: []u8) !CreatedPathParts {
    const parent_copy = try allocator.dupe(u8, parent_path);
    errdefer allocator.free(parent_copy);

    const full_path = try std.fs.path.join(allocator, &.{ parent_path, name });
    errdefer allocator.free(full_path);

    return .{
        .parent_path = parent_copy,
        .name = name,
        .full_path = full_path,
    };
}

fn freePathParts(allocator: std.mem.Allocator, parts: CreatedPathParts) void {
    allocator.free(parts.full_path);
    allocator.free(parts.parent_path);
    allocator.free(parts.name);
}

fn noopCleanup(_: Io, _: void) void {}

fn closeFileCleanup(io: Io, file: std.Io.File) void {
    file.close(io);
}
