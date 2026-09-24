#!/usr/bin/env bash
# =============================================================================
# cost-report.sh — Read JSONL ledger and generate markdown cost summary
# =============================================================================
# Part of: Hounfour Upstream Extraction (Sprint 3)
#
# Usage:
#   cost-report.sh [--ledger <path>] [--days N] [--json] [--include-legacy] [--migrate-legacy]
#                  [--window-day YYYY-MM-DD] [--reprice [--dry-run]]
#
# Options:
#   --ledger <path>    Path to cost ledger JSONL (default: the writer's own resolution —
#                      $LOA_COST_LEDGER_PATH, else metering.ledger_path from the
#                      merged config, else .run/cost-ledger.jsonl at the project root)
#   --days <n>         Report period in days (default: 30)
#   --json             Output as JSON instead of markdown
#   --top <n>          Show top N most expensive invocations (default: 5)
#   --include-legacy   Also read the pre-2.0 ledger grimoires/loa/a2a/cost-ledger.jsonl
#                      (rows tagged legacy: true in the report; the file is not changed)
#   --migrate-legacy   Append the legacy rows not yet present (by request_id) to the
#                      current ledger THROUGH the resolver-validated writer
#                      (loa_cheval.metering.ledger.append_ledger: O_NOFOLLOW, refusals
#                      intact), each tagged legacy: true, and write the receipt
#                      .run/cost-ledger-migration-<UTC>.json (paths, counts, sha256s —
#                      never row contents). Idempotent: a second run migrates 0.
#   --legacy-ledger <path>  Override the legacy path (default above)
#   --window-day YYYY-MM-DD  Also report that UTC day's rows and unpriced share as a
#                      `window` object next to the all-time fields (sprint-bug-245:
#                      the budget enforcer measures the day it certifies)
#   --reprice          Explicit, opt-in re-pricing of the historical unpriced rows the
#                      pricing ladder can now resolve (pricing_source unknown, or absent
#                      at cost 0): each changed row is priced as a fresh row with the same
#                      tokens and marked repriced_at / repriced_from / cost_estimated;
#                      priced and unresolvable rows and corrupt lines are kept byte-for-byte;
#                      a symlinked ledger is refused; the pass holds the writer's own lock
#                      (flock on the ledger inode) from read to last byte and rewrites the
#                      SAME inode in place, so a live append blocks and then lands after it;
#                      the bytes read are first copied to <ledger>.pre-reprice-<UTC>
#                      (O_EXCL|O_NOFOLLOW, fsynced) — the crash-recovery point;
#                      receipt .run/cost-ledger-reprice-<UTC>.json (counts, sha256s —
#                      never row contents). Idempotent: a second run re-prices 0.
#   --dry-run          With --reprice: report what would change, write nothing
#
# Every report prints "Unpriced rows: N (S %)" — rows whose pricing_source is
# `unknown` (cost recorded as 0, NOT as a price); JSON: unpriced_rows,
# unpriced_share (0..1), and per-row pricing_resolution counts (cycle-125 FR-5).
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Default — resolved AFTER argument parsing (an explicit --ledger never
# consults the resolver) by the writer's own resolver (cycle-124 FR-6):
# LOA_COST_LEDGER_PATH > merged metering.ledger_path > .run/cost-ledger.jsonl,
# anchored at the project root. Fail-closed like the writer (round-2 dissent
# DISS-001): a path the resolver refuses is an error here, not a silent read
# of some other file; only an UNAVAILABLE substrate falls back to the literal.
if [[ -x "${PROJECT_ROOT}/.venv/bin/python" ]]; then
    _PYTHON_BIN="${PROJECT_ROOT}/.venv/bin/python"
else
    _PYTHON_BIN="$(command -v python3 || true)"
fi
# exit 0 + path · 3 = resolver refused (message on stderr) · 4 = substrate unavailable
# No `cd`: a relative LOA_COST_LEDGER_PATH is CWD-relative for the writer and
# must be for the reader too (Sprint 1 audit, slice B).
_resolve_default_ledger() {
    PYTHONPATH="${PROJECT_ROOT}/.claude/adapters${PYTHONPATH:+:$PYTHONPATH}" "${_PYTHON_BIN}" - <<'PY'
import sys
try:
    from loa_cheval.metering.rollup import default_ledger_path
    from loa_cheval.types import ConfigError
except Exception:
    sys.exit(4)
try:
    print(default_ledger_path())
except ConfigError as e:
    print(f"cost-report: {e.code}: {e}", file=sys.stderr)
    sys.exit(3)
PY
}
LEDGER_PATH=""
REPORT_DAYS=30
OUTPUT_JSON=false
TOP_N=5
INCLUDE_LEGACY=false
MIGRATE_LEGACY=false
LEGACY_LEDGER="${PROJECT_ROOT}/grimoires/loa/a2a/cost-ledger.jsonl"
WINDOW_DAY=""
REPRICE=false
REPRICE_DRY_RUN=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --ledger)
            LEDGER_PATH="$2"
            shift 2
            ;;
        --include-legacy)
            INCLUDE_LEGACY=true
            shift
            ;;
        --migrate-legacy)
            MIGRATE_LEGACY=true
            INCLUDE_LEGACY=true
            shift
            ;;
        --legacy-ledger)
            LEGACY_LEDGER="$2"
            shift 2
            ;;
        --window-day)
            WINDOW_DAY="${2:-}"
            shift 2
            ;;
        --reprice)
            REPRICE=true
            shift
            ;;
        --dry-run)
            REPRICE_DRY_RUN=true
            shift
            ;;
        --days)
            REPORT_DAYS="$2"
            shift 2
            ;;
        --json)
            OUTPUT_JSON=true
            shift
            ;;
        --top)
            TOP_N="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: cost-report.sh [--ledger <path>] [--days N] [--json] [--top N] [--include-legacy] [--migrate-legacy] [--legacy-ledger <path>] [--window-day YYYY-MM-DD] [--reprice [--dry-run]]"
            exit 0
            ;;
        *)
            echo "ERROR: Unknown option: $1" >&2
            exit 2
            ;;
    esac
