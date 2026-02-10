#!/usr/bin/env bash
# =============================================================================
# cost-report.sh — Read JSONL ledger and generate markdown cost summary
# =============================================================================
# Part of: Hounfour Upstream Extraction (Sprint 3)
#
# Usage:
#   cost-report.sh [--ledger <path>] [--days N] [--json]
#
# Options:
#   --ledger <path>    Path to cost ledger JSONL (default: grimoires/loa/a2a/cost-ledger.jsonl)
#   --days <n>         Report period in days (default: 30)
#   --json             Output as JSON instead of markdown
#   --top <n>          Show top N most expensive invocations (default: 5)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Defaults
LEDGER_PATH="${PROJECT_ROOT}/grimoires/loa/a2a/cost-ledger.jsonl"
REPORT_DAYS=30
OUTPUT_JSON=false
TOP_N=5

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --ledger)
            LEDGER_PATH="$2"
            shift 2
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
            echo "Usage: cost-report.sh [--ledger <path>] [--days N] [--json] [--top N]"
            exit 0
            ;;
        *)
            echo "ERROR: Unknown option: $1" >&2
            exit 2
            ;;
    esac
done

# Check ledger exists
if [[ ! -f "$LEDGER_PATH" ]]; then
    if [[ "$OUTPUT_JSON" == "true" ]]; then
        echo '{"total_micro_usd":0,"entry_count":0,"agents":{},"models":{},"providers":{},"daily":[]}'
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
python3 - "$LEDGER_PATH" "$REPORT_DAYS" "$TOP_N" "$OUTPUT_JSON" <<'PYEOF'
import json
import sys
from collections import defaultdict
from datetime import datetime, timedelta, timezone

ledger_path = sys.argv[1]
report_days = int(sys.argv[2])
top_n = int(sys.argv[3])
output_json = sys.argv[4] == "true"

# Read ledger
entries = []
corrupt = 0
with open(ledger_path, "r") as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            entries.append(json.loads(line))
        except json.JSONDecodeError:
            corrupt += 1

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

for e in entries:
    cost = e.get("cost_micro_usd", 0)
    total_all += cost

    ts = parse_ts(e.get("ts"))
    if ts:
        day_key = ts.strftime("%Y-%m-%d")
        by_day[day_key] += cost

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

if output_json:
    result = {
        "total_micro_usd": total_all,
        "entry_count": len(entries),
        "corrupt_lines": corrupt,
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
