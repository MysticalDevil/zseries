# ztotp

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![Zig](https://img.shields.io/badge/zig-0.16.0--dev-f7a41d)
![Local First](https://img.shields.io/badge/storage-local--first-2d9d78)
![TOTP](https://img.shields.io/badge/otp-TOTP-6f42c1)

`ztotp` is a local-first encrypted TOTP CLI implemented in Zig.

It is designed for users who want a small terminal-first authenticator
that can manage entries locally, migrate from other apps, and keep a
clear, auditable storage format.

## Table of Contents

- [Highlights](#highlights)
- [Build](#build)
- [Quick Start](#quick-start)
- [Command Cheat Sheet](#command-cheat-sheet)
- [Format Support](#format-support)
- [Security and Storage](#security-and-storage)
- [Documentation](#documentation)
- [Development](#development)
- [License](#license)

## Highlights

- Local-first encrypted vault stored under the XDG data directory
- TOTP entry management with `init`, `add`, `list`, `search`, `code`,
  `update`, and `remove`
- Import and export support for `otpauth`, `json`, `csv`, `aegis`,
  `aegis-encrypted`, and `authy`
- Hidden TTY password prompt with `--password` and `ZTOTP_PASSWORD` overrides
- Public fixture coverage for migration formats and cross-module integration tests

> `ztotp` only manages TOTP entries. Unsupported HOTP, Steam, and
> similar token types are skipped during import.

## Build

```bash
zig build
zig build test
```

## Quick Start

Initialize a vault:

```bash
ztotp init
```

Add an entry:

```bash
ztotp add \
  --issuer GitHub \
  --account alice@example.com \
  --secret JBSWY3DPEHPK3PXP \
  --tag work
```

List entries and fetch a code:

```bash
ztotp list
ztotp code GitHub
```

Import and export:

```bash
ztotp import --from aegis --file backup.json
ztotp export --to json --file backup.json
ztotp export --to aegis-encrypted --file aegis.json
```

## Command Cheat Sheet

| Command | Purpose | Example |
| --- | --- | --- |
| `init` | Create a new encrypted local vault | `ztotp init` |
| `add` | Add a TOTP entry | `ztotp add --issuer GitHub --account alice@example.com --secret ...` |
| `list` | List stored entries | `ztotp list` |
| `search` | Filter by issuer, account, or tag | `ztotp search --tag work` |
| `code` | Show the current code for one entry | `ztotp code GitHub` |
| `update` | Update one matching entry | `ztotp update --query GitHub --set-tags work,prod` |
| `remove` | Remove an entry by id | `ztotp remove --id entry-1700000000` |
| `import` | Import entries from another app or backup file | `ztotp import --from authy --file authy.json` |
| `export` | Export entries for backup or migration | `ztotp export --to csv --file export.csv` |

For richer command help:

```bash
ztotp help
ztotp help import
ztotp update --help
```

## Format Support

| Format | Import | Export | Encrypted | Notes |
| --- | --- | --- | --- | --- |
| `otpauth` | Yes | Yes | No | Imports the TOTP subset and skips unsupported token types |
| `json` | Yes | Yes | No | Best format for full `ztotp` backups |
| `csv` | Yes | Yes | No | Useful for inspection and bulk edits |
| `aegis` | Yes | Yes | No | Compatible with public Aegis plain backup format |
| `aegis-encrypted` | Yes | Yes | Yes | Uses the current vault password during import/export |
| `authy` | Yes | Yes | Yes | Compatible with `authy-export --save` style backup JSON |

More detail lives in [`docs/formats.md`](docs/formats.md) and
[`docs/migration.md`](docs/migration.md).

## Security and Storage

- Vault path: `$XDG_DATA_HOME/ztotp/vault.bin`
- Fallback path: `$HOME/.local/share/ztotp/vault.bin`
- Vault encryption: Argon2id-derived key + XChaCha20-Poly1305
- Password sources, in priority order:
  - `--password <value>`
  - `ZTOTP_PASSWORD`
  - hidden TTY prompt

Read the full model and caveats in [`docs/security.md`](docs/security.md).

## Documentation

- [`docs/usage.md`](docs/usage.md): day-to-day CLI usage
- [`docs/migration.md`](docs/migration.md): importing and exporting
  from other apps
- [`docs/security.md`](docs/security.md): storage, password handling,
  and operational notes
- [`docs/formats.md`](docs/formats.md): support matrix and format-specific behavior
- [`docs/development.md`](docs/development.md): code layout, tests, and extension notes

## Development

Key modules:

- `src/cli.zig`: command routing
- `src/cli/help.zig`: help rendering
- `src/cli/color.zig`: ANSI styling for CLI help output
- `src/importers.zig` and `src/exporters.zig`: internal import/export flows
- `src/thirdparty/`: shared helpers and external format support

Run the full test suite:

```bash
zig build test
```

See [`docs/development.md`](docs/development.md) for the full development guide.

## License

MIT. See [`LICENSE`](LICENSE).
