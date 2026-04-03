# zlog

`zlog` is a reusable logging package in the `zseries` workspace.

## Features

- log levels: `trace`, `debug`, `info`, `warn`, `error`
- structured `key=value` fields
- file, stdout, and stderr sinks
- environment-driven defaults via `ZLOG_*`
- explicit typed API without `anytype`

## Build

```bash
zig build
zig build test
```

## Environment

- `ZLOG_LEVEL`
- `ZLOG_FILE`
- `ZLOG_STDOUT`
- `ZLOG_STDERR`

## License

MIT. See `LICENSE`.
