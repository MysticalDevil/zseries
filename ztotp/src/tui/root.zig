const std = @import("std");
const model = @import("../model.zig");
const app = @import("app.zig");
const zlog = @import("zlog");

pub const Config = struct {
    log_path: ?[]const u8 = null,
    log_level: zlog.Level = .trace,
    log_stdout: bool = false,
    log_stderr: bool = false,
};

pub fn run(allocator: std.mem.Allocator, io: std.Io, entries: []const model.Entry, config: Config) !void {
    var tui_app = app.App.init(allocator, io, entries);
    defer tui_app.deinit();
    try tui_app.configureLogger(config.log_path, config.log_level, config.log_stdout, config.log_stderr);
    try tui_app.run();
}
