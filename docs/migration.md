# Migration

This guide covers moving entries in and out of `ztotp`.

## Table of Contents

- [Supported Sources](#supported-sources)
- [Import](#import)
- [Export](#export)
- [Migrate from Aegis](#migrate-from-aegis)
- [Migrate from Authy](#migrate-from-authy)
- [Migrate from 2FAS](#migrate-from-2fas)
- [Migrate from andOTP](#migrate-from-andotp)
- [Migrate from Bitwarden](#migrate-from-bitwarden)
- [Migrate from Proton Authenticator](#migrate-from-proton-authenticator)
- [Migrate from Ente Auth](#migrate-from-ente-auth)
- [Migrate from otpauth Text Files](#migrate-from-otpauth-text-files)
- [Migration Checklist](#migration-checklist)

## Supported Sources

`ztotp` currently supports these migration formats:

- `aegis`
- `aegis-encrypted`
- `authy`
- `2fas`
- `2fas-encrypted`
- `andotp`
- `andotp-encrypted`
- `andotp-encrypted-old`
- `bitwarden`
- `proton-authenticator`
- `ente-auth`
- `otpauth`
- `json`
- `csv`

## Import

General form:

```bash
ztotp import --from <format> --file <path>
```

Examples:

```bash
ztotp import --from aegis --file aegis_plain.json
ztotp import --from aegis-encrypted --file aegis_encrypted.json
ztotp import --from authy --file authy.json
ztotp import --from otpauth --file otpauth.txt
ztotp import --from json --file backup.json
ztotp import --from csv --file export.csv
```

## Export

General form:

```bash
ztotp export --to <format> --file <path>
```

Examples:

```bash
ztotp export --to json --file backup.json
ztotp export --to csv --file export.csv
ztotp export --to otpauth --file otpauth.txt
ztotp export --to aegis --file aegis_plain.json
ztotp export --to aegis-encrypted --file aegis_encrypted.json
ztotp export --to authy --file authy.json
```

## Migrate from Aegis

Plain backup:

```bash
ztotp import --from aegis --file aegis_plain.json
```

Encrypted backup:

```bash
ztotp import --from aegis-encrypted --file aegis_encrypted.json
```

Notes:

- `aegis-encrypted` uses the current `ztotp` vault password during import and export
- Unknown extra fields in Aegis backups are ignored when possible
- Non-TOTP records are skipped

## Migrate from Authy

`ztotp` supports Authy backups compatible with `authy-export --save` style JSON.

Import:

```bash
ztotp import --from authy --file authy.json
```

Export:

```bash
ztotp export --to authy --file authy.json
```

Notes:

- This path is intended for offline backup compatibility
- Use it as a migration path, not as your primary long-term archive format
- Prefer `json` for full native `ztotp` backups

## Migrate from 2FAS

Plain export:

```bash
ztotp import --from 2fas --file twofas_plain.2fas
```

Encrypted export:

```bash
ztotp import --from 2fas-encrypted --file twofas_encrypted.2fas
```

Notes:

- non-TOTP records such as HOTP and Steam are imported as readonly
- encrypted imports use the current vault password

## Migrate from andOTP

Plain export:

```bash
ztotp import --from andotp --file andotp.json
```

Encrypted export:

```bash
ztotp import --from andotp-encrypted --file andotp.bin
```

Legacy encrypted export:

```bash
ztotp import --from andotp-encrypted-old --file andotp_old.bin
```

Notes:

- HOTP and Steam entries are preserved as readonly
- current and legacy encrypted formats use different key derivation schemes

## Migrate from Bitwarden

JSON export:

```bash
ztotp import --from bitwarden --file bitwarden.json
```

CSV export:

```bash
ztotp import --from bitwarden --file bitwarden.csv
```

Notes:

- only items with TOTP or Steam-style URI data are imported
- standard logins without OTP data are ignored

## Migrate from Proton Authenticator

```bash
ztotp import --from proton-authenticator --file proton_authenticator.json
```

## Migrate from Ente Auth

```bash
ztotp import --from ente-auth --file ente_auth.txt
```

Notes:

- Ente Auth import uses the shared URI parser
- non-TOTP URIs are preserved as readonly entries

## Migrate from otpauth Text Files

Import a newline-delimited set of `otpauth://` URIs:

```bash
ztotp import --from otpauth --file otpauth.txt
```

Export the same style:

```bash
ztotp export --to otpauth --file otpauth.txt
```

Notes:

- Only the TOTP subset is imported
- HOTP and Steam entries are skipped

## Migration Checklist

Before migration:

1. Keep the source app backup until you finish verification.
2. Decide whether the backup should stay encrypted.
3. Initialize the `ztotp` vault first.

After migration:

1. Compare imported entry counts.
2. Run `ztotp list` and inspect issuer/account labels.
3. Spot-check a few codes with `ztotp code <query>`.
4. Export a native `json` backup for long-term recovery.
