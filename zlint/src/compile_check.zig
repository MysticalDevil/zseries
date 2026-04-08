const std = @import("std");

pub const CheckResult = struct {
    ok: bool,
    term: std.process.Child.Term,
    stdout: []u8,
    stderr: []u8,

    pub fn deinit(self: *CheckResult, allocator: std.mem.Allocator) void {
        allocator.free(self.stdout);
        allocator.free(self.stderr);
    }
};

fn runCommand(allocator: std.mem.Allocator, io: std.Io, root_path: []const u8, argv: []const []const u8) !CheckResult {
    const run = try std.process.run(allocator, io, .{
        .argv = argv,
        .cwd = .{ .path = root_path },
        .stdout_limit = .unlimited,
        .stderr_limit = .unlimited,
    });

    const ok = switch (run.term) {
        .exited => |code| code == 0,
        else => false,
    };

    return .{
        .ok = ok,
        .term = run.term,
        .stdout = run.stdout,
        .stderr = run.stderr,
    };
}

pub fn runBuild(allocator: std.mem.Allocator, io: std.Io, root_path: []const u8) !CheckResult {
    return runCommand(allocator, io, root_path, &.{ "zig", "build" });
}

pub fn checkCompile(allocator: std.mem.Allocator, io: std.Io, root_path: []const u8) !CheckResult {
    return runBuild(allocator, io, root_path);
}
