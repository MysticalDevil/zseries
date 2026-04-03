const std = @import("std");
const level = @import("level.zig");
const field = @import("field.zig");
const record = @import("record.zig");
const sink_mod = @import("sink.zig");

pub const Logger = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    min_level: level.Level,
    sinks: std.ArrayList(sink_mod.Sink),
    file_sink: ?*sink_mod.FileSink,
    stdout_sink: ?*sink_mod.StdSink,
    stderr_sink: ?*sink_mod.StdSink,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, min_level: level.Level) Logger {
        return .{
            .allocator = allocator,
            .io = io,
            .min_level = min_level,
            .sinks = .empty,
            .file_sink = null,
            .stdout_sink = null,
            .stderr_sink = null,
        };
    }

    pub fn deinit(self: *Logger) void {
        for (self.sinks.items) |sink| sink.deinit();
        self.sinks.deinit(self.allocator);
        if (self.file_sink) |ptr| self.allocator.destroy(ptr);
        if (self.stdout_sink) |ptr| self.allocator.destroy(ptr);
        if (self.stderr_sink) |ptr| self.allocator.destroy(ptr);
    }

    pub fn addFileSink(self: *Logger, path: []const u8) !void {
        const ptr = try self.allocator.create(sink_mod.FileSink);
        ptr.* = try sink_mod.FileSink.initPath(self.io, path);
        self.file_sink = ptr;
        try self.sinks.append(self.allocator, ptr.sink());
    }

    pub fn addStdoutSink(self: *Logger) !void {
        const ptr = try self.allocator.create(sink_mod.StdSink);
        ptr.* = sink_mod.StdSink.stdout(self.io);
        self.stdout_sink = ptr;
        try self.sinks.append(self.allocator, ptr.sink());
    }

    pub fn addStderrSink(self: *Logger) !void {
        const ptr = try self.allocator.create(sink_mod.StdSink);
        ptr.* = sink_mod.StdSink.stderr(self.io);
        self.stderr_sink = ptr;
        try self.sinks.append(self.allocator, ptr.sink());
    }

    pub fn log(self: *Logger, message_level: level.Level, message: []const u8, fields: []const field.Field) !void {
        if (@intFromEnum(message_level) < @intFromEnum(self.min_level)) return;
        const rec = record.Record{
            .timestamp = std.Io.Clock.real.now(self.io).toSeconds(),
            .level_value = message_level,
            .message = message,
            .fields = fields,
        };
        const line = try rec.formatAlloc(self.allocator);
        defer self.allocator.free(line);
        for (self.sinks.items) |sink| try sink.write(line);
    }
};

test "logger filters lower levels" {
    const testing = std.testing;
    const io = std.Io.Threaded.init_single_threaded;
    var logger = Logger.init(testing.allocator, io, .warn);
    defer logger.deinit();
    try logger.addFileSink(".tmp-zlog-filter.log");
    defer std.Io.Dir.cwd().deleteFile(io, ".tmp-zlog-filter.log") catch {};
    try logger.log(.info, "skip me", &.{});
    try logger.log(.err, "keep me", &.{});
    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, ".tmp-zlog-filter.log", testing.allocator, .limited(4096));
    defer testing.allocator.free(bytes);
    try testing.expect(std.mem.indexOf(u8, bytes, "keep me") != null);
    try testing.expect(std.mem.indexOf(u8, bytes, "skip me") == null);
}

test "logger logs messages at the configured minimum level" {
    const testing = std.testing;
    const io = std.Io.Threaded.init_single_threaded;
    var logger = Logger.init(testing.allocator, io, .info);
    defer logger.deinit();
    try logger.addFileSink(".tmp-zlog-min-level.log");
    defer std.Io.Dir.cwd().deleteFile(io, ".tmp-zlog-min-level.log") catch {};

    try logger.log(.info, "boundary hit", &.{field.Field.string("scope", "main")});

    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, ".tmp-zlog-min-level.log", testing.allocator, .limited(4096));
    defer testing.allocator.free(bytes);

    try testing.expect(std.mem.indexOf(u8, bytes, "boundary hit") != null);
    try testing.expect(std.mem.indexOf(u8, bytes, "scope=main") != null);
}
