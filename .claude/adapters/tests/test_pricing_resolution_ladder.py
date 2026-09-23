"""cycle-125 Sprint 4 (PRD FR-5 AC 1–2, SDD §1.6) — the pricing resolution
ladder over the ids the fleet actually invokes (usage mining F5): dated
OpenAI releases, aliases, CLI-hop names. Each resolves through exact → dated
→ alias → hop with the rung recorded; unknown ids stay `unknown` and are
counted; ledger rows carry `pricing_resolution`, `resolved_model`,
`transport` and `cost_estimated`.
"""
from __future__ import annotations

import sys
from pathlib import Path

import pytest
import yaml

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from loa_cheval.metering.ledger import create_ledger_entry  # noqa: E402
from loa_cheval.metering.pricing import find_pricing  # noqa: E402

CATALOG = ROOT.parents[1] / ".claude" / "defaults" / "model-config.yaml"

# The fleet ids from grimoires/loa/reports/usage-mining-2026-09-23.md §F5,
# with the rung each one must resolve through against the real catalog.
FLEET_IDS = [
    ("openai", "gpt-5.5-2026-04-23", "dated", "gpt-5.5"),
    ("openai", "gpt-5.2-2025-12-11", "dated", "gpt-5.2"),
    ("google", "gemini-2.5-pro", "exact", "gemini-2.5-pro"),
    ("openai", "codex-headless", "hop", "gpt-5.5"),
    ("anthropic", "claude-headless", "hop", "claude-fable-5-1"),
    ("anthropic", "claude-fable-5-1", "exact", "claude-fable-5-1"),
    ("anthropic", "fable", "alias", "claude-fable-5-1"),
    ("openai", "gpt-5.5-pro", "exact", "gpt-5.5-pro"),
]


@pytest.fixture(scope="module")
def catalog() -> dict:
    with CATALOG.open() as fh:
        return yaml.safe_load(fh)


@pytest.mark.parametrize("provider,model,rung,priced_as", FLEET_IDS)
def test_fleet_ids_resolve_with_the_expected_rung(catalog, provider, model, rung, priced_as):
    entry = find_pricing(provider, model, catalog)
    assert entry is not None, f"{provider}:{model} did not resolve"
    assert entry.resolution == rung
    assert entry.model == priced_as
    assert entry.input_per_mtok > 0


def test_unknown_ids_stay_unknown(catalog):
    assert find_pricing("openai", "totally-unknown-model", catalog) is None
    assert find_pricing("nobody", "zzz-unknown-9000", catalog) is None
    assert find_pricing("openai", "", catalog) is None
    # an alias requested under the wrong provider still prices (the alias's provider wins)
    assert find_pricing("nobody", "gpt-5.5", catalog).resolution == "alias"


def test_exact_dated_entry_wins_over_stripping():
    cfg = {"providers": {"openai": {"models": {
        "gpt-x": {"pricing": {"input_per_mtok": 1_000_000, "output_per_mtok": 2_000_000}},
        "gpt-x-2026-01-01": {"pricing": {"input_per_mtok": 9_000_000, "output_per_mtok": 9_000_000}},
    }}}}
    e = find_pricing("openai", "gpt-x-2026-01-01", cfg)
    assert e.resolution == "exact" and e.input_per_mtok == 9_000_000


def test_dated_only_strips_when_the_base_exists():
    cfg = {"providers": {"openai": {"models": {
        "gpt-x": {"pricing": {"input_per_mtok": 1_000_000, "output_per_mtok": 2_000_000}},
    }}}}
    assert find_pricing("openai", "gpt-x-2026-01-01", cfg).resolution == "dated"
    assert find_pricing("openai", "gpt-y-2026-01-01", cfg) is None


def test_alias_can_cross_providers_and_hop_resolves_through_alias():
    cfg = {
        "aliases": {"fable": "anthropic:claude-fable-5-1", "codex-headless": "openai:codex-headless"},
        "providers": {
            "anthropic": {"models": {
                "claude-fable-5-1": {"pricing": {"input_per_mtok": 10_000_000, "output_per_mtok": 50_000_000}},
                "claude-headless": {"kind": "cli", "extra": {"cli_model": "fable"}},
            }},
            "openai": {"models": {
                "gpt-5.5": {"pricing": {"input_per_mtok": 5_000_000, "output_per_mtok": 25_000_000}},
                "codex-headless": {"kind": "cli", "extra": {"cli_model": "gpt-5.5"}},
                "a-loop": {"kind": "cli", "extra": {"cli_model": "a-loop"}},
            }},
        },
    }
    # alias requested under the wrong provider still prices via the alias's provider
    e = find_pricing("openai", "fable", cfg)
    assert e.resolution == "alias" and e.provider == "anthropic" and e.input_per_mtok == 10_000_000
    hop = find_pricing("anthropic", "claude-headless", cfg)
    assert hop.resolution == "hop" and hop.model == "claude-fable-5-1"
    assert find_pricing("openai", "codex-headless", cfg).resolution == "hop"
    # a hop that points at itself terminates
    assert find_pricing("openai", "a-loop", cfg) is None


def test_ledger_rows_carry_resolution_transport_and_estimate_flags(catalog):
    row = create_ledger_entry(
        trace_id="t", agent="a", provider="openai", model="gpt-5.5-2026-04-23",
        input_tokens=1000, output_tokens=100, reasoning_tokens=0, latency_ms=1,
        config=catalog, usage_source="actual",
    )
    assert row["pricing_source"] == "config" and row["pricing_resolution"] == "dated"
    assert row["cost_micro_usd"] > 0 and "cost_estimated" not in row

    est = create_ledger_entry(
        trace_id="t", agent="a", provider="anthropic", model="claude-headless",
        input_tokens=1000, output_tokens=100, reasoning_tokens=0, latency_ms=1,
        config=catalog, usage_source="estimated", resolved_model="fable", transport="cli:claude",
    )
    assert est["pricing_source"] == "config" and est["pricing_resolution"] == "hop"
    assert est["cost_estimated"] is True
    assert est["resolved_model"] == "fable" and est["transport"] == "cli:claude"

    unknown = create_ledger_entry(
        trace_id="t", agent="a", provider="openai", model="nope-9000",
        input_tokens=1000, output_tokens=100, reasoning_tokens=0, latency_ms=1,
        config=catalog, usage_source="actual",
    )
    assert unknown["pricing_source"] == "unknown" and unknown["cost_micro_usd"] == 0
    assert "pricing_resolution" not in unknown and "cost_estimated" not in unknown


def test_resolved_model_fallback_prices_a_row_whose_model_is_unknown(catalog):
    row = create_ledger_entry(
        trace_id="t", agent="a", provider="anthropic", model="some-hop-label",
        input_tokens=1000, output_tokens=100, reasoning_tokens=0, latency_ms=1,
        config=catalog, usage_source="actual", resolved_model="claude-fable-5-1",
    )
    assert row["pricing_source"] == "config" and row["pricing_resolution"] == "exact"
    assert row["resolved_model"] == "claude-fable-5-1"


def test_cli_reported_cost_still_wins_and_carries_no_resolution(catalog):
    row = create_ledger_entry(
        trace_id="t", agent="a", provider="anthropic", model="claude-headless",
        input_tokens=10, output_tokens=1, reasoning_tokens=0, latency_ms=1,
        config=catalog, usage_source="actual", reported_cost_micro_usd=1234,
    )
    assert row["pricing_source"] == "cli_reported" and row["cost_micro_usd"] == 1234
    assert "pricing_resolution" not in row
