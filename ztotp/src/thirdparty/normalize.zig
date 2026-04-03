const std = @import("std");
const model = @import("../model.zig");
const shared = @import("shared.zig");

pub const readonly_reason_non_totp = "imported_non_totp";

pub const NormalizedInput = struct {
    id: ?[]const u8 = null,
    issuer: ?[]const u8 = null,
    account_name: []const u8,
    secret: []const u8,
    kind: model.EntryKind = .totp,
    digits: u8 = 6,
    period: u32 = 30,
    counter: ?u64 = null,
    algorithm: model.Algorithm = .sha1,
    tags: []const []const u8 = &.{},
    note: ?[]const u8 = null,
    source_format: ?[]const u8 = null,
};

pub fn entryAlloc(allocator: std.mem.Allocator, input: NormalizedInput, now: i64, id_hint: usize) !model.Entry {
    const kind = input.kind;
    return .{
        .id = if (input.id) |value| try shared.dup(allocator, value) else try std.fmt.allocPrint(allocator, "import-{d}", .{id_hint}),
        .issuer = try shared.dup(allocator, input.issuer orelse ""),
        .account_name = try shared.dup(allocator, input.account_name),
        .secret = try shared.dup(allocator, input.secret),
        .kind = kind,
        .digits = input.digits,
        .period = input.period,
        .counter = input.counter,
        .algorithm = input.algorithm,
        .tags = try dupTags(allocator, input.tags),
        .note = if (input.note) |value| try shared.dup(allocator, value) else null,
        .readonly_reason = if (kind == .totp) null else try shared.dup(allocator, readonly_reason_non_totp),
        .source_format = if (input.source_format) |value| try shared.dup(allocator, value) else null,
        .created_at = now,
        .updated_at = now,
    };
}

fn dupTags(allocator: std.mem.Allocator, tags: []const []const u8) ![]const []const u8 {
    if (tags.len == 0) return &.{};
    var out = std.ArrayList([]const u8).empty;
    defer out.deinit(allocator);
    for (tags) |tag| try out.append(allocator, try shared.dup(allocator, tag));
    return out.toOwnedSlice(allocator);
}

test "marks non totp entries readonly" {
    const testing = std.testing;
    const entry = try entryAlloc(testing.allocator, .{
        .account_name = "James",
        .issuer = "Issuu",
        .secret = "YOOMIXWS5GN6RTBPUFFWKTW5M4",
        .kind = .hotp,
        .counter = 1,
        .source_format = "2fas",
    }, 0, 0);
    try testing.expectEqual(model.EntryKind.hotp, entry.kind);
    try testing.expect(entry.isReadonly());
    try testing.expectEqualStrings(readonly_reason_non_totp, entry.readonly_reason.?);
}
