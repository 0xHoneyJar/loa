#!/usr/bin/env bash
# =============================================================================
# tools/cycle-baseline-capture.sh — cycle-109 Sprint 1 T1.10
#
# Captures the 7 PRD §3.4 IMP-003 baselines to a TRACKED `baselines/`
# directory so cycle-110 can retrospectively compare cycle-109 outcomes
# against pre-cycle state. Each baseline lands as a JSON file (except
# operator-self-rating which is markdown — operators fill in at
# cycle-close).
#
# Baselines:
#   1. issue-counts.json          OPEN substrate-labeled issues (gh)
#   2. kf-recurrence.json         KF-002 recurrence count from known-failures.md
#   3. clean-fp-rate.json         "status: clean" + voices_failed > 0 rate
#                                 from MODELINV replay
#   4. legacy-loc.json            wc -l on model-adapter.sh.legacy
#   5. modelinv-coverage.json     cycle-108 T2.M envelope coverage (30d window)
#   6. issue-rate.json            substrate-issue creation rate (gh)
#   7. operator-self-rating.md    operator-attention-tax markdown template
#
# Substrate-degraded posture: gh-dependent baselines (1, 6) mark
# `skipped:gh-unavailable` when gh isn't reachable OR when --skip-gh is
# passed. modelinv-coverage falls back to a stub when the cycle-108
# tool can't run.
#
# Idempotent: numeric values stable across runs given the same inputs.
# The `captured_at` timestamp updates every run by design (provenance).
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

# Defaults (operators override via flags).
BASELINES_DIR="${PROJECT_ROOT}/grimoires/loa/cycles/cycle-109-substrate-hardening/baselines"
KNOWN_FAILURES="${PROJECT_ROOT}/grimoires/loa/known-failures.md"
LEGACY_ADAPTER="${PROJECT_ROOT}/.claude/scripts/model-adapter.sh.legacy"
MODELINV_LOG="${PROJECT_ROOT}/.run/model-invoke.jsonl"
COVERAGE_TOOL="${PROJECT_ROOT}/tools/modelinv-coverage-audit.py"
SKIP_GH=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --baselines-dir) BASELINES_DIR="$2"; shift 2 ;;
        --known-failures) KNOWN_FAILURES="$2"; shift 2 ;;
        --legacy-adapter) LEGACY_ADAPTER="$2"; shift 2 ;;
        --modelinv-log) MODELINV_LOG="$2"; shift 2 ;;
        --coverage-tool) COVERAGE_TOOL="$2"; shift 2 ;;
        --skip-gh) SKIP_GH=true; shift ;;
        -h|--help)
            sed -n '/^# =/,/^# =/p' "$0" | head -60
            exit 0
            ;;
        *)
            echo "[baseline-capture] ERROR: unknown arg: $1" >&2
            exit 2
            ;;
    esac
done

mkdir -p "$BASELINES_DIR"

# Use Python for JSON construction — avoids jq dependency.
if [[ -x "$PROJECT_ROOT/.venv/bin/python" ]]; then
    PYTHON_BIN="$PROJECT_ROOT/.venv/bin/python"
else
    PYTHON_BIN="$(command -v python3)"
fi

# Common provenance fields injected into every JSON baseline.
NOW_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

# ---------------------------------------------------------------------------
# 1. issue-counts.json — OPEN substrate-labeled issues (gh)
# ---------------------------------------------------------------------------
{
    if $SKIP_GH; then
        cat <<JSON
{
  "baseline": "issue-counts",
  "outcome": "skipped:gh-unavailable",
  "reason": "--skip-gh flag set",
  "open_substrate_count": null,
  "captured_at": "$NOW_UTC"
}
JSON
    elif command -v gh >/dev/null 2>&1; then
        # Capture count; fall back to skipped on gh failure (e.g. no auth).
        if count="$(gh issue list --label substrate --state open --limit 1000 --json number 2>/dev/null | "$PYTHON_BIN" -c 'import json,sys; print(len(json.load(sys.stdin)))' 2>/dev/null)"; then
            cat <<JSON
{
  "baseline": "issue-counts",
  "outcome": "captured",
  "open_substrate_count": $count,
  "captured_at": "$NOW_UTC"
}
JSON
        else
            cat <<JSON
{
  "baseline": "issue-counts",
  "outcome": "skipped:gh-unavailable",
  "reason": "gh issue list failed (auth or network)",
  "open_substrate_count": null,
  "captured_at": "$NOW_UTC"
}
JSON
        fi
    else
        cat <<JSON
{
  "baseline": "issue-counts",
  "outcome": "skipped:gh-unavailable",
  "reason": "gh CLI not installed",
  "open_substrate_count": null,
  "captured_at": "$NOW_UTC"
}
JSON
    fi
} > "$BASELINES_DIR/issue-counts.json"

