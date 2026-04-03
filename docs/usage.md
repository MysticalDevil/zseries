# Usage

This guide covers the normal day-to-day flow for working with `ztotp`.

## Table of Contents

- [Initialize a Vault](#initialize-a-vault)
- [Add Entries](#add-entries)
- [List and Search](#list-and-search)
- [Show a Code](#show-a-code)
- [Update Entries](#update-entries)
- [Remove Entries](#remove-entries)
- [Password Input](#password-input)
- [Common Workflows](#common-workflows)
- [Troubleshooting](#troubleshooting)

## Initialize a Vault

Create the encrypted local vault:

```bash
ztotp init
```

If the vault already exists, `ztotp` refuses to overwrite it.

## Add Entries

Minimal example:

```bash
ztotp add \
  --issuer GitHub \
  --account alice@example.com \
  --secret JBSWY3DPEHPK3PXP
```

Fuller example:

```bash
ztotp add \
  --issuer OpenAI \
  --account team@example.com \
  --secret F4YE6NZZK47VERBKIITC6WDOI5MG663F \
  --algorithm SHA256 \
  --digits 8 \
  --period 30 \
  --tag work \
  --tag prod \
  --note "shared org account"
```

## List and Search

List all stored entries:

```bash
ztotp list
```

The list output shows entry type as well as readonly state for imported
non-TOTP records.

Search by issuer:

```bash
ztotp search --issuer GitHub
```

Search by account text:

```bash
ztotp search --account alice
```

Search by tag:

```bash
ztotp search --tag work
```

## Show a Code

Query by text:

```bash
ztotp code GitHub
```

Query by exact id:

```bash
ztotp code --id 60849c8d-c5d3-4182-8a6b-5c80a614e941
```

The output includes:

- entry id
- issuer
- account name
- current code
- remaining seconds in the current time step

Readonly HOTP, Steam, and unknown imported kinds are rejected by
`ztotp code` with a clear message instead of being silently skipped.

## Update Entries

Update by exact id:

```bash
ztotp update --id entry-1700000000 --issuer GitHub --note primary
```

Update by search query:

```bash
ztotp update --query GitHub --set-tags work,prod
```

If multiple entries match, `ztotp` will ask you to choose one interactively.

Supported update fields:

- `--issuer`
- `--account`
- `--secret`
- `--digits`
- `--period`
- `--algorithm`
- `--set-tags`
- `--clear-tags`
- `--note`

## Remove Entries

```bash
ztotp remove --id entry-1700000000
```

Removal is id-based to reduce accidental deletes.

## Password Input

Password input order:

1. `--password <value>`
2. `ZTOTP_PASSWORD`
3. hidden TTY prompt

Examples:

```bash
ztotp list --password secret
```

```bash
ZTOTP_PASSWORD=secret ztotp list
```

On Linux and macOS TTYs, prompt input hides terminal echo. In
non-interactive contexts, you should prefer `--password` or
`ZTOTP_PASSWORD`.

## Common Workflows

### Create a fresh vault and add two services

```bash
ztotp init
ztotp add --issuer GitHub --account alice@example.com \
  --secret JBSWY3DPEHPK3PXP --tag work
ztotp add --issuer OpenAI --account team@example.com \
  --secret F4YE6NZZK47VERBKIITC6WDOI5MG663F --tag work
```

### Find all work entries and read one code

```bash
ztotp search --tag work
ztotp code GitHub
```

### Retag an entry after reorganizing accounts

```bash
ztotp update --query GitHub --set-tags engineering,critical
```

## Troubleshooting

### Unknown command

Use:

```bash
ztotp help
ztotp help import
```

### Vault missing

Run:

```bash
ztotp init
```

### Wrong password or encrypted import failure

Check that you are using the same password you used for:

- the local `ztotp` vault
- the encrypted Aegis/Authy export when applicable

### Import does not include every source token

`ztotp` only manages TOTP entries. Unsupported HOTP, Steam, and similar
token types are skipped.
