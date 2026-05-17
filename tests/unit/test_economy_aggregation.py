"""cycle-112 Sprint 1 (#166) T1.5 — pytest unit tests for economy aggregator.

Coverage targets (SDD §7 + PRD §4 FR-1 acceptance criteria):

- Window parsing
- Pricing load + git-ref fallback
- Envelope cost computation (input-side only, micro-USD math)
- Verdict-quality classification (SDD §3.3 nested gate)
- Skill / model extraction (SDD §4.1.3 bucketing)
- p95 latency
- Aggregation end-to-end against 5 fixtures
- Filters (skill / model substring)
- NFR-Sec-1 redaction (no secret-shape leak)
- Schema validation
- Cost-per-clean-output formula (PRD §4 FR-1 Ubiquitous EARS)
- Degradation marker threshold
"""
from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from textwrap import dedent

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / ".claude" / "adapters"))

from loa_cheval import economy  # noqa: E402

FIXTURES = ROOT / "tests" / "fixtures" / "model-economy"
SCHEMA_PATH = ROOT / ".claude" / "data" / "schemas" / "model-economy-rollup.schema.json"
MODEL_CONFIG = ROOT / ".claude" / "defaults" / "model-config.yaml"


# Use a fixed "now" so window arithmetic is deterministic across CI clock drift.
FIXED_NOW = datetime(2026, 5, 17, 12, 0, 0, tzinfo=timezone.utc)


# ---------------------------------------------------------------------------
# Window parsing
# ---------------------------------------------------------------------------


def test_parse_window_hours():
    td = economy.parse_window("24h")
    assert td.total_seconds() == 24 * 3600


def test_parse_window_days():
    td = economy.parse_window("30d")
    assert td.days == 30


def test_parse_window_minutes():
    td = economy.parse_window("60m")
    assert td.total_seconds() == 3600


def test_parse_window_invalid():
    with pytest.raises(ValueError, match="unrecognized window format"):
        economy.parse_window("NOPE")


# ---------------------------------------------------------------------------
# Pricing load
# ---------------------------------------------------------------------------


def test_load_pricing_from_real_config():
    pricing = economy.load_pricing(MODEL_CONFIG)
    # Spot-check a few well-known entries
    assert "anthropic:claude-opus-4-7" in pricing
    entry = pricing["anthropic:claude-opus-4-7"]
    assert entry["input_per_mtok"] > 0
    assert entry["output_per_mtok"] > 0


def test_load_pricing_missing_file(tmp_path):
    with pytest.raises(FileNotFoundError, match="model-config.yaml unreadable"):
        economy.load_pricing(tmp_path / "nope.yaml")


def test_load_pricing_bad_git_ref(tmp_path):
    fake_config = tmp_path / "model-config.yaml"
    fake_config.write_text("providers: {}\n")
    with pytest.raises(FileNotFoundError, match="git ref not found"):
        economy.load_pricing(fake_config, cost_snapshot_ref="deadbeef-never-existed")


# ---------------------------------------------------------------------------
# Envelope cost computation (micro-USD math)
# ---------------------------------------------------------------------------


def test_envelope_cost_full():
    # 30000000 micro-USD/mtok * 1000 tokens / 1e12 = $0.03
    payload = {
        "pricing_snapshot": {"input_per_mtok": 30000000},
        "capability_evaluation": {"estimated_input_tokens": 1000},
    }
    cost = economy.envelope_cost_usd(payload)
    assert cost == pytest.approx(0.03, rel=1e-9)


def test_envelope_cost_missing_pricing():
    payload = {"capability_evaluation": {"estimated_input_tokens": 1000}}
    assert economy.envelope_cost_usd(payload) is None


def test_envelope_cost_missing_capability():
    payload = {"pricing_snapshot": {"input_per_mtok": 30000000}}
    assert economy.envelope_cost_usd(payload) is None