# ---------------------------------------------------------------------------
# 2. kf-recurrence.json — KF-002 recurrence count
# ---------------------------------------------------------------------------
"$PYTHON_BIN" - <<PY > "$BASELINES_DIR/kf-recurrence.json"
import json
import re
from pathlib import Path

path = Path(r"$KNOWN_FAILURES")
recurrence = None
status = None
if path.is_file():
    text = path.read_text(encoding="utf-8")
    # Find the KF-002 entry block.
    m = re.search(r"^## KF-002:[\s\S]*?(?=^## KF-|\Z)", text, re.MULTILINE)
    if m:
        block = m.group(0)
        rc_match = re.search(r"\*\*Recurrence count\*\*[ \t]*:[ \t]*([^\n]+)", block)
        if rc_match:
            raw = rc_match.group(1).strip()
            digits = re.search(r"\d+", raw)
            if digits:
                recurrence = int(digits.group(0))
        st_match = re.search(r"\*\*Status\*\*[ \t]*:[ \t]*([^\n]+)", block)
        if st_match:
            status = st_match.group(1).strip()

payload = {
    "baseline": "kf-recurrence",
    "outcome": "captured" if recurrence is not None else "skipped:kf-002-not-found",
    "kf_id": "KF-002",
    "recurrence_count": recurrence,
    "status_raw": status,
    "source": str(path),
    "captured_at": "$NOW_UTC",
}
print(json.dumps(payload, indent=2))
PY

# ---------------------------------------------------------------------------
# 3. clean-fp-rate.json — "status: clean" + voices_failed > 0 from MODELINV
# ---------------------------------------------------------------------------
"$PYTHON_BIN" - <<PY > "$BASELINES_DIR/clean-fp-rate.json"
import json
from pathlib import Path

