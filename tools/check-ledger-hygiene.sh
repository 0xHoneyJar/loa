#!/usr/bin/env bash
# =============================================================================
# tools/check-ledger-hygiene.sh
#
# cycle-124 FR-6 (AC-6.2 / AC-6.3) — tripwire scan: NO test rows in the two
# production ledgers under .run/. Test harnesses that reach cheval's dispatch
# path (--mock-fixture-dir, FLATLINE_MOCK_MODE, the BB delegate e2e) used to
# append to the operator's real ledgers: 155 `mock-*` cost rows and 44
# MODELINV rows naming /tmp/cheval-e2e-* fixture dirs were found 2026-09-17.
# Isolation is LOA_COST_LEDGER_PATH + LOA_MODELINV_LOG_PATH (set by the adapter
# conftest.py, the bats suites and the BB e2e test; every spawner is checked
# by tests/unit/ledger-isolation-discovery.bats). This scanner is the tripwire
# that fires when a new harness forgets. Modeled on check-no-swallowed-jq.sh.
#
# Detection rules:
#   cost-ledger.jsonl   any JSON row whose .model, .agent or .provider starts
#                       with `mock-` (the fixture identities under
#                       tests/fixtures/cycle-109/mock-mode/*). Non-JSON lines
#                       are skipped, as the Python reader's corruption recovery
#                       does.
#   model-invoke.jsonl  any line containing `/tmp/cheval-e2e-` (the BB delegate
#                       e2e mkdtemp prefix, surfaced through
#                       payload.models_failed[].message_redacted). Seal markers
#                       (`[MODELINV-DISABLED]`) cannot match.
#
# A missing ledger prints `SKIP: <path> absent (nothing scanned)` on stderr —
# also under --quiet — so an empty .run/ never reads as a silent clean pass.
# The default .run/ itself may be absent (fresh checkout): both ledgers SKIP,
# exit 0. An explicit --root that does not exist is an argument error (2).
#
# **Tripwire scope (NOT exhaustive defense)**: only the two known pollution
# shapes are matched; rows from pytest tmp paths (/tmp/pytest-of-*) or from a
# test that hit a real provider are out of scope. The structural guard is
# ledger-isolation-discovery.bats; the remedy for a hit is the harness fix
# plus grimoires/loa/runbooks/ledger-hygiene-rotation.md (rotate, never edit —
# the MODELINV log is hash-chained).
#
# Where it runs: .run/ is gitignored, so on CI the scan is meaningful only
# AFTER the test steps (bats-tests.yml) and locally in the pre-push hook — the
# one gate that sees a real, polluted .run/.
#
# Usage:
#   tools/check-ledger-hygiene.sh                 # scan .run/
#   tools/check-ledger-hygiene.sh --root <dir>    # scan <dir>/{cost-ledger,model-invoke}.jsonl
#   tools/check-ledger-hygiene.sh --quiet         # exit-code only (SKIP lines still printed)
#
# Exit codes:
#   0  no violations
#   1  violations found (path:line printed to stderr)
#   2  argument / I/O error
#
# Tested by tests/integration/ledger-hygiene-tripwire.bats.
# =============================================================================

set -euo pipefail

QUIET=0
ROOT=".run"
ROOT_EXPLICIT=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --quiet|-q) QUIET=1; shift ;;
        --root)
            [[ $# -ge 2 ]] || { printf 'check-ledger-hygiene.sh: --root requires a directory argument\n' >&2; exit 2; }
            ROOT="$2"; ROOT_EXPLICIT=1; shift 2
            ;;
        --help|-h)
            sed -n '/^# Usage:/,/^# Tested/p' "$0" | sed 's/^# \?//'
            exit 0
            ;;
        *)
            printf 'check-ledger-hygiene.sh: unknown arg %q\n' "$1" >&2
            exit 2
            ;;
    esac
done

if ! command -v jq >/dev/null 2>&1; then
    printf 'check-ledger-hygiene.sh: jq is required\n' >&2
    exit 2
fi
COST_LEDGER="$ROOT/cost-ledger.jsonl"
MODELINV_LOG="$ROOT/model-invoke.jsonl"

