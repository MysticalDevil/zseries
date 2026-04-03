const std = @import("std");

pub const ExitCode = enum(u8) {
    success = 0,
    usage_error = 1,
    io_error = 2,
    config_error = 3,
    not_found = 4,
    permission_denied = 5,
    invalid_input = 64,
    data_error = 65,
    unavailable = 69,
    config = 78,
    internal_error = 99,
};

pub const CliError = error{
    InvalidArgs,
    MissingValue,
    NotFound,
    AlreadyExists,
    PermissionDenied,
    InvalidInput,
    ConfigError,
    Unsupported,
};

pub fn exit(code: ExitCode) noreturn {
    std.posix.exit(@intFromEnum(code));
}

pub fn printError(err: anyerror, context: ?[]const u8) void {
    const err_name = switch (err) {
        error.InvalidArgs => "Invalid arguments",
        error.MissingValue => "Missing value",
        error.NotFound => "Not found",
        error.AlreadyExists => "Already exists",
        error.PermissionDenied => "Permission denied",
        error.InvalidInput => "Invalid input",
        error.ConfigError => "Configuration error",
        error.Unsupported => "Unsupported operation",
        error.FileNotFound => "File not found",
        error.AccessDenied => "Access denied",
        error.OutOfMemory => "Out of memory",
        else => "Error",
    };
    if (context) |ctx| {
        std.debug.print("{s}: {s}\n", .{ err_name, ctx });
    } else {
        std.debug.print("{s}\n", .{err_name});
    }
}

pub fn exitWithError(err: anyerror, context: ?[]const u8) noreturn {
    printError(err, context);
    const code: ExitCode = switch (err) {
        error.InvalidArgs, error.MissingValue, error.InvalidInput => .invalid_input,
        error.NotFound => .not_found,
        error.AlreadyExists => .usage_error,
        error.PermissionDenied, error.AccessDenied => .permission_denied,
        error.ConfigError => .config,
        error.OutOfMemory => .internal_error,
        else => .data_error,
    };
    exit(code);
}

test "ExitCode values match conventional codes" {
    const testing = std.testing;
    try testing.expectEqual(@as(u8, 0), @intFromEnum(ExitCode.success));
    try testing.expectEqual(@as(u8, 1), @intFromEnum(ExitCode.usage_error));
    try testing.expectEqual(@as(u8, 64), @intFromEnum(ExitCode.invalid_input));
}
