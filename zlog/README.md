# zlog

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](../LICENSE) ![Zig](https://img.shields.io/badge/Zig-0.16.0_dev-F7A41D?logo=zig&logoColor=white)

Structured logging with levels and multiple sinks for Zig projects.

## Features

- **Log Levels** — `trace`, `debug`, `info`, `warn`, `error`
- **Structured Fields** — `key=value` format with typed API
- **Multiple Sinks** — File, stdout, and stderr outputs
- **Environment Config** — `ZLOG_*` environment variables
- **Zero Allocations** — No runtime allocations in hot path

## Usage

`zlog` currently lives inside the `zseries` monorepo. Zig package fetch expects the package root to contain `build.zig.zon`, so you cannot depend on the monorepo archive URL directly.

Vendor the `zlog/` directory into your project, then add the dependency in `build.zig.zon`:

```zig
.dependencies = .{
    .zlog = .{
        .path = "vendor/zlog",
    },
},
```

**Import in code**:

```zig
const zlog = @import("zlog");

var logger = zlog.Logger.init(allocator, io, .info);
try logger.addFileSink("app.log");
try logger.addStdoutSink();

logger.log(.info, "request_started", &.{
    zlog.Field.string("method", "GET"),
    zlog.Field.string("path", "/api/users"),
    zlog.Field.uint("status", 200),
});
```

## Environment Variables

| Variable | Description |
| -------- | ----------- |
| `ZLOG_LEVEL` | Minimum log level (trace/debug/info/warn/error) |
| `ZLOG_FILE` | Log file path |
| `ZLOG_STDOUT` | Enable stdout sink (1/0) |
| `ZLOG_STDERR` | Enable stderr sink (1/0) |

## Build

```bash
zig build test
```

## API

```zig
const Logger = struct {
    pub fn init(allocator: Allocator, io: Io, level: Level) Logger;
    pub fn deinit(self: *Logger) void;

    pub fn addFileSink(self: *Logger, path: []const u8) !void;
    pub fn addStdoutSink(self: *Logger) !void;
    pub fn addStderrSink(self: *Logger) !void;

    pub fn log(self: *Logger, level: Level, message: []const u8, fields: []const Field) void;
};

const Field = struct {
    pub fn string(key: []const u8, value: []const u8) Field;
    pub fn int(key: []const u8, value: i64) Field;
    pub fn uint(key: []const u8, value: u64) Field;
    pub fn boolean(key: []const u8, value: bool) Field;
};
```

## License

MIT. See [LICENSE](../LICENSE).
