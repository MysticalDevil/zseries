# zseries

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE) ![Zig](https://img.shields.io/badge/Zig-0.16.0_dev-F7A41D?logo=zig&logoColor=white)

A Zig workspace for applications and reusable libraries.

## Projects

| Project | Type | Description |
| ------- | ---- | ----------- |
| [ztotp](ztotp/) | Application | Local-first encrypted TOTP CLI with TUI dashboard |
| [zcli](zcli/) | Library | CLI styling and help-formatting primitives |
| [ztui](ztui/) | Library | TUI buffer, terminal, and widget primitives |
| [zlog](zlog/) | Library | Structured logging with levels and multiple sinks |
| [ztmpfile](ztmpfile/) | Library | Cross-platform temp file/dir with C ABI support |

## Quick Links

- [ztotp Documentation](ztotp/README.md) — Main application
- [Workspace Commands](#workspace-commands)

## Workspace Commands

```bash
just list-projects   # List all projects
just check          # Run Markdown checks + build/test all projects
just fmt            # Format Markdown and Zig source
just clean          # Remove build caches and artifacts
```

## License

MIT. See [LICENSE](LICENSE).