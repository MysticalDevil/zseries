# zseries

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE) ![Zig](https://img.shields.io/badge/Zig-0.16.0_dev-F7A41D?logo=zig&logoColor=white)

A Zig workspace for applications, reusable libraries, and terminal tooling.

## Features

- **ztotp** — Local-first encrypted TOTP authenticator with import/export support
- **Modular Libraries** — Reusable CLI, TUI, logging, and tempfile primitives
- **Terminal-First** — All tools designed for efficient keyboard-driven workflows
- **Cross-Platform** — Linux, macOS, Windows, and WASI support

## Projects

| Project | Type | Description | Status |
| ------- | ---- | ----------- | ------ |
| [ztotp](ztotp/) | Application | Local-first encrypted TOTP CLI with TUI dashboard | Active |
| [zcli](zcli/) | Library | Shared CLI styling and help-formatting primitives | Stable |
| [ztui](ztui/) | Library | Shared TUI buffer, terminal, and widget primitives | Stable |
| [zlog](zlog/) | Library | Structured logging with levels and multiple sinks | Stable |
| [ztmpfile](ztmpfile/) | Library | Cross-platform temp file/dir with C ABI support | Stable |

## Quick Start

### Prerequisites

- [Zig](https://ziglang.org/) 0.16.0-dev or later
- [just](https://github.com/casey/just) (optional, for workspace commands)

### Build ztotp (Main Application)

```bash
cd ztotp
zig build

# Run tests
zig build test

# Quick smoke test
./scripts/smoke.sh
```

### Using ztotp

```bash
# Initialize vault
./zig-out/bin/ztotp init

# Add a TOTP entry
./zig-out/bin/ztotp add --issuer GitHub --account alice@example.com --secret JBSWY3DPEHPK3PXP

# Show current code
./zig-out/bin/ztotp code GitHub

# Launch TUI dashboard
./zig-out/bin/ztotp tui
```

## Workspace Commands

The root `justfile` provides common workspace tasks:

```bash
just list-projects   # List all projects
just check          # Run Markdown checks + build/test all projects
just fmt            # Format Markdown and Zig source
just clean          # Remove build caches and artifacts
just smoke          # Run ztotp smoke tests
```

## Build Individual Projects

```bash
cd zcli && zig build test    # CLI library
cd ztui && zig build test    # TUI library
cd zlog && zig build test    # Logging library
cd ztmpfile && zig build test  # Temp file library
cd ztotp && zig build run    # TOTP application
```

## Project Layout

Each child project keeps its own build metadata and source tree:

```text
project/
├── build.zig
├── build.zig.zon
├── src/
└── README.md
```

Shared workspace files at the root:

- `README.md` — This file
- `LICENSE` — MIT license
- `.gitignore` — Recursive ignore rules
- `justfile` — Workspace automation

## Shared Workspace Files

These files are intentionally shared at the workspace root:

- `README.md`: top-level workspace overview
- `LICENSE`: workspace-level MIT license
- `.gitignore`: recursive ignore rules for all child projects
- `.rumdl.toml`: shared Markdown lint configuration

## License

MIT. See [LICENSE](LICENSE).
