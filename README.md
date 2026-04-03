# ztotp

`ztotp` is a local-first TOTP CLI implemented in Zig.

## Features

- Encrypted local vault stored at `XDG_DATA_HOME/ztotp/vault.bin`
- Falls back to `$HOME/.local/share/ztotp/vault.bin` when `XDG_DATA_HOME` is unset
- Manage TOTP entries with `init`, `add`, `list`, `search`, `code`, and `remove`
- Import and export `otpauth://` URIs, JSON backups, and CSV files
- Import and export Aegis plain/encrypted backups
- Import and export Authy `authy-export --save` compatible backups
- Filter by issuer, account, and tag
- Password sources: `--password`, `ZTOTP_PASSWORD`, or hidden TTY prompt

## Build

```bash
zig build
zig build test
```

## Usage

```bash
ztotp init --password secret
ztotp add --password secret --issuer GitHub --account alice@example.com --secret JBSWY3DPEHPK3PXP --tag work
ztotp list --password secret
ztotp code GitHub --password secret
ztotp export --to json --file backup.json --password secret
ztotp import --from otpauth --file seeds.txt --password secret
ztotp export --to aegis-encrypted --file aegis.json --password secret
ztotp import --from authy --file authy.json --password secret
```

## Notes

- The default vault path follows the XDG data directory convention.
- Encryption uses Argon2id-derived keys with XChaCha20-Poly1305.
- Password prompt input hides echo on Linux/macOS TTYs and falls back to plain stdin otherwise.
- Source layout:
  - `src/importers.zig` and `src/exporters.zig` split internal import/export logic
  - `src/thirdparty/shared.zig` contains shared third-party helpers
  - `src/thirdparty/aegis.zig` and `src/thirdparty/authy.zig` contain format-specific support
