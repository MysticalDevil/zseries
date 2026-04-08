const std = @import("std");
const Config = @import("config.zig").Config;

pub fn collectFiles(
    allocator: std.mem.Allocator,
    io: std.Io,
    root_path: []const u8,
    config: Config,
) ![]const []const u8 {
    var files = std.ArrayList([]const u8).empty;
    errdefer {
        for (files.items) |p| allocator.free(p);
        files.deinit(allocator);
    }

    for (config.scan.include) |include_path| {
        const full_path = try std.fs.path.join(allocator, &.{ root_path, include_path });
        defer allocator.free(full_path);
        try collectPath(allocator, io, full_path, config.scan.exclude, &files);
    }

    return files.toOwnedSlice(allocator);
}

fn normalizePathAlloc(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    var i: usize = 0;
    while (i + 1 < path.len and path[i] == '.' and path[i + 1] == '/') : (i += 2) {}

    while (i < path.len) {
        if (path[i] == '/' and i + 1 < path.len and path[i + 1] == '/') {
            i += 1;
            continue;
        }

        if (path[i] == '/' and i + 1 < path.len and path[i + 1] == '.') {
            const at_end = i + 2 >= path.len;
            const next_is_slash = !at_end and path[i + 2] == '/';
            if (at_end or next_is_slash) {
                i += if (next_is_slash) 2 else 1;
                continue;
            }
        }

        try out.append(allocator, path[i]);
        i += 1;
    }

    if (out.items.len == 0) {
        try out.append(allocator, '.');
    }

    return out.toOwnedSlice(allocator);
}

fn isExcludedPath(path: []const u8, exclude: []const []const u8) bool {
    for (exclude) |entry| {
        if (std.mem.eql(u8, path, entry)) return true;
        if (std.mem.indexOf(u8, path, entry)) |_| return true;
    }
    return false;
}

fn collectPath(
    allocator: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
    exclude: []const []const u8,
    files: *std.ArrayList([]const u8),
) !void {
    if (isExcludedPath(path, exclude)) return;

    const cwd = std.Io.Dir.cwd();
    var dir = cwd.openDir(io, path, .{ .iterate = true }) catch |err| {
        if (err == error.NotDir) {
            if (std.mem.endsWith(u8, path, ".zig")) {
                const normalized = try normalizePathAlloc(allocator, path);
                try files.append(allocator, normalized);
            }
            return;
        }
        if (err == error.FileNotFound) return;
        return err;
    };
    defer dir.close(io);

    var iter = dir.iterate();
    while (try iter.next(io)) |entry| {
        const entry_path = try std.fs.path.join(allocator, &.{ path, entry.name });
        defer allocator.free(entry_path);

        if (entry.kind == .directory) {
            if (isExcludedPath(entry.name, exclude)) continue;
            try collectPath(allocator, io, entry_path, exclude, files);
            continue;
        }

        if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".zig")) {
            const normalized = try normalizePathAlloc(allocator, entry_path);
            try files.append(allocator, normalized);
        }
    }
}
