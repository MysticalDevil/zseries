const std = @import("std");
const adapter = @import("adapter/root.zig");
const CreateOptions = @import("options.zig").CreateOptions;

pub const TempDir = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    parent_path: []u8,
    name: []u8,
    path_buf: []u8,
    cleaned: bool,

    pub fn create(allocator: std.mem.Allocator, options: CreateOptions) !TempDir {
        const io = std.Io.Threaded.global_single_threaded.io();
        const parent = if (options.parent_dir) |p| try allocator.dupe(u8, p) else try adapter.defaultTempRoot(allocator, io);
        defer allocator.free(parent);

        const created = try adapter.createUniqueDir(allocator, io, parent, options);
        return .{
            .allocator = allocator,
            .io = io,
            .parent_path = created.parent_path,
            .name = created.name,
            .path_buf = created.full_path,
            .cleaned = false,
        };
    }

    pub fn path(self: *const TempDir) []const u8 {
        return self.path_buf;
    }

    pub fn persist(self: *TempDir) []u8 {
        if (self.cleaned) return &.{};
        self.cleaned = true;

        self.allocator.free(self.parent_path);
        self.parent_path = &.{};
        self.allocator.free(self.name);
        self.name = &.{};

        const kept = self.path_buf;
        self.path_buf = &.{};
        return kept;
    }

    pub fn cleanup(self: *TempDir) void {
        if (self.cleaned) return;

        adapter.deleteTree(self.io, self.parent_path, self.name) catch |err| switch (err) {
            error.FileNotFound => {},
            else => std.debug.panic("failed to cleanup temp dir {s}: {}", .{ self.path_buf, err }),
        };
        self.allocator.free(self.path_buf);
        self.allocator.free(self.parent_path);
        self.allocator.free(self.name);

        self.path_buf = &.{};
        self.parent_path = &.{};
        self.name = &.{};
        self.cleaned = true;
    }

    pub fn deinit(self: *TempDir) void {
        self.cleanup();
    }
};
