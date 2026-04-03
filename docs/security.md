# Security

This document explains the storage and operational security model used by `ztotp`.

## Table of Contents

- [Local-First Model](#local-first-model)
- [Vault Location](#vault-location)
- [Vault Encryption](#vault-encryption)
- [Password Handling](#password-handling)
- [Backup Format Risk](#backup-format-risk)
- [Operational Recommendations](#operational-recommendations)

## Local-First Model

`ztotp` is designed to keep TOTP data on the local machine.

- No network sync is built into the tool
- The canonical state is the local encrypted vault
- Imports and exports are explicit user actions

## Vault Location

Primary path:

```text
$XDG_DATA_HOME/ztotp/vault.bin
```

Fallback when `XDG_DATA_HOME` is unset:

```text
$HOME/.local/share/ztotp/vault.bin
```

This follows the XDG data directory convention instead of storing
application state in the current working directory.

## Vault Encryption

The local vault is encrypted using:

- Argon2id for password-based key derivation
- XChaCha20-Poly1305 for authenticated encryption

Implications:

- The vault is protected at rest by the master password
- Wrong passwords fail decryption instead of silently producing bad data
- The whole vault is encrypted as one file

## Password Handling

Password source priority:

1. `--password <value>`
2. `ZTOTP_PASSWORD`
3. hidden TTY prompt

TTY behavior:

- On Linux and macOS TTYs, prompt input hides terminal echo
- In non-interactive sessions, prefer environment variables or explicit flags

Security trade-offs:

- `--password` may leak through shell history or process inspection
- `ZTOTP_PASSWORD` may leak through environment inspection in some contexts
- interactive prompt is safer for local manual use

## Backup Format Risk

Not all export formats have the same security profile.

Lower risk:

- `aegis-encrypted`
- encrypted local vault

Higher risk:

- `json`
- `csv`
- `otpauth`

Reason:

- Plain-text export formats contain enough information to generate valid
  TOTP codes if exposed

## Operational Recommendations

1. Use a strong master password.
2. Prefer interactive password entry for local manual use.
3. Keep plain-text exports only as long as necessary.
4. Delete migration files after verification.
5. Store long-term backups in encrypted form when possible.
6. Use `json` only for trusted local backup workflows.