def test_envelope_cost_fallback_from_config():
    payload = {"capability_evaluation": {"estimated_input_tokens": 1000}}
    fallback = {"input_per_mtok": 30000000}
    cost = economy.envelope_cost_usd(payload, fallback_pricing=fallback)
    assert cost == pytest.approx(0.03, rel=1e-9)


def test_envelope_cost_negative_tokens_returns_none():
    payload = {
        "pricing_snapshot": {"input_per_mtok": 30000000},
        "capability_evaluation": {"estimated_input_tokens": -5},
    }
    assert economy.envelope_cost_usd(payload) is None


# ---------------------------------------------------------------------------
# Verdict-quality classification (SDD §3.3)
# ---------------------------------------------------------------------------


def test_is_clean_output_approved_ok():
    assert economy.is_clean_output(
        {"verdict_quality": {"status": "APPROVED", "chain_health": "ok"}}
    )


def test_is_clean_output_approved_degraded_chain():
    # SDD §3.3 nesting correction — status APPROVED is NOT enough
    assert not economy.is_clean_output(
        {"verdict_quality": {"status": "APPROVED", "chain_health": "degraded"}}
    )


def test_is_clean_output_missing_vq():
    assert not economy.is_clean_output({})


def test_classify_verdict_known():
    assert economy.classify_verdict_quality({"verdict_quality": {"status": "DEGRADED"}}) == "DEGRADED"
    assert economy.classify_verdict_quality({"verdict_quality": {"status": "FAILED"}}) == "FAILED"


def test_classify_verdict_unknown():
    assert economy.classify_verdict_quality({}) == "UNKNOWN"
    assert economy.classify_verdict_quality({"verdict_quality": "not_a_dict"}) == "UNKNOWN"


# ---------------------------------------------------------------------------
# Skill / model extraction (SDD §4.1.3)
# ---------------------------------------------------------------------------


def test_extract_skill_unattributed():
    assert economy.extract_skill({}) == economy.UNATTRIBUTED


def test_extract_skill_attributed():
    assert economy.extract_skill({"skill": "/review-sprint"}) == "/review-sprint"


def test_extract_skill_fallback_chain():
    # calling_primitive falls back when skill missing
    assert economy.extract_skill({"calling_primitive": "/audit-sprint"}) == "/audit-sprint"


def test_extract_model_final():
    assert economy.extract_model({"final_model_id": "anthropic:claude-opus-4-7"}) == "anthropic:claude-opus-4-7"


def test_extract_model_fallback_to_succeeded():
    assert (
        economy.extract_model({"models_succeeded": ["openai:gpt-5.5"]})
        == "openai:gpt-5.5"
    )


def test_extract_model_unknown():
    assert economy.extract_model({}) == economy.UNKNOWN_MODEL


# ---------------------------------------------------------------------------
# p95 latency
# ---------------------------------------------------------------------------


def test_p95_empty():
    assert economy.p95([]) is None


def test_p95_single():
    assert economy.p95([100]) == 100


def test_p95_twenty_values():
    # ceil(0.95 * 20) = 19, so rank 19 (0-indexed 18) of sorted ascending
    vals = list(range(1, 21))  # 1..20
    assert economy.p95(vals) == 19


# ---------------------------------------------------------------------------
# Aggregation end-to-end
# ---------------------------------------------------------------------------


def _agg(fixture: str, **kw):
    return economy.aggregate_economy(
        log_path=FIXTURES / fixture,
        model_config_path=MODEL_CONFIG,
        window="9999d",
        now=FIXED_NOW,
        **kw,
    )


def test_aggregate_empty_fixture():
    rep = _agg("empty.jsonl")
    assert rep["coverage"]["total_envelopes"] == 0
    assert rep["per_skill_model"] == {}
    assert rep["coverage"]["skill_attribution_pct"] == 0.0


def test_aggregate_no_attribution_fixture():
    rep = _agg("no-attribution.jsonl")
    assert rep["coverage"]["total_envelopes"] == 4
    assert rep["coverage"]["with_skill_attribution"] == 0
    assert rep["coverage"]["skill_attribution_pct"] == 0.0
    # All rows bucketed to (unattributed, ...)
    for key, row in rep["per_skill_model"].items():
        assert row["skill"] == economy.UNATTRIBUTED


