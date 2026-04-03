const std = @import("std");

pub const DecodeError = error{InvalidBase32} || std.mem.Allocator.Error;

fn decodeChar(ch: u8) ?u5 {
    return switch (std.ascii.toUpper(ch)) {
        'A'...'Z' => @intCast(ch - 'A'),
        '2'...'7' => @intCast(26 + ch - '2'),
        else => null,
    };
}

pub fn normalizeAlloc(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    for (input) |ch| {
        switch (ch) {
            ' ', '\t', '\n', '\r', '-' => continue,
            '=' => continue,
            else => {
                const upper = std.ascii.toUpper(ch);
                if (decodeChar(upper) == null) return error.InvalidBase32;
                try out.append(allocator, upper);
            },
        }
    }

    return out.toOwnedSlice(allocator);
}

pub fn decodeAlloc(allocator: std.mem.Allocator, input: []const u8) DecodeError![]u8 {
    const normalized = try normalizeAlloc(allocator, input);
    defer allocator.free(normalized);

    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    var buffer: u32 = 0;
    var bits: u8 = 0;

    for (normalized) |ch| {
        const value = decodeChar(ch) orelse return error.InvalidBase32;
        buffer = (buffer << 5) | value;
        bits += 5;
        while (bits >= 8) {
            bits -= 8;
            const shift: u5 = @intCast(bits);
            try out.append(allocator, @as(u8, @truncate((buffer >> shift) & 0xff)));
        }
    }

    return out.toOwnedSlice(allocator);
}
