const std = @import("std");
const model = @import("../model.zig");
const app = @import("app.zig");

pub fn run(allocator: std.mem.Allocator, io: std.Io, entries: []const model.Entry) !void {
    var tui_app = app.App.init(allocator, io, entries);
    defer tui_app.deinit();
    try tui_app.run();
}
