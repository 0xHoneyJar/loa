"""Integer micro-USD pricing — extracted from loa-finn pricing.ts (SDD §4.5).

All prices in micro-USD per million tokens. 1 USD = 1,000,000 micro-USD.
No floating-point anywhere in the cost path.
"""

from __future__ import annotations

import datetime as _dt
import logging
import re

from dataclasses import dataclass, replace
from decimal import Decimal, InvalidOperation
from typing import Any, Dict, Optional

logger = logging.getLogger("loa_cheval.metering.pricing")

# Overflow guard: max safe integer for cost calculation.
# Python ints are arbitrary-precision, but we enforce this for parity with loa-finn
# which uses Number.MAX_SAFE_INTEGER (2^53 - 1).
MAX_SAFE_PRODUCT = (2**53) - 1


def cli_cost_micro_usd(value: Any) -> Optional[int]:
    """Normalize a CLI's USD amount without binary floating-point arithmetic.

    Missing, malformed, negative, or unrepresentable telemetry is unknown.
    Fractional micro-USD is floored, matching config-based cost accounting.
    """
    if isinstance(value, bool) or not isinstance(value, (str, int, float)):
        return None
    try:
        amount = Decimal(str(value))
        if not amount.is_finite() or amount < 0 or amount > Decimal(MAX_SAFE_PRODUCT) / 1_000_000:
            return None
        return int(amount * 1_000_000)
    except (InvalidOperation, ValueError):
        return None


@dataclass
class PricingEntry:
    """Per-model pricing in micro-USD per million tokens."""

    provider: str
    model: str
    input_per_mtok: int  # micro-USD per 1M input tokens
    output_per_mtok: int  # micro-USD per 1M output tokens
    reasoning_per_mtok: int = 0  # micro-USD per 1M reasoning tokens
    per_task_micro_usd: int = 0  # Flat per-task cost (Deep Research)
    pricing_mode: str = "token"  # "token" | "task" | "hybrid"
    # cycle-124 FR-4: prompt-cache rates. Anthropic bills cache reads at 0.1×
    # input (Fable 5.1: 0.025×) and cache writes at 1.25× input; the catalog
    # carries cache_read_per_mtok explicitly, cache_write derives when absent.
    cache_read_per_mtok: int = 0
    cache_write_per_mtok: int = 0
    # cycle-125 FR-5 (SDD §1.6): how the id was matched — exact | dated |
    # alias | hop. Additive; every pre-cycle caller sees "exact".
    resolution: str = "exact"
    # cycle-126 FR-1.9 (SDD D-1.9): the long-context premium. When the request's
    # input exceeds `long_context_threshold`, the multipliers apply to the whole
    # request (the provider's published rule for 1M-window models). None ⇒ the
    # entry has no premium tier; multipliers default to 1.0.
    long_context_threshold: Optional[int] = None
    long_context_input_multiplier: float = 1.0
    long_context_output_multiplier: float = 1.0
    # cycle-129 FR-7 (SDD D-7.6): catalog provenance, read from the model entry
    # (siblings of `pricing`). `price_date` is `YYYY-MM-DD`; a date older than
    # STALE_PRICE_DAYS marks the price stale (ledger `pricing_source:
    # stale_catalog`). Absent on every entry today — no behaviour change.
    open_weight: bool = False
    price_source: Optional[str] = None
    price_date: Optional[str] = None


@dataclass
class CostBreakdown:
    """Detailed cost breakdown for a single completion."""

    input_cost_micro: int
    output_cost_micro: int
    reasoning_cost_micro: int
    total_cost_micro: int
    remainder_input: int
    remainder_output: int
    remainder_reasoning: int
    # cycle-124 FR-4: cache read / write costs (0 when the provider reports
    # no cache tokens or the entry has no cache rate).
    cache_read_cost_micro: int = 0
    cache_write_cost_micro: int = 0
    remainder_cache_read: int = 0
    remainder_cache_write: int = 0
    # cycle-126 FR-1.9: True when the long-context multipliers were applied.
    long_context_applied: bool = False


