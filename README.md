# zseries

`zseries` is a Zig workspace for applications, reusable libraries, and terminal tooling.

## GitHub Description

Suggested repository description:

`A Zig workspace for applications, reusable libraries, and terminal tooling.`

## Projects

- `ztotp/`: local-first encrypted TOTP application
- `zcli/`: shared CLI styling and help-formatting primitives
- `ztui/`: shared TUI buffer, terminal, and widget primitives
- `zlog/`: reusable structured logging primitives
- `ztmpfile/`: temporary file utility project

## Shared Workspace Files

These files are intentionally shared at the workspace root:

- `README.md`: top-level workspace overview
- `LICENSE`: workspace-level MIT license
- `.gitignore`: recursive ignore rules for all child projects
- `.rumdl.toml`: shared Markdown lint configuration

## Layout

Each child project keeps its own build metadata and source tree.

- `build.zig`
- `build.zig.zon`
- `src/`

The application-specific README for the TOTP tool remains in `ztotp/README.md`.

Each child project may keep its own README and LICENSE when it is useful to
publish or consume that project independently.

## Build

Build a child project from inside its directory. For example:

```bash
cd ztotp
zig build
zig build test
```

Other projects:

```bash
cd zcli && zig build
cd ../ztui && zig build
cd ../zlog && zig build test
cd ../ztmpfile && zig build test
```

## Workspace Commands

The root `justfile` provides common workspace tasks:

```bash
just list-projects
just check
just fmt
just clean
just smoke
just smoke -- --keep
```

Task overview:

- `just check`: run shared Markdown checks plus child build/test commands
- `just fmt`: format shared Markdown and Zig source trees
- `just clean`: remove child build caches and smoke artifacts
- `just smoke`: run `ztotp/scripts/smoke.sh` from the workspace root

## License

MIT. See `LICENSE`.
