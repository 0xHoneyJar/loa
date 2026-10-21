#!/usr/bin/env bash
# =============================================================================
# spend.sh — cycle-130 cycle spend (SDD §5.11, PRD FR-2, DEC-0363)
#
# Prints what the cycle has spent: the run rows' cost_usd and the operator
# cost ledger's cost_micro_usd, both since the kickoff timestamp, against the cap.
#
# Usage:
#   spend.sh [--since TS] [--runs FILE…] [--ledger FILE] [--cap USD]
#            [--reserve USD] [--json]
#
#   --since TS     ledger rows with ts >= TS count (default 2026-10-14T13:50:00Z,
#                  the cycle-130 kickoff), and so do run rows whose `started` (else
#                  `finished`) is >= TS (cycle-132: the run-row files hold every
#                  earlier cycle's rows too); a run row with neither timestamp, or one
#                  that does not parse, counts (the conservative side) with one stderr
#                  note per file naming the count
#   --runs FILE…   run-row files (JSONL, `cost_usd` per row); repeatable, and every
#                  following non-option argument is a file too. Default:
#                  grimoires/loa/reports/ablation-2.0/runs.jsonl plus every
#                  evals/results/ablation-2.0/*/rows.jsonl that exists. Each run_id
#                  counts once across files: a run rowed twice counts its larger cost
#                  (a smoke row, then the graded row). A row with an empty or missing
#                  run_id cannot be deduplicated and counts on its own (one stderr
#                  warning per file naming it).
#   --ledger FILE  cost ledger (JSONL, `ts`, `cost_micro_usd`; default .run/cost-ledger.jsonl)
#   --cap USD      cycle cap (default: evals.ablation.cycle_cap_usd in .loa.config.yaml,
#                  else caps.cycle_usd in evals/suites/ablation-2.0.yaml, else 1500)
#   --reserve USD  reserve (default caps.reserve_usd in the suite file, else 250)
#   --json         one JSON object: total_usd, runs_usd, ledger_usd, since, cap_usd,
#                  headroom_usd, reserve_usd, runs_files, ledger_file, runs_rows,
#                  runs_rows_deduped, runs_rows_no_run_id, runs_rows_before_since,
#                  runs_rows_undated, ledger_rows, skipped_lines,
#                  complete (false when any line was skipped)
#
# Output: cycle spend USD T (runs R + ledger L since S); cap C; headroom H; reserve V
#   headroom = cap - total (negative when over). Default files that do not exist
#   count as zero. A malformed line is skipped and counted (stderr note), and the
#   total is then a lower bound: the line gains " INCOMPLETE (N skipped)", --json
#   says "complete": false, and the exit is 1.
#
# Exit: 0 printed and complete; 1 a named file (or an existing default) is unreadable,
#   or the total is INCOMPLETE (a skipped line); 2 usage.
# Tested by evals/tests/spend.bats.
# =============================================================================
set -euo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SINCE="2026-10-14T13:50:00Z"
LEDGER="" CAP="" RESERVE="" JSON=false
RUNS=()

usage() { sed -n '2,/^# =====.*$/p' "$0" | sed -n '2,39p' | sed 's/^# \{0,1\}//' >&2; exit 2; }
die() { echo "spend: $*" >&2; exit 2; }
num_ok() { [[ "$1" =~ ^[0-9]+(\.[0-9]+)?$ ]]; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --since) SINCE="${2:-}"; shift 2 ;;
    --runs)
      [[ -n "${2:-}" && "${2:-}" != --* ]] || die "--runs needs at least one file"
      shift
      while [[ $# -gt 0 && "$1" != --* ]]; do RUNS+=("$1"); shift; done ;;
    --ledger) LEDGER="${2:-}"; [[ -n "$LEDGER" ]] || die "--ledger needs a file"; shift 2 ;;
    --cap) CAP="${2:-}"; shift 2 ;;
    --reserve) RESERVE="${2:-}"; shift 2 ;;
    --json) JSON=true; shift ;;
    --help|-h) usage ;;
    *) die "unknown option: $1 (see --help)" ;;
  esac
