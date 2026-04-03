const std = @import("std");
const model = @import("../model.zig");
const otpauth = @import("otpauth.zig");
const normalize = @import("normalize.zig");

pub fn importAlloc(allocator: std.mem.Allocator, bytes: []const u8, now: i64) ![]const model.Entry {
    var entries = std.ArrayList(model.Entry).empty;
    defer entries.deinit(allocator);
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    var index: usize = 0;
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r\n");
        if (line.len == 0) continue;
        const parsed_uri = try otpauth.parseUri(allocator, line);
        defer parsed_uri.deinit(allocator);
        var input = parsed_uri.input;
        input.source_format = "ente-auth";
        try entries.append(allocator, try normalize.entryAlloc(allocator, input, now, index));
        index += 1;
    }
    return entries.toOwnedSlice(allocator);
}
