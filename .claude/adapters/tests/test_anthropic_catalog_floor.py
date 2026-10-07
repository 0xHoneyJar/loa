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
from loa_cheval.providers.anthropic_adapter import _BETA_HEADER_RE  # noqa: E402
from loa_cheval.providers.base import default_max_tokens  # noqa: E402
from loa_cheval.routing.ceiling import input_bound, is_foreign_transport_calibration  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[3]
CATALOG = REPO_ROOT / ".claude" / "defaults" / "model-config.yaml"
LOA_CONFIG = REPO_ROOT / ".loa.config.yaml"
LOA_CONFIG_EXAMPLE = REPO_ROOT / ".loa.config.yaml.example"

# SDD §2.1 entry table.
FAMILY_1M = {
    "claude-fable-5-1",
    "claude-fable-5",
    "claude-opus-5-5",
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
    "claude-opus-5-5",
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
    "claude-opus-5-5",
    "claude-opus-5",
    "claude-opus-4-8",
    "claude-sonnet-5",
    "claude-haiku-4-5-20251001",
}
V2_INPUT_FIELDS = ("max_input_tokens", "streaming_max_input_tokens", "legacy_max_input_tokens")
# Documented exceptions to the 0.1× cache-read rule (catalog-evidence.md).
CACHE_READ_EXCEPTIONS = {
    "claude-fable-5-1": 250_000,  # 0.025× per the reference
    "claude-opus-5-5": 200_000,  # 0.05×: $0.20 cache hit on $4 input (platform.claude.com pricing, read 2026-10-05)
}
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


def _measured(entry: dict) -> bool:
    """cycle-127 FR-3.4: a calibrated entry (operator_set / empirical_probe with
    calibrated_at) carries its own measured bound — the 180K cap is the
    uncalibrated policy, so the test follows the catalog value there."""
    cal = entry.get("ceiling_calibration") or {}
    return bool(cal.get("calibrated_at")) and cal.get("source") in ("operator_set", "empirical_probe")


def test_ceiling_is_the_computed_value_per_entry(http_entries):
    """SDD §2.1: ceiling = min(180000, context_window − default_max_tokens(entry)) — computed, not a constant.
    cycle-127 r251-1 (finding 33): a measured entry recording its raw accept is computed from it —
    min(measured_input_tokens, context_window − default_max_tokens(entry)) (cheval's I2 clamp) — in
    both fields; never the entry's own ceiling compared with itself."""
    for model_id, entry in http_entries.items():
        room = entry["context_window"] - _default_max_tokens(entry)
        cal = entry.get("ceiling_calibration") or {}
        if _measured(entry) and isinstance(cal.get("measured_input_tokens"), int):
            expected = min(cal["measured_input_tokens"], room)
            assert entry["probed_ceiling"] == entry["effective_input_ceiling"], model_id
        elif _measured(entry):
            # an API-transport probe write records no raw count: only the invariant is checkable
            expected = min(entry["effective_input_ceiling"], room)
        else:
            expected = min(CEILING_CAP, room)
        assert entry["effective_input_ceiling"] == expected, (model_id, entry["effective_input_ceiling"], expected)
        assert entry["effective_input_ceiling"] + _default_max_tokens(entry) <= entry["context_window"], model_id


def test_a_foreign_transport_calibration_carries_its_provenance(http_entries):
    """cycle-127 r251-1 (finding 32): an HTTP entry trusting a bound measured on another
    transport (ceiling_calibration.transport ≠ api) must say how it was measured and what
    the provider accepted — `method` and `measured_input_tokens` — so the cross-transport
    trust is auditable, and an observed limit on this route may tighten it (routing.ceiling)."""
    foreign = [m for m, e in http_entries.items() if is_foreign_transport_calibration(e)]
    # (review r251-2 K9 / n36: with zero foreign entries the loop would assert nothing — the live catalog has one)
    assert "claude-opus-5-5" in foreign, foreign
    for model_id in foreign:
        entry = http_entries[model_id]
        cal = entry["ceiling_calibration"]
        # a bound measured on a non-API transport was measured headless — `probed_api` there is a mislabel (n36)
        assert cal.get("method") == "probed_headless", (model_id, cal.get("transport"), cal.get("method"))
        assert isinstance(cal.get("measured_input_tokens"), int) and cal["measured_input_tokens"] > 0, model_id
        assert cal["measured_input_tokens"] >= entry["effective_input_ceiling"], (
            f"{model_id}: the written bound may be clamped below the measured accept, never above it")


