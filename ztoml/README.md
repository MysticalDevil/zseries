# ztoml

`ztoml` is a TOML parser for Zig with a DOM-style `Value` API.

## Current Status

- Maintained inside the `zseries` monorepo
- Has a `build.zig.zon`, so monorepo-local path dependencies are straightforward
- Positioned as a parser + value tree, not as a schema/serde framework

## Build And Test

```bash
zig build
zig build test
```

## Basic Usage

```zig
const std = @import("std");
const ztoml = @import("ztoml");

const source =
    \\[server]
    \\host = "localhost"
    \\port = 8080
;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    var value = try ztoml.parseString(allocator, source);
    defer value.deinit(allocator);

    const server = value.get("server").?;
    const host = server.get("host").?.getString();
    const port = server.get("port").?.getInteger();

    _ = host;
    _ = port;
}
```

## Public Surface

- `parse` / `parseFile`: parse TOML into a `Value` tree
- `tokenize`, `Lexer`, `Token`, `TokenType`: lexer-level interfaces
- `Value`: DOM value type for strings, numbers, booleans, arrays, tables, and
  datetime values
- `Error`, `ErrorSet`, `makeError`, `makeParseError`: parse and reporting
  helpers

## Module Map

- `src/lexer.zig`: tokenization and low-level TOML lexing
- `src/parser.zig`: TOML parsing into the DOM tree
- `src/value.zig`: the `Value` representation and access helpers
- `src/error.zig`: structured parse errors and formatting helpers
- `src/root.zig`: public exports

## Consumption Notes

Inside this monorepo, depend on `ztoml` as a normal local package. For other
projects, vendor or path-depend on the package root rather than trying to fetch
the whole monorepo archive as a package.

## Scope And Limitations

- DOM-style API only; no derive/schema layer
- The main contract is parse + inspect + serialize
- Maintained against the Zig 0.16-era toolchain used by this workspace

## License

MIT
