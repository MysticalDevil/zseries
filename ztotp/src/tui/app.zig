const std = @import("std");
const model = @import("../model.zig");
const input = @import("ztui").input;
const terminal = @import("ztui").terminal;
const render = @import("render.zig");

pub const App = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    entries: []const model.Entry,
    query: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator, io: std.Io, entries: []const model.Entry) App {
        return .{
            .allocator = allocator,
            .io = io,
            .entries = entries,
            .query = .empty,
        };
    }

    pub fn deinit(self: *App) void {
        self.query.deinit(self.allocator);
    }

    pub fn run(self: *App) !void {
        const raw = try input.RawMode.enter();
        defer raw.leave();
        try terminal.enterScreen();
        defer terminal.restoreScreen() catch {};

        while (true) {
            const frame = try render.renderDashboardAlloc(self.allocator, self.entries, self.query.items, std.Io.Clock.real.now(self.io).toSeconds());
            defer self.allocator.free(frame);
            try terminal.writeStdout(frame);

            switch (try input.readEvent(250)) {
                .none => continue,
                .quit => break,
                .clear_search => self.query.clearRetainingCapacity(),
                .backspace => {
                    if (self.query.items.len > 0) self.query.items.len -= 1;
                },
                .character => |ch| try self.query.append(self.allocator, ch),
            }
        }
    }
};
