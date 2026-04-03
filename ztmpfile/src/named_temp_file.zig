const std = @import("std");
const adapter = @import("adapter/root.zig");
const CreateOptions = @import("options.zig").CreateOptions;

pub const NamedTempFile = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    parent_path: []u8,
    name: []u8,
    path_buf: []u8,
    file_handle: std.Io.File,
    cleaned: bool,

    pub fn create(allocator: std.mem.Allocator, options: CreateOptions) !NamedTempFile {
        const io = std.Io.Threaded.global_single_threaded.io();
        const parent = if (options.parent_dir) |p| try allocator.dupe(u8, p) else try adapter.defaultTempRoot(allocator, io);
        defer allocator.free(parent);

        const created = try adapter.createUniqueFile(allocator, io, parent, options);
        return .{
            .allocator = allocator,
            .io = io,
            .parent_path = created.parent_path,
            .name = created.name,
            .path_buf = created.full_path,
            .file_handle = created.file,
            .cleaned = false,
        };
    }

    pub fn path(self: *const NamedTempFile) []const u8 {
        return self.path_buf;
    }

    pub fn file(self: *NamedTempFile) *std.Io.File {
        return &self.file_handle;
    }

    pub fn reopen(self: *NamedTempFile) !std.Io.File {
        return std.Io.Dir.openFileAbsolute(self.io, self.path_buf, .{ .mode = .read_write });
    }

    pub fn persist(self: *NamedTempFile, to_path: []const u8) ![]u8 {
        if (self.cleaned) return error.AlreadyClosed;

        self.file_handle.close(self.io);
        try std.Io.Dir.renameAbsolute(self.path_buf, to_path, self.io);

        self.cleaned = true;
        self.allocator.free(self.parent_path);
        self.parent_path = &.{};
        self.allocator.free(self.name);
        self.name = &.{};
        self.allocator.free(self.path_buf);
        self.path_buf = &.{};

        return self.allocator.dupe(u8, to_path);
    }

    pub fn cleanup(self: *NamedTempFile) void {
        if (self.cleaned) return;

        self.file_handle.close(self.io);
        adapter.deleteFile(self.io, self.parent_path, self.name) catch {};

        self.allocator.free(self.path_buf);
        self.allocator.free(self.parent_path);
        self.allocator.free(self.name);

        self.path_buf = &.{};
        self.parent_path = &.{};
        self.name = &.{};
        self.cleaned = true;
    }

    pub fn deinit(self: *NamedTempFile) void {
        self.cleanup();
    }
};