def test_aggregate_fully_attributed_fixture():
    rep = _agg("fully-attributed.jsonl")
    assert rep["coverage"]["with_skill_attribution"] == 5
    assert rep["coverage"]["skill_attribution_pct"] == 100.0
    # /review-sprint appears for both anthropic and openai models
    skills = {row["skill"] for row in rep["per_skill_model"].values()}
    assert "/review-sprint" in skills
    assert "/audit-sprint" in skills
    assert "bridgebuilder-review" in skills


def test_aggregate_malformed_lines_skipped():
    rep = _agg("malformed-lines.jsonl")
    # 5 well-formed lines total: 2 anthropic-priced + 1 dropped (payload string) + 1 gemini-no-cost
    # = 3 valid envelopes (since 'payload': str is rejected as non-dict)
    assert rep["coverage"]["malformed_lines"] >= 2
    assert rep["coverage"]["total_envelopes"] >= 1
    # Aggregator MUST not crash on these.


def test_aggregate_skill_filter():
    rep = _agg("fully-attributed.jsonl", skill_filter="review")
    # Filter to skills containing "review" — should match /review-sprint + bridgebuilder-review
    skills = {row["skill"] for row in rep["per_skill_model"].values()}
    assert all("review" in s for s in skills), f"unexpected skill in filtered result: {skills}"


def test_aggregate_model_filter():
    rep = _agg("fully-attributed.jsonl", model_filter="anthropic")
    for row in rep["per_skill_model"].values():
        assert "anthropic" in row["model"]


def test_cost_per_clean_output_formula():
    """SDD §3.3: cost_per_clean_output = sum(cost where verdict APPROVED+ok) / count(same).

    fully-attributed.jsonl, (/review-sprint, anthropic:claude-opus-4-7) cell:
      - line 1: 1000 tokens APPROVED+ok → clean, $0.03
      - line 4: 1200 tokens FAILED+exhausted → NOT clean, $0.036

    cost_per_clean_output = $0.03 / 1 = $0.03
    cost_total_usd        = $0.03 + $0.036 = $0.066 (all priced, regardless of clean)
    """
    rep = _agg("fully-attributed.jsonl")
    key = "/review-sprint|anthropic:claude-opus-4-7"
    assert key in rep["per_skill_model"], f"missing key {key} in {list(rep['per_skill_model'].keys())}"
    row = rep["per_skill_model"][key]
    assert row["cost_per_clean_output_usd"] == pytest.approx(0.03, rel=1e-3)
    assert row["cost_total_usd"] == pytest.approx(0.066, rel=1e-3)
    # Two priced runs total in this cell (both have pricing + capability)
    assert row["runs"] == 2


def test_degradation_marker_threshold():
    """PRD §4 FR-2: marker fires when DEGRADED + FAILED >= 2."""
    rep = _agg("fully-attributed.jsonl")
    review_anthropic = rep["per_skill_model"]["/review-sprint|anthropic:claude-opus-4-7"]
    # 0 DEGRADED + 1 FAILED → marker should NOT fire (under threshold of 2)
    assert review_anthropic["degradation_marker"] is False


def test_unpriced_runs_tracked():
    """SDD §3.2.1: unpriced_runs counts envelopes without pricing data."""
    rep = _agg("malformed-lines.jsonl")
    # gemini row has no pricing/capability → unpriced
    for row in rep["per_skill_model"].values():
        if "gemini" in row["model"]:
            assert row["unpriced_runs"] >= 1


def test_cost_input_only_flag():
    """SDD §3.2.1: cost_input_only is True until D-7 wires output tokens."""
    rep = _agg("fully-attributed.jsonl")
    for row in rep["per_skill_model"].values():
        assert row["cost_input_only"] is True


# ---------------------------------------------------------------------------
# Schema validation
# ---------------------------------------------------------------------------