def calculate_cost_micro(tokens: int, price_micro_per_million: int) -> tuple:
    """Calculate cost in micro-USD using integer arithmetic only.

    Formula: cost_micro = floor(tokens * price_per_mtok / 1_000_000)

    Returns (cost_micro, remainder_micro) for remainder carry.

    Raises ValueError on overflow (tokens * price exceeds MAX_SAFE_PRODUCT).
    """
    product = tokens * price_micro_per_million
    if product > MAX_SAFE_PRODUCT:
        raise ValueError(
            f"BUDGET_OVERFLOW: tokens({tokens}) * price({price_micro_per_million}) "
            f"= {product} exceeds MAX_SAFE_PRODUCT"
        )

    cost_micro = product // 1_000_000
    remainder_micro = product % 1_000_000

    return cost_micro, remainder_micro


def _premium_cost_micro(tokens: int, price_micro_per_million: int, multiplier: float) -> tuple:
    """cycle-126 FR-1.9 (review sprint-247): the long-context premium is applied
    to the product BEFORE flooring — floor(tokens × rate × multiplier / 1e6) —
    with the multiplier as an exact decimal (`Fraction(str(m))`), never to an
    already-floored per-category cost. Returns (cost_micro, remainder_micro)
    with the remainder scaled to the same 0..999,999 range as
    `calculate_cost_micro`; the overflow guard is the same product check."""
    from fractions import Fraction
    product = tokens * price_micro_per_million
    if product > MAX_SAFE_PRODUCT:
        raise ValueError(
            f"BUDGET_OVERFLOW: tokens({tokens}) * price({price_micro_per_million}) "
            f"= {product} exceeds MAX_SAFE_PRODUCT"
        )
    frac = Fraction(str(multiplier))
    num = product * frac.numerator
    den = 1_000_000 * frac.denominator
    cost_micro = num // den
    remainder_micro = (num % den) * 1_000_000 // den
    return cost_micro, remainder_micro


def calculate_total_cost(
    input_tokens: int,
    output_tokens: int,
    reasoning_tokens: int,
    pricing: PricingEntry,
    cache_read_tokens: int = 0,
    cache_creation_tokens: int = 0,
) -> CostBreakdown:
    """Calculate total cost for a completion in micro-USD.

    Handles three pricing modes:
    - "token": Standard per-token pricing (default)
    - "task": Flat per-task cost (e.g., Deep Research) — token counts ignored
    - "hybrid": Token cost + flat per-task cost summed

    cycle-124 FR-4: `cache_read_tokens` / `cache_creation_tokens` are the
    Anthropic usage fields (NOT included in `input_tokens`), priced at the
    entry's cache_read_per_mtok / cache_write_per_mtok.
    """
    if pricing.pricing_mode == "task":
        # Flat per-task cost only — no token math
        return CostBreakdown(
            input_cost_micro=0,
            output_cost_micro=0,
            reasoning_cost_micro=0,
            total_cost_micro=pricing.per_task_micro_usd,
            remainder_input=0,
            remainder_output=0,
            remainder_reasoning=0,
        )

    # Token-based cost calculation (shared by "token" and "hybrid" modes)
    inp_cost, inp_rem = calculate_cost_micro(input_tokens, pricing.input_per_mtok)
    out_cost, out_rem = calculate_cost_micro(output_tokens, pricing.output_per_mtok)

    if pricing.reasoning_per_mtok and reasoning_tokens:
        reas_cost, reas_rem = calculate_cost_micro(
            reasoning_tokens, pricing.reasoning_per_mtok
        )
    else:
        reas_cost, reas_rem = 0, 0

    if pricing.cache_read_per_mtok and cache_read_tokens:
        cr_cost, cr_rem = calculate_cost_micro(cache_read_tokens, pricing.cache_read_per_mtok)
    else:
        cr_cost, cr_rem = 0, 0
    if pricing.cache_write_per_mtok and cache_creation_tokens:
        cw_cost, cw_rem = calculate_cost_micro(cache_creation_tokens, pricing.cache_write_per_mtok)
    else:
        cw_cost, cw_rem = 0, 0

    # cycle-126 FR-1.9: long-context premium — above the threshold the whole
    # request is billed at the multiplied rates (input-side: input + cache
    # traffic; output-side: output + reasoning), each category recomputed from
    # tokens × rate × multiplier before flooring (review sprint-247 DISS-001:
    # multiplying the floored costs underbilled by the discarded remainders).
    long_context_applied = False
    threshold = pricing.long_context_threshold
    if threshold is not None and input_tokens > threshold:
        long_context_applied = True
        im, om = pricing.long_context_input_multiplier, pricing.long_context_output_multiplier
        inp_cost, inp_rem = _premium_cost_micro(input_tokens, pricing.input_per_mtok, im)
        out_cost, out_rem = _premium_cost_micro(output_tokens, pricing.output_per_mtok, om)
        if pricing.reasoning_per_mtok and reasoning_tokens:
            reas_cost, reas_rem = _premium_cost_micro(reasoning_tokens, pricing.reasoning_per_mtok, om)
        if pricing.cache_read_per_mtok and cache_read_tokens:
            cr_cost, cr_rem = _premium_cost_micro(cache_read_tokens, pricing.cache_read_per_mtok, im)
        if pricing.cache_write_per_mtok and cache_creation_tokens:
            cw_cost, cw_rem = _premium_cost_micro(cache_creation_tokens, pricing.cache_write_per_mtok, im)

    token_total = inp_cost + out_cost + reas_cost + cr_cost + cw_cost

    # Hybrid: add flat per-task cost on top of token cost
    if pricing.pricing_mode == "hybrid":
        token_total += pricing.per_task_micro_usd

    return CostBreakdown(
        input_cost_micro=inp_cost,
        output_cost_micro=out_cost,
        reasoning_cost_micro=reas_cost,
        total_cost_micro=token_total,
        remainder_input=inp_rem,
        remainder_output=out_rem,
        remainder_reasoning=reas_rem,
        cache_read_cost_micro=cr_cost,
        cache_write_cost_micro=cw_cost,
        remainder_cache_read=cr_rem,
        remainder_cache_write=cw_rem,
        long_context_applied=long_context_applied,
    )


