const std = @import("std");
const model = @import("../model.zig");
const shared = @import("shared.zig");

const Aead = std.crypto.aead.aes_gcm.Aes256Gcm;

const Vault = struct {
    version: u32,
    header: struct {
        slots: ?[]const Slot,
        params: ?struct { nonce: []const u8, tag: []const u8 },
    },
    db: std.json.Value,
};

const Slot = struct {
    type: u8,
    uuid: []const u8,
    key: []const u8,
    key_params: struct { nonce: []const u8, tag: []const u8 },
    n: ?u32 = null,
    r: ?u32 = null,
    p: ?u32 = null,
    salt: ?[]const u8 = null,
};

const Db = struct {
    version: u32,
    entries: []const Entry,
    groups: []const Group = &.{},
};

const Group = struct { uuid: []const u8, name: []const u8 };

const Entry = struct {
    type: []const u8,
    uuid: []const u8,
    name: []const u8,
    issuer: ?[]const u8 = null,
    note: ?[]const u8 = null,
    icon: ?[]const u8 = null,
    icon_mime: ?[]const u8 = null,
    icon_hash: ?[]const u8 = null,
    favorite: bool = false,
    info: Info,
    groups: []const []const u8 = &.{},
};

const Info = struct {
    secret: []const u8,
    algo: []const u8,
    digits: u8,
    period: ?u32 = null,
    counter: ?u64 = null,
};

fn parseTagsFromNoteAlloc(allocator: std.mem.Allocator, note: ?[]const u8) !struct { note: ?[]const u8, tags: []const []const u8 } {
    const value = note orelse return .{ .note = null, .tags = &.{} };
    if (!std.mem.startsWith(u8, value, "tags:")) {
        return .{ .note = try shared.dup(allocator, value), .tags = &.{} };
    }
    const newline = std.mem.indexOfScalar(u8, value, '\n');
    const tag_slice = if (newline) |idx| value[5..idx] else value[5..];
    var list = std.ArrayList([]const u8).empty;
    defer list.deinit(allocator);
    var it = std.mem.splitScalar(u8, tag_slice, ',');
    while (it.next()) |tag| {
        const trimmed = std.mem.trim(u8, tag, " ");
        if (trimmed.len == 0) continue;
        try list.append(allocator, try shared.dup(allocator, trimmed));
    }
    return .{
        .note = if (newline) |idx| try shared.dup(allocator, value[idx + 1 ..]) else null,
        .tags = try list.toOwnedSlice(allocator),
    };
}

fn entryNoteWithTagsAlloc(allocator: std.mem.Allocator, entry: model.Entry) !?[]const u8 {
    if (entry.tags.len == 0) return if (entry.note) |note| try shared.dup(allocator, note) else null;
    const tags = try std.mem.join(allocator, ",", entry.tags);
    defer allocator.free(tags);
    if (entry.note) |note| return try std.fmt.allocPrint(allocator, "tags:{s}\n{s}", .{ tags, note });
    return try std.fmt.allocPrint(allocator, "tags:{s}", .{tags});
}

fn entryToModel(allocator: std.mem.Allocator, entry: Entry, now: i64) !?model.Entry {
    if (!std.ascii.eqlIgnoreCase(entry.type, "totp")) return null;
    const parts = try parseTagsFromNoteAlloc(allocator, entry.note);
    return .{
        .id = try shared.dup(allocator, entry.uuid),
        .issuer = try shared.dup(allocator, entry.issuer orelse ""),
        .account_name = try shared.dup(allocator, entry.name),
        .secret = try shared.dup(allocator, entry.info.secret),
        .digits = entry.info.digits,
        .period = entry.info.period orelse 30,
        .algorithm = model.Algorithm.fromString(entry.info.algo) orelse return error.InvalidAlgorithm,
        .tags = parts.tags,
        .note = parts.note,
        .created_at = now,
        .updated_at = now,
    };
}

fn dbToModelEntries(allocator: std.mem.Allocator, db: Db, now: i64) ![]const model.Entry {
    var entries = std.ArrayList(model.Entry).empty;
    defer entries.deinit(allocator);
    for (db.entries) |entry| {
        const converted = try entryToModel(allocator, entry, now);
        if (converted) |value| try entries.append(allocator, value);
    }
    return entries.toOwnedSlice(allocator);
}