done
[[ "$SINCE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}(T[0-9]{2}:[0-9]{2}(:[0-9]{2}(\.[0-9]+)?)?(Z|[+-][0-9]{2}:[0-9]{2})?)?$ ]] \
  || die "--since must be an ISO-8601 timestamp (e.g. 2026-10-14T13:50:00Z)"
command -v python3 >/dev/null 2>&1 || die "missing tool: python3"

SUITE="$REPO_ROOT/evals/suites/ablation-2.0.yaml"
yq_num() {  # yq_num <expr> <file> — a number or empty
  local v
  [[ -f "$2" ]] && command -v yq >/dev/null 2>&1 || return 0
  v="$(yq -r "$1 // \"\"" "$2" 2>/dev/null || true)"
  num_ok "$v" && printf '%s' "$v"
  return 0
}
if [[ -z "$CAP" ]]; then
  CAP="$(yq_num '.evals.ablation.cycle_cap_usd' "$REPO_ROOT/.loa.config.yaml")"
  [[ -n "$CAP" ]] || CAP="$(yq_num '.caps.cycle_usd' "$SUITE")"
  [[ -n "$CAP" ]] || CAP=1500
fi
if [[ -z "$RESERVE" ]]; then
  RESERVE="$(yq_num '.caps.reserve_usd' "$SUITE")"
  [[ -n "$RESERVE" ]] || RESERVE=250
fi
num_ok "$CAP" || die "--cap must be a non-negative number"
num_ok "$RESERVE" || die "--reserve must be a non-negative number"

# Explicit files must be readable; defaults are optional (absent = zero).
if [[ ${#RUNS[@]} -eq 0 ]]; then
  [[ -e "$REPO_ROOT/grimoires/loa/reports/ablation-2.0/runs.jsonl" ]] && RUNS+=("$REPO_ROOT/grimoires/loa/reports/ablation-2.0/runs.jsonl")
  for f in "$REPO_ROOT"/evals/results/ablation-2.0/*/rows.jsonl; do [[ -e "$f" ]] && RUNS+=("$f"); done
fi
EXPLICIT_LEDGER=true
if [[ -z "$LEDGER" ]]; then
  EXPLICIT_LEDGER=false
  LEDGER="$REPO_ROOT/.run/cost-ledger.jsonl"
fi
for f in ${RUNS[@]+"${RUNS[@]}"}; do
  [[ -f "$f" && -r "$f" ]] || { echo "spend: run-row file unreadable: $f" >&2; exit 1; }
done
if [[ -e "$LEDGER" || "$EXPLICIT_LEDGER" == "true" ]]; then
  [[ -f "$LEDGER" && -r "$LEDGER" ]] || { echo "spend: ledger unreadable: $LEDGER" >&2; exit 1; }
else
  LEDGER=""
fi

python3 -I - "$SINCE" "$CAP" "$RESERVE" "$JSON" "$LEDGER" ${RUNS[@]+"${RUNS[@]}"} <<'PY'
import json, sys
from datetime import datetime, timezone

since_s, cap, reserve, as_json, ledger = sys.argv[1], float(sys.argv[2]), float(sys.argv[3]), sys.argv[4] == "true", sys.argv[5]
runs_files = sys.argv[6:]

def ts(s):
    s = s.strip()
    if len(s) == 10:
        s += "T00:00:00Z"
    d = datetime.fromisoformat(s.replace("Z", "+00:00"))
    return d if d.tzinfo else d.replace(tzinfo=timezone.utc)

since = ts(since_s)
skipped = 0
dedup, anon_rows, anon_usd = 0, 0, 0.0
before_since, undated = 0, 0
best = {}  # run_id -> the largest cost_usd seen for it (a re-rowed run counts its larger cost)
def row_ts(r):   # started, else finished; None when neither parses
    for k in ("started", "finished"):
        v = r.get(k)
        if isinstance(v, str) and v.strip():
            try:
                return ts(v)
            except ValueError:
                return None
    return None
for f in runs_files:
    anon_here = undated_here = 0
    for line in open(f, encoding="utf-8", errors="replace"):
        if not line.strip():
            continue
        try:
            r = json.loads(line)
            c = float(r.get("cost_usd") or 0)
        except (ValueError, TypeError, AttributeError):
            skipped += 1
            continue
        t = row_ts(r)
        if t is None:
            undated += 1
            undated_here += 1
        elif t < since:
            before_since += 1
            continue
        rid = r.get("run_id")
        if not (isinstance(rid, str) and rid):
            anon_rows += 1
            anon_here += 1
            anon_usd += c
            continue
        if rid in best:
            dedup += 1
            best[rid] = max(best[rid], c)
        else:
            best[rid] = c
    if anon_here:
        print(f"spend: {f}: {anon_here} row(s) without a run_id counted individually (no dedup possible)", file=sys.stderr)
    if undated_here:
        print(f"spend: {f}: {undated_here} row(s) with no started/finished timestamp counted (no date to compare with --since)", file=sys.stderr)
runs_usd = sum(best.values()) + anon_usd
runs_rows = len(best) + anon_rows

ledger_usd, ledger_rows = 0.0, 0
if ledger:
    for line in open(ledger, encoding="utf-8", errors="replace"):
        if not line.strip():
            continue
        try:
            r = json.loads(line)
            if ts(str(r["ts"])) < since:
                continue
            ledger_usd += float(r.get("cost_micro_usd") or 0) / 1e6
            ledger_rows += 1
        except (ValueError, TypeError, KeyError, AttributeError):
            skipped += 1

total = runs_usd + ledger_usd
headroom = cap - total
if skipped:
    print(f"spend: skipped {skipped} malformed line(s)", file=sys.stderr)
def n(x):
    x = round(x, 4)
    return int(x) if x == int(x) else x
if as_json:
    print(json.dumps({
        "total_usd": n(total), "runs_usd": n(runs_usd), "ledger_usd": n(ledger_usd),
        "since": since_s, "cap_usd": n(cap), "headroom_usd": n(headroom), "reserve_usd": n(reserve),
        "runs_files": runs_files, "ledger_file": ledger or None, "runs_rows": runs_rows,
        "runs_rows_deduped": dedup, "runs_rows_no_run_id": anon_rows, "runs_rows_before_since": before_since,
        "runs_rows_undated": undated, "ledger_rows": ledger_rows,
        "skipped_lines": skipped, "complete": skipped == 0}, sort_keys=True))
else:
    def money(x): return f"{x:,.2f}"
    def whole(x): return f"{x:,.0f}" if x == int(x) else f"{x:,.2f}"
    print(f"cycle spend USD {money(total)} (runs {money(runs_usd)} + ledger {money(ledger_usd)} since {since_s}); "
          f"cap {whole(cap)}; headroom {money(headroom)}; reserve {whole(reserve)}"
          + (f" INCOMPLETE ({skipped} skipped)" if skipped else ""))
sys.exit(1 if skipped else 0)
PY
