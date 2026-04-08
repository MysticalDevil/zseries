# zjwt

`zjwt` provides JWT encoding, verification, claims handling, key helpers, and
middleware adapters for Zig services.

## Current Status

- Maintained inside the `zseries` monorepo
- Intended for local/monorepo consumption today
- No `build.zig.zon` yet, so external consumers should vendor or path-depend on
  the directory directly

## Build And Test

```bash
zig build
zig build test
```

## Minimal Encode / Verify Example

```zig
const std = @import("std");
const zjwt = @import("zjwt");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const secret = "my-super-secret-key";

    var claims = zjwt.Claims.init(allocator);
    defer claims.deinit();

    claims.sub = "user123";
    claims.iss = "example";
    claims.exp = std.time.timestamp() + 3600;

    var encoder = zjwt.Encoder.init(
        allocator,
        .HS256,
        zjwt.Key.fromHmacSecret(secret),
    );
    const token = try encoder.encode(claims);
    defer allocator.free(token);

    var verifier = zjwt.Verifier.init(
        allocator,
        .HS256,
        zjwt.Key.fromHmacSecret(secret),
        .{ .issuer = "example" },
    );

    var verified = try verifier.verify(token);
    defer verified.deinit();
}
```

## Public Surface

- `Algorithm`: JWT signing/verification algorithm enum
- `Claims` and `ValidateOptions`: registered and custom claim storage
- `Key`, `KeyFormat`, `KeyPair`: key material helpers
- `Encoder`: token creation
- `Verifier`, `VerifierOptions`, `VerifiedToken`: token verification and
  validation
- `Header`, `Token`, `Parts`: low-level token types
- `base64UrlEncode`, `base64UrlDecode`: token encoding helpers
- `middleware`, `MiddlewareConfig`, `TokenSource`, `Strategy`: HTTP middleware
  integration points

## Middleware Notes

The middleware layer is an adapter boundary. Keep request extraction and
framework-specific glue there rather than widening `Claims`, `Verifier`, or
`Encoder` APIs for transport concerns.

## Notes For Maintainers

- `src/claims.zig` owns claims storage and validation options
- `src/encoder.zig` and `src/verifier.zig` own core token flow
- `src/key.zig` owns key parsing/material abstractions
- `src/middleware.zig` owns integration hooks

When updating examples, prefer staying close to
[`tests/basic.zig`](tests/basic.zig), which already covers the supported happy
paths and common verification failures.

## License

MIT
