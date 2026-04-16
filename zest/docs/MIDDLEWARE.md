# zest Middleware Contract

This document defines the contract between `zest` and third-party middleware
libraries.  Following the contract lets any Zig package provide middleware
that works with `zest` **without adding a hard dependency on `zest` itself**.
The only requirement is the Zig standard library.

## 1. Hook Signature

`zest` recognises three hook shapes.  They are ordinary function pointers:

```zig
pub const Handler     = *const fn (*Context) anyerror!void;
pub const BeforeHook  = *const fn (*Context) anyerror!void;
pub const AfterHook   = *const fn (*Context) anyerror!void;
```

A middleware library only needs to export values that match `BeforeHook` or
`AfterHook`.  `Context` is supplied by the caller (the application) at
`comptime` through duck-typing, so your library never needs
`@import("zest")`.

## 2. Minimum Context Interface

A middleware hook receives a pointer to the request context.  The following
members are guaranteed to exist on `zest.Context` and are safe for middleware
to call.  All types come from the Zig standard library.

| Member | Zig type | Purpose |
|--------|----------|---------|
| `ctx.header(name)` | `fn([]const u8) ?[]const u8` | Case-insensitive request header lookup |
| `ctx.status(code)` | `fn(u16) void` | Set numeric HTTP status |
| `ctx.setHeader(name, value)` | `fn([]const u8, []const u8) !void` | Append response header |
| `ctx.set(key, ptr)` | `fn([]const u8, *anyopaque) !void` | Store pointer in request-local map |
| `ctx.get(key)` | `fn([]const u8) ?*anyopaque` | Retrieve pointer from request-local map |

If your middleware only reads request metadata it needs **only** `header`.
If it writes early responses (e.g. `401 Unauthorized`) it also needs
`status` and `setHeader`.  If it passes data to downstream handlers it uses
`set` / `get`.

### Optional helpers

`zest.Context` also provides response helpers (`text`, `json`, `html`,
`redirect`, etc.) and request helpers (`param`, `paramInt`, `bodyJson`).
You may call them from middleware, but they are **not** part of the minimal
stable contract because they are convenience methods built on top of the
members above.

## 3. Execution Order

For a matched route hooks execute in this order:

1. Global before hooks (`app.before(...)`)
2. Route before hooks (`app.get(...).before(...)`)
3. Handler
4. Route after hooks (`app.get(...).after(...)`)
5. Global after hooks (`app.after(...)`)

If any step returns an error the remaining steps are skipped and `zest`
responds with `500 Internal Server Error`.

## 4. Error Handling Semantics

- A `BeforeHook` may **abort the request** by returning an error.
- It may also **write a response early** (e.g. call `ctx.status(401)` and
  `ctx.setHeader(...)`) and then return an error to stop further processing.
- An `AfterHook` may return an error as well; this causes `500` to be sent
  unless the response was already written.

## 5. How to Pass State into a Hook

`BeforeHook` / `AfterHook` are plain function pointers, so they cannot
capture runtime values directly.  The recommended pattern for stateful
middleware is a `comptime` closure struct with static variables:

```zig
pub fn auth(comptime Context: type, verifier: *Verifier, config: Config) *const fn (*Context) anyerror!void {
    const Closure = struct {
        var v: *Verifier = undefined;
        var c: Config = undefined;

        fn hook(ctx: *Context) !void {
            const token = ctx.header(c.header_name) orelse {
                if (c.strategy == .strict) {
                    ctx.status(401);
                    try ctx.setHeader("WWW-Authenticate", "Bearer");
                    return error.Unauthorized;
                }
                return;
            };
            _ = try v.verify(token);
        }
    };
    Closure.v = verifier;
    Closure.c = config;
    return Closure.hook;
}
```

The caller (your application) simply passes `zest.Context` as the
`Context` argument:

```zig
const mymw = @import("mymiddleware");
const hook = mymw.auth(zest.Context, &verifier, .{});
try app.before(hook);
```

Because the static variables are written once during setup and then only
read during request handling, this pattern is safe for the typical web-server
lifetime where one middleware instance is registered exactly once.

## 6. Full Example: Request Timer Middleware

```zig
const std = @import("std");

pub const TimerMiddleware = struct {
    pub fn beforeHook(comptime Context: type) *const fn (*Context) anyerror!void {
        return struct {
            fn hook(ctx: *Context) !void {
                const now: i64 = std.time.milliTimestamp();
                const ptr: *anyopaque = @ptrFromInt(@as(usize, @intCast(now)));
                try ctx.set("timer_start", ptr);
            }
        }.hook;
    }

    pub fn afterHook(comptime Context: type) *const fn (*Context) anyerror!void {
        return struct {
            fn hook(ctx: *Context) !void {
                const start_ptr = ctx.get("timer_start") orelse return;
                const start: i64 = @intCast(@intFromPtr(start_ptr));
                const elapsed = std.time.milliTimestamp() - start;
                var buf: [64]u8 = undefined;
                const text = try std.fmt.bufPrint(&buf, "{d}ms", .{elapsed});
                try ctx.setHeader("X-Response-Time", text);
            }
        }.hook;
    }
};
```

Usage in a `zest` application:

```zig
const timer = @import("timer");
try app.before(timer.TimerMiddleware.beforeHook(zest.Context));
try app.after(timer.TimerMiddleware.afterHook(zest.Context));
```

## 7. Best Practices

1. **Do not `@import("zest")` inside reusable middleware libraries.** Use
   `comptime Context: type` and duck-typing instead.
2. **Return errors to abort.** If authentication fails, return an error after
   optionally writing the response status and headers.
3. **Use `ctx.set` / `ctx.get` for request-local state.** Avoid global
   variables that are not protected by the closure pattern.
4. **Keep hooks lightweight.** `before` hooks run on every request; defer
   heavy work to the handler when possible.
5. **Respect the response lifecycle.** In `after` hooks you can append
   headers, but mutating the body after the handler has finished may be
   ignored by the server.
