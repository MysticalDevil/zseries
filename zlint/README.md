# zlint

`zlint` is a Zig-focused linter for repository and package code quality checks.
It is built to run against real project trees, optionally gate on `zig build`,
and report diagnostics in either human-readable text or pure JSON.

## Current Status

- Maintained inside the `zseries` monorepo
- Usable as both a workspace lint tool and a standalone package
- Planning is tracked in [`docs/TODO.md`](docs/TODO.md)
- Rule catalog and numbering live in [`docs/RULES.md`](docs/RULES.md)
- Maintainer workflow notes live in [`docs/development.md`](docs/development.md)

## Build And Test

```bash
zig build
zig build test
```

To run the local executable:

```bash
zig build run -- --root ..
```

## Usage

```bash
zlint [options]

Options:
  -f, --format <FORMAT>   Output: text or json (default: text)
  -c, --config <PATH>     Config file path (default: zlint.toml)
  -r, --root <PATH>       Project root path (default: .)
      --no-compile-check  Skip the build gate
  -q, --quiet             Suppress text output
  -v, --verbose           Show verbose text-mode trace output
                          Repeat once (`-vv`) for AST traversal trace
  -h, --help              Show help
```

## Operational Model

- By default, `zlint` runs a compile gate before linting. Today that means
  `zig build` from the selected root unless `--no-compile-check` is passed.
- `text` mode is for humans.
- `json` mode is for tools and must stay pure JSON on both success and failure
  paths.
- `-v` and `-vv` only affect `text` mode. In `json` mode they are accepted but
  ignored.
- `-q` conflicts with any verbose level.

## Test Scanning Defaults

`scan.skip_tests = true` is the default. That means `zlint` skips common test
paths and test-oriented files unless configuration explicitly opts back in.

Typical skipped patterns include:

- `tests/`
- `test/`
- `__tests__/`
- `*_test.zig`
- `*.test.zig`
- `*.spec.zig`
- `test.zig`
- `tests.zig`

## Implemented Rules

`ZAIxxx` numbers are catalog identifiers only. Config and suppression comments
always use canonical `snake_case` rule IDs.

| Number | rule_id | Default | Severity |
| --- | --- | --- | --- |
| `ZAI001` | `discarded_result` | on | `error` |
| `ZAI002` | `max_anytype_params` | on | `error` |
| `ZAI003` | `no_silent_error_handling` | on | `warning` |
| `ZAI004` | `discard_assignment` | off | `warning` |
| `ZAI005` | `catch_unreachable` | on | `error` |
| `ZAI006` | `orelse_unreachable` | on | `error` |
| `ZAI007` | `unwrap_optional` | on | `warning` |
| `ZAI008` | `suspicious_cast_chain` | on | `warning` |
| `ZAI009` | `defer_return_invalid` | on | `error` |
| `ZAI010` | `unused_allocator` | on | `error` |
| `ZAI011` | `global_allocator_in_lib` | on | `error` |
| `ZAI012` | `no_do_not_optimize_away` | on | `error` |
| `ZAI013` | `duplicated_code` | on | `warning` |
| `ZAI014` | `no_anytype_io_params` | on | `error` |
| `ZAI015` | `no_anyerror_return` | on | `warning` |

See [`docs/RULES.md`](docs/RULES.md) for rule details, planned IDs, suppression
syntax, and per-rule configuration fields.

## Configuration

Example `zlint.toml`:

```toml
version = 1

[scan]
include = ["."]
exclude = [".git", "zig-cache", ".zig-cache", "zig-out"]
skip_tests = true

[output]
format = "text"

[rules.discarded_result]
enabled = true
severity = "error"
strict = true
allow_names = ["deinit", "free"]

[rules.max_anytype_params]
enabled = true
severity = "error"
max = 2

[rules.no_silent_error_handling]
enabled = true
severity = "warning"

[rules.no_do_not_optimize_away]
enabled = true
severity = "error"
```

## Suppression Syntax

Line-level:

```zig
const value = foo() catch return; // zlint:ignore no_silent_error_handling
```

File-level:

```zig
// zlint:file-ignore duplicated_code
```

## Architecture

- `src/main.zig`: CLI entrypoint and pipeline orchestration
- `src/cli.zig`: argument parsing and help output
- `src/config.zig`: config loading and validation
- `src/compile_check.zig`: pre-lint build gate
- `src/fs_walk.zig` and `src/source_file.zig`: file discovery and AST loading
- `src/ignore_directives.zig`: line/file suppression parsing
- `src/diagnostic.zig`: diagnostic model
- `src/reporter/`: text and JSON reporters
- `src/rules/`: rule implementations and traversal helpers

## License

MIT
