const std = @import("std");
const importers = @import("importers.zig");
const exporters = @import("exporters.zig");
const model = @import("model.zig");
const totp = @import("totp.zig");

fn readFixtureAlloc(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    return std.Io.Dir.cwd().readFileAlloc(std.Io.Threaded.init_single_threaded, path, allocator, .limited(std.math.maxInt(usize)));
}

fn expectHasEntry(entries: []const model.Entry, issuer: []const u8, account: []const u8) !void {
    for (entries) |entry| {
        if (std.mem.eql(u8, entry.issuer, issuer) and std.mem.eql(u8, entry.account_name, account)) return;
    }
    return error.ExpectedEntryMissing;
}

test "integration: aegis plain import generates codes and exports json" {
    const testing = std.testing;
    const bytes = try readFixtureAlloc(testing.allocator, "testdata/aegis_plain.json");
    defer testing.allocator.free(bytes);

    const entries = try importers.third_party.aegis_plain(testing.allocator, bytes, 0);
    try testing.expectEqual(@as(usize, 3), entries.len);
    try expectHasEntry(entries, "Deno", "Mason");

    const code = try totp.generate(testing.allocator, entries[0], 1_700_000_000);
    try testing.expectEqual(@as(usize, entries[0].digits), code.len);

    const exported = try exporters.json(testing.allocator, entries, 1_700_000_000);
    defer testing.allocator.free(exported);
    const roundtrip = try importers.json(testing.allocator, exported);
    try testing.expectEqual(@as(usize, 3), roundtrip.len);
}

test "integration: authy backup roundtrip preserves totp entries" {
    const testing = std.testing;
    const entries = [_]model.Entry{
        .{
            .id = "one",
            .issuer = "Deno",
            .account_name = "Mason",
            .secret = "4SJHB4GSD43FZBAI7C2HLRJGPQ",
            .digits = 6,
            .period = 30,
            .algorithm = .sha1,
            .created_at = 0,
            .updated_at = 0,
        },
        .{
            .id = "two",
            .issuer = "SPDX",
            .account_name = "James",
            .secret = "5OM4WOOGPLQEF6UGN3CPEOOLWU",
            .digits = 7,
            .period = 30,
            .algorithm = .sha1,
            .created_at = 0,
            .updated_at = 0,
        },
    };

    const exported = try exporters.third_party.authy_backup(testing.allocator, std.Io.Threaded.init_single_threaded, &entries, "authy-pass");
    defer testing.allocator.free(exported);
    const imported = try importers.third_party.authy_backup(testing.allocator, exported, "authy-pass", 0);
    try testing.expectEqual(@as(usize, entries.len), imported.len);
    try expectHasEntry(imported, "Authy", "Deno (Mason)");
}
