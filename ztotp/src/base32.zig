const std = @import("std");

const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

pub const DecodeError = error{InvalidBase32} || std.mem.Allocator.Error;
pub const Padding = enum { padded, none };

fn encodedLen(input_len: usize, padding: Padding) usize {
    const full = (input_len / 5) * 8;
    const rem = input_len % 5;
    const extra: usize = switch (rem) {
        0 => 0,
        1 => if (padding == .padded) 8 else 2,
        2 => if (padding == .padded) 8 else 4,
        3 => if (padding == .padded) 8 else 5,
        4 => if (padding == .padded) 8 else 7,
        else => unreachable,
    };
    return full + extra;
}

fn decodeChar(ch: u8) ?u5 {
    return switch (std.ascii.toUpper(ch)) {
        'A'...'Z' => @intCast(ch - 'A'),
        '2'...'7' => @intCast(26 + ch - '2'),
        else => null,
    };
}

fn cleanedAlloc(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    for (input) |ch| {
        switch (ch) {
            ' ', '\t', '\n', '\r', '-' => continue,
            else => {
                const upper = std.ascii.toUpper(ch);
                if (upper != '=' and decodeChar(upper) == null) return error.InvalidBase32;
                try out.append(allocator, upper);
            },
        }
    }

    return out.toOwnedSlice(allocator);
}

fn expectedPadding(non_pad_len: usize) ?usize {
    return switch (non_pad_len % 8) {
        0 => 0,
        2 => 6,
        4 => 4,
        5 => 3,
        7 => 1,
        else => null,
    };
}

fn validateAndCount(cleaned: []const u8) !struct { symbols_len: usize, has_padding: bool } {
    const first_pad = std.mem.indexOfScalar(u8, cleaned, '=');
    if (first_pad) |pad_start| {
        if (cleaned.len % 8 != 0) return error.InvalidBase32;
        for (cleaned[pad_start..]) |ch| {
            if (ch != '=') return error.InvalidBase32;
        }
        const symbols_len = pad_start;
        const pad_len = cleaned.len - pad_start;
        if (expectedPadding(symbols_len) != pad_len) return error.InvalidBase32;
        return .{ .symbols_len = symbols_len, .has_padding = true };
    }

    const symbols_len = cleaned.len;
    if (expectedPadding(symbols_len) == null) return error.InvalidBase32;
    return .{ .symbols_len = symbols_len, .has_padding = false };
}

pub fn decodeAlloc(allocator: std.mem.Allocator, input: []const u8) DecodeError![]u8 {
    const cleaned = try cleanedAlloc(allocator, input);
    defer allocator.free(cleaned);
    const counted = try validateAndCount(cleaned);
    const symbols = cleaned[0..counted.symbols_len];

    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    var buffer: u64 = 0;
    var bits: u8 = 0;

    for (symbols) |ch| {
        const value = decodeChar(ch) orelse return error.InvalidBase32;
        buffer = (buffer << 5) | value;
        bits += 5;
        while (bits >= 8) {
            bits -= 8;
            const shift: u5 = @intCast(bits);
            try out.append(allocator, @as(u8, @truncate((buffer >> shift) & 0xff)));
        }
    }

    if (bits > 0) {
        const mask: u64 = (@as(u64, 1) << @intCast(bits)) - 1;
        if ((buffer & mask) != 0) return error.InvalidBase32;
    }

    return out.toOwnedSlice(allocator);
}

pub fn encodeAlloc(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    return encodeAllocWithPadding(allocator, input, .none);
}

pub fn encodeAllocPadded(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    return encodeAllocWithPadding(allocator, input, .padded);
}

pub fn encodeAllocWithPadding(allocator: std.mem.Allocator, input: []const u8, padding: Padding) ![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    try out.ensureTotalCapacity(allocator, encodedLen(input.len, padding));

    var buffer: u16 = 0;
    var bits: u8 = 0;
    for (input) |byte| {
        buffer = (buffer << 8) | byte;
        bits += 8;
        while (bits >= 5) {
            bits -= 5;
            const index: u5 = @truncate((buffer >> @as(u4, @intCast(bits))) & 0x1f);
            try out.append(allocator, alphabet[index]);
        }
    }
    if (bits > 0) {
        const index: u5 = @truncate((buffer << @as(u4, @intCast(5 - bits))) & 0x1f);
        try out.append(allocator, alphabet[index]);
    }

    if (padding == .padded) {
        const target_len = encodedLen(input.len, .padded);
        while (out.items.len < target_len) {
            try out.append(allocator, '=');
        }
    }

    return out.toOwnedSlice(allocator);
}

test "rfc4648 encode padded vectors" {
    const testing = std.testing;
    const cases = [_]struct { plain: []const u8, encoded: []const u8 }{
        .{ .plain = "", .encoded = "" },
        .{ .plain = "f", .encoded = "MY======" },
        .{ .plain = "fo", .encoded = "MZXQ====" },
        .{ .plain = "foo", .encoded = "MZXW6===" },
        .{ .plain = "foob", .encoded = "MZXW6YQ=" },
        .{ .plain = "fooba", .encoded = "MZXW6YTB" },
        .{ .plain = "foobar", .encoded = "MZXW6YTBOI======" },
    };
    for (cases) |case| {
        const encoded = try encodeAllocPadded(testing.allocator, case.plain);
        defer testing.allocator.free(encoded);
        try testing.expectEqualStrings(case.encoded, encoded);
    }
}

test "rfc4648 decode padded vectors" {
    const testing = std.testing;
    const cases = [_]struct { plain: []const u8, encoded: []const u8 }{
        .{ .plain = "", .encoded = "" },
        .{ .plain = "f", .encoded = "MY======" },
        .{ .plain = "fo", .encoded = "MZXQ====" },
        .{ .plain = "foo", .encoded = "MZXW6===" },
        .{ .plain = "foob", .encoded = "MZXW6YQ=" },
        .{ .plain = "fooba", .encoded = "MZXW6YTB" },
        .{ .plain = "foobar", .encoded = "MZXW6YTBOI======" },
    };
    for (cases) |case| {
        const decoded = try decodeAlloc(testing.allocator, case.encoded);
        defer testing.allocator.free(decoded);
        try testing.expectEqualStrings(case.plain, decoded);
    }
}

test "decode accepts unpadded lowercase and grouped input" {
    const testing = std.testing;
    const decoded = try decodeAlloc(testing.allocator, "mzxw6 ytb-oi");
    defer testing.allocator.free(decoded);
    try testing.expectEqualStrings("foobar", decoded);
}

test "encode default is unpadded" {
    const testing = std.testing;
    const encoded = try encodeAlloc(testing.allocator, "foobar");
    defer testing.allocator.free(encoded);
    try testing.expectEqualStrings("MZXW6YTBOI", encoded);
}

test "decode rejects invalid lengths and padding" {
    const testing = std.testing;
    try testing.expectError(error.InvalidBase32, decodeAlloc(testing.allocator, "A"));
    try testing.expectError(error.InvalidBase32, decodeAlloc(testing.allocator, "ABC"));
    try testing.expectError(error.InvalidBase32, decodeAlloc(testing.allocator, "M=ZXW6YQ="));
    try testing.expectError(error.InvalidBase32, decodeAlloc(testing.allocator, "MZXW6YQ=="));
}

test "decode rejects non-zero trailing bits" {
    const testing = std.testing;
    try testing.expectError(error.InvalidBase32, decodeAlloc(testing.allocator, "MZ"));
}
