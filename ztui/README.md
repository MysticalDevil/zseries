# ztui

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](../LICENSE) ![Zig](https://img.shields.io/badge/Zig-0.16.0_dev-F7A41D?logo=zig&logoColor=white)

Shared TUI primitives for Zig terminal applications.

## Features

- **ANSI Styles** — Style identifiers and ANSI escape sequences
- **Terminal Control** — Alternate screen, cursor, and clear helpers
- **Raw Input** — Non-blocking keyboard event polling
- **Cell Buffer** — 2D cell buffer with Unicode support
- **Widgets** — Boxes, labels, progress bars, lists, spinners
- **Dashboard** — Card-based dashboard framework with search

## Usage

`ztui` currently lives inside the `zseries` monorepo. Zig package fetch expects the package root to contain `build.zig.zon`, so you cannot depend on the monorepo archive URL directly.

Vendor the `ztui/` directory into your project, then add the dependency in `build.zig.zon`:

```zig
.dependencies = .{
    .ztui = .{
        .path = "vendor/ztui",
    },
},
```

**Import in code**:

```zig
const ztui = @import("ztui");

// Enter alternate screen
const raw = try ztui.input.RawMode.enter();
defer raw.leave();
try ztui.terminal.enterScreen();
defer ztui.terminal.restoreScreen();

// Create buffer and draw
var buf = try ztui.buffer.Buffer.init(allocator, 80, 24);
defer buf.deinit();
ztui.widgets.boxSingle(&buf, .{ .x = 0, .y = 0, .width = 20, .height = 5 }, .heading);
```

## Build

```bash
zig build test
```

## Core Modules

| Module | Description |
| ------ | ----------- |
| `style` | Style identifiers (title, heading, code, muted, etc.) |
| `buffer` | 2D cell buffer with Unicode rendering |
| `terminal` | Alternate screen and cursor control |
| `input` | Raw keyboard event polling |

## Widget Modules

| Module | Description |
| ------ | ----------- |
| `widgets.core` | Box, label, and progress bar primitives |
| `widgets.dashboard` | Card-based dashboard with sections |
| `widgets.list` | Selectable list component |
| `widgets.spinner` | Loading animation |
| `widgets.status` | Status bar component |

## License

MIT. See [LICENSE](../LICENSE).
