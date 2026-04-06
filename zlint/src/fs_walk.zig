const std = @import("std");
const Config = @import("config.zig").Config;

/// Find all .zig files to scan
pub fn collectFiles(
    allocator: std.mem.Allocator,
    io: std.Io,
    root_path: []const u8,
    config: Config,
) ![]const []const u8 {
    var files = std.ArrayList([]const u8).empty;
    errdefer files.deinit(allocator);

    for (config.scan.include) |include_path| {
        const full_path = try std.fs.path.join(allocator, &.{ root_path, include_path });
        defer allocator.free(full_path);

        try collectPath(allocator, io, full_path, config, &files);
    }

    return files.toOwnedSlice(allocator);
}

fn collectPath(
    allocator: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
    config: Config,
    files: *std.ArrayList([]const u8),
) !void {
    const cwd = std.Io.Dir.cwd();

    // First, try to open as directory
    var dir = cwd.openDir(io, path, .{ .iterate = true }) catch |open_err| {
        // Not a directory, try as file
        if (open_err == error.NotDir or open_err == error.FileNotFound) {
            // Check if it's a .zig file
            if (std.mem.endsWith(u8, path, ".zig")) {
                const owned_path = try allocator.dupe(u8, path);
                try files.append(allocator, owned_path);
            }
        } else {
            std.log.warn("Cannot open {s}: {}", .{ path, open_err });
        }
        return;
    };
    defer dir.close(io);

    // Iterate directory
    var iter = dir.iterate();
    while (iter.next(io) catch |e| {
        std.log.warn("Error iterating {s}: {}", .{ path, e });
        return;
    }) |entry| {
        // Skip excluded directories
        if (entry.kind == .directory) {
            var excluded = false;
            for (config.scan.exclude) |exclude| {
                if (std.mem.eql(u8, entry.name, exclude)) {
                    excluded = true;
                    break;
                }
            }
            if (excluded) continue;
        }

        const entry_path = try std.fs.path.join(allocator, &.{ path, entry.name });
        defer allocator.free(entry_path);

        if (entry.kind == .directory) {
            try collectPath(allocator, io, entry_path, config, files);
        } else if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".zig")) {
            const owned_path = try allocator.dupe(u8, entry_path);
            try files.append(allocator, owned_path);
        }
    }
}
