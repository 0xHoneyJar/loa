"""cycle-126 Sprint 1 Task 1.7 (PRD FR-1.9, SDD D-1.9) — the pricing ladder
knows the long-context premium: an entry may declare
`pricing.long_context: {threshold_tokens, input_multiplier, output_multiplier}`
and `calculate_total_cost` applies the multipliers to the whole request when
the input exceeds the threshold. Entries without the block price as before.
"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from loa_cheval.metering.pricing import PricingEntry, calculate_total_cost, find_pricing  # noqa: E402

CONFIG = {
    "providers": {
        "anthropic": {
            "models": {
                "big": {
                    "pricing": {
                        "input_per_mtok": 5_000_000, "output_per_mtok": 25_000_000,
                        "long_context": {"threshold_tokens": 200_000, "input_multiplier": 2.0, "output_multiplier": 1.5},
                    }
                },
                "plain": {"pricing": {"input_per_mtok": 5_000_000, "output_per_mtok": 25_000_000}},
            }
        }
    }
}


def test_entry_carries_the_long_context_block():
    big = find_pricing("anthropic", "big", CONFIG)
    assert big.long_context_threshold == 200_000
    assert big.long_context_input_multiplier == 2.0 and big.long_context_output_multiplier == 1.5
    plain = find_pricing("anthropic", "plain", CONFIG)
    assert plain.long_context_threshold is None


def test_below_the_threshold_prices_as_before():
    big = find_pricing("anthropic", "big", CONFIG)
    plain = find_pricing("anthropic", "plain", CONFIG)
    a = calculate_total_cost(150_000, 10_000, 0, big)
    b = calculate_total_cost(150_000, 10_000, 0, plain)
    assert a.total_cost_micro == b.total_cost_micro == 150_000 * 5 + 10_000 * 25
    assert a.long_context_applied is False


def test_above_the_threshold_applies_the_multipliers_to_the_whole_request():
    big = find_pricing("anthropic", "big", CONFIG)
    c = calculate_total_cost(600_000, 10_000, 0, big)
    assert c.long_context_applied is True
    assert c.input_cost_micro == 600_000 * 5 * 2
    assert c.output_cost_micro == int(10_000 * 25 * 1.5)
    assert c.total_cost_micro == c.input_cost_micro + c.output_cost_micro
    # exactly at the threshold is NOT above it
    assert calculate_total_cost(200_000, 1, 0, big).long_context_applied is False


def test_missing_multipliers_default_to_one():
    entry = PricingEntry(provider="p", model="m", input_per_mtok=1_000_000, output_per_mtok=1_000_000,
                         long_context_threshold=100)
    c = calculate_total_cost(1_000, 1_000, 0, entry)
    assert c.long_context_applied is True and c.total_cost_micro == 2_000
