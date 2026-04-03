# zseries

`zseries` is a Zig workspace containing multiple related projects.

## Projects

- `ztotp/`: local-first encrypted TOTP application
- `zcli/`: shared CLI styling and help-formatting primitives
- `ztui/`: shared TUI buffer, terminal, and widget primitives
- `ztmpfile/`: temporary file utility project

## Layout

Each child project keeps its own build metadata and source tree.

- `build.zig`
- `build.zig.zon`
- `src/`

The application-specific README for the TOTP tool remains in `ztotp/README.md`.

## Build

Build a child project from inside its directory. For example:

```bash
cd ztotp
zig build
zig build test
```
