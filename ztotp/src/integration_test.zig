const std = @import("std");
const importers = @import("importers.zig");
const exporters = @import("exporters.zig");
const model = @import("model.zig");
const totp = @import("totp.zig");
const ztmpfile = @import("ztmpfile");

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
    try testing.expectEqual(@as(usize, 7), entries.len);
    try expectHasEntry(entries, "Deno", "Mason");

    const code = try totp.generate(testing.allocator, entries[0], 1_700_000_000);
    try testing.expectEqual(@as(usize, entries[0].digits), code.len);

    const exported = try exporters.json(testing.allocator, entries, 1_700_000_000);
    defer testing.allocator.free(exported);
    const roundtrip = try importers.json(testing.allocator, exported);
    try testing.expectEqual(@as(usize, 7), roundtrip.len);
    try testing.expect(roundtrip[3].isReadonly());
}

test "integration: 2fas and andotp imports preserve readonly kinds" {
    const testing = std.testing;
    const twofas_bytes = try readFixtureAlloc(testing.allocator, "testdata/twofas_plain.2fas");
    defer testing.allocator.free(twofas_bytes);
    const andotp_bytes = try readFixtureAlloc(testing.allocator, "testdata/andotp_plain.json");
    defer testing.allocator.free(andotp_bytes);

    const twofas_entries = try importers.third_party.twofas_plain(testing.allocator, twofas_bytes, 0);
    const andotp_entries = try importers.third_party.andotp_plain(testing.allocator, andotp_bytes, 0);
    try testing.expectEqual(@as(usize, 7), twofas_entries.len);
    try testing.expectEqual(@as(usize, 7), andotp_entries.len);
    try testing.expect(twofas_entries[1].isReadonly());
    try testing.expect(andotp_entries[6].isReadonly());
    try testing.expectEqual(model.EntryKind.steam, andotp_entries[6].kind);
}

test "integration: encrypted 2fas and andotp imports work with public passwords" {
    const testing = std.testing;
    const twofas_bytes = try readFixtureAlloc(testing.allocator, "testdata/twofas_encrypted.2fas");
    defer testing.allocator.free(twofas_bytes);
    const andotp_bytes = try readFixtureAlloc(testing.allocator, "testdata/andotp_encrypted.bin");
    defer testing.allocator.free(andotp_bytes);
    const andotp_old_bytes = try readFixtureAlloc(testing.allocator, "testdata/andotp_encrypted_old.bin");
    defer testing.allocator.free(andotp_old_bytes);

    const twofas_entries = try importers.third_party.twofas_encrypted(testing.allocator, twofas_bytes, "test", 0);
    const andotp_entries = try importers.third_party.andotp_encrypted(testing.allocator, andotp_bytes, "test", 0);
    const andotp_old_entries = try importers.third_party.andotp_encrypted_old(testing.allocator, andotp_old_bytes, "test", 0);
    try testing.expectEqual(@as(usize, 7), twofas_entries.len);
    try testing.expectEqual(@as(usize, 7), andotp_entries.len);
    try testing.expectEqual(@as(usize, 7), andotp_old_entries.len);
}

test "integration: bitwarden proton and ente imports work" {
    const testing = std.testing;
    const bitwarden_bytes = try readFixtureAlloc(testing.allocator, "testdata/bitwarden.json");
    defer testing.allocator.free(bitwarden_bytes);
    const proton_bytes = try readFixtureAlloc(testing.allocator, "testdata/proton_authenticator.json");
    defer testing.allocator.free(proton_bytes);
    const ente_bytes = try readFixtureAlloc(testing.allocator, "testdata/ente_auth.txt");
    defer testing.allocator.free(ente_bytes);

    const bitwarden_entries = try importers.third_party.bitwarden(testing.allocator, bitwarden_bytes, 0);
    const proton_entries = try importers.third_party.proton_authenticator(testing.allocator, proton_bytes, 0);
    const ente_entries = try importers.third_party.ente_auth(testing.allocator, ente_bytes, 0);
    try testing.expectEqual(@as(usize, 4), bitwarden_entries.len);
    try testing.expect(bitwarden_entries[3].isReadonly());
    try testing.expectEqual(@as(usize, 3), proton_entries.len);
    try testing.expectEqual(@as(usize, 3), ente_entries.len);
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

test "integration: json export can be written through ztmpfile and re-imported" {
    const testing = std.testing;
    const entries = [_]model.Entry{
        .{
            .id = "demo",
            .issuer = "GitHub",
            .account_name = "alice@example.com",
            .secret = "JBSWY3DPEHPK3PXP",
            .created_at = 0,
            .updated_at = 0,
        },
    };

    const exported = try exporters.json(testing.allocator, &entries, 1_700_000_000);
    defer testing.allocator.free(exported);

    var tmp = try ztmpfile.tempfile(testing.allocator);
    defer tmp.deinit();
    var write_buffer: [256]u8 = undefined;
    var writer = tmp.file().writer(std.Io.Threaded.init_single_threaded, &write_buffer);
    try writer.interface.writeAll(exported);
    try writer.interface.flush();

    var reopened = try tmp.reopen();
    defer reopened.close(std.Io.Threaded.init_single_threaded);
    const bytes = try reopened.readToEndAlloc(testing.allocator, 4096);
    defer testing.allocator.free(bytes);

    const imported = try importers.json(testing.allocator, bytes);
    try testing.expectEqual(@as(usize, 1), imported.len);
    try expectHasEntry(imported, "GitHub", "alice@example.com");
}
