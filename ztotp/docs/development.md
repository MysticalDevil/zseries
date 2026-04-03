# Development

This guide explains how the project is laid out and how to work on it safely.

## Table of Contents

- [Build and Test](#build-and-test)
- [Code Layout](#code-layout)
- [Help System](#help-system)
- [Import and Export Flow](#import-and-export-flow)
- [Third-Party Format Modules](#third-party-format-modules)
- [Fixtures and Tests](#fixtures-and-tests)
- [Adding a New Format](#adding-a-new-format)

## Build and Test

Build the project:

```bash
zig build
```

Run the test suite:

```bash
zig build test
```

Smoke-check help output:

```bash
zig build run -- help
zig build run -- help import
zig build run -- add --help
```

Run a quick local smoke flow with built-in test entries:

```bash
./scripts/smoke.sh
./scripts/smoke.sh --keep
./scripts/smoke.sh --tui
```

## Code Layout

Core modules:

- `src/main.zig`: process entry point
- `src/cli.zig`: command dispatch and top-level CLI flow
- `src/model.zig`: core data structures
- `src/totp.zig`: TOTP generation logic
- `src/storage.zig`: encrypted vault loading and saving
- `src/base32.zig`: Base32 encoding and decoding

CLI help modules:

- `src/cli/help.zig`: help text rendering and layout
- `src/cli/color.zig`: ANSI style abstraction for help output

Data movement modules:

- `src/importers.zig`: import entry points and format-specific adapters
- `src/exporters.zig`: export entry points and format-specific adapters

Third-party modules:

- `src/thirdparty/shared.zig`: crypto and encoding helpers shared by external formats
- `src/thirdparty/aegis.zig`: Aegis import/export support
- `src/thirdparty/authy.zig`: Authy-compatible backup support

## Help System

The help system is intentionally separated from business logic.

Why:

- command routing stays small
- help rendering can be tested independently
- color decisions stay isolated in one module

Key entry points:

- `help.renderHelpAlloc(...)`
- `color.writeStyled(...)`

## Import and Export Flow

Import path:

1. `cli.zig` validates arguments
2. `importers.zig` selects the format entry point
3. `src/thirdparty/*` handles external formats when needed
4. imported `model.Entry` values are appended to the local vault

Export path:

1. `cli.zig` loads the current vault
2. `exporters.zig` selects the target format
3. `src/thirdparty/*` renders external backup formats when needed

## Third-Party Format Modules

The `thirdparty/` directory exists to keep external format compatibility isolated.

Current rules:

- shared helpers live in `shared.zig`
- format-specific parsing and rendering live in their own module
- `importers.zig` and `exporters.zig` provide the stable internal dispatch points

This keeps future additions like `2fas`, `andotp`, or other backup
formats from bloating core CLI logic.

## Fixtures and Tests

Public migration fixtures live in `testdata/` and are tracked in git.

Current public samples include:

- Aegis plain and encrypted JSON
- Authy XML samples
- otpauth plain text samples

Test layers:

- unit tests in feature modules
- format compatibility tests in importer/exporter modules
- cross-module integration coverage in `src/integration_test.zig`

## Adding a New Format

Recommended process:

1. Put shared logic in `src/thirdparty/shared.zig` only if it is actually reusable.
2. Add a new format module under `src/thirdparty/`.
3. Wire import entry points through `src/importers.zig`.
4. Wire export entry points through `src/exporters.zig`.
5. Add public fixture-driven tests if a redistributable sample exists.
6. Add at least one integration path when the format is part of normal
   migration workflows.
7. Update `README.md` and `docs/formats.md`.
