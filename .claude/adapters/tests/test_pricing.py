"""Tests for integer micro-USD pricing (Sprint 3, SDD §4.5)."""

import json
import os
import tempfile

import pytest

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from loa_cheval.metering.pricing import (
    CostBreakdown,
    PricingEntry,
    RemainderAccumulator,
    calculate_cost_micro,
    calculate_total_cost,
    find_pricing,
)
from loa_cheval.metering.ledger import (
    append_ledger,
    create_ledger_entry,
    read_daily_spend,
    read_ledger,
    record_cost,
    update_daily_spend,
)


# ── Pricing Calculation Tests ─────────────────────────────────────────────────


class TestCalculateCostMicro:
    """Integer micro-USD arithmetic tests."""

    def test_basic_calculation(self):
        """1000 tokens at $10/1M = 10,000 micro-USD."""
        cost, remainder = calculate_cost_micro(1000, 10_000_000)
        assert cost == 10_000
        assert remainder == 0

    def test_small_token_count(self):
        """100 tokens at $10/1M = 1,000 micro-USD."""
        cost, remainder = calculate_cost_micro(100, 10_000_000)
        assert cost == 1_000
        assert remainder == 0

    def test_remainder_produced(self):
        """Non-divisible amounts produce remainder."""
        cost, remainder = calculate_cost_micro(1, 10_000_000)
        assert cost == 10
        assert remainder == 0

    def test_very_small_with_remainder(self):
        """3 tokens at $2.50/1M → cost=7, remainder=500000."""
        cost, remainder = calculate_cost_micro(3, 2_500_000)
        assert cost == 7
        assert remainder == 500_000

    def test_zero_tokens(self):
        cost, remainder = calculate_cost_micro(0, 10_000_000)
        assert cost == 0
        assert remainder == 0

    def test_zero_price(self):
        cost, remainder = calculate_cost_micro(1000, 0)
        assert cost == 0
        assert remainder == 0

    def test_large_realistic_values(self):
        """200K tokens at $75/1M (Opus output)."""
        cost, remainder = calculate_cost_micro(200_000, 75_000_000)
        assert cost == 15_000_000  # $15.00

    def test_overflow_guard(self):
        """Overflow detection for unrealistic values."""
        with pytest.raises(ValueError, match="BUDGET_OVERFLOW"):
            calculate_cost_micro(10**10, 10**10)


class TestCalculateTotalCost:
    """Full cost breakdown tests."""

    OPENAI_PRICING = PricingEntry(
        provider="openai",
        model="gpt-5.2",
        input_per_mtok=10_000_000,   # $10/1M
        output_per_mtok=30_000_000,  # $30/1M
        reasoning_per_mtok=0,
    )

    ANTHROPIC_PRICING = PricingEntry(
        provider="anthropic",
        model="claude-opus-4-6",
        input_per_mtok=5_000_000,     # $5/1M
        output_per_mtok=25_000_000,   # $25/1M
        reasoning_per_mtok=25_000_000,
    )

    def test_openai_basic(self):
        breakdown = calculate_total_cost(
            input_tokens=4200,
            output_tokens=1800,
            reasoning_tokens=0,
            pricing=self.OPENAI_PRICING,
        )
        # 4200 * 10M / 1M = 42,000
        assert breakdown.input_cost_micro == 42_000
        # 1800 * 30M / 1M = 54,000
        assert breakdown.output_cost_micro == 54_000
        assert breakdown.reasoning_cost_micro == 0
        assert breakdown.total_cost_micro == 96_000

    def test_anthropic_with_reasoning(self):
        breakdown = calculate_total_cost(
            input_tokens=10000,
            output_tokens=2000,
            reasoning_tokens=5000,
            pricing=self.ANTHROPIC_PRICING,
        )
        assert breakdown.input_cost_micro == 50_000   # 10K * $5/1M
        assert breakdown.output_cost_micro == 50_000   # 2K * $25/1M
        assert breakdown.reasoning_cost_micro == 125_000  # 5K * $25/1M
        assert breakdown.total_cost_micro == 225_000

    def test_zero_usage(self):
        breakdown = calculate_total_cost(0, 0, 0, self.OPENAI_PRICING)
        assert breakdown.total_cost_micro == 0


