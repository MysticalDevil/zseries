const std = @import("std");

/// Detailed error information for TOML parsing
pub const Error = struct {
    message: []const u8,
    line: usize,
    column: usize,
    expected: ?[]const u8 = null,
    found: ?[]const u8 = null,

    pub fn format(
        self: Error,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("TOML Error at {}:{}", .{ self.line, self.column });
        if (self.expected) |expected| {
            try writer.print(" - expected: '{s}'", .{expected});
        }
        if (self.found) |found| {
            try writer.print(", found: '{s}'", .{found});
        }
        try writer.print(" - {s}", .{self.message});
    }
};

/// Error set for TOML operations
pub const ErrorSet = error{
    InvalidSyntax,
    UnexpectedToken,
    InvalidNumber,
    InvalidString,
    InvalidDateTime,
    DuplicateKey,
    InvalidTable,
    InvalidArray,
    InvalidEscapeSequence,
    OutOfMemory,
    IoError,
};

/// Create an error with position information
pub fn makeError(
    message: []const u8,
    line: usize,
    column: usize,
) Error {
    return .{
        .message = message,
        .line = line,
        .column = column,
    };
}

/// Create an error with expected/found information
pub fn makeParseError(
    message: []const u8,
    line: usize,
    column: usize,
    expected: []const u8,
    found: []const u8,
) Error {
    return .{
        .message = message,
        .line = line,
        .column = column,
        .expected = expected,
        .found = found,
    };
}