def test_lookup_returns_the_concrete_bound_through_the_gate_path(catalog, monkeypatch):
    """review r251-2 K9 (n35): one concrete check THROUGH `_lookup_max_input_tokens` — the gate answers a calibrated
    entry's catalog bound (not the policy cap). claude-opus-5-5 is calibrated; claude-opus-5 is not, and answers its
    probed value (the policy cap). r251-3 R2 (AC 3): the expectation is READ from the catalog, so this check moves
    with the next re-probe instead of pinning today's bound by literal."""
    monkeypatch.delenv("LOA_CHEVAL_DISABLE_STREAMING", raising=False)
    monkeypatch.delenv("LOA_CHEVAL_LEGACY_WIRE", raising=False)
    monkeypatch.setenv("LOA_CHEVAL_CEILING_OBSERVED_PATH", "/nonexistent/ceiling-observed.json")  # no host observations
    cal = catalog["providers"]["anthropic"]["models"]["claude-opus-5-5"]
    assert cal["ceiling_calibration"].get("calibrated_at"), "claude-opus-5-5 is expected to be calibrated"
    want = cal["effective_input_ceiling"]
    assert isinstance(want, int) and want != CEILING_CAP, want
    assert input_bound(cal, max_tokens=_default_max_tokens(cal)).basis == "calibrated"
    assert _lookup_max_input_tokens("anthropic", "claude-opus-5-5", catalog) == want
    uncal = catalog["providers"]["anthropic"]["models"]["claude-opus-5"]
    assert not uncal["ceiling_calibration"].get("calibrated_at")
    assert _lookup_max_input_tokens("anthropic", "claude-opus-5", catalog) == uncal["probed_ceiling"] == CEILING_CAP


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
    monkeypatch.setenv("LOA_CHEVAL_CEILING_OBSERVED_PATH", "/nonexistent/ceiling-observed.json")  # no host observations
    for model_id, entry in http_entries.items():
        # r251-1 (finding 33): the policy decides the bound, not a test-local mirror of it
        want = input_bound(entry, max_tokens=_default_max_tokens(entry)).value
        assert _lookup_max_input_tokens("anthropic", model_id, catalog) == want, model_id
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

    assert price("claude-opus-5-5") == (4_000_000, 20_000_000)
    assert price("claude-opus-5") == (5_000_000, 25_000_000)
    assert price("claude-fable-5-1") == (10_000_000, 50_000_000)
    assert price("claude-sonnet-5") == (2_000_000, 10_000_000)


def test_aliases_retargeted_to_the_new_generation(catalog):
    aliases = catalog["aliases"]
    compat = catalog["backward_compat_aliases"]
    assert aliases["opus"] == "anthropic:claude-opus-5-5"
    assert aliases["cheap"] == "anthropic:claude-sonnet-5"
    assert aliases["fable"] == "anthropic:claude-fable-5-1"
    assert compat["claude-opus-5-5"] == compat["claude-opus-5.5"] == "anthropic:claude-opus-5-5"
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
    # audit slice D: every Opus pin in the live config sits on the floor, not only the advisor tier
    bb_models = cfg["run_bridge"]["bridgebuilder"]["multi_model"]["models"]
    # 2026-10-01 operator directive (2fb4f9f2): the BB anthropic voice is Fable 5.1 through the CLI
    assert [m["model_id"] for m in bb_models if m.get("provider") == "anthropic"] == ["claude-headless"]
    # …and the alias is a floor check only through what it dispatches: the catalog's cli_model for it sits on the floor too
    # (cycle-126 thirty-first run, e1 DISS-C-003 — `fable`/`opus`/`sonnet` are the CLI's own current-generation aliases)
    with CATALOG.open() as fh:
        cli_model = (yaml.safe_load(fh)["providers"]["anthropic"]["models"]["claude-headless"].get("extra") or {}).get("cli_model")
    # (thirty-second run, e1 DISS-C-003: the directive is Fable 5.1 — `opus`/`sonnet` passed a downgrade with the suite green)
    assert cli_model in {"fable", "claude-fable-5-1"}, cli_model
    assert cfg["red_team"]["models"]["evaluator_primary"] == "claude-opus-5"
    assert 'opus: "anthropic:claude-opus-5-5"' in LOA_CONFIG_EXAMPLE.read_text()
    assert 'cheap: "anthropic:claude-sonnet-5"' in LOA_CONFIG_EXAMPLE.read_text()
    example = LOA_CONFIG_EXAMPLE.read_text()
    assert "anthropic: claude-opus-5" in example
    assert "anthropic: claude-opus-4-7" not in example.split("tier_aliases:")[1].split("executor:")[0]


# --- cycle-126 Sprint 1 (PRD FR-1.1 / FR-1.2 / FR-1.9, SDD D-1.1 / D-1.2 / D-1.9) --------

FIVE_FAMILY = {"claude-fable-5-1", "claude-fable-5", "claude-opus-5", "claude-sonnet-5"}


@pytest.fixture(autouse=True)
def _default_ceiling_policy(monkeypatch):
    for var in ("LOA_CHEVAL_LEGACY_CEILING", "LOA_CHEVAL_UNCALIBRATED_CEILING", "LOA_CHEVAL_MAX_INPUT_TOKENS"):
        monkeypatch.delenv(var, raising=False)


