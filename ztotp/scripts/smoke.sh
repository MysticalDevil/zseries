#!/usr/bin/env sh
# Quick local smoke test for ztotp.
#
# Purpose:
#   Create a temporary vault in the current repository, seed a few built-in
#   TOTP entries, and run a small end-to-end verification flow.
#
# Usage:
#   ./scripts/smoke.sh [--keep] [--tui] [--quick] [--password VALUE]
#
# Options:
#   --keep       Keep temporary files after exit
#   --tui        Run interactive TUI dashboard
#   --quick      Use fast Argon2 params (for CI/development speed)
#   --password   Set master password (default: test)

set -eu

keep=0
run_tui=0
quick=0
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
        --quick)
            quick=1
            ;;
        --password)
            shift
            if [ "$#" -eq 0 ]; then
                fail "Missing value for --password"
            fi
            password="$1"
            ;;
        -h|--help)
            printf '%s\n' "Usage: ./scripts/smoke.sh [--keep] [--tui] [--quick] [--password VALUE]"
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
readonly_otpauth="$tmp_root/readonly-otpauth.txt"

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
if [ "$quick" -eq 1 ]; then
    info "Quick mode: using low-security Argon2id params"
fi

build_mode="ReleaseFast"
build_flag="-Doptimize=${build_mode}"

section "Build"
run_checked "zig build ($build_mode)" zig build "$build_flag"
status_build="pass"

section "Reset Temp Data"
rm -rf "$tmp_root"
mkdir -p "$tmp_root"
ok "Prepared temporary workspace"

quick_flag=""
if [ "$quick" -eq 1 ]; then
    quick_flag="--quick-init"
fi

run_ztotp() {
    XDG_DATA_HOME="$data_root" ZTOTP_PASSWORD="$password" "$repo_root/zig-out/bin/ztotp" "$@"
}

run_ztotp_quick() {
    if [ "$quick" -eq 1 ]; then
        XDG_DATA_HOME="$data_root" ZTOTP_PASSWORD="$password" ZTOTP_LOW_SECURITY=1 "$repo_root/zig-out/bin/ztotp" "$@"
    else
        run_ztotp "$@"
    fi
}

section "Init"
run_checked "initialize temporary vault" run_ztotp_quick init $quick_flag
status_init="pass"

section "Add Entries"
cat > "$seed_otpauth" <<'EOF'
otpauth://totp/GitHub:alice@example.com?secret=JBSWY3DPEHPK3PXP&issuer=GitHub&algorithm=SHA1&digits=6&period=30
otpauth://totp/OpenAI:team@example.com?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ&issuer=OpenAI&algorithm=SHA256&digits=8&period=30
otpauth://totp/Internal:ops@example.com?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZA====&issuer=Internal&algorithm=SHA512&digits=6&period=60
otpauth://totp/GitLab:platform@example.com?secret=MFRGGZDFMZTWQ2LK&issuer=GitLab&algorithm=SHA1&digits=6&period=30
otpauth://totp/Bitwarden:vault@example.com?secret=MZXW6YTBOI&issuer=Bitwarden&algorithm=SHA1&digits=6&period=30
otpauth://totp/Proton:mail@example.com?secret=ONSWG4TFOQ&issuer=Proton&algorithm=SHA1&digits=6&period=30
otpauth://totp/Cloudflare:edge@example.com?secret=MZXW6YTBOJTG633C&issuer=Cloudflare&algorithm=SHA256&digits=8&period=45
otpauth://totp/Grafana:alerts@example.com?secret=KRUGS4ZAON2HE2LOM4&issuer=Grafana&algorithm=SHA1&digits=6&period=30
otpauth://totp/Sentry:errors@example.com?secret=NRXW4ZDJNZTSA5DIMU&issuer=Sentry&algorithm=SHA1&digits=6&period=30
otpauth://totp/Linear:pm@example.com?secret=OJQW4YLSN5XGOIDBOI&issuer=Linear&algorithm=SHA1&digits=6&period=30
otpauth://totp/Vercel:deploy@example.com?secret=NZXW6YTBONSWG4TFORQQ&issuer=Vercel&algorithm=SHA1&digits=6&period=30
otpauth://totp/Scale:batch@example.com?secret=KRSXG5DSNFXGOIDBNRUWG&issuer=Scale&algorithm=SHA1&digits=6&period=30
otpauth://totp/PagerDuty:oncall@example.com?secret=M5XW6YTBOJSWG5DF&issuer=PagerDuty&algorithm=SHA1&digits=6&period=30
otpauth://totp/Datadog:metrics@example.com?secret=MZXW6YTBORQW4ZBA&issuer=Datadog&algorithm=SHA1&digits=6&period=30
otpauth://totp/Slack:chat@example.com?secret=MFZG65DIMVZG63TH&issuer=Slack&algorithm=SHA1&digits=6&period=30
otpauth://totp/Figma:design@example.com?secret=INXW24DMMV4HI2LO&issuer=Figma&algorithm=SHA1&digits=6&period=30
EOF
run_ztotp_quick import --from otpauth --file "$seed_otpauth"
ok "Imported 16 TOTP entries via otpauth"

cat > "$readonly_otpauth" <<'EOF'
otpauth://hotp/Issuu:James?secret=YOOMIXWS5GN6RTBPUFFWKTW5M4&issuer=Issuu&algorithm=SHA1&digits=6&counter=1
otpauth://hotp/Nozbe:David?secret=MNUGC3DVMRZXIYJAONUGC4TF&issuer=Nozbe&algorithm=SHA1&digits=8&counter=7
steam://NB2W45DFOIZA====
EOF
run_ztotp_quick import --from otpauth --file "$readonly_otpauth"
ok "Imported readonly HOTP and Steam fixtures"

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
run_ztotp_quick init $quick_flag
run_ztotp_quick import --from json --file "$json_export"
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