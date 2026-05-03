#!/usr/bin/env bash
# =============================================================================
# panel-distribution-audit.sh — FR-L1-8 selection-seed distribution audit
#
# cycle-098 Sprint 1D — walks the L1 panel-decisions audit log over a 30-day
# window, counts selections per panelist, and reports concentration.
# Exits non-zero when N≥10 decisions AND any panelist >50% selection rate.
#
# When N<10, exits 0 (telemetry threshold not met).
# When the log file is missing, exits 0 (no decisions to audit).
#
# Usage:
#   panel-distribution-audit.sh [--log <path>] [--window-days N] [--json]
#
# Options:
#   --log <path>          path to L1 panel-decisions log (default
#                         .run/panel-decisions.jsonl)
#   --window-days <N>     window in days (default 30)
#   --json                emit a structured JSON report instead of markdown
#
# Exit codes:
#   0 — no concentration breach (or N<10, or no log)
#   1 — N≥10 AND ≥1 panelist >50% selection rate
#   2 — invalid arguments
# =============================================================================

set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_REPO_ROOT="$(cd "${_SCRIPT_DIR}/.." && pwd)"

LOG_PATH=""
WINDOW_DAYS=30
JSON_MODE=0

_usage() {
    cat <<'USAGE'
panel-distribution-audit.sh — FR-L1-8 selection-seed distribution audit

Usage:
  panel-distribution-audit.sh [--log <path>] [--window-days N] [--json]

Options:
  --log <path>          path to panel-decisions.jsonl (default .run/panel-decisions.jsonl)
  --window-days <N>     window size in days (default 30)
  --json                emit JSON report instead of markdown

Exit codes:
  0 — no concentration breach (or N<10, or no log)
  1 — N≥10 AND any panelist >50% selection rate
  2 — invalid arguments
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --log)
            LOG_PATH="$2"
            shift 2
            ;;
        --window-days)
            WINDOW_DAYS="$2"
            shift 2
            ;;
        --json)
            JSON_MODE=1
            shift
            ;;
        --help|-h)
            _usage
            exit 0
            ;;
        *)
            echo "panel-distribution-audit: unknown argument '$1'" >&2
            _usage >&2
            exit 2
            ;;
    esac
done

if [[ -z "$LOG_PATH" ]]; then
    LOG_PATH="${_REPO_ROOT}/.run/panel-decisions.jsonl"
fi

# Numeric guard.
case "$WINDOW_DAYS" in
    ''|*[!0-9]*)
        echo "panel-distribution-audit: --window-days must be a positive integer" >&2
        exit 2
        ;;
esac

# Missing log → graceful no-op.
if [[ ! -f "$LOG_PATH" ]]; then
    if [[ "$JSON_MODE" -eq 1 ]]; then
        jq -nc \
            --argjson w "$WINDOW_DAYS" \
            '{
                window_days:$w,
                total_decisions:0,
                distribution:{},
                violations:[],
                threshold_n:10,
                threshold_max_pct:50.0,
                note:"log file missing"
            }'
    else
        echo "## L1 Panel Distribution Audit"
        echo
        echo "Log file not found: $LOG_PATH"
        echo "No decisions to audit."
    fi
    exit 0
fi

# ---- Aggregation (Python) ---------------------------------------------------
# We delegate the per-line filter + counter aggregation to a Python helper so
# the date-window arithmetic and ordered-dict traversal are uniform across
# Linux + macOS.
LOA_DA_LOG="$LOG_PATH" \
LOA_DA_WINDOW="$WINDOW_DAYS" \
python3 - <<'PY' > /tmp/panel-distribution-audit-result.$$ 2>&1
import json
import os
import sys
from collections import OrderedDict
from datetime import datetime, timedelta, timezone

log_path = os.environ["LOA_DA_LOG"]
window_days = int(os.environ["LOA_DA_WINDOW"])
threshold_n = 10
threshold_pct = 50.0  # exclusive: strictly >50% trips the violation

cutoff = datetime.now(timezone.utc) - timedelta(days=window_days)

counts = OrderedDict()  # preserves first-seen order for stable output
total = 0

def parse_ts(ts):
    """Parse ISO-8601 UTC timestamp tolerantly (Z suffix or +00:00)."""
    s = ts.replace("Z", "+00:00")
    try:
        return datetime.fromisoformat(s)
    except Exception:
        return None

