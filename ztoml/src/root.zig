const std = @import("std");
const errors = @import("error.zig");
const lexer = @import("lexer.zig");
const value_zig = @import("value.zig");
const parser = @import("parser.zig");

pub const Error = errors.Error;
pub const ErrorSet = errors.ErrorSet;
pub const makeError = errors.makeError;
pub const makeParseError = errors.makeParseError;

pub const Token = lexer.Token;
pub const TokenType = lexer.TokenType;
pub const Lexer = lexer.Lexer;
pub const tokenize = lexer.tokenize;

pub const Value = value_zig.Value;
pub const DatetimeValue = Value.DatetimeValue;

pub const parse = parser.parse;
pub const parseFile = parser.parseFile;

/// Parse TOML source string into a Value
pub fn parseString(allocator: std.mem.Allocator, source: []const u8) ErrorSet!Value {
    return parse(allocator, source);
}

/// Serialize a Value to a string (caller owns memory)
pub fn toString(allocator: std.mem.Allocator, value: Value) std.mem.Allocator.Error![]u8 {
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);
    try serializeToArrayList(&list, allocator, value);
    return list.toOwnedSlice(allocator);
}

fn serializeToArrayList(list: *std.ArrayList(u8), allocator: std.mem.Allocator, value: Value) std.mem.Allocator.Error!void {
    switch (value) {
        .String => |s| {
            try list.appendSlice(allocator, "\"");
            try list.appendSlice(allocator, s);
            try list.appendSlice(allocator, "\"");
        },
        .Integer => |i| {
            const str = try std.fmt.allocPrint(allocator, "{d}", .{i});
            defer allocator.free(str);
            try list.appendSlice(allocator, str);
        },
        .Float => |f| {
            if (std.math.isInf(f)) {
                if (f > 0) {
                    try list.appendSlice(allocator, "inf");
                } else {
                    try list.appendSlice(allocator, "-inf");
                }
            } else if (std.math.isNan(f)) {
                try list.appendSlice(allocator, "nan");
            } else {
                const str = try std.fmt.allocPrint(allocator, "{e}", .{f});
                defer allocator.free(str);
                try list.appendSlice(allocator, str);
            }
        },
        .Boolean => |b| {
            try list.appendSlice(allocator, if (b) "true" else "false");
        },
        .Datetime => |dt| {
            try list.appendSlice(allocator, dt.raw);
        },
        .Array => |arr| {
            try list.appendSlice(allocator, "[");
            for (arr.items, 0..) |item, i| {
                if (i > 0) try list.appendSlice(allocator, ", ");
                try serializeToArrayList(list, allocator, item);
            }
            try list.appendSlice(allocator, "]");
        },
        .Table => |table| {
            try list.appendSlice(allocator, "{");
            var it = table.iterator();
            var first = true;
            while (it.next()) |entry| {
                if (!first) try list.appendSlice(allocator, ", ");
                first = false;
                try list.appendSlice(allocator, entry.key_ptr.*);
                try list.appendSlice(allocator, " = ");
                try serializeToArrayList(list, allocator, entry.value_ptr.*);
            }
            try list.appendSlice(allocator, "}");
        },
    }
}

// Simple deserialization for basic types
pub fn deserializeInt(value: Value) ErrorSet!i64 {
    return value.getInteger() orelse ErrorSet.InvalidSyntax;
}

pub fn deserializeFloat(value: Value) ErrorSet!f64 {
    return value.getFloat() orelse ErrorSet.InvalidSyntax;
}

pub fn deserializeBool(value: Value) ErrorSet!bool {
    return value.getBoolean() orelse ErrorSet.InvalidSyntax;
}

pub fn deserializeString(value: Value) ErrorSet![]const u8 {
    return value.getString() orelse ErrorSet.InvalidSyntax;
}

// Tests
const gpa = std.testing.allocator;

test "parse simple key-value" {
    const source =
        \\name = "test"
        \\value = 42
    ;

    var value = try parseString(gpa, source);
    defer value.deinit(gpa);

    try std.testing.expect(value.isTable());

    const name_val = value.get("name") orelse return error.MissingKey;
    const name = name_val.getString() orelse return error.TypeMismatch;
    try std.testing.expectEqualStrings("test", name);

    const num_val = value.get("value") orelse return error.MissingKey;
    const num = num_val.getInteger() orelse return error.TypeMismatch;
    try std.testing.expectEqual(@as(i64, 42), num);
}

test "parse nested table" {
    const source =
        \\[server]
        \\host = "localhost"
        \\port = 8080
    ;

    var value = try parseString(gpa, source);
    defer value.deinit(gpa);

    const server = value.get("server") orelse return error.MissingKey;
    try std.testing.expect(server.isTable());

    const host_val = server.get("host") orelse return error.MissingKey;
    const host = host_val.getString() orelse return error.TypeMismatch;
    try std.testing.expectEqualStrings("localhost", host);

    const port_val = server.get("port") orelse return error.MissingKey;
    const port = port_val.getInteger() orelse return error.TypeMismatch;
    try std.testing.expectEqual(@as(i64, 8080), port);
}

test "parse array" {
    const source =
        \\numbers = [1, 2, 3]
    ;

    var value = try parseString(gpa, source);
    defer value.deinit(gpa);

    const arr = value.get("numbers") orelse return error.MissingKey;
    try std.testing.expect(arr.isArray());

    const first_val = arr.at(0) orelse return error.MissingKey;
    const first = first_val.getInteger() orelse return error.TypeMismatch;
    try std.testing.expectEqual(@as(i64, 1), first);
}

test "parse boolean" {
    const source =
        \\enabled = true
        \\disabled = false
    ;

    var value = try parseString(gpa, source);
    defer value.deinit(gpa);

    const enabled_val = value.get("enabled") orelse return error.MissingKey;
    const enabled = enabled_val.getBoolean() orelse return error.TypeMismatch;
    try std.testing.expect(enabled);

    const disabled_val = value.get("disabled") orelse return error.MissingKey;
    const disabled = disabled_val.getBoolean() orelse return error.TypeMismatch;
    try std.testing.expect(!disabled);
}

test "parse float" {
    const source =
        \\pi = 3.14159
    ;

    var value = try parseString(gpa, source);
    defer value.deinit(gpa);

    const pi_val = value.get("pi") orelse return error.MissingKey;
    const pi = pi_val.getFloat() orelse return error.TypeMismatch;
    try std.testing.expectApproxEqAbs(@as(f64, 3.14159), pi, 0.00001);
}

test "serialize value" {
    var table = Value.table(gpa);
    defer table.deinit(gpa);

    try table.put("name", Value.string("test"));
    try table.put("count", Value.integer(42));

    const str = try toString(gpa, table);
    defer gpa.free(str);

    try std.testing.expect(std.mem.indexOf(u8, str, "name") != null);
    try std.testing.expect(std.mem.indexOf(u8, str, "test") != null);
    try std.testing.expect(std.mem.indexOf(u8, str, "count") != null);
    try std.testing.expect(std.mem.indexOf(u8, str, "42") != null);
}

test "lexer tokenize" {
    const source = "key = \"value\"";
    const tokens = try tokenize(gpa, source);
    defer gpa.free(tokens);

    try std.testing.expect(tokens.len > 0);
    try std.testing.expectEqual(TokenType.Identifier, tokens[0].type);
}
