const std = @import("std");

pub const Algorithm = enum {
    sha1,
    sha256,
    sha512,

    pub fn fromString(value: []const u8) ?Algorithm {
        if (std.ascii.eqlIgnoreCase(value, "SHA1")) return .sha1;
        if (std.ascii.eqlIgnoreCase(value, "SHA256")) return .sha256;
        if (std.ascii.eqlIgnoreCase(value, "SHA512")) return .sha512;
        return null;
    }

    pub fn asString(self: Algorithm) []const u8 {
        return switch (self) {
            .sha1 => "SHA1",
            .sha256 => "SHA256",
            .sha512 => "SHA512",
        };
    }
};

pub const EntryKind = enum {
    totp,
    hotp,
    steam,
    unknown,

    pub fn fromString(value: []const u8) ?EntryKind {
        if (std.ascii.eqlIgnoreCase(value, "totp")) return .totp;
        if (std.ascii.eqlIgnoreCase(value, "hotp")) return .hotp;
        if (std.ascii.eqlIgnoreCase(value, "steam")) return .steam;
        if (std.ascii.eqlIgnoreCase(value, "unknown")) return .unknown;
        return null;
    }

    pub fn asString(self: EntryKind) []const u8 {
        return switch (self) {
            .totp => "totp",
            .hotp => "hotp",
            .steam => "steam",
            .unknown => "unknown",
        };
    }
};

pub const Entry = struct {
    id: []const u8,
    issuer: []const u8,
    account_name: []const u8,
    secret: []const u8,
    kind: EntryKind = .totp,
    digits: u8 = 6,
    period: u32 = 30,
    counter: ?u64 = null,
    algorithm: Algorithm = .sha1,
    tags: []const []const u8 = &.{},
    note: ?[]const u8 = null,
    readonly_reason: ?[]const u8 = null,
    source_format: ?[]const u8 = null,
    created_at: i64,
    updated_at: i64,

    pub fn isReadonly(self: Entry) bool {
        return self.readonly_reason != null;
    }
};

pub const VaultPayload = struct {
    version: u32 = 1,
    entries: []const Entry = &.{},
};

pub const ExportBundle = struct {
    version: u32 = 1,
    exported_at: i64,
    entries: []const Entry,
};
