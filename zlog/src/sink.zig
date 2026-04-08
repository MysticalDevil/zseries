const std = @import("std");

pub const Kind = enum { stdout, stderr, file };

pub const Sink = struct {
    ptr: *anyopaque,
    kind: Kind,
    writeFn: *const fn (*anyopaque, []const u8) anyerror!void,
    flushFn: *const fn (*anyopaque) anyerror!void,
    deinitFn: *const fn (*anyopaque) void,

    pub fn write(self: Sink, bytes: []const u8) !void {
        try self.writeFn(self.ptr, bytes);
    }

    pub fn flush(self: Sink) !void {
        try self.flushFn(self.ptr);
    }

    pub fn deinit(self: Sink) void {
        self.deinitFn(self.ptr);
    }
};

pub const FileSink = struct {
    io: std.Io,
    file: std.Io.File,

    pub fn initPath(io: std.Io, path: []const u8) !FileSink {
        const file = if (std.fs.path.isAbsolute(path))
            try std.Io.Dir.createFileAbsolute(io, path, .{ .truncate = true })
        else
            try std.Io.Dir.cwd().createFile(io, path, .{ .truncate = true });
        return .{ .io = io, .file = file };
    }

    fn write(ptr: *anyopaque, bytes: []const u8) !void {
        const self: *FileSink = @ptrCast(@alignCast(ptr));
        const offset = try self.file.length(self.io);
        try self.file.writePositionalAll(self.io, bytes, offset);
    }

    fn flush(ptr: *anyopaque) !void {
        const self: *FileSink = @ptrCast(@alignCast(ptr));
        try self.file.sync(self.io);
    }

    fn deinit(ptr: *anyopaque) void {
        const self: *FileSink = @ptrCast(@alignCast(ptr));
        self.file.close(self.io);
    }

    pub fn sink(self: *FileSink) Sink {
        return .{ .ptr = self, .kind = .file, .writeFn = write, .flushFn = flush, .deinitFn = deinit };
    }
};

pub const StdSink = struct {
    io: std.Io,
    file: std.Io.File,
    kind: Kind,

    pub fn stdout(io: std.Io) StdSink {
        return .{ .io = io, .file = std.Io.File.stdout(), .kind = .stdout };
    }

    pub fn stderr(io: std.Io) StdSink {
        return .{ .io = io, .file = std.Io.File.stderr(), .kind = .stderr };
    }

    fn write(ptr: *anyopaque, bytes: []const u8) !void {
        const self: *StdSink = @ptrCast(@alignCast(ptr));
        var buffer: [4096]u8 = undefined;
        var writer = self.file.writer(self.io, &buffer);
        try writer.interface.writeAll(bytes);
        try writer.interface.flush();
    }

    fn flush(_: *anyopaque) !void {}

    fn deinit(_: *anyopaque) void {}

    pub fn sink(self: *StdSink) Sink {
        return .{ .ptr = self, .kind = self.kind, .writeFn = write, .flushFn = flush, .deinitFn = deinit };
    }
};

test "file sink writes and flushes" {
    const testing = std.testing;
    const io = std.Io.Threaded.init_single_threaded;
    var file_sink = try FileSink.initPath(io, ".tmp-zlog-sink.log");
    defer std.Io.Dir.cwd().deleteFile(io, ".tmp-zlog-sink.log") catch |err| switch (err) {
        error.FileNotFound => {},
        else => std.debug.panic("failed to remove .tmp-zlog-sink.log: {}", .{err}),
    };
    const sink = file_sink.sink();
    try sink.write("hello\n");
    try sink.flush();
    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, ".tmp-zlog-sink.log", testing.allocator, .limited(4096));
    defer testing.allocator.free(bytes);
    try testing.expect(std.mem.indexOf(u8, bytes, "hello") != null);
    sink.deinit();
}

test "file sink appends sequential writes" {
    const testing = std.testing;
    const io = std.Io.Threaded.init_single_threaded;
    var file_sink = try FileSink.initPath(io, ".tmp-zlog-sink-append.log");
    defer std.Io.Dir.cwd().deleteFile(io, ".tmp-zlog-sink-append.log") catch |err| switch (err) {
        error.FileNotFound => {},
        else => std.debug.panic("failed to remove .tmp-zlog-sink-append.log: {}", .{err}),
    };
    const sink = file_sink.sink();

    try sink.write("first\n");
    try sink.write("second\n");
    try sink.flush();

    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, ".tmp-zlog-sink-append.log", testing.allocator, .limited(4096));
    defer testing.allocator.free(bytes);

    try testing.expect(std.mem.indexOf(u8, bytes, "first\nsecond\n") != null);
    sink.deinit();
}