fn modelToEntry(allocator: std.mem.Allocator, io: std.Io, entry: model.Entry) !Entry {
    return .{
        .type = "totp",
        .uuid = try shared.uuidLikeAlloc(allocator, io),
        .name = try shared.dup(allocator, entry.account_name),
        .issuer = try shared.dup(allocator, entry.issuer),
        .note = try entryNoteWithTagsAlloc(allocator, entry),
        .info = .{
            .secret = try shared.dup(allocator, entry.secret),
            .algo = entry.algorithm.asString(),
            .digits = entry.digits,
            .period = entry.period,
        },
    };
}

fn derivePasswordKey(allocator: std.mem.Allocator, password: []const u8, salt: []const u8) ![32]u8 {
    var key: [32]u8 = undefined;
    try std.crypto.pwhash.scrypt.kdf(allocator, &key, password, salt, .{ .ln = 15, .r = 8, .p = 1 });
    return key;
}

fn decryptMasterKey(allocator: std.mem.Allocator, slot: Slot, password: []const u8) ![32]u8 {
    if (slot.type != 1 or slot.salt == null) return error.InvalidAegisVault;
    const wrapped = try shared.hexDecodeAlloc(allocator, slot.key);
    defer allocator.free(wrapped);
    const nonce_bytes = try shared.hexDecodeAlloc(allocator, slot.key_params.nonce);
    defer allocator.free(nonce_bytes);
    const tag_bytes = try shared.hexDecodeAlloc(allocator, slot.key_params.tag);
    defer allocator.free(tag_bytes);
    const salt_bytes = try shared.hexDecodeAlloc(allocator, slot.salt.?);
    defer allocator.free(salt_bytes);
    var nonce: [Aead.nonce_length]u8 = undefined;
    @memcpy(&nonce, nonce_bytes);
    var tag: [Aead.tag_length]u8 = undefined;
    @memcpy(&tag, tag_bytes);
    const wrapper_key = try derivePasswordKey(allocator, password, salt_bytes);
    var master_key: [32]u8 = undefined;
    try Aead.decrypt(&master_key, wrapped, tag, "", nonce, wrapper_key);
    return master_key;
}

