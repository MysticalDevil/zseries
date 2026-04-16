const std = @import("std");
const verifier_zig = @import("verifier.zig");
const claims = @import("claims.zig");
const Verifier = verifier_zig.Verifier;
const VerifiedToken = verifier_zig.VerifiedToken;
const Claims = claims.Claims;

pub const MiddlewareConfig = struct {
    token_source: TokenSource = .both,
    header_name: []const u8 = "Authorization",
    cookie_name: []const u8 = "access_token",
    strategy: Strategy = .strict,
    claims_callback: ?ClaimsCallback = null,
};

pub const TokenSource = enum {
    header,
    cookie,
    both,
};

pub const Strategy = enum {
    strict,
    permissive,
};

pub const ClaimsCallback = *const fn (*anyopaque, Claims) anyerror!void;

pub const JwtMiddleware = struct {
    verifier: *Verifier,
    config: MiddlewareConfig,

    pub fn createHook(self: *JwtMiddleware) zestBeforeHook {
        return .{
            .ptr = self,
            .call = hookImpl,
        };
    }

    fn hookImpl(ctx: *anyopaque) !void {
        const self = @as(*JwtMiddleware, @ptrCast(@alignCast(ctx)));

        const token_str = self.extractToken(ctx) orelse {
            if (self.config.strategy == .strict) {
                return error.Unauthorized;
            }
            return;
        };

        const verified = self.verifier.verify(token_str) catch |err| {
            if (self.config.strategy == .strict) {
                return err;
            }
            return;
        };
        defer verified.deinit();

        if (self.config.claims_callback) |callback| {
            try callback(ctx, verified.claims);
        }

        // If sliding expiration generated a new token, it could be set here
        // via ctx.setHeader("X-New-Token", new_token) if Context supports it
    }

    fn extractToken(self: *JwtMiddleware, ctx: *anyopaque) ?[]const u8 {
        // Implementation depends on zest Context structure
        // Would extract from header or cookie based on config.token_source
        // This is a stub that should be integrated with actual Context
        return extractFromHeader(ctx, self.config.header_name);
    }
};

pub const zestBeforeHook = struct {
    ptr: *anyopaque,
    call: *const fn (*anyopaque) anyerror!void,
};

// Helper function to create a zest-compatible before hook
pub fn createHook(verifier: *Verifier, config: MiddlewareConfig) zestBeforeHook {
    // Store both verifier and config
    // For now, we use verifier pointer to hold the data
    const v = @intFromPtr(verifier);
    const c = @intFromPtr(&config);
    const combined = v + c;
    const ptr = @as(*anyopaque, @ptrFromInt(combined));
    return .{
        .ptr = ptr,
        .call = genericHook,
    };
}

fn genericHook(ptr: *anyopaque) !void {
    const stored = @as(*MiddlewareConfig, @ptrCast(@alignCast(ptr)));
    // This is a stub - actual implementation needs zest Context integration
    // Would use stored.token_source, stored.strategy, etc.
    if (stored.strategy == .strict) {
        return error.NotImplemented;
    }
    return error.NotImplemented;
}

// Stub function for header extraction - would need actual Context implementation
fn extractFromHeader(ctx: *anyopaque, header_name: []const u8) ?[]const u8 {
    // Stub implementation
    // In real integration, this would call ctx.header(header_name)
    const context = @as(*anyopaque, @ptrCast(@alignCast(ctx)));
    const name = header_name;
    // Use both to avoid unused warnings
    if (@intFromPtr(context) == 0 and name.len == 0) {
        return null;
    }
    return null;
}