def test_every_http_entry_carries_the_probed_bound_and_account_limits(http_entries):
    for model_id, entry in http_entries.items():
        # cycle-127 FR-3.4: a measured entry carries its measurement in both fields
        assert entry.get("probed_ceiling") == (entry["effective_input_ceiling"] if _measured(entry) else CEILING_CAP), model_id
        cal = entry["ceiling_calibration"]
        if not cal.get("calibrated_at"):
            assert entry["effective_input_ceiling"] == entry["probed_ceiling"], (
                f"{model_id}: uncalibrated ⇒ the v3 field the older readers consume IS the probed value")
        limits = entry.get("account_limits")
        assert isinstance(limits, dict) and set(limits) == {"tier", "itpm"}, model_id
        assert limits["tier"] in ("unverified", "1", "2", "3", "4", "custom"), model_id
        assert limits["itpm"] is None or (isinstance(limits["itpm"], int) and limits["itpm"] > 0), model_id


def test_i1_and_i2_per_entry_from_the_fields(http_entries):
    """I1: the bound never exceeds context_window − max_tokens; I2: probed by default,
    derived only under the opt-in — and never max() with the probed value."""
    for model_id, entry in http_entries.items():
        mt = _default_max_tokens(entry)
        d = input_bound(entry, max_tokens=mt)
        assert d is not None and d.value + mt <= entry["context_window"], (model_id, d)
        assert d.value <= entry["probed_ceiling"], (model_id, d)  # never above the probed value by default
        if entry["ceiling_calibration"].get("calibrated_at"):
            assert d.basis == "calibrated"
        else:
            assert d.basis in ("probed", "i1"), (model_id, d.basis)
        derived = input_bound(entry, max_tokens=mt, policy="derived")
        assert derived.value == min(entry["context_window"] - mt, entry["probed_ceiling"] if d.calibrated else entry["context_window"] - mt) \
            or derived.basis in ("calibrated", "i1"), (model_id, derived)
        assert derived.value + mt <= entry["context_window"], model_id
        # the legacy kill switch is the literal, whatever the arithmetic says
        assert input_bound(entry, max_tokens=mt, policy="legacy").value == entry["effective_input_ceiling"]


def test_walk_gate_threshold_is_the_policy_bound_not_the_literal(catalog, http_entries):
    for model_id, entry in http_entries.items():
        mt = _default_max_tokens(entry)
        expected = input_bound(entry, max_tokens=mt).value
        assert _lookup_max_input_tokens("anthropic", model_id, catalog, max_tokens=mt) == expected, model_id


def test_five_family_declares_the_beta_header_list_and_the_long_context_tier(anthropic):
    for model_id in FIVE_FAMILY:
        entry = anthropic[model_id]
        beta = (entry.get("params") or {}).get("beta_headers")
        assert isinstance(beta, list), f"{model_id}: params.beta_headers must be a list (empty until an account needs one)"
        assert all(isinstance(v, str) and _BETA_HEADER_RE.match(v) for v in beta), (model_id, beta)
        lc = (entry.get("pricing") or {}).get("long_context")
        assert lc == {"threshold_tokens": 200_000, "input_multiplier": 2.0, "output_multiplier": 1.5, "verified": False}, model_id
        assert entry["context_window"] > lc["threshold_tokens"]


def test_entries_outside_the_five_family_carry_no_long_context_tier(http_entries):
    for model_id, entry in http_entries.items():
        if model_id not in FIVE_FAMILY:
            assert "long_context" not in (entry.get("pricing") or {}), model_id


def test_opus_5_5_has_the_1m_window_at_standard_pricing(anthropic):
    """cycle-126 bd-2fti: the vendor pricing page puts 4.6-and-later on the full 1M window at
    standard pricing, so 5.5 carries no long_context tier; its ceiling is the conservative
    default until a probe measures it (cycle-127 FR-3.4: either state, each with its shape)."""
    entry = anthropic["claude-opus-5-5"]
    assert "long_context" not in entry["pricing"]
    cal = entry["ceiling_calibration"]
    if _measured(entry):
        # a probe wrote it: the measured bound is both values, with its provenance
        assert entry["probed_ceiling"] == entry["effective_input_ceiling"]
        assert isinstance(cal.get("reprobe_trigger"), str) and cal["reprobe_trigger"]
        # r251-1 C4: the probe's own outcome and the number of samples taken are structured, not comment-only
        if cal.get("method") == "probed_headless":
            assert cal.get("probe_outcome") in ("clean", "partial"), cal.get("probe_outcome")
            assert isinstance(cal.get("sample_size"), int) and cal["sample_size"] > 0, cal.get("sample_size")
    else:
        assert cal["source"] == "conservative_default"
        assert cal["calibrated_at"] is None
    assert entry["fallback_chain"][0] == "anthropic:claude-opus-5"
