const std = @import("std");
const verifier_zig = @import("verifier.zig");
const Verifier = verifier_zig.Verifier;
const Claims = @import("claims.zig").Claims;

pub const AuthConfig = struct {
    header_name: []const u8 = "Authorization",
    strategy: Strategy = .strict,
    claims_callback: ?*const fn (*anyopaque, Claims) anyerror!void = null,
};

pub const Strategy = enum {
    strict,
    permissive,
};

/// Returns a zest-compatible `BeforeHook` for any `Context` type that provides
/// `header`, `status`, and `setHeader`.
pub fn auth(comptime Context: type, verifier: *Verifier, config: AuthConfig) *const fn (*Context) anyerror!void {
    const Closure = struct {
        var v: *Verifier = undefined;
        var c: AuthConfig = undefined;

        fn hook(ctx: *Context) !void {
            const raw = ctx.header(c.header_name) orelse {
                if (c.strategy == .strict) {
                    ctx.status(401);
                    try ctx.setHeader("WWW-Authenticate", "Bearer");
                    return error.Unauthorized;
                }
                return;
            };

            const token = stripBearer(raw) orelse raw;

            const verified = v.verify(token) catch |err| {
                if (c.strategy == .strict) {
                    ctx.status(401);
                    try ctx.setHeader("WWW-Authenticate", "Bearer");
                    return err;
                }
                return;
            };
            defer verified.deinit();

            if (c.claims_callback) |cb| {
                try cb(ctx, verified.claims);
            }
        }
    };

    Closure.v = verifier;
    Closure.c = config;
    return Closure.hook;
}

fn stripBearer(value: []const u8) ?[]const u8 {
    const prefix = "Bearer ";
    if (std.mem.startsWith(u8, value, prefix)) {
        return std.mem.trim(u8, value[prefix.len..], &std.ascii.whitespace);
    }
    return null;
}