class TestRemainderAccumulator:
    """Remainder carry tests."""

    def test_accumulate_and_carry(self):
        acc = RemainderAccumulator()
        # 3 carries of 500K → total 1.5M → should carry 1
        carry1 = acc.carry("test", 500_000)
        assert carry1 == 0
        carry2 = acc.carry("test", 500_000)
        assert carry2 == 1  # 1M accumulated → carry 1
        assert acc.get("test") == 0  # Remainder cleared

    def test_multiple_scopes(self):
        acc = RemainderAccumulator()
        acc.carry("scope-a", 700_000)
        acc.carry("scope-b", 300_000)
        assert acc.get("scope-a") == 700_000
        assert acc.get("scope-b") == 300_000

    def test_clear(self):
        acc = RemainderAccumulator()
        acc.carry("test", 500_000)
        acc.clear()
        assert acc.get("test") == 0

    def test_no_carry_below_million(self):
        acc = RemainderAccumulator()
        carry = acc.carry("test", 999_999)
        assert carry == 0
        assert acc.get("test") == 999_999


class TestFindPricing:
    """Config-based pricing lookup tests."""

    CONFIG = {
        "providers": {
            "openai": {
                "models": {
                    "gpt-5.2": {
                        "pricing": {
                            "input_per_mtok": 10_000_000,
                            "output_per_mtok": 30_000_000,
                        }
                    }
                }
            },
            "google": {
                "models": {
                    "gemini-2.5-flash": {
                        "pricing": {
                            "input_per_mtok": 150_000,
                            "output_per_mtok": 600_000,
                        }
                    },
                    "gemini-2.5-pro": {
                        "pricing": {
                            "input_per_mtok": 1_250_000,
                            "output_per_mtok": 10_000_000,
                        }
                    }
                }
            }
        }
    }

    def test_found(self):
        pricing = find_pricing("openai", "gpt-5.2", self.CONFIG)
        assert pricing is not None
        assert pricing.input_per_mtok == 10_000_000

    def test_google_found(self):
        pricing = find_pricing("google", "gemini-2.5-flash", self.CONFIG)
        assert pricing is not None
        assert pricing.input_per_mtok == 150_000
        assert pricing.output_per_mtok == 600_000

    def test_google_cost_calculation(self):
        pricing = find_pricing("google", "gemini-2.5-flash", self.CONFIG)
        assert pricing is not None
        breakdown = calculate_total_cost(
            input_tokens=10000,
            output_tokens=2000,
            reasoning_tokens=0,
            pricing=pricing,
        )
        # 10000 * 150_000 / 1M = 1_500 micro-USD
        assert breakdown.input_cost_micro == 1_500
        # 2000 * 600_000 / 1M = 1_200 micro-USD
        assert breakdown.output_cost_micro == 1_200
        assert breakdown.total_cost_micro == 2_700

    def test_not_found_provider(self):
        assert find_pricing("mistral", "mistral-large", self.CONFIG) is None

    def test_not_found_model(self):
        assert find_pricing("openai", "gpt-99", self.CONFIG) is None


# ── Ledger Tests ──────────────────────────────────────────────────────────────


class TestLedgerAppend:
    """JSONL append and read tests."""

    def test_append_and_read(self, tmp_path):
        ledger = str(tmp_path / "test.jsonl")
        entry = {"ts": "2026-02-10T12:00:00Z", "cost_micro_usd": 1000, "agent": "test"}

        append_ledger(entry, ledger)
        append_ledger(entry, ledger)

        entries = read_ledger(ledger)
        assert len(entries) == 2
        assert entries[0]["cost_micro_usd"] == 1000

    def test_read_empty_file(self, tmp_path):
        ledger = str(tmp_path / "empty.jsonl")
        with open(ledger, "w"):
            pass
        entries = read_ledger(ledger)
        assert entries == []

    def test_read_nonexistent(self, tmp_path):
        entries = read_ledger(str(tmp_path / "nope.jsonl"))
        assert entries == []

    def test_corruption_recovery(self, tmp_path):
        ledger = str(tmp_path / "corrupt.jsonl")
        with open(ledger, "w") as f:
            f.write('{"valid": true}\n')
            f.write('this is not json\n')
            f.write('{"also_valid": true}\n')

        entries = read_ledger(ledger)
        assert len(entries) == 2


