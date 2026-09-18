"""cycle-124 Sprint 1 Task 1.3 (FR-3 / SDD §2.1) — Anthropic catalog floor.

Invariants over the LIVE `.claude/defaults/model-config.yaml` (not a
fixture): the catalog must describe the Opus 5 / Sonnet 5 / Fable 5.1
generation the way the `claude-api` reference (model table cached
2026-06-24) describes it, and every enforcement-critical field must carry
provenance. Values marked `reference` vs `probed` are recorded in
`grimoires/loa/reports/2026-09-17-cycle-124-catalog-evidence.md`.
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest
import yaml

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from cheval import _LEGACY_TRANSPORT_INPUT_WALL, _lookup_max_input_tokens  # noqa: E402
from loa_cheval.providers.base import default_max_tokens  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[3]
CATALOG = REPO_ROOT / ".claude" / "defaults" / "model-config.yaml"
LOA_CONFIG = REPO_ROOT / ".loa.config.yaml"
LOA_CONFIG_EXAMPLE = REPO_ROOT / ".loa.config.yaml.example"

# SDD §2.1 entry table.
FAMILY_1M = {
    "claude-fable-5-1",
    "claude-fable-5",
    "claude-opus-5",
    "claude-opus-4-8",
    "claude-opus-4-7",
    "claude-opus-4-6",
    "claude-sonnet-5",
    "claude-sonnet-4-6",
}
# Entries that emit `thinking: {type: adaptive}` (FR-1): required explicitly
# on the 4.6/4.7/4.8 family, default-on for Opus 5 / Sonnet 5; Fable rejects
# every thinking shape except adaptive-or-omitted, so it is NOT flagged.
ADAPTIVE = {
    "claude-opus-5",
    "claude-opus-4-8",
    "claude-opus-4-7",
    "claude-opus-4-6",
    "claude-sonnet-5",
    "claude-sonnet-4-6",
}
# `output_config.format` json_schema support per the reference.
STRUCTURED_JSON = {
    "claude-fable-5-1",
    "claude-fable-5",
    "claude-opus-5",
    "claude-opus-4-8",
    "claude-sonnet-5",
    "claude-haiku-4-5-20251001",
}
V2_INPUT_FIELDS = ("max_input_tokens", "streaming_max_input_tokens", "legacy_max_input_tokens")
# Documented exceptions to the 0.1× cache-read rule (catalog-evidence.md).
CACHE_READ_EXCEPTIONS = {"claude-fable-5-1": 250_000}  # 0.025× per the reference
CEILING_CAP = 180_000


@pytest.fixture(autouse=True)
def _streaming_default_env(monkeypatch):
    """default_max_tokens() reads two env switches; the ceiling arithmetic is
    defined against the streaming default (audit slice D: the test used to
    mirror the helper locally and would not have noticed a constant change)."""
    monkeypatch.delenv("LOA_CHEVAL_DISABLE_STREAMING", raising=False)
    monkeypatch.delenv("LOA_CHEVAL_LEGACY_WIRE", raising=False)


def _default_max_tokens(entry: dict) -> int:
    return default_max_tokens(provider="anthropic", model_max_output=entry.get("max_output_tokens"))


@pytest.fixture(scope="module")
def catalog() -> dict:
    with CATALOG.open() as fh:
        return yaml.safe_load(fh)


@pytest.fixture(scope="module")
def anthropic(catalog) -> dict:
    return catalog["providers"]["anthropic"]["models"]


@pytest.fixture(scope="module")
def http_entries(anthropic) -> dict:
    return {k: v for k, v in anthropic.items() if v.get("auth_type") == "http_api"}


def test_new_generation_entries_exist(anthropic):
    for model_id in ("claude-opus-5", "claude-fable-5-1"):
        assert model_id in anthropic, f"{model_id} missing from providers.anthropic.models"
        assert anthropic[model_id].get("auth_type") == "http_api"


@pytest.mark.parametrize("model_id", sorted(FAMILY_1M))
def test_family_is_1m_context_128k_output(anthropic, model_id):
    entry = anthropic[model_id]
    assert entry.get("context_window") == 1_000_000, model_id
    assert entry.get("max_output_tokens") == 128_000, model_id


def test_no_anthropic_entry_carries_v2_input_fields(anthropic):
    offenders = {
        model_id: [f for f in V2_INPUT_FIELDS if f in entry]
        for model_id, entry in anthropic.items()
        if any(f in entry for f in V2_INPUT_FIELDS)
    }
    assert offenders == {}, offenders


def test_every_http_entry_has_ceiling_with_provenance(http_entries):
    for model_id, entry in http_entries.items():
        ceiling = entry.get("effective_input_ceiling")
        assert isinstance(ceiling, int) and ceiling > 0, f"{model_id}: no positive effective_input_ceiling"
        cal = entry.get("ceiling_calibration")
        assert isinstance(cal, dict), f"{model_id}: enforcement-critical ceiling without ceiling_calibration"
        assert cal.get("source") in ("empirical_probe", "kf_derived", "operator_set", "conservative_default"), model_id
        assert isinstance(cal.get("stale_after_days"), int) and cal["stale_after_days"] > 0, model_id


def test_ceiling_is_the_computed_value_per_entry(http_entries):
    """SDD §2.1: ceiling = min(180000, context_window − default_max_tokens(entry)) — computed, not a constant."""
    for model_id, entry in http_entries.items():
        expected = min(CEILING_CAP, entry["context_window"] - _default_max_tokens(entry))
        assert entry["effective_input_ceiling"] == expected, (model_id, entry["effective_input_ceiling"], expected)
        assert entry["effective_input_ceiling"] + _default_max_tokens(entry) <= entry["context_window"], model_id


@pytest.mark.parametrize("kill_switch", ["", "1"])
def test_input_gate_positive_with_and_without_streaming_kill_switch(catalog, http_entries, monkeypatch, kill_switch):
    if kill_switch:
        monkeypatch.setenv("LOA_CHEVAL_DISABLE_STREAMING", kill_switch)
    else:
        monkeypatch.delenv("LOA_CHEVAL_DISABLE_STREAMING", raising=False)
    for model_id in http_entries:
        threshold = _lookup_max_input_tokens("anthropic", model_id, catalog)
        assert isinstance(threshold, int) and threshold > 0, (model_id, kill_switch, threshold)


def test_legacy_wall_applies_only_to_anthropic_under_the_kill_switch(catalog, http_entries, monkeypatch):
    """SDD §3.2: 180K was probed under streaming; killing streaming re-applies the 36K KF-002 wall."""
    assert _LEGACY_TRANSPORT_INPUT_WALL == 36_000
    monkeypatch.delenv("LOA_CHEVAL_DISABLE_STREAMING", raising=False)
    for model_id in http_entries:
        assert _lookup_max_input_tokens("anthropic", model_id, catalog) == CEILING_CAP, model_id
    monkeypatch.setenv("LOA_CHEVAL_DISABLE_STREAMING", "1")
    for model_id in http_entries:
        assert _lookup_max_input_tokens("anthropic", model_id, catalog) == _LEGACY_TRANSPORT_INPUT_WALL, model_id
    # Non-Anthropic entries keep their own v2 split fields (openai legacy 24K), untouched by the constant.
    assert _lookup_max_input_tokens("openai", "gpt-5.5", catalog) == 24_000


def test_thinking_adaptive_exactly_on_the_adaptive_set(anthropic):
    flagged = {m for m, e in anthropic.items() if (e.get("params") or {}).get("thinking_adaptive") is True}
    assert flagged == ADAPTIVE
    # Any non-boolean value is a misspelling the schema cannot catch —
    # `is None or isinstance(bool)`, because `1 in (None, True, False)` is True.
    for model_id, entry in anthropic.items():
        val = (entry.get("params") or {}).get("thinking_adaptive")
        assert val is None or isinstance(val, bool), (model_id, val)


def test_thinking_adaptive_implies_temperature_unsupported(anthropic):
    for model_id in ADAPTIVE:
        params = anthropic[model_id].get("params") or {}
        assert params.get("temperature_supported") is False, model_id


def test_structured_json_exactly_on_the_supported_set(anthropic):
    flagged = {m for m, e in anthropic.items() if "structured_json" in (e.get("capabilities") or [])}
    assert flagged == STRUCTURED_JSON


def test_cache_read_pricing_is_one_tenth_of_input(http_entries):
    for model_id, entry in http_entries.items():
        pricing = entry.get("pricing") or {}
        assert isinstance(pricing.get("input_per_mtok"), int), model_id
        assert isinstance(pricing.get("output_per_mtok"), int), model_id
        cache_read = pricing.get("cache_read_per_mtok")
        assert isinstance(cache_read, int) and cache_read > 0, f"{model_id}: cache_read_per_mtok missing"
        expected = CACHE_READ_EXCEPTIONS.get(model_id, pricing["input_per_mtok"] // 10)
        assert cache_read == expected, (model_id, cache_read, expected)


def test_generation_pricing_matches_reference(anthropic):
    def price(model_id):
        p = anthropic[model_id]["pricing"]
        return p["input_per_mtok"], p["output_per_mtok"]

    assert price("claude-opus-5") == (5_000_000, 25_000_000)
    assert price("claude-fable-5-1") == (10_000_000, 50_000_000)
    assert price("claude-sonnet-5") == (2_000_000, 10_000_000)


def test_aliases_retargeted_to_the_new_generation(catalog):
    aliases = catalog["aliases"]
    compat = catalog["backward_compat_aliases"]
    assert aliases["opus"] == "anthropic:claude-opus-5"
    assert aliases["fable"] == "anthropic:claude-fable-5-1"
    assert compat["claude-opus-5"] == "anthropic:claude-opus-5"
    assert compat["claude-fable-5-1"] == "anthropic:claude-fable-5-1"
    # cycle-114 self-maps keep resolving (pinnable fallback).
    assert compat["claude-opus-4-8"] == "anthropic:claude-opus-4-8"


def test_fallback_chain_targets_exist(catalog, anthropic):
    providers = catalog["providers"]
    for model_id, entry in anthropic.items():
        for hop in entry.get("fallback_chain") or []:
            prov, _, target = hop.partition(":")
            assert target in providers.get(prov, {}).get("models", {}), (model_id, hop)
    assert anthropic["claude-fable-5-1"]["fallback_chain"] == [
        "anthropic:claude-fable-5",
        "anthropic:claude-opus-5",
        "anthropic:claude-headless",
    ]
    assert anthropic["claude-opus-5"]["fallback_chain"] == [
        "anthropic:claude-opus-4-8",
        "anthropic:claude-sonnet-5",
        "anthropic:claude-headless",
    ]


def test_advisor_loader_resolves_the_review_role_to_opus_5():
    """AC-3.4 via the code path cheval takes (review round-1 low 4): the loader
    over the live .loa.config.yaml resolves role=review on the Anthropic
    provider to the advisor tier's claude-opus-5."""
    from loa_cheval.config.advisor_strategy import load_advisor_strategy
    cfg = load_advisor_strategy(REPO_ROOT)
    assert cfg.enabled, "advisor_strategy is disabled in .loa.config.yaml"
    tier = cfg.resolve(role="review", skill="reviewing-code", provider="anthropic")
    assert tier.tier == "advisor"
    assert tier.model_id == "claude-opus-5"


def test_advisor_tier_points_at_opus_5():
    with LOA_CONFIG.open() as fh:
        cfg = yaml.safe_load(fh)
    assert cfg["advisor_strategy"]["tier_aliases"]["advisor"]["anthropic"] == "claude-opus-5"
    example = LOA_CONFIG_EXAMPLE.read_text()
    assert "anthropic: claude-opus-5" in example
    assert "anthropic: claude-opus-4-7" not in example.split("tier_aliases:")[1].split("executor:")[0]