done

if [[ -n "$WINDOW_DAY" && ! "$WINDOW_DAY" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    echo "ERROR: --window-day expects a UTC day as YYYY-MM-DD (got: ${WINDOW_DAY})" >&2
    exit 2
fi

if [[ -z "$LEDGER_PATH" ]]; then
    if LEDGER_PATH="$(_resolve_default_ledger)"; then
        :
    else
        _rc=$?
        if [[ "$_rc" -eq 3 ]]; then
            echo "ERROR: cost ledger path rejected by the resolver (see message above); pass --ledger <path> to read another file" >&2
            exit 2
        fi
        # Substrate unavailable: only an explicit env redirect is trustworthy;
        # guessing .run/ would report another file's numbers.
        if [[ -n "${LOA_COST_LEDGER_PATH:-}" ]]; then
            LEDGER_PATH="$LOA_COST_LEDGER_PATH"
        else
            echo "ERROR: cannot resolve the cost ledger (the cheval Python substrate is unavailable); pass --ledger <path> or set LOA_COST_LEDGER_PATH" >&2
            exit 2
        fi
    fi
fi

# Check ledger exists
# --- cycle-125 FR-5: legacy ledger migration (before the report reads) ------
# Appends legacy rows not yet present (by request_id) to the current ledger
# through the resolver-validated writer, tags them legacy: true, and writes a
# receipt with paths, counts and sha256s — never row contents. Idempotent.
if [[ "$MIGRATE_LEGACY" == "true" ]]; then
    if [[ ! -f "$LEGACY_LEDGER" ]]; then
        echo "ERROR: --migrate-legacy: legacy ledger not found at ${LEGACY_LEDGER}" >&2
        exit 2
    fi
    [[ -n "$_PYTHON_BIN" ]] || { echo "ERROR: --migrate-legacy needs the cheval Python substrate (python3)" >&2; exit 2; }
    _receipt_dir="${LOA_RUN_DIR:-${PROJECT_ROOT}/.run}"
    mkdir -p "$_receipt_dir"
    PYTHONPATH="${PROJECT_ROOT}/.claude/adapters" "$_PYTHON_BIN" - "$LEGACY_LEDGER" "$LEDGER_PATH" "$_receipt_dir" <<'PYMIG'
import hashlib, json, os, sys, time
legacy_path, target_path, receipt_dir = sys.argv[1], sys.argv[2], sys.argv[3]
from loa_cheval.metering.ledger import append_ledger  # resolver-validated writer (O_NOFOLLOW)

def sha256(path):
    h = hashlib.sha256()
    if os.path.isfile(path):
        with open(path, "rb") as fh:
            for chunk in iter(lambda: fh.read(1 << 20), b""):
                h.update(chunk)
    return h.hexdigest()

def rows(path):
    out, bad = [], 0
    if not os.path.isfile(path):
        return out, bad
    with open(path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                out.append(json.loads(line))
            except json.JSONDecodeError:
                bad += 1
    return out, bad

legacy, legacy_bad = rows(legacy_path)
current, _ = rows(target_path)

def row_key(r):
    """request_id when the row has one; else a content key so rows written
    before request ids existed still migrate exactly once."""
    rid = r.get("request_id")
    if rid:
        return "id:" + str(rid)
    core = {k: r.get(k) for k in ("ts", "trace_id", "agent", "provider", "model", "tokens_in", "tokens_out", "cost_micro_usd")}
    return "ck:" + hashlib.sha256(json.dumps(core, sort_keys=True).encode("utf-8")).hexdigest()

present = {row_key(r) for r in current}
sha_before = sha256(target_path)
migrated = skipped = 0
for r in legacy:
    key = row_key(r)
    if key in present:
        skipped += 1
        continue
    entry = dict(r)
    entry["legacy"] = True
    entry.setdefault("legacy_source", os.path.basename(legacy_path))
    append_ledger(entry, target_path)
    present.add(key)
    migrated += 1
ts = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())
receipt = {
    "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "source": legacy_path, "target": target_path,
    "rows_legacy": len(legacy), "rows_migrated": migrated, "rows_skipped_duplicate": skipped,
    "rows_legacy_corrupt": legacy_bad,
    "sha256_source": sha256(legacy_path), "sha256_target_before": sha_before, "sha256_target_after": sha256(target_path),
    "writer": "loa_cheval.metering.ledger.append_ledger",
}
from loa_cheval.metering.reprice import write_receipt  # O_EXCL|O_NOFOLLOW temp, renamed into place (audit F-4)
receipt_path = write_receipt(receipt_dir, f"cost-ledger-migration-{ts}", receipt)
print(f"cost-report: migrated {migrated} legacy row(s) ({skipped} already present) → {target_path}; receipt {receipt_path}", file=sys.stderr)
PYMIG
    _mig_rc=$?
    if [[ $_mig_rc -ne 0 ]]; then
        echo "ERROR: --migrate-legacy failed (exit $_mig_rc); the current ledger was only ever appended through the writer" >&2
        exit "$_mig_rc"
    fi
fi

# --- sprint-bug-245 (bead bd-ypbg): explicit re-pricing of historical unpriced rows
# Prices every unpriced row the ladder can now resolve exactly as a fresh row
# with the same tokens (loa_cheval.metering.reprice.reprice_ledger_file): holds
# the writer's flock on the ledger inode, copies the bytes read to a backup
# (O_EXCL|O_NOFOLLOW), rewrites the same inode in place with every other line
# byte-for-byte, and writes a receipt. Opt-in; --dry-run writes nothing.
if [[ "$REPRICE" == "true" ]]; then
    [[ -n "$_PYTHON_BIN" ]] || { echo "ERROR: --reprice needs the cheval Python substrate (python3)" >&2; exit 2; }
    if [[ -L "$LEDGER_PATH" ]]; then
        echo "ERROR: --reprice refuses a symlinked ledger (${LEDGER_PATH}); point --ledger at the real file" >&2
        exit 3
    fi
    if [[ ! -f "$LEDGER_PATH" ]]; then
        echo "ERROR: --reprice: no ledger at ${LEDGER_PATH}" >&2
        exit 2
    fi
    _receipt_dir="${LOA_RUN_DIR:-${PROJECT_ROOT}/.run}"
    [[ "$REPRICE_DRY_RUN" == "true" ]] || mkdir -p "$_receipt_dir"
    _rp_rc=0
    PYTHONPATH="${PROJECT_ROOT}/.claude/adapters${PYTHONPATH:+:$PYTHONPATH}" "$_PYTHON_BIN" - "$LEDGER_PATH" "$_receipt_dir" "$REPRICE_DRY_RUN" "$PROJECT_ROOT" <<'PYREP' || _rp_rc=$?
import sys
ledger, receipt_dir, dry_run, project_root = sys.argv[1], sys.argv[2], sys.argv[3] == "true", sys.argv[4]
from loa_cheval.config.loader import load_config
from loa_cheval.metering.reprice import RepriceRefused, reprice_ledger_file
config, _sources = load_config(project_root)
try:
    r = reprice_ledger_file(
        ledger, receipt_dir, config, dry_run=dry_run,
        catalog_note={"project_root": project_root, "loader": "loa_cheval.config.loader.load_config"},
    )
except RepriceRefused as exc:
    print(f"cost-report: --reprice {exc}", file=sys.stderr)
    sys.exit(3)
total = r["rows_repriced"] + r["rows_still_unpriced"]
if dry_run:
    print(f"cost-report: --reprice --dry-run: {r['rows_repriced']} of {total} unpriced row(s) would be re-priced "
          f"({r['rows_still_unpriced']} still unresolvable); nothing written", file=sys.stderr)
else:
    print(f"cost-report: --reprice: re-priced {r['rows_repriced']} of {total} unpriced row(s) "
          f"({r['rows_still_unpriced']} still unpriced) → {ledger}; backup {r['backup'] or 'none (nothing changed)'}; "
          f"receipt {r['receipt_path']}", file=sys.stderr)
PYREP
    if [[ $_rp_rc -ne 0 ]]; then
        echo "ERROR: --reprice failed (exit $_rp_rc); the ledger is rewritten only after its backup is durable (see the receipt / <ledger>.pre-reprice-* for recovery)" >&2
        exit "$_rp_rc"
    fi
fi

_legacy_arg=""
if [[ "$INCLUDE_LEGACY" == "true" && -f "$LEGACY_LEDGER" ]]; then
    _legacy_arg="$LEGACY_LEDGER"
fi

if [[ ! -f "$LEDGER_PATH" && -z "$_legacy_arg" ]]; then
    if [[ "$OUTPUT_JSON" == "true" ]]; then
        # The empty envelope answers the same questions as a populated one: a
        # --window-day caller (the budget enforcer) gets an empty window, not a
        # missing field (a fresh mount has no ledger yet — CI, first run).
        jq -nc --arg d "$WINDOW_DAY" '{total_micro_usd:0, entry_count:0, agents:{}, models:{}, providers:{}, daily:[], unpriced_rows:0, unpriced_share:0, unclassified_rows:0, estimated_rows:0, legacy_rows:0, repriced_rows:0, pricing_resolution:{}}
            + (if $d == "" then {} else {window: {day: $d, entry_count: 0, unpriced_rows: 0, unpriced_share: 0}} end)'
    else
        echo "# Cost Report"
        echo ""
        echo "No cost ledger found at \`${LEDGER_PATH}\`."
        echo ""
        echo "Cost tracking will begin when model-invoke calls are made with metering enabled."
    fi
    exit 0
fi

# Use Python for JSONL parsing and aggregation (jq can't handle complex aggregation well)
python3 - "$LEDGER_PATH" "$REPORT_DAYS" "$TOP_N" "$OUTPUT_JSON" "$_legacy_arg" "$WINDOW_DAY" <<'PYEOF'
import json
import os
import sys
from collections import defaultdict
from datetime import datetime, timedelta, timezone

ledger_path = sys.argv[1]
report_days = int(sys.argv[2])
top_n = int(sys.argv[3])
output_json = sys.argv[4] == "true"
legacy_path = sys.argv[5] if len(sys.argv) > 5 else ""
window_day = sys.argv[6] if len(sys.argv) > 6 else ""  # sprint-bug-245: per-day window

# Read ledger (+ the legacy ledger when asked; its rows are tagged and
# de-duplicated against the current ledger by request_id so a migrated
# history is never counted twice)
corrupt = 0
def _read(path, tag_legacy=False):
    global corrupt
    out = []
    if not path or not os.path.isfile(path):
        return out
    with open(path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                row = json.loads(line)
            except json.JSONDecodeError:
                corrupt += 1
                continue
            if tag_legacy:
                row = dict(row)
                row.setdefault("legacy", True)
            out.append(row)
    return out
entries = _read(ledger_path)
legacy_rows = 0
if legacy_path:
    import hashlib
    def _row_key(r):
        rid = r.get("request_id")
        if rid:
            return "id:" + str(rid)
        core = {k: r.get(k) for k in ("ts", "trace_id", "agent", "provider", "model", "tokens_in", "tokens_out", "cost_micro_usd")}
        return "ck:" + hashlib.sha256(json.dumps(core, sort_keys=True).encode("utf-8")).hexdigest()
    seen = {_row_key(e) for e in entries}
    for row in _read(legacy_path, tag_legacy=True):
        if _row_key(row) in seen:
            continue
        entries.append(row)
        legacy_rows += 1

now = datetime.now(timezone.utc)
today = now.strftime("%Y-%m-%d")

# Filter by time windows
def parse_ts(ts_str):
    try:
        return datetime.fromisoformat(ts_str.replace("Z", "+00:00"))
    except (ValueError, AttributeError):
        return None

cutoff_1d = now - timedelta(days=1)
cutoff_7d = now - timedelta(days=7)
cutoff_30d = now - timedelta(days=report_days)

# Aggregations
total_all = 0
total_1d = 0
total_7d = 0
total_30d = 0
by_agent = defaultdict(int)
by_model = defaultdict(int)
by_provider = defaultdict(int)
by_day = defaultdict(int)
top_invocations = []

unpriced_rows = 0
unclassified_rows = 0
estimated_rows = 0
repriced_rows = 0
window_entries = 0
window_unpriced = 0
by_resolution = defaultdict(int)
for e in entries:
    cost = e.get("cost_micro_usd", 0)
    total_all += cost
    # cycle-125 FR-5: an unpriced row records cost 0 — count it, never call it a price.
    # A pre-metadata row (no pricing_source) that already carries a cost was priced by
    # its writer: it is "unclassified", not unpriced (Bridgebuilder PR #1269 FIND-004).
    src = e.get("pricing_source")
    row_unpriced = src == "unknown" or (src is None and not cost)
    if row_unpriced:
        unpriced_rows += 1
    elif src is None:
        unclassified_rows += 1
    if e.get("cost_estimated"):
        estimated_rows += 1
    if e.get("repriced_at"):
        repriced_rows += 1
    by_resolution[e.get("pricing_resolution") or e.get("pricing_source", "unknown")] += 1

    ts = parse_ts(e.get("ts"))
    if ts:
        day_key = ts.strftime("%Y-%m-%d")
        by_day[day_key] += cost
        if window_day and day_key == window_day:
            window_entries += 1
            if row_unpriced:
                window_unpriced += 1

        if ts >= cutoff_1d:
            total_1d += cost
        if ts >= cutoff_7d:
            total_7d += cost
        if ts >= cutoff_30d:
            total_30d += cost

    by_agent[e.get("agent", "unknown")] += cost
    by_model[f"{e.get('provider', '?')}:{e.get('model', '?')}"] += cost
    by_provider[e.get("provider", "unknown")] += cost

    top_invocations.append({
        "cost_micro_usd": cost,
        "agent": e.get("agent", "unknown"),
        "model": f"{e.get('provider', '?')}:{e.get('model', '?')}",
        "tokens_in": e.get("tokens_in", 0),
        "tokens_out": e.get("tokens_out", 0),
        "ts": e.get("ts", ""),
    })

# Sort top invocations
top_invocations.sort(key=lambda x: x["cost_micro_usd"], reverse=True)
top_invocations = top_invocations[:top_n]

def fmt_usd(micro):
    """Format micro-USD as dollar amount."""
    return f"${micro / 1_000_000:.2f}"

unpriced_share = (unpriced_rows / len(entries)) if entries else 0.0

if output_json:
    result = {
        "total_micro_usd": total_all,
        "entry_count": len(entries),
        "corrupt_lines": corrupt,
        "unpriced_rows": unpriced_rows,
        "unpriced_share": round(unpriced_share, 6),
        "unclassified_rows": unclassified_rows,
        "estimated_rows": estimated_rows,
        "legacy_rows": legacy_rows,
        "repriced_rows": repriced_rows,
        "pricing_resolution": dict(by_resolution),
        "summary": {
            "today_micro_usd": total_1d,
            "week_micro_usd": total_7d,
            "month_micro_usd": total_30d,
        },
        "agents": dict(by_agent),
        "models": dict(by_model),
        "providers": dict(by_provider),
        "top_invocations": top_invocations,
    }
    if window_day:
        result["window"] = {
            "day": window_day,
            "entry_count": window_entries,
            "unpriced_rows": window_unpriced,
            "unpriced_share": round((window_unpriced / window_entries) if window_entries else 0.0, 6),
        }
    print(json.dumps(result, indent=2))
else:
    print("# Cost Report")
    print()
    print(f"**Generated**: {now.strftime('%Y-%m-%d %H:%M UTC')}")
    print(f"**Ledger**: `{ledger_path}`")
    print(f"**Entries**: {len(entries)}" + (f" ({corrupt} corrupted)" if corrupt else ""))
    print()

    print("## Summary")
    print()
    print("| Period | Cost |")
    print("|--------|------|")
    print(f"| Today | {fmt_usd(total_1d)} |")
    print(f"| Last 7 days | {fmt_usd(total_7d)} |")
    print(f"| Last {report_days} days | {fmt_usd(total_30d)} |")
    print(f"| All time | {fmt_usd(total_all)} |")
    print()
    print(f"Unpriced rows: {unpriced_rows} ({unpriced_share * 100:.1f} %) — recorded as cost 0, not as a price"
          + (f"; unclassified (pre-metadata, priced by their writer): {unclassified_rows}" if unclassified_rows else "")
          + (f"; estimated rows: {estimated_rows}" if estimated_rows else "")
          + (f"; legacy rows included: {legacy_rows}" if legacy_rows else "")
          + (f"; repriced rows: {repriced_rows}" if repriced_rows else ""))
    if by_resolution:
        print("Pricing resolution: " + ", ".join(f"{k} {v}" for k, v in sorted(by_resolution.items())))
    if window_day:
        _wshare = (window_unpriced / window_entries * 100) if window_entries else 0.0
        print(f"Window {window_day}: {window_entries} row(s), {window_unpriced} unpriced ({_wshare:.1f} %)")
    print()

    if by_agent:
        print("## By Agent")
        print()
        print("| Agent | Cost |")
        print("|-------|------|")
        for agent, cost in sorted(by_agent.items(), key=lambda x: x[1], reverse=True):
            print(f"| {agent} | {fmt_usd(cost)} |")
        print()

    if by_model:
        print("## By Model")
        print()
        print("| Model | Cost |")
        print("|-------|------|")
        for model, cost in sorted(by_model.items(), key=lambda x: x[1], reverse=True):
            print(f"| {model} | {fmt_usd(cost)} |")
        print()

    if by_provider:
        print("## By Provider")
        print()
        print("| Provider | Cost |")
        print("|----------|------|")
        for provider, cost in sorted(by_provider.items(), key=lambda x: x[1], reverse=True):
            print(f"| {provider} | {fmt_usd(cost)} |")
        print()

    if top_invocations:
        print(f"## Top {top_n} Most Expensive Invocations")
        print()
        print("| Agent | Model | Tokens (in/out) | Cost | Time |")
        print("|-------|-------|-----------------|------|------|")
        for inv in top_invocations:
            print(f"| {inv['agent']} | {inv['model']} | {inv['tokens_in']}/{inv['tokens_out']} | {fmt_usd(inv['cost_micro_usd'])} | {inv['ts'][:19]} |")
        print()
PYEOF
