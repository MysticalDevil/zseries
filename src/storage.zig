const std = @import("std");
const model = @import("model.zig");

const Aead = std.crypto.aead.chacha_poly.XChaCha20Poly1305;
const argon2 = std.crypto.pwhash.argon2;

const magic = "ZTOTP01";
const current_version: u8 = 1;
const salt_len = 16;

pub const VaultHeader = struct {
    version: u8,
    mem_kib: u32,
    iterations: u32,
    lanes: u24,
    salt: [salt_len]u8,
    nonce: [Aead.nonce_length]u8,
    ciphertext_len: u64,
};

pub const LoadedVault = struct {
    payload: model.VaultPayload,
    arena: std.heap.ArenaAllocator,

    pub fn deinit(self: *LoadedVault) void {
        self.arena.deinit();
    }
};

fn headerSize() usize {
    return magic.len + 1 + 4 + 4 + 3 + salt_len + Aead.nonce_length + 8;
}

fn deriveKey(allocator: std.mem.Allocator, password: []const u8, salt: [salt_len]u8, io: std.Io) ![Aead.key_length]u8 {
    var key: [Aead.key_length]u8 = undefined;
    try argon2.kdf(
        allocator,
        &key,
        password,
        &salt,
        .{ .m = 64 * 1024, .t = 3, .p = 1 },
        .argon2id,
        io,
    );
    return key;
}

fn payloadToJson(allocator: std.mem.Allocator, payload: model.VaultPayload) ![]u8 {
    return std.fmt.allocPrint(allocator, "{f}", .{std.json.fmt(payload, .{})});
}

fn parsePayload(allocator: std.mem.Allocator, bytes: []const u8) !model.VaultPayload {
    return try std.json.parseFromSliceLeaky(model.VaultPayload, allocator, bytes, .{ .allocate = .alloc_always });
}

fn writeHeader(buffer: []u8, header: VaultHeader) void {
    @memcpy(buffer[0..magic.len], magic);
    buffer[magic.len] = header.version;
    std.mem.writeInt(u32, buffer[8..12], header.mem_kib, .little);
    std.mem.writeInt(u32, buffer[12..16], header.iterations, .little);
    std.mem.writeInt(u24, buffer[16..19], header.lanes, .little);
    @memcpy(buffer[19..35], &header.salt);
    @memcpy(buffer[35 .. 35 + Aead.nonce_length], &header.nonce);
    std.mem.writeInt(u64, buffer[59..67], header.ciphertext_len, .little);
}

fn readHeader(buffer: []const u8) !VaultHeader {
    if (buffer.len < headerSize()) return error.InvalidVault;
    if (!std.mem.eql(u8, buffer[0..magic.len], magic)) return error.InvalidVault;
    const version = buffer[magic.len];
    if (version != current_version) return error.UnsupportedVaultVersion;

    var salt: [salt_len]u8 = undefined;
    @memcpy(&salt, buffer[19..35]);
    var nonce: [Aead.nonce_length]u8 = undefined;
    @memcpy(&nonce, buffer[35 .. 35 + Aead.nonce_length]);

    return .{
        .version = version,
        .mem_kib = std.mem.readInt(u32, buffer[8..12], .little),
        .iterations = std.mem.readInt(u32, buffer[12..16], .little),
        .lanes = std.mem.readInt(u24, buffer[16..19], .little),
        .salt = salt,
        .nonce = nonce,
        .ciphertext_len = std.mem.readInt(u64, buffer[59..67], .little),
    };
}

fn vaultPathAlloc(allocator: std.mem.Allocator, data_dir: []const u8) ![]u8 {
    return std.fs.path.join(allocator, &.{ data_dir, "ztotp", "vault.bin" });
}

pub fn ensureVaultDir(allocator: std.mem.Allocator, io: std.Io, data_dir: []const u8) ![]u8 {
    const path = try vaultPathAlloc(allocator, data_dir);
    errdefer allocator.free(path);
    const dir_path = std.fs.path.dirname(path) orelse return error.InvalidPath;
    try std.Io.Dir.cwd().createDirPath(io, dir_path);
    return path;
}

pub fn saveVault(allocator: std.mem.Allocator, io: std.Io, data_dir: []const u8, password: []const u8, payload: model.VaultPayload) ![]u8 {
    const path = try ensureVaultDir(allocator, io, data_dir);
    errdefer allocator.free(path);

    const plaintext = try payloadToJson(allocator, payload);
    defer allocator.free(plaintext);

    var salt: [salt_len]u8 = undefined;
    io.random(&salt);
    var nonce: [Aead.nonce_length]u8 = undefined;
    io.random(&nonce);

    const key = try deriveKey(allocator, password, salt, io);
    const ciphertext = try allocator.alloc(u8, plaintext.len);
    defer allocator.free(ciphertext);
    var tag: [Aead.tag_length]u8 = undefined;
    Aead.encrypt(ciphertext, &tag, plaintext, "", nonce, key);

    const header = VaultHeader{
        .version = current_version,
        .mem_kib = 64 * 1024,
        .iterations = 3,
        .lanes = 1,
        .salt = salt,
        .nonce = nonce,
        .ciphertext_len = ciphertext.len + tag.len,
    };

    const bytes = try allocator.alloc(u8, headerSize() + ciphertext.len + tag.len);
    defer allocator.free(bytes);
    writeHeader(bytes[0..headerSize()], header);
    @memcpy(bytes[headerSize() .. headerSize() + ciphertext.len], ciphertext);
    @memcpy(bytes[headerSize() + ciphertext.len ..], &tag);

    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = bytes });
    return path;
}

pub fn loadVault(allocator: std.mem.Allocator, io: std.Io, data_dir: []const u8, password: []const u8) !LoadedVault {
    const path = try vaultPathAlloc(allocator, data_dir);
    defer allocator.free(path);
    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(std.math.maxInt(usize)));
    defer allocator.free(bytes);

    const header = try readHeader(bytes[0..headerSize()]);
    const cipher_and_tag = bytes[headerSize()..];
    if (cipher_and_tag.len != header.ciphertext_len) return error.InvalidVault;
    if (cipher_and_tag.len < Aead.tag_length) return error.InvalidVault;

    const ciphertext = cipher_and_tag[0 .. cipher_and_tag.len - Aead.tag_length];
    var tag: [Aead.tag_length]u8 = undefined;
    @memcpy(&tag, cipher_and_tag[ciphertext.len..]);

    const key = try deriveKey(allocator, password, header.salt, io);
    const plaintext = try allocator.alloc(u8, ciphertext.len);
    defer allocator.free(plaintext);
    try Aead.decrypt(plaintext, ciphertext, tag, "", header.nonce, key);

    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();
    const payload = try parsePayload(arena.allocator(), plaintext);
    return .{ .payload = payload, .arena = arena };
}

pub fn vaultExists(allocator: std.mem.Allocator, io: std.Io, data_dir: []const u8) !bool {
    const path = try vaultPathAlloc(allocator, data_dir);
    defer allocator.free(path);
    std.Io.Dir.cwd().access(io, path, .{}) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    return true;
}
