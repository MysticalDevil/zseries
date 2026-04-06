# zlint

A Zig project linter for enforcing code quality rules.

## Features

- **Compile-first approach**: Runs `zig build` before linting
- **DOM-style AST analysis**: Uses `std.zig.Ast` for structured analysis
- **Configurable rules**: Via `zlint.toml`
- **Colorful CLI output**: Using zcli for styled output
- **Exit codes**: Following PLAN.md specification

## Rules

### discarded-result
Detects `_ = xxx;` patterns for discarded values.

### max-anytype-params
Limits the number of `anytype` parameters in functions (default: 2).

### no-do-not-optimize-away
Forbids calls to `std.mem.doNotOptimizeAway`.

## Usage

```bash
zlint [options]

Options:
  -f, --format <FORMAT>   Output format: text or json (default: text)
  -c, --config <PATH>     Config file path (default: zlint.toml)
  -r, --root <PATH>       Project root path (default: .)
      --no-compile-check  Skip compile check
  -q, --quiet             Suppress output
  -h, --help              Show this help
```

## Exit Codes

- `0`: No diagnostics or only warnings
- `1`: At least one error
- `2`: Compile check failed
- `3`: Config or CLI error

## Configuration

Create `zlint.toml`:

```toml
version = 1

[scan]
include = ["."]
exclude = [".git", "zig-cache", ".zig-cache", "zig-out"]

[output]
format = "text"

[rules.discarded-result]
enabled = true
severity = "error"
strict = true
allow_names = ["deinit", "free"]

[rules.max-anytype-params]
enabled = true
severity = "error"
max = 2

[rules.no-do-not-optimize-away]
enabled = true
severity = "error"
```

## Ignore Directives

Line-level ignore:
```zig
_ = foo(); // zlint:ignore discarded-result
```

File-level ignore:
```zig
// zlint:file-ignore max-anytype-params
```

## Build

```bash
zig build
zig build test
zig build install
```

## Architecture

- `main.zig`: Entry point with `std.process.Init`
- `cli.zig`: CLI argument parsing with zcli
- `config.zig`: Configuration loading
- `compile_check.zig`: Pre-lint compile verification
- `fs_walk.zig`: File discovery
- `source_file.zig`: Source file + AST management
- `ignore_directives.zig`: Ignore comment parsing
- `diagnostic.zig`: Diagnostic types
- `reporter/`: Output formatters
- `rules/`: Lint rules
- `ast/`: AST helper functions

## Dependencies

- `ztoml`: TOML parsing (monorepo local)
- `zcli`: CLI styling (monorepo local)

## License

MIT
