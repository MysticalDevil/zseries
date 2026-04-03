# ztmpfile

`ztmpfile` is a Zig temp directory/file library with a Rust
`tempfile`-style API and optional C ABI.

## Features

- `TempDir` and `NamedTempFile` lifecycle APIs
- Builder-style configuration (`prefix`, `suffix`, `randLen`, `maxAttempts`, `inDir`)
- Cross-platform backend split:
  - `linux` and `darwin` separated, both reusing shared `posix_core`
  - dedicated `windows` backend
  - dedicated `wasi` backend
- Optional runtime smoke tests for Wine and WASM runners

## Zig Usage

```zig
const ztmpfile = @import("ztmpfile");

var dir = try ztmpfile.tempdir(std.heap.page_allocator);
defer dir.deinit();

var file = try ztmpfile.tempfile(std.heap.page_allocator);
defer file.deinit();
```

## C ABI

Header: `include/ztmpfile.h`  
Library: `libztmpfile.a`

### Build and Install

```bash
zig build
```

Artifacts are installed under `zig-out/`:

- `zig-out/lib/libztmpfile.a`
- `zig-out/include/ztmpfile.h`

### Link Example (C)

```bash
zig cc app.c zig-out/lib/libztmpfile.a -Izig-out/include -o app
```

### Memory Ownership

- Path outputs from C ABI are heap-owned `char*`.
- Always release with `ztmpfile_string_free`.

## Test Commands

```bash
zig build test-unit
zig build test-integration
zig build test-cross
zig build test-c
zig build test
```

Optional runtime smoke:

```bash
zig build test-wine
zig build test-wasm
zig build test-runtime
zig build test-all
```

- `test-wine` requires `wine`/`wine64`.
- `test-wasm` requires `wasmtime` or `wasmer`.
- If runner is unavailable, step prints `SKIP ...` and succeeds.

## License

MIT. See `LICENSE`.