with open(log_path) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        # Skip non-JSON marker lines (e.g. [CHAIN-RECOVERED ...]).
        if not line.startswith("{"):
            continue
        try:
            entry = json.loads(line)
        except json.JSONDecodeError:
            continue

        if entry.get("event_type") != "panel.bind":
            continue
        if entry.get("primitive_id") != "L1":
            continue

        ts = parse_ts(entry.get("ts_utc", ""))
        if ts is None or ts < cutoff:
            continue

        payload = entry.get("payload") or {}
        sel = payload.get("selected_panelist_id")
        if not sel or not isinstance(sel, str):
            continue

        counts[sel] = counts.get(sel, 0) + 1
        total += 1

# Compute distribution as percentages.
distribution = OrderedDict()
violations = []
for pid, c in counts.items():
    pct = (c / total * 100.0) if total else 0.0
    distribution[pid] = {
        "count": c,
        "percentage": round(pct, 2)
    }
    if total >= threshold_n and pct > threshold_pct:
        violations.append({
            "panelist_id": pid,
            "count": c,
            "percentage": round(pct, 2),
            "reason": ">50% selection rate"
        })

result = {
    "window_days": window_days,
    "total_decisions": total,
    "distribution": distribution,
    "violations": violations,
    "threshold_n": threshold_n,
    "threshold_max_pct": threshold_pct
}
print(json.dumps(result))
PY
PY_EXIT=$?

if [[ "$PY_EXIT" -ne 0 ]]; then
    echo "panel-distribution-audit: aggregation helper failed (exit=$PY_EXIT)" >&2
    cat /tmp/panel-distribution-audit-result.$$ >&2
    rm -f /tmp/panel-distribution-audit-result.$$
    exit 2
fi

REPORT_JSON=$(cat /tmp/panel-distribution-audit-result.$$)
rm -f /tmp/panel-distribution-audit-result.$$

# ---- Output -----------------------------------------------------------------
if [[ "$JSON_MODE" -eq 1 ]]; then
    echo "$REPORT_JSON"
else
    total_decisions=$(printf '%s' "$REPORT_JSON" | jq -r '.total_decisions')
    threshold_n=$(printf '%s' "$REPORT_JSON" | jq -r '.threshold_n')
    threshold_pct=$(printf '%s' "$REPORT_JSON" | jq -r '.threshold_max_pct')
    n_violations=$(printf '%s' "$REPORT_JSON" | jq -r '.violations | length')

    echo "## L1 Panel Distribution Audit"
    echo
    echo "- **Log**: $LOG_PATH"
    echo "- **Window**: ${WINDOW_DAYS}d"
    echo "- **Total decisions** (panel.bind): $total_decisions"
    echo "- **Threshold**: N≥${threshold_n} AND any panelist >${threshold_pct}%"
    echo

    if [[ "$total_decisions" -eq 0 ]]; then
        echo "No panel.bind decisions in window. Nothing to audit."
    else
        echo "### Distribution"
        echo
        printf '%s' "$REPORT_JSON" | jq -r '
            .distribution
            | to_entries
            | sort_by(-.value.count)
            | map("- `\(.key)`: \(.value.count) (\(.value.percentage)%)")
            | join("\n")
        '
        echo
    fi

    if [[ "$n_violations" -gt 0 ]]; then
        echo "### Violations (>${threshold_pct}% with N≥${threshold_n})"
        echo
        printf '%s' "$REPORT_JSON" | jq -r '
            .violations
            | map("- **\(.panelist_id)**: \(.count) selections (\(.percentage)%) — \(.reason)")
            | join("\n")
        '
        echo
    fi
fi

# ---- Exit ------------------------------------------------------------------
total_decisions=$(printf '%s' "$REPORT_JSON" | jq -r '.total_decisions')
n_violations=$(printf '%s' "$REPORT_JSON" | jq -r '.violations | length')

# When N<threshold_n, never trip. When N≥threshold_n, exit 1 on violations.
if [[ "$total_decisions" -lt 10 ]]; then
    exit 0
fi
if [[ "$n_violations" -gt 0 ]]; then
    exit 1
fi
exit 0