pub fn importPlain(allocator: std.mem.Allocator, bytes: []const u8, now: i64) ![]const model.Entry {
    const vault = try std.json.parseFromSliceLeaky(Vault, allocator, bytes, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
    const db = switch (vault.db) {
        .object => try std.json.parseFromValueLeaky(Db, allocator, vault.db, .{ .ignore_unknown_fields = true }),
        else => return error.InvalidAegisVault,
    };
    return dbToModelEntries(allocator, db, now);
}

pub fn importEncrypted(allocator: std.mem.Allocator, bytes: []const u8, password: []const u8, now: i64) ![]const model.Entry {
    const vault = try std.json.parseFromSliceLeaky(Vault, allocator, bytes, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
    const slots = vault.header.slots orelse return error.InvalidAegisVault;
    const params = vault.header.params orelse return error.InvalidAegisVault;
    const master_key = try decryptMasterKey(allocator, slots[0], password);
    const db_b64 = switch (vault.db) {
        .string => |s| s,
        else => return error.InvalidAegisVault,
    };
    const ciphertext = try shared.base64DecodeAlloc(allocator, db_b64);
    defer allocator.free(ciphertext);
    const nonce_bytes = try shared.hexDecodeAlloc(allocator, params.nonce);
    defer allocator.free(nonce_bytes);
    const tag_bytes = try shared.hexDecodeAlloc(allocator, params.tag);
    defer allocator.free(tag_bytes);
    var nonce: [Aead.nonce_length]u8 = undefined;
    @memcpy(&nonce, nonce_bytes);
    var tag: [Aead.tag_length]u8 = undefined;
    @memcpy(&tag, tag_bytes);
    const plaintext = try allocator.alloc(u8, ciphertext.len);
    defer allocator.free(plaintext);
    try Aead.decrypt(plaintext, ciphertext, tag, "", nonce, master_key);
    const db = try std.json.parseFromSliceLeaky(Db, allocator, plaintext, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
    return dbToModelEntries(allocator, db, now);
}

pub fn exportPlain(allocator: std.mem.Allocator, io: std.Io, entries: []const model.Entry) ![]u8 {
    var aegis_entries = std.ArrayList(Entry).empty;
    defer aegis_entries.deinit(allocator);
    for (entries) |entry| try aegis_entries.append(allocator, try modelToEntry(allocator, io, entry));
    const db = Db{ .version = 3, .entries = try aegis_entries.toOwnedSlice(allocator) };
    return std.fmt.allocPrint(allocator, "{f}\n", .{std.json.fmt(struct {
        version: u32,
        header: struct {
            slots: ?[]const Slot,
            params: ?struct { nonce: []const u8, tag: []const u8 },
        },
        db: Db,
    }{ .version = 1, .header = .{ .slots = null, .params = null }, .db = db }, .{ .whitespace = .indent_2 })});
}

pub fn exportEncrypted(allocator: std.mem.Allocator, io: std.Io, entries: []const model.Entry, password: []const u8) ![]u8 {
    var master_key: [32]u8 = undefined;
    io.random(&master_key);
    var aegis_entries = std.ArrayList(Entry).empty;
    defer aegis_entries.deinit(allocator);
    for (entries) |entry| try aegis_entries.append(allocator, try modelToEntry(allocator, io, entry));
    const db_json = try std.fmt.allocPrint(allocator, "{f}", .{std.json.fmt(Db{ .version = 3, .entries = try aegis_entries.toOwnedSlice(allocator) }, .{})});
    defer allocator.free(db_json);

    var db_nonce: [Aead.nonce_length]u8 = undefined;
    io.random(&db_nonce);
    const db_ciphertext = try allocator.alloc(u8, db_json.len);
    defer allocator.free(db_ciphertext);
    var db_tag: [Aead.tag_length]u8 = undefined;
    Aead.encrypt(db_ciphertext, &db_tag, db_json, "", db_nonce, master_key);

    const salt_hex = try shared.randomHexAlloc(allocator, io, 32);
    const salt_bytes = try shared.hexDecodeAlloc(allocator, salt_hex);
    defer allocator.free(salt_bytes);
    const wrapper_key = try derivePasswordKey(allocator, password, salt_bytes);
    var slot_nonce: [Aead.nonce_length]u8 = undefined;
    io.random(&slot_nonce);
    var slot_tag: [Aead.tag_length]u8 = undefined;
    var wrapped: [32]u8 = undefined;
    Aead.encrypt(&wrapped, &slot_tag, &master_key, "", slot_nonce, wrapper_key);

    const slot = Slot{
        .type = 1,
        .uuid = try shared.uuidLikeAlloc(allocator, io),
        .key = try shared.hexEncodeAlloc(allocator, &wrapped),
        .key_params = .{ .nonce = try shared.hexEncodeAlloc(allocator, &slot_nonce), .tag = try shared.hexEncodeAlloc(allocator, &slot_tag) },
        .n = 32768,
        .r = 8,
        .p = 1,
        .salt = salt_hex,
    };

    return std.fmt.allocPrint(allocator, "{f}\n", .{std.json.fmt(struct {
        version: u32,
        header: struct {
            slots: []const Slot,
            params: struct { nonce: []const u8, tag: []const u8 },
        },
        db: []const u8,
    }{
        .version = 1,
        .header = .{ .slots = &.{slot}, .params = .{ .nonce = try shared.hexEncodeAlloc(allocator, &db_nonce), .tag = try shared.hexEncodeAlloc(allocator, &db_tag) } },
        .db = try shared.base64EncodeAlloc(allocator, db_ciphertext),
    }, .{ .whitespace = .indent_2 })});
}

fn readFixtureAlloc(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    return std.Io.Dir.cwd().readFileAlloc(std.Io.Threaded.init_single_threaded, path, allocator, .limited(std.math.maxInt(usize)));
}

test "imports public aegis plain sample" {
    const testing = std.testing;
    const bytes = try readFixtureAlloc(testing.allocator, "testdata/aegis_plain.json");
    defer testing.allocator.free(bytes);
    const entries = try importPlain(testing.allocator, bytes, 0);
    try testing.expectEqual(@as(usize, 3), entries.len);
    try testing.expectEqualStrings("Deno", entries[0].issuer);
    try testing.expectEqualStrings("Mason", entries[0].account_name);
}

test "aegis plain export roundtrip preserves totp entries" {
    const testing = std.testing;
    const bytes = try readFixtureAlloc(testing.allocator, "testdata/aegis_plain.json");
    defer testing.allocator.free(bytes);
    const entries = try importPlain(testing.allocator, bytes, 0);
    const exported = try exportPlain(testing.allocator, std.Io.Threaded.init_single_threaded, entries);
    defer testing.allocator.free(exported);
    const roundtrip = try importPlain(testing.allocator, exported, 0);
    try testing.expectEqual(@as(usize, entries.len), roundtrip.len);
}
