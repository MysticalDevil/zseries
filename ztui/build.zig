const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    _ = b.standardOptimizeOption(.{});
    _ = b.addModule("ztui", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });
}
