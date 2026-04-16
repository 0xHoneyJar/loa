#!/usr/bin/env bash
# =============================================================================
# lint-arithmetic-increment.sh — Detect (( var++ )) without || true guard
# =============================================================================
# Cycle: cycle-081
#
# Under set -e (bash strict mode), (( expr )) exits with status 1 when
# the expression evaluates to 0 (falsy). This means (( count++ )) will
# terminate the script when count=0, because:
#   1. count is 0 (pre-increment value is the return)
#   2. (( 0 )) evaluates to false
#   3. set -e treats non-zero exit as fatal
#
# Approved replacement:
#   count=$((count + 1))    # Always exits 0
#
# Existing guard (also acceptable):
#   ((count++)) || true     # Suppresses the exit
#
# Usage:
#   lint-arithmetic-increment.sh [--error] [--scan-only]
#
# Exit codes:
#   0 — No findings (or WARNING mode)
#   1 — --error mode with findings
# =============================================================================

set -euo pipefail
shopt -s globstar 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

error_mode=false
scan_only=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --error) error_mode=true; shift ;;
        --scan-only) scan_only=true; shift ;;
        --help|-h)
            echo "Usage: lint-arithmetic-increment.sh [--error] [--scan-only]"
            echo "Detect (( var++ )) without || true guard in set -e scripts."
            exit 0
            ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
done

findings=0

# Only check scripts that use set -e
for script in "$PROJECT_ROOT/.claude/scripts/"*.sh "$PROJECT_ROOT/.claude/scripts/"**/*.sh; do
    [[ -f "$script" ]] || continue
    [[ "$script" == *"test"* ]] && continue
    [[ "$script" == *".bats"* ]] && continue
    [[ "$script" == *".legacy"* ]] && continue

    # Skip scripts without set -e
    grep -q 'set -e' "$script" 2>/dev/null || continue

    # Find unguarded (( var++ )) or (( var-- ))
    while IFS=: read -r line content; do
        # Skip if guarded with || true
        [[ "$content" == *"|| true"* ]] && continue
        # Skip comments
        [[ "$content" =~ ^[[:space:]]*# ]] && continue
        # Skip inline suppression
        [[ "$content" == *"lint:allow-arithmetic"* ]] && continue

        findings=$((findings + 1))

        if [[ "$scan_only" == "false" ]]; then
            local_severity="WARNING"
            [[ "$error_mode" == "true" ]] && local_severity="ERROR"

            echo "  ${local_severity}: ${script}:${line} — unguarded (( var++ )) under set -e"
            echo "           Exits with status 1 when var=0. Use: var=\$((var + 1))"
            echo "           ${content}"
            echo ""
        fi
    done < <(grep -n -E '\(\(\s*\w+(\+\+|--)\s*\)\)' "$script" 2>/dev/null || true)
done

if [[ "$scan_only" == "true" ]]; then
    echo "$findings"
    exit 0
fi

if [[ "$findings" -gt 0 ]]; then
    echo "═══════════════════════════════════════════════"
    echo "  (( var++ )) under set -e: $findings site(s)"
    echo "═══════════════════════════════════════════════"
    echo ""
    echo "Fix: var=\$((var + 1))  # Always exits 0"
    echo "Or:  ((var++)) || true  # Guard the exit"
    echo "Suppress: add '# lint:allow-arithmetic' to the line"

    if [[ "$error_mode" == "true" ]]; then
        exit 1
    fi
else
    echo "No unguarded (( var++ )) found."
fi
