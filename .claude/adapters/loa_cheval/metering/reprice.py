"""Explicit, opt-in re-pricing of historical unpriced cost-ledger rows.

sprint-bug-245 (cycle-125 follow-up, bead bd-ypbg). A ledger row recorded
before the pricing ladder existed carries ``pricing_source: unknown`` and cost
0. The ladder (``find_pricing``: exact → dated → alias → hop) can now price
many of those ids; this module prices such a row exactly as
``create_ledger_entry`` would price a fresh row with the same tokens and
marks it, so history is never rewritten silently:

    cost_micro_usd      recomputed from the row's tokens at today's catalog rates
    pricing_source      "config"
    pricing_mode        the entry's mode
    pricing_resolution  the ladder rung that matched
    resolved_model      the catalog id the rung priced (when it differs from `model`)
    cost_estimated      True — a price applied after the fact, at current rates
    repriced_at         the pass's UTC timestamp
    repriced_from       {pricing_source, cost_micro_usd} as they were

Rows that are already priced, rows the ladder still cannot resolve, and rows
that already carry ``repriced_at`` come back unchanged — the same object, so a
caller can tell by identity which lines to rewrite. The input list is never
mutated. ``cost-report.sh --reprice [--dry-run]`` is the caller; it owns the
file handling (symlink refusal, byte copy, atomic replace, receipt).
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional, Tuple

from .pricing import calculate_total_cost, find_pricing

Row = Dict[str, Any]

STATS_KEYS = ("rows_scanned", "rows_repriced", "rows_still_unpriced", "rows_skipped_priced", "micro_usd_added")


def _int(value: Any) -> int:
    try:
        return int(value) if value is not None else 0
    except (TypeError, ValueError):
        return 0


def is_unpriced(row: Row) -> bool:
    """The report's own definition (cost-report.sh; Bridgebuilder #1269
    FIND-004): ``pricing_source`` is ``unknown``, or absent on a row that
    carries no cost. A pre-metadata row that carries a cost was priced by
    its writer and is not touched."""
    source = row.get("pricing_source")
    if source == "unknown":
        return True
    return source is None and not _int(row.get("cost_micro_usd"))


def reprice_row(row: Row, config: Dict[str, Any], now_iso: str) -> Optional[Row]:
    """A re-priced copy of ``row``, or None when the row is not unpriced,
    was already re-priced, or still cannot be priced through the ladder."""
    if not is_unpriced(row) or row.get("repriced_at"):
        return None
    provider = row.get("provider")
    model = row.get("model")
    if not isinstance(provider, str) or not provider or not isinstance(model, str) or not model:
        return None
    pricing = find_pricing(provider, model, config)
    hint = row.get("resolved_model")
    if pricing is None and isinstance(hint, str) and hint and hint != model:
        pricing = find_pricing(provider, hint, config)
    if pricing is None:
        return None
    breakdown = calculate_total_cost(
        _int(row.get("tokens_in")),
        _int(row.get("tokens_out")),
        _int(row.get("tokens_reasoning")),
        pricing,
        cache_read_tokens=_int(row.get("tokens_cache_read")),
        cache_creation_tokens=_int(row.get("tokens_cache_creation")),
    )
    new = dict(row)
    new["repriced_from"] = {
        "pricing_source": row.get("pricing_source"),
        "cost_micro_usd": _int(row.get("cost_micro_usd")),
    }
    new["cost_micro_usd"] = breakdown.total_cost_micro
    new["pricing_source"] = "config"
    new["pricing_mode"] = pricing.pricing_mode
    new["pricing_resolution"] = pricing.resolution
    if pricing.model != model:
        new["resolved_model"] = pricing.model
    new["cost_estimated"] = True
    new["repriced_at"] = now_iso
    return new


def reprice_rows(rows: List[Row], config: Dict[str, Any], now_iso: str) -> Tuple[List[Row], Dict[str, int]]:
    """Re-price every eligible row in ``rows``.

    Returns ``(out, stats)`` where ``out[i] is rows[i]`` for every row that was
    not changed and ``stats`` counts rows_scanned / rows_repriced /
    rows_still_unpriced / rows_skipped_priced / micro_usd_added.
    """
    stats = {key: 0 for key in STATS_KEYS}
    stats["rows_scanned"] = len(rows)
    out: List[Row] = []
    for row in rows:
        if not is_unpriced(row) or row.get("repriced_at"):
            stats["rows_skipped_priced"] += 1
            out.append(row)
            continue
        new = reprice_row(row, config, now_iso)
        if new is None:
            stats["rows_still_unpriced"] += 1
            out.append(row)
        else:
            stats["rows_repriced"] += 1
            stats["micro_usd_added"] += int(new["cost_micro_usd"])
            out.append(new)
    return out, stats