path = Path(r"$MODELINV_LOG")
total = 0
clean_with_failed = 0
if path.is_file():
    with path.open("r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
            except json.JSONDecodeError:
                continue
            payload = entry.get("payload", {})
            if not isinstance(payload, dict):
                continue
            total += 1
            failed = payload.get("models_failed", [])
            succeeded = payload.get("models_succeeded", [])
            # A "clean" emission is one where operator_visible_warn is False
            # AND there's at least one failed voice — the cycle-109 FR-2
            # target failure mode.
            warn = payload.get("operator_visible_warn", False)
            if (not warn) and isinstance(failed, list) and len(failed) > 0:
                clean_with_failed += 1

rate = (clean_with_failed / total) if total > 0 else None
payload = {
    "baseline": "clean-fp-rate",
    "outcome": "captured" if total > 0 else "skipped:no-entries",
    "false_positive_count": clean_with_failed,
    "total_entries": total,
    "clean_fp_rate": rate,
    "source": str(path),
    "captured_at": "$NOW_UTC",
}
print(json.dumps(payload, indent=2))
PY

# ---------------------------------------------------------------------------
# 4. legacy-loc.json — wc -l on model-adapter.sh.legacy
# ---------------------------------------------------------------------------
{
    if [[ -f "$LEGACY_ADAPTER" ]]; then
        line_count="$(wc -l < "$LEGACY_ADAPTER" | tr -d '[:space:]')"
        cat <<JSON
{
  "baseline": "legacy-loc",
  "outcome": "captured",
  "line_count": $line_count,
  "source": "$LEGACY_ADAPTER",
  "captured_at": "$NOW_UTC"
}
JSON
    else
        cat <<JSON
{
  "baseline": "legacy-loc",
  "outcome": "skipped:adapter-not-found",
  "line_count": 0,
  "source": "$LEGACY_ADAPTER",
  "captured_at": "$NOW_UTC"
}
JSON
    fi
} > "$BASELINES_DIR/legacy-loc.json"

# ---------------------------------------------------------------------------
# 5. modelinv-coverage.json — cycle-108 T2.M tool (30d window)
# ---------------------------------------------------------------------------
{
    if [[ -x "$COVERAGE_TOOL" ]] || [[ -f "$COVERAGE_TOOL" ]]; then
        # Best-effort; tool may require network / database access we can't
        # provide under the substrate-degraded posture. Fall back to
        # stub on any non-zero exit.
        if coverage="$("$PYTHON_BIN" "$COVERAGE_TOOL" --window 30d --json 2>/dev/null)"; then
            cat <<JSON
{
  "baseline": "modelinv-coverage",
  "outcome": "captured",
  "tool_output": $coverage,
  "captured_at": "$NOW_UTC"
}
JSON
        else
            cat <<JSON
{
  "baseline": "modelinv-coverage",
  "outcome": "skipped:tool-unavailable",
  "reason": "modelinv-coverage-audit.py failed or unreachable",
  "captured_at": "$NOW_UTC"
}
JSON
        fi
    else
        cat <<JSON
{
  "baseline": "modelinv-coverage",
  "outcome": "skipped:tool-unavailable",
  "reason": "modelinv-coverage-audit.py not found",
  "captured_at": "$NOW_UTC"
}
JSON
    fi
} > "$BASELINES_DIR/modelinv-coverage.json"

# ---------------------------------------------------------------------------
# 6. issue-rate.json — substrate-issue creation rate
# ---------------------------------------------------------------------------
{
    if $SKIP_GH; then
        cat <<JSON
{
  "baseline": "issue-rate",
  "outcome": "skipped:gh-unavailable",
  "reason": "--skip-gh flag set",
  "issues_created_window": null,
  "window_start": null,
  "window_end": "$NOW_UTC",
  "captured_at": "$NOW_UTC"
}
JSON
    elif command -v gh >/dev/null 2>&1; then
        # Baseline window: post-cycle-108 close (2026-05-09) through now.
        if count="$(gh issue list --label substrate --search 'created:>=2026-05-09' --limit 1000 --json number 2>/dev/null | "$PYTHON_BIN" -c 'import json,sys; print(len(json.load(sys.stdin)))' 2>/dev/null)"; then
            cat <<JSON
{
  "baseline": "issue-rate",
  "outcome": "captured",
  "issues_created_window": $count,
  "window_start": "2026-05-09",
  "window_end": "$NOW_UTC",
  "captured_at": "$NOW_UTC"
}
JSON
        else
            cat <<JSON
{
  "baseline": "issue-rate",
  "outcome": "skipped:gh-unavailable",
  "reason": "gh issue list failed",
  "issues_created_window": null,
  "window_start": "2026-05-09",
  "window_end": "$NOW_UTC",
  "captured_at": "$NOW_UTC"
}
JSON
        fi
    else
        cat <<JSON
{
  "baseline": "issue-rate",
  "outcome": "skipped:gh-unavailable",
  "reason": "gh CLI not installed",
  "issues_created_window": null,
  "window_start": "2026-05-09",
  "window_end": "$NOW_UTC",
  "captured_at": "$NOW_UTC"
}
JSON
    fi
} > "$BASELINES_DIR/issue-rate.json"

# ---------------------------------------------------------------------------
# 7. operator-self-rating.md — operator-attention-tax template
# ---------------------------------------------------------------------------
{
    cat <<'MD'
# Operator-attention-tax baseline (PRD §3.4 IMP-003)

> Self-rating on a 1-10 scale of how much headspace cycle-109 multi-model
> substrate consumes RIGHT NOW. The cycle-109 close re-measurement will
> compare against this baseline. Subjective by design — operator
> intuition is the load-bearing signal.

## Cycle kickoff baseline (2026-05-13)

| Field | Value |
|-------|-------|
| Rating (1-10) | _OPERATOR — fill in_ |
| One-line context | _OPERATOR — fill in_ |
| Notable pain points | _OPERATOR — bullet list_ |

## Cycle close re-measurement

| Field | Value |
|-------|-------|
| Rating (1-10) | _to be filled at cycle close_ |
| Delta from baseline | _to be computed at cycle close_ |
| One-line context | _to be filled at cycle close_ |

## Notes

This file is TRACKED in git. Operator fills it in via PR alongside the
cycle-109 sprint-1 debrief (T1.11) and re-measures at cycle close.
MD
} > "$BASELINES_DIR/operator-self-rating.md"

echo "[baseline-capture] wrote 7 baselines to $BASELINES_DIR"
