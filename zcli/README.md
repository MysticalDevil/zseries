# zcli

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](../LICENSE) ![Zig](https://img.shields.io/badge/Zig-0.16.0_dev-F7A41D?logo=zig&logoColor=white)

Shared CLI styling and help-formatting primitives for Zig projects.

## Features

- **ANSI Colors** — Terminal color and style helpers
- **Help Formatting** — Automatic `--help` generation from command definitions
- **Input Helpers** — Interactive prompts, password input, and selection menus
- **Argument Parsing** — Flag extraction, positional arguments, and subcommand routing
- **Table Output** — Structured table rendering for CLI output
- **Exit Codes** — Standardized exit codes and error formatting

## Usage

**Add dependency** (in `build.zig.zon`):

```zig
.dependencies = .{
    .zcli = .{
        .url = "https://github.com/MysticalDevil/zseries/archive/< commit-sha >.tar.gz",
        .hash = "< package-hash >",
    },
},
```

**Import in code**:

```zig
const zcli = @import("zcli");

// Use color styling
const color = zcli.color;
try color.writeStyled(writer, true, .title, "Hello");

// Parse arguments
const args = zcli.args;
if (args.hasFlag(cmd_args, "--verbose")) { ... }

// Interactive input
const input = zcli.input;
const password = try input.promptPassword(allocator, io, "Password: ");
```

## Build

```bash
zig build test
```

## Modules

| Module | Description |
| ------ | ----------- |
| `color` | ANSI color and style helpers |
| `helpfmt` | Help text formatting |
| `input` | Interactive prompts and selections |
| `args` | Argument parsing utilities |
| `table` | Table output helpers |
| `exit` | Exit codes and error formatting |
| `format` | JSON/YAML formatting helpers |
| `help` | Automatic `--help` generation |
| `pager` | Paginated output |

## License

MIT. See [LICENSE](../LICENSE).