class TestCreateLedgerEntry:
    """Entry creation tests."""

    CONFIG = {
        "providers": {
            "openai": {
                "models": {
                    "gpt-5.2": {
                        "pricing": {
                            "input_per_mtok": 10_000_000,
                            "output_per_mtok": 30_000_000,
                        }
                    }
                }
            }
        }
    }

    def test_known_pricing(self):
        entry = create_ledger_entry(
            trace_id="tr-test",
            agent="reviewing-code",
            provider="openai",
            model="gpt-5.2",
            input_tokens=1000,
            output_tokens=500,
            reasoning_tokens=0,
            latency_ms=2000,
            config=self.CONFIG,
        )
        assert entry["pricing_source"] == "config"
        assert entry["cost_micro_usd"] == 25_000  # 1K*$10 + 500*$30
        assert entry["usage_source"] == "actual"

    def test_unknown_pricing(self):
        entry = create_ledger_entry(
            trace_id="tr-test",
            agent="unknown-agent",
            provider="mistral",
            model="mistral-large",
            input_tokens=1000,
            output_tokens=500,
            reasoning_tokens=0,
            latency_ms=1000,
            config=self.CONFIG,
        )
        assert entry["pricing_source"] == "unknown"
        assert entry["cost_micro_usd"] == 0

    def test_estimated_usage(self):
        entry = create_ledger_entry(
            trace_id="tr-test",
            agent="test",
            provider="openai",
            model="gpt-5.2",
            input_tokens=1000,
            output_tokens=500,
            reasoning_tokens=0,
            latency_ms=1000,
            config=self.CONFIG,
            usage_source="estimated",
        )
        assert entry["usage_source"] == "estimated"
        assert entry["cost_micro_usd"] > 0  # Still calculated

    def test_entry_has_all_fields(self):
        entry = create_ledger_entry(
            trace_id="tr-test",
            agent="test",
            provider="openai",
            model="gpt-5.2",
            input_tokens=100,
            output_tokens=50,
            reasoning_tokens=0,
            latency_ms=500,
            config=self.CONFIG,
            phase_id="flatline_prd",
            sprint_id="sprint-3",
            attempt=2,
        )
        required = [
            "ts", "trace_id", "request_id", "agent", "provider", "model",
            "tokens_in", "tokens_out", "tokens_reasoning", "latency_ms",
            "cost_micro_usd", "usage_source", "pricing_source",
            "phase_id", "sprint_id", "attempt",
        ]
        for field in required:
            assert field in entry, f"Missing field: {field}"


class TestDailySpend:
    """Daily spend counter tests."""

    def test_update_and_read(self, tmp_path):
        ledger = str(tmp_path / "test.jsonl")
        update_daily_spend(50_000, ledger)
        update_daily_spend(30_000, ledger)
        spent = read_daily_spend(ledger)
        assert spent == 80_000

    def test_read_nonexistent(self, tmp_path):
        ledger = str(tmp_path / "nope.jsonl")
        assert read_daily_spend(ledger) == 0

    def test_record_cost_updates_both(self, tmp_path):
        ledger = str(tmp_path / "test.jsonl")
        entry = {"ts": "2026-02-10T12:00:00Z", "cost_micro_usd": 42_000}
        record_cost(entry, ledger)

        entries = read_ledger(ledger)
        assert len(entries) == 1

        spent = read_daily_spend(ledger)
        assert spent == 42_000
