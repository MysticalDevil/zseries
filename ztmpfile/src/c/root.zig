const std = @import("std");
const ztmpfile = @import("ztmpfile");

const abi_allocator = std.heap.page_allocator;

const TempDirBox = struct {
    value: ztmpfile.TempDir,
};

const TempFileBox = struct {
    value: ztmpfile.NamedTempFile,
};

pub const Status = enum(c_int) {
    ok = 0,
    invalid_argument = 1,
    out_of_memory = 2,
    io_error = 3,
    already_closed = 4,
    invalid_state = 5,
    unknown_error = 255,
};

var last_error_buf: [512]u8 = [_]u8{0} ** 512;

fn setLastErrorMsg(msg: []const u8) void {
    const n = @min(msg.len, last_error_buf.len - 1);
    @memcpy(last_error_buf[0..n], msg[0..n]);
    last_error_buf[n] = 0;
}

fn setLastError(err: anyerror) void {
    setLastErrorMsg(@errorName(err));
}

fn statusFromError(err: anyerror) Status {
    return switch (err) {
        error.OutOfMemory => .out_of_memory,
        error.AlreadyClosed => .already_closed,
        error.InvalidPath => .invalid_argument,
        error.FileNotFound,
        error.AccessDenied,
        error.PermissionDenied,
        error.NoDevice,
        error.ReadOnlyFileSystem,
        error.PathAlreadyExists,
        error.NotDir,
        error.IsDir,
        error.CrossDevice,
        error.SystemResources,
        => .io_error,
        else => .unknown_error,
    };
}

fn allocCString(bytes: []const u8) ?[*:0]u8 {
    const out = abi_allocator.alloc(u8, bytes.len + 1) catch return null;
    @memcpy(out[0..bytes.len], bytes);
    out[bytes.len] = 0;
    return @ptrCast(out.ptr);
}

fn toSlice(ptr: ?[*:0]const u8) ?[]const u8 {
    const p = ptr orelse return null;
    return std.mem.span(p);
}

fn toTempDirBox(ptr: ?*anyopaque) ?*TempDirBox {
    const raw = ptr orelse return null;
    return @ptrCast(@alignCast(raw));
}

fn toTempFileBox(ptr: ?*anyopaque) ?*TempFileBox {
    const raw = ptr orelse return null;
    return @ptrCast(@alignCast(raw));
}

pub export fn ztmpfile_last_error_message() callconv(.c) [*:0]const u8 {
    return @ptrCast(&last_error_buf);
}

pub export fn ztmpfile_string_free(ptr: ?[*:0]u8) callconv(.c) void {
    const p = ptr orelse return;
    const bytes = std.mem.span(p);
    const buf = @as([*]u8, @ptrCast(p))[0 .. bytes.len + 1];
    abi_allocator.free(buf);
}

pub export fn ztmpfile_tempdir_create(
    prefix: ?[*:0]const u8,
    parent_dir: ?[*:0]const u8,
    out_handle: ?*?*anyopaque,
) callconv(.c) c_int {
    if (out_handle == null) {
        setLastErrorMsg("out_handle is null");
        return @intFromEnum(Status.invalid_argument);
    }

    var options = ztmpfile.CreateOptions{};
    if (toSlice(prefix)) |p| options.prefix = p;
    if (toSlice(parent_dir)) |d| options.parent_dir = d;

    const value = ztmpfile.TempDir.create(abi_allocator, options) catch |err| {
        setLastError(err);
        return @intFromEnum(statusFromError(err));
    };

    const box = abi_allocator.create(TempDirBox) catch |err| {
        var v = value;
        v.deinit();
        setLastError(err);
        return @intFromEnum(Status.out_of_memory);
    };
    box.* = .{ .value = value };
    out_handle.?.* = @ptrCast(box);
    return @intFromEnum(Status.ok);
}

pub export fn ztmpfile_tempdir_path_copy(
    handle: ?*anyopaque,
    out_owned_path: ?*?[*:0]u8,
) callconv(.c) c_int {
    if (out_owned_path == null) {
        setLastErrorMsg("out_owned_path is null");
        return @intFromEnum(Status.invalid_argument);
    }
    const box = toTempDirBox(handle) orelse {
        setLastErrorMsg("handle is null");
        return @intFromEnum(Status.invalid_argument);
    };
    const path = box.value.path();
    if (path.len == 0) {
        setLastErrorMsg("tempdir path unavailable");
        return @intFromEnum(Status.invalid_state);
    }
    const out = allocCString(path) orelse {
        setLastErrorMsg("out of memory");
        return @intFromEnum(Status.out_of_memory);
    };
    out_owned_path.?.* = out;
    return @intFromEnum(Status.ok);
}

