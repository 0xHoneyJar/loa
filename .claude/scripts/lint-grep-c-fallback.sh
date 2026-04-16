#!/usr/bin/env bash
# =============================================================================
# lint-grep-c-fallback.sh — Detect grep -c / wc -l with || echo 0 anti-pattern
# =============================================================================
# Issue: https://github.com/0xHoneyJar/loa/issues/531
# Cycle: cycle-079
#
# Under set -o pipefail, `grep -c 'pattern' FILE || echo "0"` produces "0\n0"
# when the count is zero:
#   1. grep -c outputs "0" to stdout (always, even on zero matches)
#   2. grep -c exits 1 on zero matches (POSIX behavior)
#   3. pipefail triggers, || echo "0" fallback fires
#   4. Command substitution captures: "0\n0"
#   5. Downstream arithmetic fails: [[ "0\n0" -lt 5 ]] → syntax error
#
# This bug class was found 3 independent times in cycle-075 (PRs #518, #524, #526).
#
# Approved replacement:
#   count=$(awk '/pattern/{c++} END{print c+0}' FILE 2>/dev/null || echo 0)
#
# Usage:
#   lint-grep-c-fallback.sh [--error]     # Default: WARNING level
#   lint-grep-c-fallback.sh --scan-only   # Print count only (for CI integration)
#
# Inline suppression:
#   Add `# lint:allow-grep-c-fallback` to the line to suppress the warning.
#
# Exit codes:
#   0 — No findings (or WARNING mode with findings)
#   1 — --error mode with findings
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

error_mode=false
scan_only=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --error) error_mode=true; shift ;;
        --scan-only) scan_only=true; shift ;;
        --help|-h)
            echo "Usage: lint-grep-c-fallback.sh [--error] [--scan-only]"
            echo ""
            echo "Detect grep -c / wc -l with || echo 0 anti-pattern in .claude/scripts/"
            echo ""
            echo "Options:"
            echo "  --error      Exit 1 if any findings (default: WARNING only)"
            echo "  --scan-only  Print count of findings and exit"
            exit 0
            ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
done

findings=0

while IFS=: read -r file line content; do
    # Skip test files
    [[ "$file" == *"test"* ]] && continue
    [[ "$file" == *".bats"* ]] && continue

    # Skip inline suppression
    [[ "$content" == *"lint:allow-grep-c-fallback"* ]] && continue

    # Skip comment lines
    [[ "$content" =~ ^[[:space:]]*# ]] && continue

    findings=$((findings + 1))

    if [[ "$scan_only" == "false" ]]; then
        local_severity="WARNING"
        [[ "$error_mode" == "true" ]] && local_severity="ERROR"

        echo "  ${local_severity}: ${file}:${line} — 'grep -c' or 'wc -l' with '|| echo' fallback"
        echo "           Under set -o pipefail, this produces '0\\n0' on zero matches."
        echo "           Use: count=\$(awk '/pattern/{c++} END{print c+0}' FILE)"
        echo "           ${content}"
        echo ""
    fi
done < <(grep -rn -E '(grep\s+-c.*\|\|\s*echo|wc\s+-l.*\|\|\s*echo)' \
    "$PROJECT_ROOT/.claude/scripts/"*.sh \
    "$PROJECT_ROOT/.claude/scripts/"**/*.sh \
    2>/dev/null || true)

if [[ "$scan_only" == "true" ]]; then
    echo "$findings"
    exit 0
fi

if [[ "$findings" -gt 0 ]]; then
    echo "═══════════════════════════════════════════════"
    echo "  grep -c / wc -l || echo 0: $findings site(s) found"
    echo "═══════════════════════════════════════════════"
    echo ""
    echo "See: https://github.com/0xHoneyJar/loa/issues/531"
    echo "Fix: count=\$(awk '/pattern/{c++} END{print c+0}' FILE)"
    echo "Suppress: add '# lint:allow-grep-c-fallback' to the line"

    if [[ "$error_mode" == "true" ]]; then
        exit 1
    fi
else
    echo "No grep -c / wc -l || echo 0 anti-pattern found."
fi
