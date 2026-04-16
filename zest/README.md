# zest

`zest` is a small HTTP layer for Zig applications. It provides the pieces
needed to build request/response handlers, attach middleware, and listen on a
socket without pulling in a larger framework.

## Current Status

- Maintained inside the `zseries` monorepo
- Intended for local/monorepo consumption today
- Has a `build.zig.zon` for Zig package manager consumption

## Build And Test

```bash
zig build
zig build test
```

## Minimal Example

```zig
const std = @import("std");
const zest = @import("zest");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    var app = try zest.App.init(allocator, io);
    defer app.deinit();

    try app.get("/", indexHandler);
    try app.get("/health", healthHandler);

    const addr = std.Io.net.Ip4Address.loopback(8080);
    try app.listen(addr);
}

fn indexHandler(ctx: *zest.Context) !void {
    try ctx.jsonStatus(zest.Status.ok, .{ .message = "hello" });
}

fn healthHandler(ctx: *zest.Context) !void {
    try ctx.jsonStatus(zest.Status.ok, .{ .status = "ok" });
}
```

## Per-Route Middleware

```zig
const authHook = struct {
    fn h(ctx: *zest.Context) !void {
        if (ctx.header("Authorization") == null) {
            try ctx.jsonStatus(zest.Status.unauthorized, .{ .error = "missing auth" });
            return error.Unauthorized;
        }
    }
}.h;

_ = try app.get("/admin", adminHandler).before(authHook);
```

## Route Groups

```zig
var api = try app.group("/api");
defer api.deinit();

try api.before(authHook);
_ = try api.get("/users/:id", getUserHandler);
_ = try api.post("/users", createUserHandler);
```

## Error Recovery

If a handler panics or returns an error, `zest` automatically responds with
`500 Internal Server Error` and keeps the server running instead of crashing
the connection loop.

For a fuller example with hooks and logging, see
[`examples/basic.zig`](examples/basic.zig).

## Public Surface

- `App`: route registration, global hook registration, and server startup
- `Group`: prefix-based route grouping with group-level hooks
- `RouteBuilder`: fluent API for per-route `.before()` / `.after()` middleware
- `Route`: a registered route with method, path, handler, and hooks
- `Context`: request/response state passed into handlers
- `Server`: lower-level server primitive
- `Router` and `PathParams`: route matching and parameter extraction
- `Status`: HTTP status constants
- `middleware`, `Handler`, `BeforeHook`, `AfterHook`: hook and middleware types

## Notes For Maintainers

- `src/app.zig` owns the high-level application surface
- `src/context.zig` owns request parsing and response helpers
- `src/router.zig` owns route registration and path matching
- `src/server.zig` owns the listening/accept loop
- `src/middleware.zig` defines handler and hook contracts

`zest` currently documents the API through source and examples rather than a
stable external package contract. Keep README examples aligned with
[`src/root.zig`](src/root.zig) and the tests when changing exported names.

## License

MIT