class RemainderAccumulator:
    """Accumulates remainder from integer division across requests.

    When remainder >= 1_000_000, carries 1 micro-USD to cost.
    """

    def __init__(self) -> None:
        self._remainders: Dict[str, int] = {}

    def carry(self, scope_key: str, remainder_micro: int) -> int:
        """Apply remainder carry for a scope.

        Returns the extra micro-USD to add to cost (0 or 1+).
        """
        current = self._remainders.get(scope_key, 0)
        total = current + remainder_micro
        extra = total // 1_000_000
        self._remainders[scope_key] = total % 1_000_000
        return extra

    def get(self, scope_key: str) -> int:
        """Get current accumulated remainder for a scope."""
        return self._remainders.get(scope_key, 0)

    def clear(self) -> None:
        """Reset all accumulators."""
        self._remainders.clear()


def _int_rate(value: Any, derived: int) -> int:
    """A catalog rate only when it is a non-negative whole number (bool excluded); else the derived default.

    A YAML float that is a whole number (``250000.0``) is accepted as that int;
    a non-null value that is discarded is logged so an override that "looks
    applied" never silently is not (late Sprint 2 review, slice A).
    """
    if isinstance(value, bool):
        logger.warning("pricing: ignoring boolean cache rate %r (using derived %d)", value, derived)
        return derived
    if isinstance(value, int) and value >= 0:
        return value
    if isinstance(value, float) and value.is_integer() and value >= 0:
        return int(value)
    if value is not None:
        logger.warning("pricing: ignoring non-integer cache rate %r (using derived %d)", value, derived)
    return derived


