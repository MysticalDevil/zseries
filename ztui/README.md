# ztui

`ztui` provides shared terminal UI primitives for the `zseries`
workspace.

## Scope

- ANSI style mapping
- terminal screen enter/restore helpers
- raw input polling
- cell buffer rendering
- simple Unicode widgets such as boxes, labels, and progress bars

## Build

```bash
zig build
```

## Modules

- `src/style.zig`: style identifiers and ANSI mappings
- `src/terminal.zig`: alternate-screen and stdout helpers
- `src/input.zig`: raw keyboard input polling
- `src/buffer.zig`: cell buffer renderer
- `src/widgets.zig`: Unicode widget primitives

## License

MIT. See `LICENSE`.
