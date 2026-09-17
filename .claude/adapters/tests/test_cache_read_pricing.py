"""cycle-124 Sprint 1 Task 1.6 (FR-4 / SDD §2.4) — prompt-cache pricing.

Anthropic bills cache reads at 0.1× input (Fable 5.1: 0.025×, an explicit
catalog exception) and cache writes at 1.25× input; `usage.input_tokens`
excludes both. The metering path prices them from the catalog rates, the
ledger row records them, and the MODELINV pricing_snapshot carries the rates
so roll-ups never re-price history from today's catalog.
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest
import yaml

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from loa_cheval.metering.ledger import create_ledger_entry  # noqa: E402
from loa_cheval.metering.pricing import (  # noqa: E402
    PricingEntry,
    calculate_total_cost,
    find_pricing,
)

CATALOG = ROOT.parents[1] / ".claude" / "defaults" / "model-config.yaml"


@pytest.fixture(scope="module")
def catalog() -> dict:
    with CATALOG.open() as fh:
        return yaml.safe_load(fh)


def test_find_pricing_reads_explicit_cache_rate_and_derives_write_rate(catalog):
    opus = find_pricing("anthropic", "claude-opus-5", catalog)
    assert opus.input_per_mtok == 5_000_000
    assert opus.cache_read_per_mtok == 500_000            # explicit in the catalog (0.1×)
    assert opus.cache_write_per_mtok == 6_250_000         # derived 1.25×
    fable = find_pricing("anthropic", "claude-fable-5-1", catalog)
    assert fable.cache_read_per_mtok == 250_000           # documented 0.025× exception
    assert fable.cache_write_per_mtok == 12_500_000


def test_find_pricing_derives_defaults_when_catalog_has_no_cache_rate():
    cfg = {"providers": {"openai": {"models": {"gpt-x": {"pricing": {"input_per_mtok": 2_000_000, "output_per_mtok": 8_000_000}}}}}}
    entry = find_pricing("openai", "gpt-x", cfg)
    assert entry.cache_read_per_mtok == 200_000
    assert entry.cache_write_per_mtok == 2_500_000


def test_cache_tokens_are_priced_at_their_own_rates():
    pricing = PricingEntry(provider="anthropic", model="claude-opus-5",
                           input_per_mtok=5_000_000, output_per_mtok=25_000_000,
                           cache_read_per_mtok=500_000, cache_write_per_mtok=6_250_000)
    plain = calculate_total_cost(1_000, 100, 0, pricing)
    assert plain.total_cost_micro == 5_000 + 2_500
    assert plain.cache_read_cost_micro == 0 and plain.cache_write_cost_micro == 0

    cached = calculate_total_cost(1_000, 100, 0, pricing, cache_read_tokens=20_000, cache_creation_tokens=4_000)
    assert cached.cache_read_cost_micro == 10_000        # 20K × $0.50/M
    assert cached.cache_write_cost_micro == 25_000       # 4K × $6.25/M
    assert cached.total_cost_micro == 5_000 + 2_500 + 10_000 + 25_000
    # A cached call is cheaper than paying full input price for the same prefix.
    uncached_equiv = calculate_total_cost(1_000 + 20_000, 100, 0, pricing)
    assert cached.total_cost_micro - 25_000 < uncached_equiv.total_cost_micro


def test_task_mode_ignores_cache_tokens():
    pricing = PricingEntry(provider="google", model="deep-research", input_per_mtok=0, output_per_mtok=0,
                           per_task_micro_usd=1_000_000, pricing_mode="task",
                           cache_read_per_mtok=1, cache_write_per_mtok=1)
    out = calculate_total_cost(10, 10, 0, pricing, cache_read_tokens=10_000, cache_creation_tokens=10_000)
    assert out.total_cost_micro == 1_000_000
    assert out.cache_read_cost_micro == 0


def test_zero_rate_entries_price_cache_tokens_at_zero():
    pricing = PricingEntry(provider="x", model="y", input_per_mtok=1_000_000, output_per_mtok=1_000_000)
    out = calculate_total_cost(0, 0, 0, pricing, cache_read_tokens=1_000_000, cache_creation_tokens=1_000_000)
    assert out.total_cost_micro == 0


def test_ledger_entry_records_cache_tokens_only_when_present(catalog):
    base = dict(trace_id="tr-1", agent="reviewing-code", provider="anthropic", model="claude-opus-5",
                input_tokens=1_000, output_tokens=100, reasoning_tokens=0, latency_ms=5, config=catalog)
    plain = create_ledger_entry(**base)
    assert "tokens_cache_read" not in plain and "tokens_cache_creation" not in plain
    assert plain["cost_micro_usd"] == 5_000 + 2_500

    cached = create_ledger_entry(**base, cache_read_tokens=20_000, cache_creation_tokens=4_000)
    assert cached["tokens_cache_read"] == 20_000
    assert cached["tokens_cache_creation"] == 4_000
    assert cached["cost_micro_usd"] == 5_000 + 2_500 + 10_000 + 25_000
    assert cached["tokens_in"] == 1_000                  # input_tokens still excludes cache tokens


def test_cli_reported_cost_still_wins_over_cache_math(catalog):
    entry = create_ledger_entry(trace_id="tr-1", agent="a", provider="anthropic", model="claude-opus-5",
                                input_tokens=1_000, output_tokens=100, reasoning_tokens=0, latency_ms=5,
                                config=catalog, reported_cost_micro_usd=777,
                                cache_read_tokens=20_000, cache_creation_tokens=4_000)
    assert entry["cost_micro_usd"] == 777
    assert entry["pricing_source"] == "cli_reported"
    assert entry["tokens_cache_read"] == 20_000