if [[ ! -d "$ROOT" ]]; then
    if [[ $ROOT_EXPLICIT -eq 1 ]]; then
        printf 'check-ledger-hygiene.sh: scan root %q not a directory\n' "$ROOT" >&2
        exit 2
    fi
    # Default .run/ is gitignored and may not exist yet (fresh checkout, CI
    # runner where every harness stayed isolated): nothing to scan, said out
    # loud rather than a silent pass.
    printf 'SKIP: %s absent (nothing scanned)\n' "$COST_LEDGER" >&2
    printf 'SKIP: %s absent (nothing scanned)\n' "$MODELINV_LOG" >&2
    [[ $QUIET -eq 0 ]] && printf 'OK — no test rows in 0 ledger(s) under %s\n' "$ROOT"
    exit 0
fi

# jq -R reads raw lines so one corrupt line cannot abort the scan;
# input_line_number keeps the report addressable.
JQ_MOCK_ROWS='input_line_number as $n
  | (fromjson? // empty)
  | select(type == "object")
  | select([.model, .agent, .provider] | map(tostring | startswith("mock-")) | any)
  | "\($n)"'

violations=""
scanned=0

if [[ -f "$COST_LEDGER" ]]; then
    if [[ ! -r "$COST_LEDGER" ]]; then
        printf 'check-ledger-hygiene.sh: cannot read %s\n' "$COST_LEDGER" >&2
        exit 2
    fi
    if ! hits=$(jq -Rr "$JQ_MOCK_ROWS" "$COST_LEDGER"); then
        printf 'check-ledger-hygiene.sh: jq failed scanning %s\n' "$COST_LEDGER" >&2
        exit 2
    fi
    while IFS= read -r n; do
        [[ -n "$n" ]] && violations+="$COST_LEDGER:$n: mock-* identity in .model/.agent/.provider"$'\n'
    done <<< "$hits"
    scanned=$((scanned + 1))
else
    printf 'SKIP: %s absent (nothing scanned)\n' "$COST_LEDGER" >&2
fi

if [[ -f "$MODELINV_LOG" ]]; then
    if [[ ! -r "$MODELINV_LOG" ]]; then
        printf 'check-ledger-hygiene.sh: cannot read %s\n' "$MODELINV_LOG" >&2
        exit 2
    fi
    # `cheval-e2e-` without the tmp root: macOS mkdtemp lives under /var/folders/.
    hits=$(grep -nF -- 'cheval-e2e-' "$MODELINV_LOG") && grep_rc=0 || grep_rc=$?
    if [[ "$grep_rc" -gt 1 ]]; then
        printf 'check-ledger-hygiene.sh: grep failed scanning %s\n' "$MODELINV_LOG" >&2
        exit 2
    fi
    while IFS= read -r line; do
        [[ -n "$line" ]] && violations+="$MODELINV_LOG:${line%%:*}: cheval-e2e-* fixture path in MODELINV row"$'\n'
    done <<< "$hits"
    scanned=$((scanned + 1))
else
    printf 'SKIP: %s absent (nothing scanned)\n' "$MODELINV_LOG" >&2
fi

if [[ -n "$violations" ]]; then
    if [[ $QUIET -eq 0 ]]; then
        printf 'cycle-124 FR-6: test rows detected in production ledgers under %s\n' "$ROOT" >&2
        printf 'A test harness reached cheval dispatch without LOA_COST_LEDGER_PATH / LOA_MODELINV_LOG_PATH.\n' >&2
        printf 'Fix the harness (see .claude/adapters/tests/conftest.py and tests/unit/ledger-isolation-discovery.bats),\n' >&2
        printf 'then rotate — never edit — per grimoires/loa/runbooks/ledger-hygiene-rotation.md.\n' >&2
        printf '\nViolations:\n' >&2
        printf '%s' "$violations" >&2
    fi
    exit 1
fi

[[ $QUIET -eq 0 ]] && printf 'OK — no test rows in %d ledger(s) under %s\n' "$scanned" "$ROOT"
exit 0
