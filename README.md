# zseries

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE) ![Zig](https://img.shields.io/badge/Zig-0.16.0_dev-F7A41D?logo=zig&logoColor=white)

A Zig workspace for applications and reusable libraries.

## Library Consumption

The reusable libraries in this repository currently live inside the `zseries` monorepo.

For third-party projects, vendor the library directory you want to consume and depend on it with a local `.path` entry such as `vendor/ztmpfile`. A monorepo archive URL does not work directly with Zig package fetch because the package root must contain `build.zig.zon`.

## Projects

| Project | Type | Description |
| ------- | ---- | ----------- |
| [zest](zest/) | Library | Lightweight HTTP primitives for apps, routing, and middleware |
| [zjwt](zjwt/) | Library | JWT encode/verify helpers, claims, keys, and middleware adapters |
| [zlint](zlint/) | Tool | Zig linter for repository and package quality rules |
| [zcors](zcors/) | Library | Standalone CORS middleware with comptime duck-typing hooks |
| [ztotp](ztotp/) | Application | Local-first encrypted TOTP CLI with TUI dashboard |
| [zcli](zcli/) | Library | CLI styling and help-formatting primitives |
| [ztui](ztui/) | Library | TUI buffer, terminal, and widget primitives |
| [zlog](zlog/) | Library | Structured logging with levels and multiple sinks |
| [ztmpfile](ztmpfile/) | Library | Cross-platform temp file/dir with C ABI support |
| [ztoml](ztoml/) | Library | TOML parsing library with DOM-style API |

### Examples

| Project | Stack | Description |
| ------- | ----- | ----------- |
| [memos](examples/memos/) | Zig + SQLite + Vite | Full-stack JWT auth, CRUD memos, CORS, request logging |

## Quick Links

- [zlint Documentation](zlint/README.md) - Linting tool and rule catalog entrypoint
- [zest Documentation](zest/README.md) - HTTP primitives and examples
- [zjwt Documentation](zjwt/README.md) - JWT library usage and middleware notes
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