def _exact_pricing(
    provider: str,
    model: str,
    config: Dict[str, Any],
) -> Optional[PricingEntry]:
    """`providers.<provider>.models.<model>.pricing` — the only rung that reads rates."""
    providers = config.get("providers", {})
    provider_config = providers.get(provider, {}) or {}
    model_config = (provider_config.get("models", {}) or {}).get(model, {}) or {}
    pricing = model_config.get("pricing")

    if not pricing:
        return None

    input_per_mtok = pricing.get("input_per_mtok", 0)
    return PricingEntry(
        provider=provider,
        model=model,
        input_per_mtok=input_per_mtok,
        output_per_mtok=pricing.get("output_per_mtok", 0),
        reasoning_per_mtok=pricing.get("reasoning_per_mtok", 0),
        per_task_micro_usd=pricing.get("per_task_micro_usd", 0),
        pricing_mode=pricing.get("pricing_mode", "token"),
        # cycle-124 FR-4: explicit catalog rate, else the Anthropic defaults
        # (0.1× read, 1.25× write); providers that never report cache tokens
        # never exercise them.
        # `dict.get(key, default)` returns an explicit YAML null as-is, which
        # would price cache tokens at $0 under pricing_source=config (audit,
        # slice B) — only a real integer overrides the derived rate.
        cache_read_per_mtok=_int_rate(pricing.get("cache_read_per_mtok"), input_per_mtok // 10),
        cache_write_per_mtok=_int_rate(pricing.get("cache_write_per_mtok"), input_per_mtok * 5 // 4),
        **_long_context_fields(pricing.get("long_context")),
        **_provenance_fields(model_config),
    )


def _provenance_fields(model_config: Dict[str, Any]) -> Dict[str, Any]:
    """cycle-129 D-7.6: `open_weight`, `price_source`, `price_date` from the model entry (strings kept as given;
    a non-string is dropped — the catalog test is where a malformed value fails, never the cost path)."""
    out: Dict[str, Any] = {"open_weight": model_config.get("open_weight") is True}
    for key in ("price_source", "price_date"):
        value = model_config.get(key)
        if isinstance(value, _dt.date):   # YAML reads an unquoted 2026-10-14 as a date
            value = value.isoformat()
        if isinstance(value, str) and value.strip():
            out[key] = value.strip()
    return out


# cycle-129 D-7.6: a catalog price older than this is stale.
STALE_PRICE_DAYS = 90
_PRICE_DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
_STALE_WARNED: set = set()


def price_date_of(entry: Optional[PricingEntry]) -> Optional[_dt.date]:
    """The entry's `price_date` as a date, or None when absent or not a valid `YYYY-MM-DD`."""
    raw = getattr(entry, "price_date", None)
    if not isinstance(raw, str) or not _PRICE_DATE_RE.match(raw):
        return None
    try:
        return _dt.date.fromisoformat(raw)
    except ValueError:
        return None


def price_is_stale(entry: Optional[PricingEntry], today: Optional[_dt.date] = None) -> bool:
    """True when the entry carries a `price_date` older than STALE_PRICE_DAYS (an entry without one is not stale:
    provenance is required only of open-weight non-zero prices, and the catalog test enforces that)."""
    date = price_date_of(entry)
    if date is None:
        return False
    today = today or _dt.datetime.now(_dt.timezone.utc).date()
    return (today - date).days > STALE_PRICE_DAYS


def pricing_source_for(entry: Optional[PricingEntry], today: Optional[_dt.date] = None) -> str:
    """`config` for a catalog price, `stale_catalog` for one whose `price_date` is past STALE_PRICE_DAYS (WARNed once
    per entry per process), `unknown` for no price."""
    if entry is None:
        return "unknown"
    if price_is_stale(entry, today):
        key = (entry.provider, entry.model)
        if key not in _STALE_WARNED:
            _STALE_WARNED.add(key)
            logger.warning(
                "pricing: the catalog price of %s:%s is dated %s, older than %d days — recorded as stale_catalog; "
                "re-check it against its price_source (%s)",
                entry.provider, entry.model, entry.price_date, STALE_PRICE_DAYS, entry.price_source or "none given",
            )
        return "stale_catalog"
    return "config"


def _long_context_fields(block: Any) -> Dict[str, Any]:
    """cycle-126 FR-1.9: parse `pricing.long_context` (threshold + multipliers);
    a malformed or absent block means no premium tier."""
    if not isinstance(block, dict):
        return {}
    threshold = block.get("threshold_tokens")
    if isinstance(threshold, bool) or not isinstance(threshold, int) or threshold <= 0:
        return {}
    def _mult(value: Any) -> float:
        # review sprint-247 round 2: a non-finite value (`.inf`, `nan`, `1e309`)
        # passed `> 0` and later crashed `Fraction(str(m))` in the cost path —
        # finite and positive, or the multiplier is 1.0 (the contract).
        import math
        if isinstance(value, bool):
            return 1.0
        try:
            m = float(value)
        except (TypeError, ValueError):
            return 1.0
        return m if (math.isfinite(m) and m > 0) else 1.0
    return {
        "long_context_threshold": threshold,
        "long_context_input_multiplier": _mult(block.get("input_multiplier", 1.0)),
        "long_context_output_multiplier": _mult(block.get("output_multiplier", 1.0)),
    }


# cycle-125 FR-5 (SDD §1.6): the resolution ladder. Fleet ledgers carried
# 79 % `pricing_source: unknown` on the current path because the ids that
# actually get invoked are dated releases, aliases and CLI-hop names, none of
# which is a `providers.<p>.models` key.
_DATED_SUFFIX_RE = re.compile(r"^(?P<base>.+?)-\d{4}-\d{2}-\d{2}$")
_HOP_NAMES = frozenset({
    "codex-headless", "claude-headless", "agy-headless", "cursor-headless",
    "gemini-headless", "grok-headless",
})
_MAX_LADDER_DEPTH = 4


def _alias_target(model: str, config: Dict[str, Any]) -> Optional[str]:
    """`aliases` then `backward_compat_aliases` → "provider:model" (or None)."""
    for table in ("aliases", "backward_compat_aliases"):
        aliases = config.get(table) or {}
        target = aliases.get(model)
        if isinstance(target, str) and target:
            return target
    return None


def find_pricing(
    provider: str,
    model: str,
    config: Dict[str, Any],
    _depth: int = 0,
) -> Optional[PricingEntry]:
    """Look up pricing for (provider, model) through the resolution ladder:

    1. exact  — `providers.<p>.models.<m>.pricing`
    2. dated  — `<m>` with a trailing `-YYYY-MM-DD` stripped, when that base
                id exists (an exact dated entry always wins — rung 1 ran first)
    3. alias  — `<m>` through `aliases` / `backward_compat_aliases` to
                `provider:model` (the alias's provider wins over the caller's)
    4. hop    — a CLI hop (`kind: cli` or a known `*-headless` name) prices as
                its configured `extra.cli_model`, itself resolved through the
                ladder

    Returns a PricingEntry whose `resolution` names the rung, or None (the
    caller records `pricing_source: unknown` and the row is counted).
    """
    if _depth > _MAX_LADDER_DEPTH or not model:
        return None

    exact = _exact_pricing(provider, model, config)
    if exact:
        return exact

    dated = _DATED_SUFFIX_RE.match(model)
    if dated:
        base = _exact_pricing(provider, dated.group("base"), config)
        if base:
            return replace(base, resolution="dated")

    target = _alias_target(model, config)
    if target:
        t_provider, _, t_model = target.partition(":")
        if not t_model:
            t_provider, t_model = provider, t_provider
        if (t_provider, t_model) != (provider, model):
            via_alias = find_pricing(t_provider, t_model, config, _depth + 1)
            if via_alias:
                return replace(via_alias, resolution="alias")

    providers = config.get("providers", {}) or {}
    model_config = ((providers.get(provider, {}) or {}).get("models", {}) or {}).get(model, {}) or {}
    if model in _HOP_NAMES or model_config.get("kind") == "cli":
        underlying = (model_config.get("extra") or {}).get("cli_model")
        if isinstance(underlying, str) and underlying and underlying != model:
            via_hop = find_pricing(provider, underlying, config, _depth + 1)
            if via_hop:
                return replace(via_hop, resolution="hop")

    return None


# ---------------------------------------------------------------------------
# cycle-129 FR-7 (SDD D-7.6): the price lookup CLI the dissent budget gate asks.
#
#   python3 -m loa_cheval.metering.pricing --alias <alias> [--alias <alias>…] [--json]
#                                          [--catalog <model-config.yaml>] [--config <.loa.config.yaml>]
#
# One line per alias: `alias=<a> input_per_mtok=<n> output_per_mtok=<n> pricing_source=<config|stale_catalog|unknown>`
# (with --json, one JSON object per line). Rates are the catalog's unit: micro-USD per million tokens. An alias with
# no catalog price prints `-` for both rates and `pricing_source=unknown` — the caller decides the fallback; no price
# is ever invented here. The catalog is the System Zone file beside this package, overlaid with the project
# config's `hounfour.providers` / `hounfour.aliases` (the same two layers cheval merges). Exit 0 on any lookup,
# 2 on a usage error or an unreadable catalog.
# ---------------------------------------------------------------------------
_MAX_ALIAS_DEPTH = 10


def _merge(base: Any, overlay: Any) -> Any:
    if isinstance(base, dict) and isinstance(overlay, dict):
        out = dict(base)
        for key, value in overlay.items():
            out[key] = _merge(base.get(key), value) if key in base else value
        return out
    return overlay


def load_pricing_config(catalog_path: str, config_path: Optional[str]) -> Dict[str, Any]:
    """The catalog's providers / aliases / backward_compat_aliases overlaid with the project's `hounfour:` ones."""
    import yaml  # the package's own dependency (the loader reads YAML the same way)

    with open(catalog_path, "r", encoding="utf-8") as fh:
        catalog = yaml.safe_load(fh) or {}
    if not isinstance(catalog, dict):
        raise ValueError(f"catalog {catalog_path} is not a mapping")
    merged: Dict[str, Any] = {k: catalog.get(k) or {} for k in ("providers", "aliases", "backward_compat_aliases")}
    if config_path:
        try:
            with open(config_path, "r", encoding="utf-8") as fh:
                project = yaml.safe_load(fh) or {}
        except FileNotFoundError:
            project = {}
        hounfour = project.get("hounfour") if isinstance(project, dict) else None
        if isinstance(hounfour, dict):
            for key in ("providers", "aliases"):
                if isinstance(hounfour.get(key), dict):
                    merged[key] = _merge(merged.get(key) or {}, hounfour[key])
    return merged


def resolve_alias_target(alias: str, config: Dict[str, Any]) -> Optional[tuple]:
    """`provider:model` → (provider, model); an alias → its chain's target; a bare model id → its one provider.
    None when nothing (or more than one provider) matches."""
    name = (alias or "").strip()
    if not name:
        return None
    if ":" in name:
        provider, _, model = name.partition(":")
        return (provider, model) if provider and model else None
    current, seen = name, set()
    for _ in range(_MAX_ALIAS_DEPTH):
        target = _alias_target(current, config)
        if not target:
            break
        if ":" in target:
            provider, _, model = target.partition(":")
            return (provider, model) if provider and model else None
        if target in seen:
            return None
        seen.add(current)
        current = target
    providers = config.get("providers") or {}
    matches = [p for p, block in providers.items()
               if isinstance(block, dict) and current in (block.get("models") or {})]
    return (matches[0], current) if len(matches) == 1 else None


def lookup_alias(alias: str, config: Dict[str, Any], today: Optional[_dt.date] = None) -> Dict[str, Any]:
    """The budget gate's view of one alias: rates (micro-USD per Mtok) or None, and the pricing source."""
    target = resolve_alias_target(alias, config)
    entry = find_pricing(target[0], target[1], config) if target else None
    return {
        "alias": alias,
        "provider": target[0] if target else None,
        "model": target[1] if target else None,
        "input_per_mtok": entry.input_per_mtok if entry else None,
        "output_per_mtok": entry.output_per_mtok if entry else None,
        "pricing_source": pricing_source_for(entry, today),
        "resolution": entry.resolution if entry else None,
        "open_weight": bool(entry.open_weight) if entry else False,
        "price_date": entry.price_date if entry else None,
    }


def _main(argv: Optional[list] = None) -> int:
    import argparse
    import json
    import sys
    from pathlib import Path

    here = Path(__file__).resolve()
    parser = argparse.ArgumentParser(prog="python3 -m loa_cheval.metering.pricing",
                                     description="Print an alias's catalog price (micro-USD per million tokens).")
    parser.add_argument("--alias", action="append", required=True, help="model alias, id or provider:id (repeatable)")
    parser.add_argument("--json", action="store_true", help="one JSON object per alias")
    parser.add_argument("--catalog", default=str(here.parents[3] / "defaults" / "model-config.yaml"))
    parser.add_argument("--config", default=str(here.parents[4] / ".loa.config.yaml"),
                        help="project config whose hounfour.providers / hounfour.aliases overlay the catalog")
    args = parser.parse_args(argv)
    logging.basicConfig(level=logging.WARNING, format="[pricing] %(message)s")
    try:
        config = load_pricing_config(args.catalog, args.config)
    except Exception as exc:  # noqa: BLE001 — an unreadable catalog is a usage error, said
        print(f"pricing: cannot read the catalog: {type(exc).__name__}: {exc}"[:300], file=sys.stderr)
        return 2
    for alias in args.alias:
        row = lookup_alias(alias, config)
        if args.json:
            print(json.dumps(row, sort_keys=True))
        else:
            rate = lambda v: "-" if v is None else str(v)  # noqa: E731
            print(f"alias={alias} input_per_mtok={rate(row['input_per_mtok'])} "
                  f"output_per_mtok={rate(row['output_per_mtok'])} pricing_source={row['pricing_source']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
