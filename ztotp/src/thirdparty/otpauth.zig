const std = @import("std");
const model = @import("../model.zig");
const normalize = @import("normalize.zig");

pub const ParsedUri = struct {
    input: normalize.NormalizedInput,

    pub fn deinit(self: ParsedUri, allocator: std.mem.Allocator) void {
        allocator.free(self.input.account_name);
        allocator.free(self.input.secret);
        if (self.input.issuer) |issuer| allocator.free(issuer);
    }
};

fn decodeUriComponentAlloc(allocator: std.mem.Allocator, component: std.Uri.Component) ![]const u8 {
    return try component.toRawMaybeAlloc(allocator);
}

fn queryValue(query: []const u8, key: []const u8) ?[]const u8 {
    var iter = std.mem.splitScalar(u8, query, '&');
    while (iter.next()) |part| {
        var pair_iter = std.mem.splitScalar(u8, part, '=');
        const current_key = pair_iter.next() orelse continue;
        const current_value = pair_iter.next() orelse "";
        if (std.mem.eql(u8, current_key, key)) return current_value;
    }
    return null;
}

pub fn parseUri(allocator: std.mem.Allocator, line: []const u8) !ParsedUri {
    if (std.mem.startsWith(u8, line, "steam://")) {
        return .{ .input = .{
            .issuer = try allocator.dupe(u8, "Steam"),
            .account_name = try allocator.dupe(u8, "Steam account"),
            .secret = try allocator.dupe(u8, line[8..]),
            .kind = .steam,
            .digits = 5,
            .period = 30,
            .algorithm = .sha1,
        } };
    }

    const uri = try std.Uri.parse(line);
    if (!std.ascii.eqlIgnoreCase(uri.scheme, "otpauth")) return error.InvalidOtpAuth;
    const host = try uri.getHostAlloc(allocator);
    const raw_path = try decodeUriComponentAlloc(allocator, uri.path);
    defer allocator.free(raw_path);
    const label = std.mem.trim(u8, raw_path, "/");
    const query_component = uri.query orelse return error.MissingSecret;
    const query = try decodeUriComponentAlloc(allocator, query_component);
    defer allocator.free(query);
    const secret_value = queryValue(query, "secret") orelse return error.MissingSecret;
    var issuer = queryValue(query, "issuer") orelse "";
    var account = label;
    if (std.mem.indexOfScalar(u8, label, ':')) |idx| {
        issuer = std.mem.trim(u8, label[0..idx], " ");
        account = std.mem.trim(u8, label[idx + 1 ..], " ");
    }
    const kind = if (std.ascii.eqlIgnoreCase(host.bytes, "totp"))
        model.EntryKind.totp
    else if (std.ascii.eqlIgnoreCase(host.bytes, "hotp"))
        model.EntryKind.hotp
    else if (std.ascii.eqlIgnoreCase(host.bytes, "steam"))
        model.EntryKind.steam
    else
        model.EntryKind.unknown;

    return .{ .input = .{
        .issuer = try allocator.dupe(u8, issuer),
        .account_name = try allocator.dupe(u8, account),
        .secret = try allocator.dupe(u8, secret_value),
        .kind = kind,
        .digits = if (queryValue(query, "digits")) |value| try std.fmt.parseInt(u8, value, 10) else if (kind == .steam) 5 else 6,
        .period = if (queryValue(query, "period")) |value| try std.fmt.parseInt(u32, value, 10) else 30,
        .counter = if (queryValue(query, "counter")) |value| try std.fmt.parseInt(u64, value, 10) else null,
        .algorithm = if (queryValue(query, "algorithm")) |value| model.Algorithm.fromString(value) orelse .sha1 else .sha1,
    } };
}

test "parses hotp otpauth uri" {
    const testing = std.testing;
    const parsed = try parseUri(testing.allocator, "otpauth://hotp/Issuu:James?secret=YOOMIXWS5GN6RTBPUFFWKTW5M4&issuer=Issuu&algorithm=SHA1&digits=6&counter=1");
    defer parsed.deinit(testing.allocator);
    try testing.expectEqual(model.EntryKind.hotp, parsed.input.kind);
    try testing.expectEqual(@as(?u64, 1), parsed.input.counter);
}
