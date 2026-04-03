const std = @import("std");

pub fn dup(allocator: std.mem.Allocator, value: []const u8) ![]const u8 {
    return try allocator.dupe(u8, value);
}

pub fn hexEncodeAlloc(allocator: std.mem.Allocator, bytes: []const u8) ![]u8 {
    const out = try allocator.alloc(u8, bytes.len * 2);
    const alphabet = "0123456789abcdef";
    for (bytes, 0..) |byte, index| {
        out[index * 2] = alphabet[byte >> 4];
        out[index * 2 + 1] = alphabet[byte & 0x0f];
    }
    return out;
}

pub fn hexDecodeAlloc(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    if (text.len % 2 != 0) return error.InvalidHex;
    const out = try allocator.alloc(u8, text.len / 2);
    errdefer allocator.free(out);
    const written = try std.fmt.hexToBytes(out, text);
    if (written.len != out.len) return error.InvalidHex;
    return out;
}

pub fn base64EncodeAlloc(allocator: std.mem.Allocator, bytes: []const u8) ![]u8 {
    const encoder = std.base64.standard.Encoder;
    const out = try allocator.alloc(u8, encoder.calcSize(bytes.len));
    const written = encoder.encode(out, bytes);
    if (written.len != out.len) return error.InvalidBase64;
    return out;
}

pub fn base64DecodeAlloc(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    const decoder = std.base64.standard.Decoder;
    const size = try decoder.calcSizeForSlice(text);
    const out = try allocator.alloc(u8, size);
    errdefer allocator.free(out);
    try decoder.decode(out, text);
    return out;
}

pub fn randomHexAlloc(allocator: std.mem.Allocator, io: std.Io, len: usize) ![]u8 {
    const bytes = try allocator.alloc(u8, len);
    defer allocator.free(bytes);
    io.random(bytes);
    return hexEncodeAlloc(allocator, bytes);
}

pub fn uuidLikeAlloc(allocator: std.mem.Allocator, io: std.Io) ![]u8 {
    var bytes: [16]u8 = undefined;
    io.random(&bytes);
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    return std.fmt.allocPrint(
        allocator,
        "{s}-{s}-{s}-{s}-{s}",
        .{
            &std.fmt.bytesToHex(bytes[0..4], .lower),
            &std.fmt.bytesToHex(bytes[4..6], .lower),
            &std.fmt.bytesToHex(bytes[6..8], .lower),
            &std.fmt.bytesToHex(bytes[8..10], .lower),
            &std.fmt.bytesToHex(bytes[10..16], .lower),
        },
    );
}

pub fn pkcs7PadAlloc(allocator: std.mem.Allocator, bytes: []const u8, block_len: usize) ![]u8 {
    const padding = block_len - (bytes.len % block_len);
    const out = try allocator.alloc(u8, bytes.len + padding);
    @memcpy(out[0..bytes.len], bytes);
    @memset(out[bytes.len..], @intCast(padding));
    return out;
}

pub fn pkcs7Unpad(bytes: []u8, block_len: usize) ![]u8 {
    if (bytes.len == 0 or bytes.len % block_len != 0) return error.InvalidPadding;
    const padding = bytes[bytes.len - 1];
    if (padding == 0 or padding > block_len or padding > bytes.len) return error.InvalidPadding;
    const start = bytes.len - padding;
    for (bytes[start..]) |b| if (b != padding) return error.InvalidPadding;
    return bytes[0..start];
}

pub fn aes256CbcEncryptAlloc(allocator: std.mem.Allocator, plaintext: []const u8, key: [32]u8) ![]u8 {
    const padded = try pkcs7PadAlloc(allocator, plaintext, 16);
    errdefer allocator.free(padded);
    const out = try allocator.alloc(u8, padded.len);
    errdefer allocator.free(out);
    var prev = [_]u8{0} ** 16;
    var aes = std.crypto.core.aes.Aes256.initEnc(key);
    var offset: usize = 0;
    while (offset < padded.len) : (offset += 16) {
        var block: [16]u8 = undefined;
        var encrypted: [16]u8 = undefined;
        for (0..16) |i| block[i] = padded[offset + i] ^ prev[i];
        aes.encrypt(&encrypted, &block);
        @memcpy(out[offset .. offset + 16], &encrypted);
        prev = encrypted;
    }
    allocator.free(padded);
    return out;
}

pub fn aes256CbcDecryptAlloc(allocator: std.mem.Allocator, ciphertext: []const u8, key: [32]u8) ![]u8 {
    if (ciphertext.len == 0 or ciphertext.len % 16 != 0) return error.InvalidCiphertext;
    const out = try allocator.alloc(u8, ciphertext.len);
    errdefer allocator.free(out);
    var prev = [_]u8{0} ** 16;
    var aes = std.crypto.core.aes.Aes256.initDec(key);
    var offset: usize = 0;
    while (offset < ciphertext.len) : (offset += 16) {
        var cipher_block: [16]u8 = undefined;
        var block: [16]u8 = undefined;
        @memcpy(&cipher_block, ciphertext[offset .. offset + 16]);
        aes.decrypt(&block, &cipher_block);
        for (0..16) |i| out[offset + i] = block[i] ^ prev[i];
        prev = cipher_block;
    }
    const unpadded = try pkcs7Unpad(out, 16);
    const result = try allocator.dupe(u8, unpadded);
    allocator.free(out);
    return result;
}
