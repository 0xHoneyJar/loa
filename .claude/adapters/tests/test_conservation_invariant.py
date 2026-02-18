"""Conservation invariant property-based tests (Sprint 7, Task 7.4).

The conservation invariant is the most important architectural property
in the metering system. It spans three layers (pricing → budget → ledger)
and states:

    For any cost calculation:
        tokens * price_per_million == cost_micro * 1_000_000 + remainder

    Equivalently:
        cost_micro + remainder == tokens * price_per_million

This is verified nowhere as a cross-cutting property. These tests use
randomized inputs to verify the invariant holds across the full range.

Bridgebuilder Review Part II: "The conservation invariant is a social
contract — it promises that no micro-USD is ever created or destroyed
in the cost pipeline."

Uses hypothesis for property-based testing where available, falls back
to parameterized range tests otherwise.
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from loa_cheval.metering.pricing import (
    MAX_SAFE_PRODUCT,
    CostBreakdown,
    PricingEntry,
    RemainderAccumulator,
    calculate_cost_micro,
    calculate_total_cost,
)
from loa_cheval.metering.ledger import create_ledger_entry

# ── Constants ────────────────────────────────────────────────────────────────

# Safe ranges that won't trigger overflow
MAX_SAFE_TOKENS = 10_000_000  # 10M tokens
MAX_SAFE_PRICE = 100_000_000  # $100/1M tokens in micro-USD

CONFIG_WITH_PRICING = {
    "providers": {
        "openai": {
            "models": {
                "gpt-5.2": {
                    "pricing": {
                        "input_per_mtok": 10_000_000,
                        "output_per_mtok": 30_000_000,
                    },
                },
            },
        },
        "google": {
            "models": {
                "deep-research-pro": {
                    "pricing": {
                        "per_task_micro_usd": 50_000_000,
                        "pricing_mode": "task",
                    },
                },
            },
        },
    },
}


# ── Property Tests (hypothesis) ──────────────────────────────────────────────
# Conditionally defined: class bodies reference hypothesis decorators at
# definition time, so skipif alone is insufficient — we must guard the
# entire class definition behind the import check.

try:
    from hypothesis import given, settings, assume
    from hypothesis.strategies import integers

    class TestConservationPropertyHypothesis:
        """Property-based tests using hypothesis library."""

        @given(
            tokens=integers(min_value=0, max_value=MAX_SAFE_TOKENS),
            price=integers(min_value=0, max_value=MAX_SAFE_PRICE),
        )
        @settings(max_examples=200)
        def test_cost_plus_remainder_equals_product(self, tokens, price):
            """INV-001: cost_micro * 1_000_000 + remainder == tokens * price.

            The fundamental conservation invariant: no micro-USD is created
            or destroyed during integer division.
            """
            assume(tokens * price <= MAX_SAFE_PRODUCT)
            cost, remainder = calculate_cost_micro(tokens, price)
            assert cost * 1_000_000 + remainder == tokens * price

        @given(
            tokens=integers(min_value=0, max_value=MAX_SAFE_TOKENS),
            price=integers(min_value=0, max_value=MAX_SAFE_PRICE),
        )
        @settings(max_examples=200)
        def test_remainder_bounded(self, tokens, price):
            """Remainder is always in [0, 999_999]."""
            assume(tokens * price <= MAX_SAFE_PRODUCT)
            _, remainder = calculate_cost_micro(tokens, price)
            assert 0 <= remainder < 1_000_000

        @given(
            tokens=integers(min_value=0, max_value=MAX_SAFE_TOKENS),
            price=integers(min_value=0, max_value=MAX_SAFE_PRICE),
        )
        @settings(max_examples=200)
        def test_cost_non_negative(self, tokens, price):
            """Cost is always non-negative."""
            assume(tokens * price <= MAX_SAFE_PRODUCT)
            cost, _ = calculate_cost_micro(tokens, price)
            assert cost >= 0

    class TestRemainderAccumulatorPropertyHypothesis:
        """Accumulator conservation: sum(carries) + final_remainder == sum(inputs)."""

        @given(
            r1=integers(min_value=0, max_value=999_999),
            r2=integers(min_value=0, max_value=999_999),
            r3=integers(min_value=0, max_value=999_999),
            r4=integers(min_value=0, max_value=999_999),
            r5=integers(min_value=0, max_value=999_999),
        )
        @settings(max_examples=200)
        def test_accumulator_conservation(self, r1, r2, r3, r4, r5):
            """Sum of carry outputs * 1M + final remainder == sum of inputs.

            This verifies the RemainderAccumulator never creates or destroys
            value during accumulation across multiple requests.
            """
            acc = RemainderAccumulator()
            remainders = [r1, r2, r3, r4, r5]
            total_input = sum(remainders)
            total_carried = 0

            for r in remainders:
                carry = acc.carry("test", r)
                total_carried += carry

            final_remainder = acc.get("test")
            assert total_carried * 1_000_000 + final_remainder == total_input

except ImportError:
    pass  # hypothesis not available — range-based tests below cover the same invariants


# ── Fallback Tests (no hypothesis) ──────────────────────────────────────────


class TestConservationPropertyRange:
    """Range-based conservation tests (no hypothesis required)."""

    # Representative token counts and prices
    TOKEN_SAMPLES = [0, 1, 3, 7, 42, 100, 999, 1000, 5000, 10000, 100000, 1000000]
    PRICE_SAMPLES = [0, 1, 100, 1000, 150_000, 600_000, 1_250_000, 2_500_000,
                     5_000_000, 10_000_000, 25_000_000, 30_000_000, 75_000_000]

    def test_conservation_across_range(self):
        """INV-001: cost * 1M + remainder == tokens * price for all sample pairs."""
        for tokens in self.TOKEN_SAMPLES:
            for price in self.PRICE_SAMPLES:
                product = tokens * price
                if product > MAX_SAFE_PRODUCT:
                    continue
                cost, remainder = calculate_cost_micro(tokens, price)
                assert cost * 1_000_000 + remainder == product, (
                    f"Conservation violated: tokens={tokens}, price={price}, "
                    f"cost={cost}, remainder={remainder}, product={product}"
                )

    def test_remainder_always_bounded(self):
        """Remainder in [0, 999_999] for all sample pairs."""
        for tokens in self.TOKEN_SAMPLES:
            for price in self.PRICE_SAMPLES:
                if tokens * price > MAX_SAFE_PRODUCT:
                    continue
                _, remainder = calculate_cost_micro(tokens, price)
                assert 0 <= remainder < 1_000_000

    def test_cost_always_non_negative(self):
        """Cost >= 0 for all non-negative inputs."""
        for tokens in self.TOKEN_SAMPLES:
            for price in self.PRICE_SAMPLES:
                if tokens * price > MAX_SAFE_PRODUCT:
                    continue
                cost, _ = calculate_cost_micro(tokens, price)
                assert cost >= 0


class TestRemainderAccumulatorConservation:
    """Accumulator conservation without hypothesis."""

    def test_exact_carry_at_million(self):
        """500K + 500K = 1M → carry 1, remainder 0."""
        acc = RemainderAccumulator()
        c1 = acc.carry("s", 500_000)
        c2 = acc.carry("s", 500_000)
        assert c1 == 0
        assert c2 == 1
        assert acc.get("s") == 0
        # Conservation: (0 + 1) * 1M + 0 == 500K + 500K
        assert (c1 + c2) * 1_000_000 + acc.get("s") == 1_000_000

    def test_multi_step_conservation(self):
        """Conservation over 10 accumulated remainders."""
        acc = RemainderAccumulator()
        remainders = [333_333, 666_667, 1, 999_999, 500_000,
                      250_000, 750_000, 100_000, 900_000, 499_999]
        total_input = sum(remainders)
        total_carried = 0

        for r in remainders:
            carry = acc.carry("scope", r)
            total_carried += carry

        final = acc.get("scope")
        assert total_carried * 1_000_000 + final == total_input

    def test_large_remainder_multi_carry(self):
        """When accumulated remainder >> 1M, extra carry is correct."""
        acc = RemainderAccumulator()
        # 999_999 * 3 = 2_999_997 → should carry 2, remainder 999_997
        c1 = acc.carry("s", 999_999)
        c2 = acc.carry("s", 999_999)
        c3 = acc.carry("s", 999_999)
        total_carried = c1 + c2 + c3
        assert total_carried * 1_000_000 + acc.get("s") == 999_999 * 3

    def test_independent_scopes_conserve_independently(self):
        """Each scope key maintains independent conservation."""
        acc = RemainderAccumulator()
        ca1 = acc.carry("a", 600_000)
        cb1 = acc.carry("b", 400_000)
        ca2 = acc.carry("a", 600_000)
        cb2 = acc.carry("b", 400_000)

        total_a = (ca1 + ca2) * 1_000_000 + acc.get("a")
        total_b = (cb1 + cb2) * 1_000_000 + acc.get("b")
        assert total_a == 1_200_000
        assert total_b == 800_000


class TestTotalCostConservation:
    """calculate_total_cost conserves across input/output/reasoning."""

    def test_token_mode_conservation(self):
        """Token mode: total == sum of components."""
        pricing = PricingEntry(
            provider="openai", model="gpt-5.2",
            input_per_mtok=10_000_000, output_per_mtok=30_000_000,
            reasoning_per_mtok=25_000_000,
        )
        breakdown = calculate_total_cost(
            input_tokens=1234, output_tokens=567, reasoning_tokens=890,
            pricing=pricing,
        )
        assert breakdown.total_cost_micro == (
            breakdown.input_cost_micro +
            breakdown.output_cost_micro +
            breakdown.reasoning_cost_micro
        )

    def test_task_mode_ignores_tokens(self):
        """Task mode: total == per_task_micro_usd, token costs zero."""
        pricing = PricingEntry(
            provider="google", model="deep-research-pro",
            input_per_mtok=0, output_per_mtok=0,
            per_task_micro_usd=50_000_000,
            pricing_mode="task",
        )
        breakdown = calculate_total_cost(
            input_tokens=10000, output_tokens=5000, reasoning_tokens=0,
            pricing=pricing,
        )
        assert breakdown.total_cost_micro == 50_000_000
        assert breakdown.input_cost_micro == 0
        assert breakdown.output_cost_micro == 0
        assert breakdown.remainder_input == 0
        assert breakdown.remainder_output == 0

    def test_hybrid_mode_conservation(self):
        """Hybrid mode: total == token_cost + per_task_cost."""
        pricing = PricingEntry(
            provider="google", model="hybrid-model",
            input_per_mtok=2_500_000, output_per_mtok=15_000_000,
            per_task_micro_usd=1_000_000,
            pricing_mode="hybrid",
        )
        breakdown = calculate_total_cost(
            input_tokens=1000, output_tokens=500, reasoning_tokens=0,
            pricing=pricing,
        )
        token_total = breakdown.input_cost_micro + breakdown.output_cost_micro
        assert breakdown.total_cost_micro == token_total + 1_000_000


class TestLedgerEntryRoundTrip:
    """create_ledger_entry preserves cost from calculate_total_cost."""

    def test_known_pricing_round_trip(self):
        """Ledger entry cost matches direct calculation."""
        entry = create_ledger_entry(
            trace_id="tr-test",
            agent="reviewing-code",
            provider="openai",
            model="gpt-5.2",
            input_tokens=4200,
            output_tokens=1800,
            reasoning_tokens=0,
            latency_ms=1000,
            config=CONFIG_WITH_PRICING,
        )
        # Direct calculation
        pricing = PricingEntry(
            provider="openai", model="gpt-5.2",
            input_per_mtok=10_000_000, output_per_mtok=30_000_000,
        )
        breakdown = calculate_total_cost(4200, 1800, 0, pricing)
        assert entry["cost_micro_usd"] == breakdown.total_cost_micro

    def test_zero_tokens_zero_cost(self):
        entry = create_ledger_entry(
            trace_id="tr-test",
            agent="test",
            provider="openai",
            model="gpt-5.2",
            input_tokens=0,
            output_tokens=0,
            reasoning_tokens=0,
            latency_ms=0,
            config=CONFIG_WITH_PRICING,
        )
        assert entry["cost_micro_usd"] == 0

    def test_task_pricing_round_trip(self):
        """Deep Research task pricing preserved in ledger entry."""
        entry = create_ledger_entry(
            trace_id="tr-test",
            agent="deep-researcher",
            provider="google",
            model="deep-research-pro",
            input_tokens=5000,
            output_tokens=10000,
            reasoning_tokens=0,
            latency_ms=60000,
            config=CONFIG_WITH_PRICING,
        )
        assert entry["cost_micro_usd"] == 50_000_000
        assert entry["pricing_mode"] == "task"


class TestDailySpendNonNegative:
    """INV-002: daily_spend >= 0 at all times."""

    def test_initial_spend_zero(self, tmp_path):
        from loa_cheval.metering.ledger import read_daily_spend
        assert read_daily_spend(str(tmp_path / "ledger.jsonl")) == 0

    def test_spend_increases_monotonically(self, tmp_path):
        """INV-004: daily spend only increases."""
        from loa_cheval.metering.ledger import read_daily_spend, update_daily_spend
        ledger_path = str(tmp_path / "ledger.jsonl")

        costs = [10_000, 20_000, 5_000, 100_000, 1]
        previous = 0
        for cost in costs:
            update_daily_spend(cost, ledger_path)
            current = read_daily_spend(ledger_path)
            assert current >= previous, f"Daily spend decreased: {current} < {previous}"
            previous = current

        assert previous == sum(costs)


class TestOverflowGuard:
    """Overflow detection prevents silent precision loss."""

    def test_overflow_detected(self):
        with pytest.raises(ValueError, match="BUDGET_OVERFLOW"):
            calculate_cost_micro(10**10, 10**10)

    def test_max_safe_product_boundary(self):
        """Values just under MAX_SAFE_PRODUCT succeed."""
        # 9_007_199 tokens at $1/1M = 9_007 micro-USD
        cost, remainder = calculate_cost_micro(9_007_199, 1_000_000)
        assert cost == 9_007_199
        assert remainder == 0
