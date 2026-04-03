#!/usr/bin/env sh
# Quick local smoke test for ztotp.
#
# Purpose:
#   Create a temporary vault in the current repository, seed a few built-in
#   TOTP entries, and run a small end-to-end verification flow.
#
# Usage:
#   ./scripts/smoke.sh [--keep] [--tui] [--password VALUE]

set -eu

keep=0
run_tui=0
stress=0
password="test"
status_build="pending"
status_init="pending"
status_add="pending"
status_query="pending"
status_export="pending"
status_reimport="pending"
status_tui="skipped"

if [ -t 1 ] && [ "${NO_COLOR:-}" = "" ]; then
    c_reset='\033[0m'
    c_title='\033[1;96m'
    c_section='\033[1;94m'
    c_ok='\033[1;92m'
    c_warn='\033[1;93m'
    c_fail='\033[1;91m'
    c_info='\033[2;37m'
    c_value='\033[36m'
else
    c_reset=''
    c_title=''
    c_section=''
    c_ok=''
    c_warn=''
    c_fail=''
    c_info=''
    c_value=''
fi

title() {
    printf '%b%s%b\n' "$c_title" "$1" "$c_reset"
}

section() {
    printf '\n%b== %s ==%b\n' "$c_section" "$1" "$c_reset"
}

step() {
    printf '%b[>] %s%b\n' "$c_section" "$1" "$c_reset"
}

ok() {
    printf '%b[+] %s%b\n' "$c_ok" "$1" "$c_reset"
}

info() {
    printf '%b[i] %s%b\n' "$c_info" "$1" "$c_reset"
}

warn() {
    printf '%b[!] %s%b\n' "$c_warn" "$1" "$c_reset"
}

fail() {
    printf '%b[-] %s%b\n' "$c_fail" "$1" "$c_reset" >&2
    exit 1
}

run_checked() {
    label="$1"
    shift
    step "$label"
    "$@" || fail "$label failed"
}

summary_line() {
    label="$1"
    value="$2"
    color="$c_info"
    case "$value" in
        pass) color="$c_ok" ;;
        skipped) color="$c_warn" ;;
        fail) color="$c_fail" ;;
    esac
    printf '  %-14s %b%s%b\n' "$label:" "$color" "$value" "$c_reset"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --keep)
            keep=1
            ;;
        --tui)
            run_tui=1
            ;;
        --stress)
            stress=1
            ;;
        --password)
            shift
            if [ "$#" -eq 0 ]; then
                fail "Missing value for --password"
            fi
            password="$1"
            ;;
        -h|--help)
            printf '%s\n' "Usage: ./scripts/smoke.sh [--keep] [--tui] [--stress] [--password VALUE]"
            exit 0
            ;;
        *)
            fail "Unknown argument: $1"
            ;;
    esac
    shift
done

repo_root=$(pwd)
tmp_root="$repo_root/.tmp-smoke-local"
data_root="$tmp_root/data"
json_export="$tmp_root/backup.json"
csv_export="$tmp_root/backup.csv"
otpauth_export="$tmp_root/backup.txt"
seed_otpauth="$tmp_root/seed-otpauth.txt"
stress_otpauth="$tmp_root/stress-otpauth.txt"

cleanup() {
    if [ "$keep" -eq 0 ]; then
        rm -rf "$tmp_root"
    fi
}

trap cleanup EXIT INT TERM

title "ztotp smoke"
info "Current directory: $repo_root"
info "Temporary data root: $tmp_root"
info "Seed entries:"
printf '  - 16 built-in TOTP entries across SHA1 / SHA256 / SHA512\n'
printf '  - 3 readonly fixtures via local otpauth import (2 HOTP + 1 Steam)\n'
if [ "$stress" -eq 1 ]; then
    printf '  - 12 extra generated TOTP entries for TUI stress coverage\n'
fi

section "Build"
run_checked "zig build" zig build
status_build="pass"

section "Reset Temp Data"
rm -rf "$tmp_root"
mkdir -p "$tmp_root"
ok "Prepared temporary workspace"

run_ztotp() {
    XDG_DATA_HOME="$data_root" ZTOTP_PASSWORD="$password" "$repo_root/zig-out/bin/ztotp" "$@"
}

seed_entry() {
    issuer="$1"
    account="$2"
    secret="$3"
    digits="$4"
    period="$5"
    algorithm="$6"
    tag="$7"

    run_ztotp add \
        --issuer "$issuer" \
        --account "$account" \
        --secret "$secret" \
        --digits "$digits" \
        --period "$period" \
        --algorithm "$algorithm" \
        --tag "$tag"
    ok "Added $issuer / $account"
}