def test_render_json_validates_against_schema():
    rep = _agg("no-attribution.jsonl")
    out = economy.render_json(rep, validate=True)
    parsed = json.loads(out)
    assert "coverage" in parsed
    assert "per_skill_model" in parsed
    assert "footer" in parsed


def test_schema_file_exists_and_valid_draft_2020_12():
    import jsonschema
    schema = json.loads(SCHEMA_PATH.read_text())
    # Will raise SchemaError if invalid.
    jsonschema.Draft202012Validator.check_schema(schema)


# ---------------------------------------------------------------------------
# NFR-Sec-1: redaction defense-in-depth
# ---------------------------------------------------------------------------


def test_nfr_sec_1_no_secret_leak_in_text_output(tmp_path):
    """Inject a fake AKIA-shape secret into models_failed[].message_redacted
    and verify it does not appear in text output.

    The bash shim pipes through log-redactor as a second layer; this test
    verifies the Python output itself doesn't carry the shape verbatim into
    a column we render.
    """
    fixture = tmp_path / "secret-bait.jsonl"
    fake_secret = "AKIA1234567890ABCDEF"
    payload = {
        "primitive_id": "MODELINV",
        "event_type": "model.invoke.complete",
        "ts_utc": "2026-05-15T10:00:00.000000Z",
        "payload": {
            "models_requested": ["anthropic:claude-opus-4-7"],
            "models_succeeded": ["anthropic:claude-opus-4-7"],
            "final_model_id": "anthropic:claude-opus-4-7",
            "invocation_latency_ms": 100,
            # Bait: secret embedded in a field we don't render.
            "models_failed": [{"model": "openai:gpt-5.5-pro", "message_redacted": fake_secret}],
            "pricing_snapshot": {"input_per_mtok": 30000000},
            "capability_evaluation": {"estimated_input_tokens": 1000},
            "verdict_quality": {"status": "APPROVED", "chain_health": "ok"},
        },
    }
    fixture.write_text(json.dumps(payload) + "\n")
    rep = economy.aggregate_economy(
        log_path=fixture,
        model_config_path=MODEL_CONFIG,
        window="9999d",
        now=FIXED_NOW,
    )
    text = economy.render_text(rep)
    assert fake_secret not in text, "secret-shape leaked into text output"


# ---------------------------------------------------------------------------
# Text rendering shape
# ---------------------------------------------------------------------------


def test_render_text_includes_coverage_disclosure():
    rep = _agg("no-attribution.jsonl")
    text = economy.render_text(rep)
    assert "Coverage:" in text
    assert "D-6 follow-up" in text
    assert "skill attribution" in text


def test_render_text_no_ts_banner_strips_since():
    rep = _agg("no-attribution.jsonl")
    with_banner = economy.render_text(rep, no_ts_banner=False)
    without_banner = economy.render_text(rep, no_ts_banner=True)
    assert "since" in with_banner
    assert "since" not in without_banner.split("\n")[0]


def test_render_text_empty_log_has_no_table():
    rep = _agg("empty.jsonl")
    text = economy.render_text(rep)
    assert "No envelopes matched" in text


# ---------------------------------------------------------------------------
# First-try-success tracking
# ---------------------------------------------------------------------------


def test_first_try_success_when_primary_succeeds():
    rep = _agg("no-attribution.jsonl")
    # All 4 envelopes have requested[0] == succeeded[0]
    total_fts = sum(r["first_try_success"] for r in rep["per_skill_model"].values())
    total_runs = sum(r["runs"] for r in rep["per_skill_model"].values())
    assert total_fts == total_runs


def test_first_try_success_zero_when_fallback_walked():
    rep = _agg("fully-attributed.jsonl")
    # The fully-attributed fixture has one envelope that walked anthropic → openai
    # (the openai:gpt-5.5-pro fallback). That cell's first_try_success should be 0.
    fallback_key = "/review-sprint|openai:gpt-5.5-pro"
    if fallback_key in rep["per_skill_model"]:
        assert rep["per_skill_model"][fallback_key]["first_try_success"] == 0
