"""Cost-attribution rollup over the cheval ledger (intel-routing fix-plan #1).

The sequencing gate from the 2026-06-10 intel-routing review: no tier→dispatch
wiring lands before per-actor cost attribution exists. The ledger already
records agent + model + cost_micro_usd per call; this module is the missing
aggregation. Pure functions + a tiny CLI — no dispatch behavior changes.

Scope note (honest): this aggregates the CHEVAL path (path B). Form C
composition runs dispatch through the harness Workflow tool and do not write
this ledger; their design-time attribution is the emit-time cost card
(rooms-substrate, fix-plan #5) and their runtime actuals live in the harness
session metering.

Usage:
    python3 -m loa_cheval.metering.rollup [--ledger PATH] \
        [--by agent|model|provider|day|trace] [--since YYYY-MM-DD] [--json]

Group keys:
    agent     (default) — the cheval agent/voice binding; the per-actor view
    model     — final model id; the "which models are spending" view
    provider  — provider id
    day       — UTC date prefix of ts
    trace     — trace_id; the per-invocation-chain view

Every row carries `unpriced_calls`: entries whose pricing_source != "config"
metered as $0 (the blind-spot detector that motivated pricing-before-
routability). A non-zero unpriced count means the cost column UNDERSTATES.
"""

from __future__ import annotations

import argparse
import json
import sys
from typing import Any, Dict, Iterable, List

from loa_cheval.metering.ledger import read_ledger

GROUP_KEYS = ("agent", "model", "provider", "day", "trace")

FALLBACK_LEDGER = ".run/cost-ledger.jsonl"


def default_ledger_path() -> str:
    """Resolve the ledger path the way cheval itself does (codex P2 on #1000):
    metering.ledger_path from the merged config when loadable, else the
    literal fallback cheval.py uses. An explicit --ledger always wins."""
    try:
        import yaml  # repo CI installs PyYAML; degrade gracefully without it

        with open(".claude/defaults/model-config.yaml") as f:
            cfg = yaml.safe_load(f) or {}
        return (cfg.get("metering") or {}).get("ledger_path") or FALLBACK_LEDGER
    except Exception:
        return FALLBACK_LEDGER


def _group_value(entry: Dict[str, Any], by: str) -> str:
    if by == "day":
        return str(entry.get("ts", ""))[:10] or "(no-ts)"
    if by == "trace":
        return str(entry.get("trace_id") or "(no-trace)")
    return str(entry.get(by) or f"(no-{by})")


def rollup_entries(
    entries: Iterable[Dict[str, Any]],
    by: str = "agent",
    since: str = "",
) -> List[Dict[str, Any]]:
    """Aggregate ledger entries by the given key. Pure; deterministic order.

    Returns rows sorted by total cost descending, each:
      {key, calls, tokens_in, tokens_out, tokens_reasoning,
       cost_micro_usd, unpriced_calls, models}
    """
    if by not in GROUP_KEYS:
        raise ValueError(f"--by must be one of {GROUP_KEYS}, got {by!r}")

    groups: Dict[str, Dict[str, Any]] = {}
    for e in entries:
        if since and str(e.get("ts", ""))[:10] < since:
            continue
        k = _group_value(e, by)
        g = groups.setdefault(
            k,
            {
                "key": k,
                "calls": 0,
                "tokens_in": 0,
                "tokens_out": 0,
                "tokens_reasoning": 0,
                "cost_micro_usd": 0,
                "unpriced_calls": 0,
                "models": set(),
            },
        )
        g["calls"] += 1
        g["tokens_in"] += int(e.get("tokens_in") or 0)
        g["tokens_out"] += int(e.get("tokens_out") or 0)
        g["tokens_reasoning"] += int(e.get("tokens_reasoning") or 0)
        g["cost_micro_usd"] += int(e.get("cost_micro_usd") or 0)
        if e.get("pricing_source") != "config":
            g["unpriced_calls"] += 1
        if e.get("model"):
            g["models"].add(str(e["model"]))

    rows = []
    for g in groups.values():
        g["models"] = sorted(g["models"])
        rows.append(g)
    # cost desc, then key asc for deterministic ties
    rows.sort(key=lambda r: (-r["cost_micro_usd"], r["key"]))
    return rows


def format_table(rows: List[Dict[str, Any]], by: str) -> str:
    """Human-readable table. Costs rendered in USD; micro-USD stays in JSON."""
    if not rows:
        return "cheval-cost-rollup: ledger empty (or nothing after --since)"
    header = f"{by:<32} {'calls':>6} {'tok_in':>10} {'tok_out':>9} {'cost_usd':>10} {'unpriced':>8}  models"
    lines = [header, "-" * len(header)]
    total_cost = 0
    total_calls = 0
    total_unpriced = 0
    for r in rows:
        total_cost += r["cost_micro_usd"]
        total_calls += r["calls"]
        total_unpriced += r["unpriced_calls"]
        lines.append(
            f"{r['key'][:32]:<32} {r['calls']:>6} {r['tokens_in']:>10} "
            f"{r['tokens_out']:>9} {r['cost_micro_usd'] / 1_000_000:>10.4f} "
            f"{r['unpriced_calls']:>8}  {','.join(r['models'])[:48]}"
        )
    lines.append("-" * len(header))
    lines.append(
        f"{'TOTAL':<32} {total_calls:>6} {'':>10} {'':>9} "
        f"{total_cost / 1_000_000:>10.4f} {total_unpriced:>8}"
    )
    if total_unpriced:
        lines.append(
            f"WARNING: {total_unpriced} call(s) had no pricing entry "
            f"(pricing_source != config) and metered as $0 — the cost column "
            f"UNDERSTATES. Register pricing in model-config.yaml."
        )
    return "\n".join(lines)


def main(argv: List[str] | None = None) -> int:
    ap = argparse.ArgumentParser(
        prog="cheval-cost-rollup",
        description="Per-actor cost attribution over the cheval ledger.",
    )
    ap.add_argument(
        "--ledger",
        default=None,
        help="ledger path (default: metering.ledger_path from model-config.yaml)",
    )
    ap.add_argument("--by", default="agent", choices=GROUP_KEYS)
    ap.add_argument("--since", default="", help="YYYY-MM-DD inclusive lower bound")
    ap.add_argument("--json", action="store_true", help="emit JSON rows")
    args = ap.parse_args(argv)

    ledger = args.ledger or default_ledger_path()
    rows = rollup_entries(read_ledger(ledger), by=args.by, since=args.since)
    if args.json:
        print(json.dumps({"by": args.by, "since": args.since or None, "rows": rows}))
    else:
        print(format_table(rows, args.by))
    return 0


if __name__ == "__main__":
    sys.exit(main())