seed_builtin_entries() {
    seed_entry "GitHub" "alice@example.com" "JBSWY3DPEHPK3PXP" 6 30 SHA1 work
    seed_entry "OpenAI" "team@example.com" "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ" 8 30 SHA256 prod
    seed_entry "Internal" "ops@example.com" "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZA====" 6 60 SHA512 infra
    seed_entry "GitLab" "platform@example.com" "MFRGGZDFMZTWQ2LK" 6 30 SHA1 work
    seed_entry "Bitwarden" "vault@example.com" "MZXW6YTBOI" 6 30 SHA1 vault
    seed_entry "Proton" "mail@example.com" "ONSWG4TFOQ" 6 30 SHA1 mail
    seed_entry "Cloudflare" "edge@example.com" "MZXW6YTBOJTG633C" 8 45 SHA256 edge
    seed_entry "Grafana" "alerts@example.com" "KRUGS4ZAON2HE2LOM4" 6 30 SHA1 obs
    seed_entry "Sentry" "errors@example.com" "NRXW4ZDJNZTSA5DIMU" 6 30 SHA1 obs
    seed_entry "Linear" "pm@example.com" "OJQW4YLSN5XGOIDBOI" 6 30 SHA1 ops
    seed_entry "Vercel" "deploy@example.com" "NZXW6YTBONSWG4TFORQQ" 6 30 SHA1 deploy
    seed_entry "Scale" "batch@example.com" "KRSXG5DSNFXGOIDBNRUWG" 6 30 SHA1 batch
    seed_entry "PagerDuty" "oncall@example.com" "M5XW6YTBOJSWG5DF" 6 30 SHA1 ops
    seed_entry "Datadog" "metrics@example.com" "MZXW6YTBORQW4ZBA" 6 30 SHA1 obs
    seed_entry "Slack" "chat@example.com" "MFZG65DIMVZG63TH" 6 30 SHA1 comms
    seed_entry "Figma" "design@example.com" "INXW24DMMV4HI2LO" 6 30 SHA1 design
}

seed_readonly_entries() {
    cat > "$seed_otpauth" <<'EOF'
otpauth://hotp/Issuu:James?secret=YOOMIXWS5GN6RTBPUFFWKTW5M4&issuer=Issuu&algorithm=SHA1&digits=6&counter=1
otpauth://hotp/Nozbe:David?secret=MNUGC3DVMRZXIYJAONUGC4TF&issuer=Nozbe&algorithm=SHA1&digits=8&counter=7
steam://NB2W45DFOIZA====
EOF
    run_ztotp import --from otpauth --file "$seed_otpauth"
    ok "Imported readonly HOTP and Steam fixtures"
}

seed_stress_entries() {
    : > "$stress_otpauth"
    i=1
    while [ "$i" -le 12 ]; do
        suffix=$(printf '%02d' "$i")
        case $((i % 3)) in
            0)
                algorithm="SHA512"
                digits=6
                period=60
                ;;
            1)
                algorithm="SHA1"
                digits=6
                period=30
                ;;
            2)
                algorithm="SHA256"
                digits=8
                period=45
                ;;
        esac
        printf 'otpauth://totp/Demo%s:user%s@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Demo%s&algorithm=%s&digits=%s&period=%s\n' \
            "$suffix" "$suffix" "$suffix" "$algorithm" "$digits" "$period" >> "$stress_otpauth"
        i=$((i + 1))
    done
    run_ztotp import --from otpauth --file "$stress_otpauth"
    ok "Imported 12 extra stress entries"
}

section "Init"
run_checked "initialize temporary vault" run_ztotp init
status_init="pass"

section "Add Entries"
seed_builtin_entries
seed_readonly_entries
if [ "$stress" -eq 1 ]; then
    seed_stress_entries
fi
status_add="pass"

section "List"
run_ztotp list

section "Search"
run_ztotp search --issuer GitHub
ok "Search returned GitHub entries"

section "Readonly Search"
run_ztotp search --issuer Issuu
ok "Readonly imported entries are visible"

section "Code"
run_ztotp code GitHub
ok "Generated a live code"
step "validate readonly rejection"
if run_ztotp code Issuu >/dev/null 2>&1; then
    fail "readonly code generation unexpectedly succeeded"
fi
ok "Readonly entry rejected by code command as expected"
status_query="pass"

section "Update"
run_ztotp update --query GitHub --note smoke --set-tags work,smoke
ok "Updated the GitHub entry"
run_ztotp list

section "Export"
run_ztotp export --to json --file "$json_export"
run_ztotp export --to csv --file "$csv_export"
run_ztotp export --to otpauth --file "$otpauth_export"
ok "Exported JSON, CSV, and otpauth backups"
status_export="pass"

section "Re-import JSON Into Fresh Temp Vault"
rm -rf "$data_root"
run_ztotp init
run_ztotp import --from json --file "$json_export"
run_ztotp list
ok "Re-imported exported JSON into a fresh temporary vault"
status_reimport="pass"

if [ "$run_tui" -eq 1 ]; then
    section "TUI"
    if command -v script >/dev/null 2>&1; then
        info "Press q to exit the TUI..."
        script -qec "env XDG_DATA_HOME=$data_root ZTOTP_PASSWORD=$password $repo_root/zig-out/bin/ztotp tui" /dev/null
        ok "TUI exited successfully"
        status_tui="pass"
    else
        warn "Skipping TUI: 'script' is not available."
        status_tui="skipped"
    fi
fi

section "Summary"
summary_line "build" "$status_build"
summary_line "init" "$status_init"
summary_line "add" "$status_add"
summary_line "query" "$status_query"
summary_line "export" "$status_export"
summary_line "reimport" "$status_reimport"
summary_line "tui" "$status_tui"
printf '  %-14s %b%s%b\n' "temp dir:" "$c_value" "$tmp_root" "$c_reset"
if [ "$keep" -eq 1 ]; then
    info "Kept temporary files for inspection."
else
    info "Temporary files will be removed."
fi