pub export fn ztmpfile_tempdir_persist(
    handle: ?*anyopaque,
    out_owned_path: ?*?[*:0]u8,
) callconv(.c) c_int {
    if (out_owned_path == null) {
        setLastErrorMsg("out_owned_path is null");
        return @intFromEnum(Status.invalid_argument);
    }
    const box = toTempDirBox(handle) orelse {
        setLastErrorMsg("handle is null");
        return @intFromEnum(Status.invalid_argument);
    };
    const raw = box.value.persist();
    defer abi_allocator.free(raw);

    const out = allocCString(raw) orelse {
        setLastErrorMsg("out of memory");
        return @intFromEnum(Status.out_of_memory);
    };
    out_owned_path.?.* = out;
    return @intFromEnum(Status.ok);
}

pub export fn ztmpfile_tempdir_destroy(handle: ?*anyopaque) callconv(.c) void {
    const box = toTempDirBox(handle) orelse return;
    box.value.deinit();
    abi_allocator.destroy(box);
}

pub export fn ztmpfile_tempfile_create(
    prefix: ?[*:0]const u8,
    parent_dir: ?[*:0]const u8,
    out_handle: ?*?*anyopaque,
) callconv(.c) c_int {
    if (out_handle == null) {
        setLastErrorMsg("out_handle is null");
        return @intFromEnum(Status.invalid_argument);
    }

    var options = ztmpfile.CreateOptions{};
    if (toSlice(prefix)) |p| options.prefix = p;
    if (toSlice(parent_dir)) |d| options.parent_dir = d;

    const value = ztmpfile.NamedTempFile.create(abi_allocator, options) catch |err| {
        setLastError(err);
        return @intFromEnum(statusFromError(err));
    };

    const box = abi_allocator.create(TempFileBox) catch |err| {
        var v = value;
        v.deinit();
        setLastError(err);
        return @intFromEnum(Status.out_of_memory);
    };
    box.* = .{ .value = value };
    out_handle.?.* = @ptrCast(box);
    return @intFromEnum(Status.ok);
}

pub export fn ztmpfile_tempfile_path_copy(
    handle: ?*anyopaque,
    out_owned_path: ?*?[*:0]u8,
) callconv(.c) c_int {
    if (out_owned_path == null) {
        setLastErrorMsg("out_owned_path is null");
        return @intFromEnum(Status.invalid_argument);
    }
    const box = toTempFileBox(handle) orelse {
        setLastErrorMsg("handle is null");
        return @intFromEnum(Status.invalid_argument);
    };
    const path = box.value.path();
    if (path.len == 0) {
        setLastErrorMsg("tempfile path unavailable");
        return @intFromEnum(Status.invalid_state);
    }
    const out = allocCString(path) orelse {
        setLastErrorMsg("out of memory");
        return @intFromEnum(Status.out_of_memory);
    };
    out_owned_path.?.* = out;
    return @intFromEnum(Status.ok);
}

pub export fn ztmpfile_tempfile_persist(
    handle: ?*anyopaque,
    to_path: ?[*:0]const u8,
    out_owned_path: ?*?[*:0]u8,
) callconv(.c) c_int {
    if (out_owned_path == null) {
        setLastErrorMsg("out_owned_path is null");
        return @intFromEnum(Status.invalid_argument);
    }
    const box = toTempFileBox(handle) orelse {
        setLastErrorMsg("handle is null");
        return @intFromEnum(Status.invalid_argument);
    };
    const target = toSlice(to_path) orelse {
        setLastErrorMsg("to_path is null");
        return @intFromEnum(Status.invalid_argument);
    };

    const raw = box.value.persist(target) catch |err| {
        setLastError(err);
        return @intFromEnum(statusFromError(err));
    };
    defer abi_allocator.free(raw);

    const out = allocCString(raw) orelse {
        setLastErrorMsg("out of memory");
        return @intFromEnum(Status.out_of_memory);
    };
    out_owned_path.?.* = out;
    return @intFromEnum(Status.ok);
}

pub export fn ztmpfile_tempfile_destroy(handle: ?*anyopaque) callconv(.c) void {
    const box = toTempFileBox(handle) orelse return;
    box.value.deinit();
    abi_allocator.destroy(box);
}
