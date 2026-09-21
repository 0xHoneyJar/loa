"""Integer micro-USD pricing — extracted from loa-finn pricing.ts (SDD §4.5).

All prices in micro-USD per million tokens. 1 USD = 1,000,000 micro-USD.
No floating-point anywhere in the cost path.
"""

from __future__ import annotations

import logging

from dataclasses import dataclass
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


def find_pricing(
    provider: str,
    model: str,
    config: Dict[str, Any],
) -> Optional[PricingEntry]:
    """Look up pricing from config providers section.

    Returns PricingEntry if found, None otherwise.
    """
    providers = config.get("providers", {})
    provider_config = providers.get(provider, {})
    model_config = provider_config.get("models", {}).get(model, {})
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
    )
