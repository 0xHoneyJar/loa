"""sprint-bug-245 (bead bd-ypbg) — explicit re-pricing of historical unpriced
ledger rows. `reprice_rows(rows, config, now_iso)` prices an `unknown` row
exactly as `create_ledger_entry` would price a fresh row with the same tokens
(ladder + `calculate_total_cost`), marks every changed row (`repriced_at`,
`repriced_from`, `cost_estimated`), never touches a priced or an unresolvable
row, never mutates its input, and is idempotent.
"""
from __future__ import annotations

import copy
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from loa_cheval.metering.ledger import create_ledger_entry  # noqa: E402
from loa_cheval.metering.reprice import is_unpriced, reprice_row, reprice_rows  # noqa: E402

CONFIG = {
    "providers": {
        "openai": {
            "models": {
                "gpt-5.5": {"pricing": {"input_per_mtok": 2_000_000, "output_per_mtok": 8_000_000}},
                "codex-headless": {"kind": "cli", "extra": {"cli_model": "gpt-5.5"}},
            }
        }
    },
    "aliases": {},
}
NOW = "2026-09-24T02:00:00Z"


def unknown_row(**over):
    row = {
        "ts": "2026-09-22T09:19:17.719Z",
        "request_id": "r-unknown",
        "agent": "codex-headless",
        "provider": "openai",
        "model": "codex-headless",
        "tokens_in": 47947,
        "tokens_out": 527,
        "tokens_reasoning": 0,
        "cost_micro_usd": 0,
        "pricing_source": "unknown",
        "pricing_mode": "token",
    }
    row.update(over)
    return row


def test_hop_row_is_repriced_with_marks_and_the_fresh_row_cost():
    rows = [unknown_row()]
    snapshot = copy.deepcopy(rows)
    out, stats = reprice_rows(rows, CONFIG, NOW)
    fresh = create_ledger_entry(
        trace_id="t", agent="a", provider="openai", model="codex-headless",
        input_tokens=47947, output_tokens=527, reasoning_tokens=0, latency_ms=0, config=CONFIG,
    )
    assert fresh["pricing_source"] == "config" and fresh["pricing_resolution"] == "hop"
    r = out[0]
    assert r["cost_micro_usd"] == fresh["cost_micro_usd"] > 0
    assert r["pricing_source"] == "config"
    assert r["pricing_resolution"] == "hop"
    assert r["resolved_model"] == "gpt-5.5"
    assert r["cost_estimated"] is True
    assert r["repriced_at"] == NOW
    assert r["repriced_from"] == {"pricing_source": "unknown", "cost_micro_usd": 0}
    # untouched identity fields
    assert r["request_id"] == "r-unknown" and r["ts"] == "2026-09-22T09:19:17.719Z" and r["tokens_in"] == 47947
    assert stats == {
        "rows_scanned": 1, "rows_repriced": 1, "rows_still_unpriced": 0,
        "rows_skipped_priced": 0, "micro_usd_added": r["cost_micro_usd"],
    }
    assert rows == snapshot, "the input rows are never mutated"


def test_unresolvable_row_stays_unknown_and_is_the_same_object():
    row = unknown_row(provider="acme", model="nope-9000")
    out, stats = reprice_rows([row], CONFIG, NOW)
    assert out[0] is row
    assert row["pricing_source"] == "unknown" and row["cost_micro_usd"] == 0 and "repriced_at" not in row
    assert stats["rows_still_unpriced"] == 1 and stats["rows_repriced"] == 0
    assert reprice_row(row, CONFIG, NOW) is None


def test_priced_rows_are_never_touched():
    config_row = unknown_row(request_id="c", model="gpt-5.5", cost_micro_usd=900, pricing_source="config", pricing_resolution="exact")
    cli_row = unknown_row(request_id="k", cost_micro_usd=1200, pricing_source="cli_reported")
    legacy_priced = unknown_row(request_id="l", cost_micro_usd=300)
    del legacy_priced["pricing_source"]  # pre-metadata row that carries a cost: unclassified, not unpriced
    out, stats = reprice_rows([config_row, cli_row, legacy_priced], CONFIG, NOW)
    assert out[0] is config_row and out[1] is cli_row and out[2] is legacy_priced
    assert stats["rows_skipped_priced"] == 3 and stats["rows_repriced"] == 0
    for r in (config_row, cli_row, legacy_priced):
        assert "repriced_at" not in r


def test_pre_metadata_row_with_cost_zero_is_unpriced_and_eligible():
    row = unknown_row(request_id="old0")
    del row["pricing_source"]  # no pricing_source, cost 0 → the report counts it unpriced (FIND-004 rule)
    assert is_unpriced(row)
    out, stats = reprice_rows([row], CONFIG, NOW)
    assert out[0]["pricing_source"] == "config" and out[0]["repriced_from"] == {"pricing_source": None, "cost_micro_usd": 0}
    assert stats["rows_repriced"] == 1


def test_repricing_is_idempotent():
    once, s1 = reprice_rows([unknown_row()], CONFIG, NOW)
    twice, s2 = reprice_rows(once, CONFIG, "2026-09-25T00:00:00Z")
    assert twice == once
    assert s1["rows_repriced"] == 1
    assert s2 == {"rows_scanned": 1, "rows_repriced": 0, "rows_still_unpriced": 0, "rows_skipped_priced": 1, "micro_usd_added": 0}


def test_resolved_model_hint_is_used_when_the_model_itself_does_not_resolve():
    row = unknown_row(model="some-other-cli", resolved_model="gpt-5.5")
    out, stats = reprice_rows([row], CONFIG, NOW)
    r = out[0]
    assert stats["rows_repriced"] == 1
    assert r["pricing_resolution"] == "exact" and r["resolved_model"] == "gpt-5.5" and r["cost_micro_usd"] > 0


def test_tokens_default_to_zero_when_absent_and_cache_tokens_are_priced():
    priced_cfg = copy.deepcopy(CONFIG)
    priced_cfg["providers"]["openai"]["models"]["gpt-5.5"]["pricing"]["cache_read_per_mtok"] = 200_000
    row = unknown_row(model="gpt-5.5", tokens_cache_read=1_000_000)
    del row["tokens_reasoning"]
    out, _ = reprice_rows([row], priced_cfg, NOW)
    fresh = create_ledger_entry(
        trace_id="t", agent="a", provider="openai", model="gpt-5.5",
        input_tokens=47947, output_tokens=527, reasoning_tokens=0, latency_ms=0, config=priced_cfg,
        cache_read_tokens=1_000_000,
    )
    assert out[0]["cost_micro_usd"] == fresh["cost_micro_usd"]
    no_tokens = unknown_row(model="gpt-5.5")
    for k in ("tokens_in", "tokens_out", "tokens_reasoning"):
        del no_tokens[k]
    out2, stats2 = reprice_rows([no_tokens], CONFIG, NOW)
    assert stats2["rows_repriced"] == 1 and out2[0]["cost_micro_usd"] == 0 and out2[0]["pricing_source"] == "config"
