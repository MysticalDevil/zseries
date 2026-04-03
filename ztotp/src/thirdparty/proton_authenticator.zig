const std = @import("std");
const model = @import("../model.zig");
const otpauth = @import("otpauth.zig");
const normalize = @import("normalize.zig");

const Export = struct {
    entries: []const Entry,
};

const Entry = struct {
    id: []const u8,
    note: ?[]const u8 = null,
    content: struct {
        uri: []const u8,
        entry_type: ?[]const u8 = null,
        name: ?[]const u8 = null,
    },
};

pub fn importAlloc(allocator: std.mem.Allocator, bytes: []const u8, now: i64) ![]const model.Entry {
    const parsed = try std.json.parseFromSliceLeaky(Export, allocator, bytes, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
    var entries = std.ArrayList(model.Entry).empty;
    defer entries.deinit(allocator);
    for (parsed.entries, 0..) |entry, i| {
        const parsed_uri = try otpauth.parseUri(allocator, entry.content.uri);
        defer parsed_uri.deinit(allocator);
        var input = parsed_uri.input;
        input.id = entry.id;
        input.note = entry.note;
        input.source_format = "proton-authenticator";
        try entries.append(allocator, try normalize.entryAlloc(allocator, input, now, i));
    }
    return entries.toOwnedSlice(allocator);
}
