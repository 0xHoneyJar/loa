#!/usr/bin/env bash
# =============================================================================
# tools/check-bb-no-direct-fetch.sh
#
# cycle-104 sprint-3 T3.3 — narrower companion to
# `tools/check-no-direct-llm-fetch.sh`. Where that tool scans the whole repo
# for provider hostnames, THIS tool scans only the BB skill resources
# (`.claude/skills/bridgebuilder-review/resources/`) for raw HTTP-client
# primitives that would bypass the ChevalDelegateAdapter routing.
#
# The premise (SDD §1.4.5 + sprint-3-evidence.md): after cycle-103 PR #846,
# BB's adapter-factory unconditionally returns ChevalDelegateAdapter; the
# per-provider Node adapter registry was retired. If a future PR
# reintroduces `fetch(...)`, `https.request(...)`, `undici`, or similar
# direct-HTTP primitives in BB resources, KF-001 + KF-008 absorption
# guarantees (cycle-104 voice-drop, within-company chain walk) silently
# regress. This scanner is the regression catcher.
#
# Detection (per BB-resources file):
#   - File-type filter: .ts / .tsx / .js / .mjs (BB ships TypeScript +
#     compiled JS dist).
#   - Exempt-file filter: paths listed in tools/check-bb-no-direct-fetch.allowlist
#     (one path per line, `#` for comments).
#   - Skip line-leading comments (`//`, `*`).
#   - Skip lines with `// check-bb-no-direct-fetch: ok` suppression marker.
#   - Match raw-HTTP shapes:
#       * fetch\(           — Node 18+ global / undici fetch
#       * https\.request\(  — node:https module
#       * https\.get\(      — node:https module
#       * http\.request\(   — node:http module (non-TLS; rare but pin it)
#       * require\(["']undici["']\)  — CJS require
#       * from\s+["']undici["'] — ESM import
#       * from\s+["']node:https?["'] — ESM import of node http/s
#
# Output:
#   stdout: violation list (path:line:match) when any are found
#   stderr: scanner diagnostics
#   exit 0: no violations
#   exit 1: violations
#   exit 2: argument / I/O error
#
# Tested by tests/unit/test_bb_zero_direct_fetch.bats.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BB_RESOURCES="$PROJECT_ROOT/.claude/skills/bridgebuilder-review/resources"
ALLOWLIST="$SCRIPT_DIR/check-bb-no-direct-fetch.allowlist"

QUIET=0

usage() {
    cat >&2 <<'USAGE'
Usage: check-bb-no-direct-fetch.sh [--quiet] [--root <dir>]

Scans BB skill resources for raw HTTP-client primitives that would bypass
the ChevalDelegateAdapter routing.

  --quiet        Suppress non-error output (exit code only).
  --root <dir>   Override scan root (default:
                 .claude/skills/bridgebuilder-review/resources).
  --help         This message.

Exit:
  0  no violations
  1  violations found
  2  argument / I/O error
USAGE
}

# ---- arg parse ------------------------------------------------------------

while [[ $# -gt 0 ]]; do
    case "$1" in
        --quiet) QUIET=1; shift ;;
        --root)
            [[ $# -ge 2 ]] || { usage; exit 2; }
            BB_RESOURCES="$2"
            shift 2
            ;;
        --help|-h) usage; exit 0 ;;
        *)
            echo "ERROR: unknown argument: $1" >&2
            usage
            exit 2
            ;;
    esac
done

if [[ ! -d "$BB_RESOURCES" ]]; then
    echo "ERROR: BB resources dir not found: $BB_RESOURCES" >&2
    exit 2
fi

# ---- allowlist load -------------------------------------------------------

declare -A EXEMPT=()
if [[ -f "$ALLOWLIST" ]]; then
    while IFS= read -r line; do
        # strip comments, skip blanks
        line="${line%%#*}"
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -z "$line" ]] && continue
        # Resolve to absolute under project root.
        EXEMPT["$PROJECT_ROOT/$line"]=1
    done < "$ALLOWLIST"
fi

# ---- scan ----------------------------------------------------------------

# The raw-HTTP patterns. Multi-line awk regex (one per OR-branch); each
# line of source is tested against all of them.
PATTERNS='fetch\(|https?\.request\(|https?\.get\(|require\(["'\'']undici["'\'']\)|from[[:space:]]+["'\'']undici["'\'']|from[[:space:]]+["'\'']node:https?["'\'']'

SUPPRESS_MARKER='// check-bb-no-direct-fetch: ok'

violations=0

# Build the file list with a single find pass so the scanner is O(files
# under BB_RESOURCES), not O(rg invocations).
while IFS= read -r -d '' file; do
    # Path-rooted-against-PROJECT_ROOT match for allowlist hits.
    if [[ -n "${EXEMPT[$file]:-}" ]]; then
        continue
    fi
    # Skip files in dist/ unless --root opted in explicitly. dist/ is
    # generated output and not source-of-truth; the gate scans source.
    case "$file" in
        "$PROJECT_ROOT/.claude/skills/bridgebuilder-review/resources/dist/"*) continue ;;
        */__tests__/*) continue ;;
    esac

    # Walk lines, skipping comment-leading patterns and the suppression
    # marker. POSIX awk for portability.
    while IFS= read -r match; do
        violations=$((violations + 1))
        if [[ "$QUIET" -eq 0 ]]; then
            printf '%s\n' "$match"
        fi
    done < <(
        awk -v patterns="$PATTERNS" -v marker="$SUPPRESS_MARKER" '
            # Skip line-leading // and * (block-comment continuation).
            /^[[:space:]]*\/\// { next }
            /^[[:space:]]*\*/ { next }
            # Skip lines with the suppression marker.
            index($0, marker) > 0 { next }
            $0 ~ patterns {
                printf "%s:%d: %s\n", FILENAME, NR, $0
            }
        ' "$file"
    )
done < <(
    find "$BB_RESOURCES" \
        \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.mjs' \) \
        -type f -print0
)

if [[ "$violations" -gt 0 ]]; then
    if [[ "$QUIET" -eq 0 ]]; then
        echo "" >&2
        echo "FAIL: $violations direct-HTTP primitive(s) found in BB resources." >&2
        echo "BB MUST route all provider calls through ChevalDelegateAdapter." >&2
        echo "See grimoires/loa/cycles/cycle-104-multi-model-stabilization/sprint-3-evidence.md" >&2
    fi
    exit 1
fi

if [[ "$QUIET" -eq 0 ]]; then
    echo "OK: no direct-HTTP primitives in BB resources." >&2
fi
exit 0
