# ztmpfile

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](../LICENSE) ![Zig](https://img.shields.io/badge/Zig-0.16.0_dev-F7A41D?logo=zig&logoColor=white) ![C ABI](https://img.shields.io/badge/C_ABI-supported-9B59B6)

Cross-platform temp file/dir library with optional C ABI.

## Features

- **TempDir / NamedTempFile** — Lifecycle-managed temporary resources
- **Builder Pattern** — Configure prefix, suffix, directory, and randomness length
- **Cross-Platform** — Linux, macOS, Windows, and WASI backends
- **C ABI** — Optional `libztmpfile.a` and `ztmpfile.h`
- **Recursive Cleanup** — Directories cleaned on `deinit()`

## Usage

`ztmpfile` currently lives inside the `zseries` monorepo. Zig package fetch expects the package root to contain `build.zig.zon`, so you cannot depend on the monorepo archive URL directly.

Vendor the `ztmpfile/` directory into your project, then add the dependency in `build.zig.zon`:

```zig
.dependencies = .{
    .ztmpfile = .{
        .path = "vendor/ztmpfile",
    },
},
```

**Import in code**:

```zig
const std = @import("std");
const ztmpfile = @import("ztmpfile");

// Temporary directory
var dir = try ztmpfile.tempdir(allocator);
defer dir.deinit(); // Cleanup on scope exit

// Temporary file
var file = try ztmpfile.tempfile(allocator);
defer file.deinit();

const io = std.Io.Threaded.global_single_threaded.io();
var write_buffer: [256]u8 = undefined;
var writer = file.file().writer(io, &write_buffer);
try writer.interface.writeAll("hello\n");
try writer.interface.flush();

// Builder pattern
var builder = ztmpfile.Builder.init();
var dir2 = try builder
    .prefix("myapp_")
    .suffix("_tmp")
    .inDir("/var/tmp")
    .tempDir(allocator);
defer dir2.deinit();
```

## Build

```bash
zig build test
```

## C ABI

```bash
zig build                          # Build library and header
zig cc app.c zig-out/lib/libztmpfile.a -Izig-out/include -o app
```

## Test Commands

```bash
zig build test-unit        # Unit tests
zig build test-integration # Integration tests
zig build test-c           # C ABI tests
zig build test             # All tests
```

## License

MIT. See [LICENSE](../LICENSE).
