const std = @import("std");
const Algorithm = @import("algorithm.zig").Algorithm;

pub const Key = union(enum) {
    hmac: []const u8,
    rsa_pem: []const u8,
    rsa_der: []const u8,
    ecdsa_pem: []const u8,
    ecdsa_der: []const u8,

    pub fn deinit(self: Key, allocator: std.mem.Allocator) void {
        switch (self) {
            inline else => |data| allocator.free(data),
        }
    }

    pub fn fromHmacSecret(secret: []const u8) Key {
        return .{ .hmac = secret };
    }

    pub fn fromFile(allocator: std.mem.Allocator, path: []const u8, format: KeyFormat) !Key {
        const data = try std.fs.cwd().readFileAlloc(allocator, path, 65536);
        errdefer allocator.free(data);

        return switch (format) {
            .hmac => .{ .hmac = data },
            .rsa_pem => .{ .rsa_pem = data },
            .rsa_der => .{ .rsa_der = data },
            .ecdsa_pem => .{ .ecdsa_pem = data },
            .ecdsa_der => .{ .ecdsa_der = data },
        };
    }

    pub fn generateHmacSecret(allocator: std.mem.Allocator, bits: usize) ![]const u8 {
        const bytes = bits / 8;
        const secret = try allocator.alloc(u8, bytes);
        errdefer allocator.free(secret);

        var csprng = std.crypto.random;
        csprng.bytes(secret);

        return secret;
    }
};

pub const KeyFormat = enum {
    hmac,
    rsa_pem,
    rsa_der,
    ecdsa_pem,
    ecdsa_der,
};

pub const KeyPair = struct {
    private: Key,
    public: Key,

    pub fn deinit(self: KeyPair, allocator: std.mem.Allocator) void {
        self.private.deinit(allocator);
        self.public.deinit(allocator);
    }
};

const testing = std.testing;

test "key from hmac secret" {
    const secret = "my-secret-key";
    const key = Key.fromHmacSecret(secret);

    try testing.expectEqualStrings(secret, key.hmac);
}

test "generate hmac secret" {
    const secret = try Key.generateHmacSecret(testing.allocator, 256);
    defer testing.allocator.free(secret);

    try testing.expectEqual(@as(usize, 32), secret.len);
}
