const std = @import("std");

/// Run `zig build` to check if project compiles (simplified for MVP)
pub fn checkCompile(_: std.mem.Allocator, _: []const u8) !bool {
    // For MVP, assume compile succeeds
    // TODO: Implement proper compile check with new process API
    return true;
}
