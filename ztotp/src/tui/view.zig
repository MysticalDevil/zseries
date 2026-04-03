const std = @import("std");
const model = @import("../model.zig");
const totp = @import("../totp.zig");

pub const EntryView = struct {
    issuer: []const u8,
    account_name: []const u8,
    source_label: []const u8,
    kind_label: []const u8,
    readonly_reason: ?[]const u8,
    code: ?[8]u8,
    code_len: usize,
    remaining_seconds: u32,
    period: u32,
    is_readonly: bool,
};

pub fn sourceLabel(entry: model.Entry) []const u8 {
    return entry.source_format orelse "local";
}

pub fn matchesSearch(entry: model.Entry, query: []const u8) bool {
    if (query.len == 0) return true;
    return std.mem.indexOf(u8, entry.issuer, query) != null or
        std.mem.indexOf(u8, entry.account_name, query) != null or
        std.mem.indexOf(u8, entry.kind.asString(), query) != null or
        std.mem.indexOf(u8, sourceLabel(entry), query) != null;
}

pub fn entryView(allocator: std.mem.Allocator, entry: model.Entry, timestamp: i64) !EntryView {
    if (entry.kind == .totp and !entry.isReadonly()) {
        const current = try totp.generate(allocator, entry, timestamp);
        return .{
            .issuer = entry.issuer,
            .account_name = entry.account_name,
            .source_label = sourceLabel(entry),
            .kind_label = entry.kind.asString(),
            .readonly_reason = entry.readonly_reason,
            .code = current.code,
            .code_len = current.len,
            .remaining_seconds = current.remaining_seconds,
            .period = entry.period,
            .is_readonly = false,
        };
    }

    return .{
        .issuer = entry.issuer,
        .account_name = entry.account_name,
        .source_label = sourceLabel(entry),
        .kind_label = entry.kind.asString(),
        .readonly_reason = entry.readonly_reason,
        .code = null,
        .code_len = 0,
        .remaining_seconds = 0,
        .period = entry.period,
        .is_readonly = true,
    };
}
