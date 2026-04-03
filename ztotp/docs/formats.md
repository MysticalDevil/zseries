# Formats

This document describes the current import and export compatibility matrix for `ztotp`.

## Compatibility Matrix

| Format | Import | Export | Encrypted | Intended Use | Notes |
| --- | --- | --- | --- | --- | --- |
| `otpauth` | Yes | Yes | No | URI migration | Imports only TOTP entries and skips unsupported token types |
| `json` | Yes | Yes | No | Native backup | Best plain-text round-trip format for `ztotp` |
| `csv` | Yes | Yes | No | Spreadsheet-friendly export | Useful for inspection and bulk review |
| `aegis` | Yes | Yes | No | Aegis migration | Supports public plain backup JSON |
| `aegis-encrypted` | Yes | Yes | Yes | Aegis migration | Uses the current vault password in `ztotp` |
| `authy` | Yes | Yes | Yes | Authy migration | Compatible with `authy-export --save` style JSON |
| `2fas` | Yes | No | No | 2FAS migration | Supports plain `.2fas` exports |
| `2fas-encrypted` | Yes | No | Yes | 2FAS migration | PBKDF2-HMAC-SHA256 + AES-GCM encrypted `.2fas` exports |
| `andotp` | Yes | No | No | andOTP migration | Supports plain JSON exports |
| `andotp-encrypted` | Yes | No | Yes | andOTP migration | Supports current encrypted backup format |
| `andotp-encrypted-old` | Yes | No | Yes | andOTP migration | Supports the legacy encrypted format |
| `bitwarden` | Yes | No | Mixed | Password manager migration | Imports JSON and CSV exports that contain OTP URIs |
| `proton-authenticator` | Yes | No | No | Authenticator migration | Imports Proton Authenticator export JSON |
| `ente-auth` | Yes | No | No | Authenticator migration | Imports newline-delimited otpauth and steam URIs |

## otpauth

Supported:

- TOTP entries
- issuer/account parsing from URI label and query
- `SHA1`, `SHA256`, `SHA512`
- custom digits and period values

Unsupported:

- HOTP import
- Steam token import

Behavior:

- unsupported token types are skipped during import

## json

This is the native plain-text backup format for `ztotp`.

Recommended uses:

- round-trip backups
- debugging import/export behavior
- stable cross-version inspection during development

## csv

CSV is intended for interoperability and inspection.

Characteristics:

- easy to open in editors and spreadsheets
- less expressive than JSON
- not a preferred archival format for long-term backups

## Aegis

Plain Aegis support:

- import public plain backup JSON
- export compatible plain backup JSON

Encrypted Aegis support:

- import encrypted backups
- export encrypted backups
- ignore unknown extra fields when possible for better compatibility with real exports

Behavior notes:

- only TOTP entries are imported
- non-TOTP Aegis records are skipped

## Authy

Authy support targets backups compatible with `authy-export --save` style JSON.

Behavior notes:

- suitable for offline migration and compatibility
- not intended as a richer native archive than `json`
- current implementation treats imported entries as TOTP records usable inside `ztotp`

## 2FAS

Current support:

- plain `.2fas` export import
- encrypted `.2fas` export import
- TOTP, HOTP, and Steam record recognition

Behavior notes:

- TOTP entries are fully usable after import
- HOTP and Steam entries are imported as readonly

## andOTP

Current support:

- plain JSON import
- encrypted import
- legacy encrypted import

Behavior notes:

- TOTP entries are imported as normal `ztotp` records
- HOTP and Steam entries are preserved as readonly

## Bitwarden

Current support:

- JSON export import
- CSV export import when the `login_totp` column is present

Behavior notes:

- TOTP URIs are extracted from login records
- Steam URIs are imported as readonly steam entries

## Proton Authenticator

Current support:

- JSON export import

Behavior notes:

- TOTP entries are imported directly from each content URI

## Ente Auth

Current support:

- text export import

Behavior notes:

- imported line-by-line through shared URI parsing
- non-TOTP URIs remain readonly

## Choosing a Format

Use this rule of thumb:

- choose `json` for native `ztotp` backups
- choose `aegis-encrypted` when moving to or from Aegis with encryption
- choose `authy` only when migrating through Authy-compatible tooling
- choose `2fas` or `andotp` when migrating directly from those apps
- choose `bitwarden` or `proton-authenticator` when OTP data comes from those exports
- choose `otpauth` for simple TOTP URI interchange
- choose `csv` only for review or bulk external processing
