const std = @import("std");
const model = @import("../model.zig");
const input = @import("ztui").input;
const terminal = @import("ztui").terminal;
const zlog = @import("zlog");
const render = @import("render.zig");

pub const App = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    entries: []const model.Entry,
    query: std.ArrayList(u8),
    logger: ?zlog.Logger,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, entries: []const model.Entry) App {
        return .{
            .allocator = allocator,
            .io = io,
            .entries = entries,
            .query = .empty,
            .logger = null,
        };
    }

    pub fn deinit(self: *App) void {
        if (self.logger) |*logger| logger.deinit();
        self.query.deinit(self.allocator);
    }

    pub fn configureLogger(self: *App, path: ?[]const u8, level_value: zlog.Level, stdout_enabled: bool, stderr_enabled: bool) !void {
        if (path == null and !stdout_enabled and !stderr_enabled) return;
        var logger = zlog.Logger.init(self.allocator, self.io, level_value);
        errdefer logger.deinit();
        if (path) |value| try logger.addFileSink(value);
        if (stdout_enabled) try logger.addStdoutSink();
        if (stderr_enabled) try logger.addStderrSink();
        self.logger = logger;
        self.log(.info, "logger_configured", &.{
            zlog.Field.string("path", path orelse ""),
            zlog.Field.boolean("stdout", stdout_enabled),
            zlog.Field.boolean("stderr", stderr_enabled),
        });
    }

    fn log(self: *App, level_value: zlog.Level, message: []const u8, fields: []const zlog.Field) void {
        if (self.logger) |*logger| logger.log(level_value, message, fields) catch {};
    }

    pub fn run(self: *App) !void {
        const raw = try input.RawMode.enter();
        defer raw.leave();
        try terminal.enterScreen();
        defer terminal.restoreScreen() catch {};

        var frame_index: u64 = 0;
        var last_hash: ?u64 = null;
        var last_size: ?u64 = null;

        while (true) {
            const dashboard = try render.renderDashboardAlloc(self.allocator, self.entries, self.query.items, std.Io.Clock.real.now(self.io).toSeconds());
            defer dashboard.deinit(self.allocator);
            const changed = last_hash == null or last_hash.? != dashboard.frame_hash;
            const current_size = (@as(u64, dashboard.width) << 32) | @as(u64, dashboard.height);
            const size_changed = last_size == null or last_size.? != current_size;
            self.log(.trace, if (changed) "render" else "skip", &.{
                zlog.Field.uint("index", frame_index),
                zlog.Field.uint("width", dashboard.width),
                zlog.Field.uint("height", dashboard.height),
                zlog.Field.uint("totp", dashboard.totp_count),
                zlog.Field.uint("readonly", dashboard.readonly_count),
                zlog.Field.uint("hash", dashboard.frame_hash),
                zlog.Field.boolean("changed", changed),
                zlog.Field.boolean("size_changed", size_changed),
                zlog.Field.string("query", self.query.items),
            });
            if (changed) {
                if (size_changed) {
                    try terminal.clearScreen();
                } else {
                    try terminal.homeCursor();
                }
                try terminal.writeStdout(dashboard.frame);
                last_hash = dashboard.frame_hash;
                last_size = current_size;
            }
            frame_index += 1;

            switch (try input.readEvent(250)) {
                .none => continue,
                .quit => {
                    self.log(.info, "event", &.{zlog.Field.string("kind", "quit")});
                    break;
                },
                .clear_search => {
                    self.query.clearRetainingCapacity();
                    self.log(.trace, "event", &.{zlog.Field.string("kind", "clear_search")});
                },
                .backspace => {
                    if (self.query.items.len > 0) self.query.items.len -= 1;
                    self.log(.trace, "event", &.{ zlog.Field.string("kind", "backspace"), zlog.Field.string("query", self.query.items) });
                },
                .character => |ch| {
                    try self.query.append(self.allocator, ch);
                    var char_buf: [1]u8 = .{ch};
                    self.log(.trace, "event", &.{ zlog.Field.string("kind", "character"), zlog.Field.string("char", &char_buf), zlog.Field.string("query", self.query.items) });
                },
            }
        }
    }
};

test "app logger writes diagnostic lines" {
    const testing = std.testing;
    const path = ".tmp-app-tui.log";
    var app = App.init(testing.allocator, std.Io.Threaded.init_single_threaded, &.{});
    defer app.deinit();
    defer std.Io.Dir.cwd().deleteFile(std.Io.Threaded.init_single_threaded, path) catch {};
    try app.configureLogger(path, .trace, false, false);
    app.log(.info, "frame", &.{ zlog.Field.uint("index", 1), zlog.Field.boolean("changed", true) });
    const bytes = try std.Io.Dir.cwd().readFileAlloc(std.Io.Threaded.init_single_threaded, path, testing.allocator, .limited(4096));
    defer testing.allocator.free(bytes);
    try testing.expect(std.mem.indexOf(u8, bytes, "msg=frame") != null);
    try testing.expect(std.mem.indexOf(u8, bytes, "index=1") != null);
}

test "app logger writes to absolute path" {
    const testing = std.testing;
    const path = "/home/omega/Projects/zseries/ztotp/.tmp-app-tui-abs.log";
    var app = App.init(testing.allocator, std.Io.Threaded.init_single_threaded, &.{});
    defer app.deinit();
    defer std.Io.Dir.deleteFileAbsolute(std.Io.Threaded.init_single_threaded, path) catch {};
    try app.configureLogger(path, .trace, false, false);
    app.log(.info, "frame", &.{ zlog.Field.uint("index", 2), zlog.Field.boolean("changed", false) });
    const bytes = try std.Io.Dir.readFileAllocAbsolute(std.Io.Threaded.init_single_threaded, path, testing.allocator, .limited(4096));
    defer testing.allocator.free(bytes);
    try testing.expect(std.mem.indexOf(u8, bytes, "index=2") != null);
}
