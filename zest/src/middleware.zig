const std = @import("std");
const Context = @import("context.zig").Context;

pub const Handler = *const fn (*Context) anyerror!void;
pub const BeforeHook = *const fn (*Context) anyerror!void;
pub const AfterHook = *const fn (*Context) anyerror!void;

pub const Middleware = struct {
    before_hooks: std.ArrayList(BeforeHook),
    after_hooks: std.ArrayList(AfterHook),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Middleware {
        return .{
            .before_hooks = std.ArrayList(BeforeHook).init(allocator),
            .after_hooks = std.ArrayList(AfterHook).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Middleware) void {
        self.before_hooks.deinit();
        self.after_hooks.deinit();
    }

    pub fn before(self: *Middleware, hook: BeforeHook) !void {
        try self.before_hooks.append(hook);
    }

    pub fn after(self: *Middleware, hook: AfterHook) !void {
        try self.after_hooks.append(hook);
    }

    pub fn execute(self: *Middleware, ctx: *Context, handler: Handler) !void {
        for (self.before_hooks.items) |hook| {
            try hook(ctx);
        }

        try handler(ctx);

        for (self.after_hooks.items) |hook| {
            try hook(ctx);
        }
    }
};
