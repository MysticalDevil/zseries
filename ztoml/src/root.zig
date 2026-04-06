const std = @import("std");

pub const Error = @import("error.zig").Error;
pub const ErrorSet = @import("error.zig").ErrorSet;
pub const makeError = @import("error.zig").makeError;
pub const makeParseError = @import("error.zig").makeParseError;

pub const Token = @import("lexer.zig").Token;
pub const TokenType = @import("lexer.zig").TokenType;
pub const Lexer = @import("lexer.zig").Lexer;
pub const tokenize = @import("lexer.zig").tokenize;

pub const Value = @import("value.zig").Value;
pub const DatetimeValue = Value.DatetimeValue;

pub const parse = @import("parser.zig").parse;
pub const parseFile = @import("parser.zig").parseFile;

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

    const name = value.get("name").?.getString();
    try std.testing.expectEqualStrings("test", name.?);

    const num = value.get("value").?.getInteger();
    try std.testing.expectEqual(@as(i64, 42), num.?);
}

test "parse nested table" {
    const source =
        \\[server]
        \\host = "localhost"
        \\port = 8080
    ;

    var value = try parseString(gpa, source);
    defer value.deinit(gpa);

    const server = value.get("server").?;
    try std.testing.expect(server.isTable());

    const host = server.get("host").?.getString();
    try std.testing.expectEqualStrings("localhost", host.?);

    const port = server.get("port").?.getInteger();
    try std.testing.expectEqual(@as(i64, 8080), port.?);
}

test "parse array" {
    const source =
        \\numbers = [1, 2, 3]
    ;

    var value = try parseString(gpa, source);
    defer value.deinit(gpa);

    const arr = value.get("numbers").?;
    try std.testing.expect(arr.isArray());

    const first = arr.at(0).?.getInteger();
    try std.testing.expectEqual(@as(i64, 1), first.?);
}

test "parse boolean" {
    const source =
        \\enabled = true
        \\disabled = false
    ;

    var value = try parseString(gpa, source);
    defer value.deinit(gpa);

    const enabled = value.get("enabled").?.getBoolean();
    try std.testing.expect(enabled.?);

    const disabled = value.get("disabled").?.getBoolean();
    try std.testing.expect(!disabled.?);
}

test "parse float" {
    const source =
        \\pi = 3.14159
    ;

    var value = try parseString(gpa, source);
    defer value.deinit(gpa);

    const pi = value.get("pi").?.getFloat();
    try std.testing.expectApproxEqAbs(@as(f64, 3.14159), pi.?, 0.00001);
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
