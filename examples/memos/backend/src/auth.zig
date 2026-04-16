const std = @import("std");
const zjwt = @import("zjwt");
const Db = @import("db.zig").Db;
const time = @import("time.zig");

pub const AuthState = struct {
    encoder: zjwt.Encoder,
    verifier: zjwt.Verifier,
    db: *Db,
    allocator: std.mem.Allocator,
    io: std.Io,

    pub fn init(allocator: std.mem.Allocator, db: *Db, io: std.Io) AuthState {
        const secret = "memos-example-secret-do-not-use-in-production";
        return .{
            .encoder = zjwt.Encoder.init(allocator, .HS256, zjwt.Key.fromHmacSecret(secret), io),
            .verifier = zjwt.Verifier.init(allocator, .HS256, zjwt.Key.fromHmacSecret(secret), .{}, io),
            .db = db,
            .allocator = allocator,
            .io = io,
        };
    }

    pub fn hashPassword(allocator: std.mem.Allocator, password: []const u8) ![]u8 {
        // NOTE: example-only, not production-grade password hashing
        var hash: [std.crypto.hash.blake2.Blake2b256.digest_length]u8 = undefined;
        std.crypto.hash.blake2.Blake2b256.hash(password, &hash, .{});
        return try std.fmt.allocPrint(allocator, "{x}", .{hash});
    }

    pub fn generateToken(self: *AuthState, username: []const u8, user_id: i64) ![]const u8 {
        var claims = zjwt.Claims.init(self.allocator);
        defer claims.deinit();
        claims.sub = try self.allocator.dupe(u8, username);
        claims.exp = @divTrunc(time.nowMillis(self.io), 1000) + 86400; // 1 day
        try claims.setInt("user_id", user_id);
        return try self.encoder.encode(claims);
    }

    pub fn authMiddleware(comptime Context: type, state: *AuthState) *const fn (*Context) anyerror!void {
        const Closure = struct {
            var v: *zjwt.Verifier = undefined;

            fn hook(ctx: *Context) !void {
                const raw = ctx.header("Authorization") orelse {
                    ctx.status(401);
                    try ctx.setHeader("WWW-Authenticate", "Bearer");
                    return error.Unauthorized;
                };
                const token = stripBearer(raw) orelse raw;
                var verified = v.verify(token) catch |err| {
                    ctx.status(401);
                    try ctx.setHeader("WWW-Authenticate", "Bearer");
                    return err;
                };
                defer verified.deinit();
                const user_id = verified.claims.getInt("user_id") orelse return error.Unauthorized;
                const uptr: *anyopaque = @ptrFromInt(@as(usize, @intCast(user_id)));
                try ctx.set("user_id", uptr);
            }
        };
        Closure.v = &state.verifier;
        return Closure.hook;
    }
};

fn stripBearer(value: []const u8) ?[]const u8 {
    const prefix = "Bearer ";
    if (std.mem.startsWith(u8, value, prefix)) {
        return std.mem.trim(u8, value[prefix.len..], &std.ascii.whitespace);
    }
    return null;
}
