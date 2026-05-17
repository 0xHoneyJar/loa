"""cycle-109 Sprint 5 T5.4-T5.5 — substrate-health aggregator tests."""

from __future__ import annotations

import json
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))


def _make_modelinv_envelope(
    payload: dict,
    *,
    timestamp: str = "2026-05-14T12:00:00Z",
) -> str:
    """Serialize a MODELINV envelope wrapping the payload."""
    envelope = {
        "primitive_id": "MODELINV",
        "event_type": "model.invoke.complete",
        "timestamp": timestamp,
        "payload": payload,
    }
    return json.dumps(envelope, separators=(",", ":"))


def _write_log(tmp_path: Path, envelopes: list) -> Path:
    log = tmp_path / "model-invoke.jsonl"
    log.write_text("\n".join(envelopes) + "\n")
    return log


# ---------------------------------------------------------------------------
# Threshold bands (FR-5.7)
# ---------------------------------------------------------------------------


def test_classify_band_green_at_80():
    from loa_cheval.health import classify_band

    assert classify_band(0.80) == "green"
    assert classify_band(0.95) == "green"
    assert classify_band(1.00) == "green"


def test_classify_band_yellow_50_to_80():
    from loa_cheval.health import classify_band

    assert classify_band(0.79) == "yellow"
    assert classify_band(0.65) == "yellow"
    assert classify_band(0.50) == "yellow"


def test_classify_band_red_below_50():
    from loa_cheval.health import classify_band

    assert classify_band(0.49) == "red"
    assert classify_band(0.0) == "red"


# ---------------------------------------------------------------------------
# Window parsing
# ---------------------------------------------------------------------------


def test_parse_window_hours():
    from loa_cheval.health import parse_window

    assert parse_window("24h") == timedelta(hours=24)
    assert parse_window("1h") == timedelta(hours=1)


def test_parse_window_days():
    from loa_cheval.health import parse_window

    assert parse_window("7d") == timedelta(days=7)
    assert parse_window("30d") == timedelta(days=30)


def test_parse_window_minutes():
    from loa_cheval.health import parse_window

    assert parse_window("60m") == timedelta(minutes=60)


def test_parse_window_invalid_raises():
    from loa_cheval.health import parse_window

    with pytest.raises(ValueError):
        parse_window("foo")


# ---------------------------------------------------------------------------
# Aggregation — basic cases
# ---------------------------------------------------------------------------


def test_aggregate_empty_log_returns_zero_invocations(tmp_path):
    from loa_cheval.health import aggregate_substrate_health

    log = tmp_path / "empty.jsonl"
    log.write_text("")
    result = aggregate_substrate_health(log)
    assert result["total_invocations"] == 0
    assert result["overall"]["succeeded"] == 0


def test_aggregate_missing_log_returns_zero(tmp_path):
    from loa_cheval.health import aggregate_substrate_health

    result = aggregate_substrate_health(tmp_path / "does-not-exist.jsonl")
    assert result["total_invocations"] == 0


def test_aggregate_single_successful_invocation(tmp_path):
    from loa_cheval.health import aggregate_substrate_health

    now = datetime(2026, 5, 14, 13, 0, 0, tzinfo=timezone.utc)
    log = _write_log(tmp_path, [
        _make_modelinv_envelope({
            "models_requested": ["anthropic:claude-opus-4-7"],
            "models_succeeded": ["anthropic:claude-opus-4-7"],
            "models_failed": [],
            "operator_visible_warn": False,
            "final_model_id": "anthropic:claude-opus-4-7",
        }, timestamp="2026-05-14T12:00:00Z"),
    ])
    result = aggregate_substrate_health(log, now=now)
    assert result["total_invocations"] == 1
    assert result["overall"]["succeeded"] == 1
    assert result["overall"]["success_rate"] == 1.0
    assert result["overall"]["band"] == "green"


def test_aggregate_partial_failures_compute_per_model_rate(tmp_path):
    from loa_cheval.health import aggregate_substrate_health

    now = datetime(2026, 5, 14, 13, 0, 0, tzinfo=timezone.utc)
    envelopes = []
    # opus: 8 succeed, 2 fail → 80% green
    for i in range(8):
        envelopes.append(_make_modelinv_envelope({
            "models_requested": ["anthropic:claude-opus-4-7"],
            "models_succeeded": ["anthropic:claude-opus-4-7"],
            "models_failed": [], "operator_visible_warn": False,
            "final_model_id": "anthropic:claude-opus-4-7",
        }, timestamp="2026-05-14T12:00:00Z"))
    for i in range(2):
        envelopes.append(_make_modelinv_envelope({
            "models_requested": ["anthropic:claude-opus-4-7"],
            "models_succeeded": [],
            "models_failed": [{
                "model": "anthropic:claude-opus-4-7", "provider": "anthropic",
                "error_class": "EMPTY_CONTENT", "message_redacted": "x",
            }],
            "operator_visible_warn": True,
        }, timestamp="2026-05-14T12:00:00Z"))
    log = _write_log(tmp_path, envelopes)
    result = aggregate_substrate_health(log, now=now)
    assert result["total_invocations"] == 10
    assert result["overall"]["succeeded"] == 8
    assert result["overall"]["success_rate"] == 0.80
    assert result["overall"]["band"] == "green"


def test_aggregate_window_filter_excludes_old_entries(tmp_path):
    """Entries older than the window are excluded."""
    from loa_cheval.health import aggregate_substrate_health

    now = datetime(2026, 5, 14, 13, 0, 0, tzinfo=timezone.utc)
    envelopes = [
        # 36h ago — outside 24h window
        _make_modelinv_envelope({
            "models_requested": ["anthropic:claude-opus-4-7"],
            "models_succeeded": ["anthropic:claude-opus-4-7"],
            "models_failed": [], "operator_visible_warn": False,
            "final_model_id": "anthropic:claude-opus-4-7",
        }, timestamp="2026-05-13T01:00:00Z"),
        # 2h ago — inside window
        _make_modelinv_envelope({
            "models_requested": ["anthropic:claude-opus-4-7"],
            "models_succeeded": ["anthropic:claude-opus-4-7"],
            "models_failed": [], "operator_visible_warn": False,
            "final_model_id": "anthropic:claude-opus-4-7",
        }, timestamp="2026-05-14T11:00:00Z"),
    ]
    log = _write_log(tmp_path, envelopes)
    result = aggregate_substrate_health(log, window="24h", now=now)
    assert result["total_invocations"] == 1  # only the in-window entry


def test_aggregate_captures_chunked_review_field(tmp_path):
    """T4.7 chunked_review snapshot surfaces in the per-model aggregate."""
    from loa_cheval.health import aggregate_substrate_health

    now = datetime(2026, 5, 14, 13, 0, 0, tzinfo=timezone.utc)
    log = _write_log(tmp_path, [
        _make_modelinv_envelope({
            "models_requested": ["anthropic:claude-opus-4-7"],
            "models_succeeded": ["anthropic:claude-opus-4-7"],
            "models_failed": [], "operator_visible_warn": False,
            "final_model_id": "anthropic:claude-opus-4-7",
            "chunked_review": {"chunked": True, "chunks_reviewed": 5},
        }, timestamp="2026-05-14T12:00:00Z"),
    ])
    result = aggregate_substrate_health(log, now=now)
    assert result["per_model"]["anthropic:claude-opus-4-7"]["chunked"] == 1


def test_aggregate_captures_streaming_aborts(tmp_path):
    """T4.7 streaming_recovery.triggered envelopes are counted per-reason."""
    from loa_cheval.health import aggregate_substrate_health

    now = datetime(2026, 5, 14, 13, 0, 0, tzinfo=timezone.utc)
    log = _write_log(tmp_path, [
        _make_modelinv_envelope({
            "models_requested": ["anthropic:claude-opus-4-7"],
            "models_succeeded": [],
            "models_failed": [{
                "model": "anthropic:claude-opus-4-7", "provider": "anthropic",
                "error_class": "EMPTY_CONTENT", "message_redacted": "x",
            }],
            "operator_visible_warn": True,
            "final_model_id": "anthropic:claude-opus-4-7",
            "streaming_recovery": {
                "triggered": True, "tokens_before_abort": 200,
                "reason": "empty_content_window",
            },
        }, timestamp="2026-05-14T12:00:00Z"),
    ])
    result = aggregate_substrate_health(log, now=now)
    aborts = result["per_model"]["anthropic:claude-opus-4-7"]["streaming_aborts"]
    assert aborts.get("empty_content_window") == 1


def test_aggregate_verdict_status_distribution(tmp_path):
    """T2.3 verdict_quality.status counts per model."""
    from loa_cheval.health import aggregate_substrate_health

    now = datetime(2026, 5, 14, 13, 0, 0, tzinfo=timezone.utc)
    envelopes = []
    for status in ("APPROVED", "APPROVED", "DEGRADED", "FAILED"):
        envelopes.append(_make_modelinv_envelope({
            "models_requested": ["anthropic:claude-opus-4-7"],
            "models_succeeded": ["anthropic:claude-opus-4-7"] if status != "FAILED" else [],
            "models_failed": [] if status != "FAILED" else [{
                "model": "anthropic:claude-opus-4-7", "provider": "anthropic",
                "error_class": "EMPTY_CONTENT", "message_redacted": "x",
            }],
            "operator_visible_warn": status != "APPROVED",
            "final_model_id": "anthropic:claude-opus-4-7",
            "verdict_quality": {
                "status": status, "consensus_outcome": "consensus",
                "truncation_waiver_applied": False, "voices_planned": 1,
                "voices_succeeded": 1 if status != "FAILED" else 0,
                "voices_succeeded_ids": ["x"] if status != "FAILED" else [],
                "voices_dropped": [],
                "chain_health": "ok",
                "confidence_floor": "low",
                "rationale": "x",
            },
        }, timestamp="2026-05-14T12:00:00Z"))
    log = _write_log(tmp_path, envelopes)
    result = aggregate_substrate_health(log, now=now)
    verdict_dist = result["per_model"]["anthropic:claude-opus-4-7"]["verdict_status"]
    assert verdict_dist["APPROVED"] == 2
    assert verdict_dist["DEGRADED"] == 1
    assert verdict_dist["FAILED"] == 1


def test_text_rendering_includes_band_marker(tmp_path):
    from loa_cheval.health import aggregate_substrate_health, render_text

    now = datetime(2026, 5, 14, 13, 0, 0, tzinfo=timezone.utc)
    log = _write_log(tmp_path, [
        _make_modelinv_envelope({
            "models_requested": ["anthropic:claude-opus-4-7"],
            "models_succeeded": ["anthropic:claude-opus-4-7"],
            "models_failed": [], "operator_visible_warn": False,
            "final_model_id": "anthropic:claude-opus-4-7",
        }, timestamp="2026-05-14T12:00:00Z"),
    ])
    report = aggregate_substrate_health(log, now=now)
    text = render_text(report)
    assert "GREEN" in text
    assert "anthropic:claude-opus-4-7" in text


def test_text_rendering_red_band_emits_warning(tmp_path):
    """T5.5 FR-5.7: red band emits KF-suggest warning text."""
    from loa_cheval.health import aggregate_substrate_health, render_text

    now = datetime(2026, 5, 14, 13, 0, 0, tzinfo=timezone.utc)
    envelopes = []
    for _ in range(2):
        envelopes.append(_make_modelinv_envelope({
            "models_requested": ["anthropic:claude-opus-4-7"],
            "models_succeeded": ["anthropic:claude-opus-4-7"],
            "models_failed": [], "operator_visible_warn": False,
            "final_model_id": "anthropic:claude-opus-4-7",
        }, timestamp="2026-05-14T12:00:00Z"))
    for _ in range(8):
        envelopes.append(_make_modelinv_envelope({
            "models_requested": ["anthropic:claude-opus-4-7"],
            "models_succeeded": [],
            "models_failed": [{
                "model": "anthropic:claude-opus-4-7", "provider": "anthropic",
                "error_class": "EMPTY_CONTENT", "message_redacted": "x",
            }],
            "operator_visible_warn": True,
        }, timestamp="2026-05-14T12:00:00Z"))
    log = _write_log(tmp_path, envelopes)
    report = aggregate_substrate_health(log, now=now)
    text = render_text(report)
    assert report["overall"]["band"] == "red"
    assert "RED" in text
    assert "RED band" in text
    assert "KF entry" in text


def test_text_rendering_yellow_band_emits_warning(tmp_path):
    """T5.5 FR-5.7: yellow band emits a degradation-watch warning."""
    from loa_cheval.health import aggregate_substrate_health, render_text

    now = datetime(2026, 5, 14, 13, 0, 0, tzinfo=timezone.utc)
    envelopes = []
    for _ in range(6):
        envelopes.append(_make_modelinv_envelope({
            "models_requested": ["anthropic:claude-opus-4-7"],
            "models_succeeded": ["anthropic:claude-opus-4-7"],
            "models_failed": [], "operator_visible_warn": False,
            "final_model_id": "anthropic:claude-opus-4-7",
        }, timestamp="2026-05-14T12:00:00Z"))
    for _ in range(4):
        envelopes.append(_make_modelinv_envelope({
            "models_requested": ["anthropic:claude-opus-4-7"],
            "models_succeeded": [],
            "models_failed": [{
                "model": "anthropic:claude-opus-4-7", "provider": "anthropic",
                "error_class": "EMPTY_CONTENT", "message_redacted": "x",
            }],
            "operator_visible_warn": True,
        }, timestamp="2026-05-14T12:00:00Z"))
    log = _write_log(tmp_path, envelopes)
    report = aggregate_substrate_health(log, now=now)
    text = render_text(report)
    assert report["overall"]["band"] == "yellow"
    assert "YELLOW band" in text


def test_text_rendering_zero_invocations_suppresses_band_warning(tmp_path):
    """T5.5: zero invocations classifies as red mathematically but
    should NOT emit the 'degraded' warning text (it's not a real
    degradation signal — just an empty window)."""
    from loa_cheval.health import aggregate_substrate_health, render_text

    log = tmp_path / "empty.jsonl"
    log.write_text("")
    report = aggregate_substrate_health(log)
    text = render_text(report)
    assert report["total_invocations"] == 0
    assert "RED band" not in text
    assert "YELLOW band" not in text


# ---------------------------------------------------------------------------
# Bug #900 — primary-failure visibility after fallback rescue
#
# Regression: `aggregate_substrate_health` buckets per-model state by
# `final_model_id`, so a primary that fails and gets rescued by a chain
# fallback is invisible to the operator-facing health report. Fix adds
# additive `attempts`, `first_try_success`, `first_try_success_rate`
# counters keyed by `models_requested[]`.
# ---------------------------------------------------------------------------


def test_rescued_primary_visible_in_per_model_with_zero_first_try_success(tmp_path):
    """Bug #900: a primary that fails and is rescued by a fallback walk
    MUST appear in `per_model` with `attempts >= 1` and
    `first_try_success_rate == 0.0`. Pre-fix, the failing primary is
    absent from `per_model` entirely when every invocation is rescued."""
    from loa_cheval.health import aggregate_substrate_health

    now = datetime(2026, 5, 14, 13, 0, 0, tzinfo=timezone.utc)
    log = _write_log(tmp_path, [
        _make_modelinv_envelope({
            "models_requested": [
                "anthropic:claude-opus-4-7",
                "anthropic:claude-opus-4-6",
            ],
            "models_succeeded": ["anthropic:claude-opus-4-6"],
            "models_failed": [{
                "model": "anthropic:claude-opus-4-7", "provider": "anthropic",
                "error_class": "EMPTY_CONTENT", "message_redacted": "x",
            }],
            "operator_visible_warn": True,
            "final_model_id": "anthropic:claude-opus-4-6",
        }, timestamp="2026-05-14T12:00:00Z"),
    ])
    result = aggregate_substrate_health(log, now=now)

    # Primary MUST be visible.
    assert "anthropic:claude-opus-4-7" in result["per_model"], (
        "failing primary missing from per_model — primary-failure visibility regression"
    )
    primary = result["per_model"]["anthropic:claude-opus-4-7"]
    assert primary["attempts"] == 1
    assert primary["first_try_success"] == 0
    assert primary["first_try_success_rate"] == 0.0

    # Rescuer is also visible and counted in attempts (it was requested too).
    rescuer = result["per_model"]["anthropic:claude-opus-4-6"]
    assert rescuer["attempts"] == 1
    # Rescuer was NOT the head of models_requested → no first-try credit.
    assert rescuer["first_try_success"] == 0
    assert rescuer["first_try_success_rate"] == 0.0
    # Backward-compat: rescuer keeps its final-model success.
    assert rescuer["succeeded"] == 1


def test_clean_first_try_increments_both_attempts_and_first_try_success(tmp_path):
    """When the primary succeeds without a fallback walk, BOTH `attempts`
    and `first_try_success` increment on the same model."""
    from loa_cheval.health import aggregate_substrate_health

    now = datetime(2026, 5, 14, 13, 0, 0, tzinfo=timezone.utc)
    log = _write_log(tmp_path, [
        _make_modelinv_envelope({
            "models_requested": ["anthropic:claude-opus-4-7"],
            "models_succeeded": ["anthropic:claude-opus-4-7"],
            "models_failed": [],
            "operator_visible_warn": False,
            "final_model_id": "anthropic:claude-opus-4-7",
        }, timestamp="2026-05-14T12:00:00Z"),
    ])
    result = aggregate_substrate_health(log, now=now)
    primary = result["per_model"]["anthropic:claude-opus-4-7"]
    assert primary["attempts"] == 1
    assert primary["first_try_success"] == 1
    assert primary["first_try_success_rate"] == 1.0
    # Existing semantics preserved (additive change).
    assert primary["invocations"] == 1
    assert primary["succeeded"] == 1
    assert primary["success_rate"] == 1.0


def test_total_chain_exhaustion_attempts_all_with_zero_success(tmp_path):
    """When the full chain is exhausted (no `models_succeeded`), every
    entry in `models_requested[]` gets `attempts++`, none get
    `first_try_success++`, none get `succeeded++`."""
    from loa_cheval.health import aggregate_substrate_health

    now = datetime(2026, 5, 14, 13, 0, 0, tzinfo=timezone.utc)
    log = _write_log(tmp_path, [
        _make_modelinv_envelope({
            "models_requested": [
                "anthropic:claude-opus-4-7",
                "anthropic:claude-opus-4-6",
                "openai:gpt-5-5-pro",
            ],
            "models_succeeded": [],
            "models_failed": [
                {"model": "anthropic:claude-opus-4-7", "provider": "anthropic",
                 "error_class": "EMPTY_CONTENT", "message_redacted": "x"},
                {"model": "anthropic:claude-opus-4-6", "provider": "anthropic",
                 "error_class": "EMPTY_CONTENT", "message_redacted": "x"},
                {"model": "openai:gpt-5-5-pro", "provider": "openai",
                 "error_class": "RATE_LIMITED", "message_redacted": "x"},
            ],
            "operator_visible_warn": True,
        }, timestamp="2026-05-14T12:00:00Z"),
    ])
    result = aggregate_substrate_health(log, now=now)
    for model_id in (
        "anthropic:claude-opus-4-7",
        "anthropic:claude-opus-4-6",
        "openai:gpt-5-5-pro",
    ):
        bucket = result["per_model"][model_id]
        assert bucket["attempts"] == 1, f"{model_id} attempts"
        assert bucket["first_try_success"] == 0, f"{model_id} first_try_success"
        assert bucket["first_try_success_rate"] == 0.0, f"{model_id} rate"
        assert bucket["succeeded"] == 0, f"{model_id} succeeded"


def test_render_text_surfaces_first_try_rate_for_rescued_primary(tmp_path):
    """Bug #900 UX: the text renderer surfaces `first_try_success_rate` so
    the operator sees primary degradation even when the rescuer's band is
    green. Without this, a rescued chain looks healthy in the report."""
    from loa_cheval.health import aggregate_substrate_health, render_text

    now = datetime(2026, 5, 14, 13, 0, 0, tzinfo=timezone.utc)
    envelopes = []
    for _ in range(3):
        envelopes.append(_make_modelinv_envelope({
            "models_requested": [
                "anthropic:claude-opus-4-7",
                "anthropic:claude-opus-4-6",
            ],
            "models_succeeded": ["anthropic:claude-opus-4-6"],
            "models_failed": [{
                "model": "anthropic:claude-opus-4-7", "provider": "anthropic",
                "error_class": "EMPTY_CONTENT", "message_redacted": "x",
            }],
            "operator_visible_warn": True,
            "final_model_id": "anthropic:claude-opus-4-6",
        }, timestamp="2026-05-14T12:00:00Z"))
    log = _write_log(tmp_path, envelopes)
    report = aggregate_substrate_health(log, now=now)
    text = render_text(report)
    assert "first-try" in text.lower()
    # The failing primary's header line is followed by its first-try
    # detail line (indented sub-line; doesn't repeat the model id).
    lines = text.splitlines()
    primary_header_idx = next(
        i for i, line in enumerate(lines)
        if "anthropic:claude-opus-4-7" in line
    )
    primary_first_try = lines[primary_header_idx + 1]
    assert "first-try" in primary_first_try.lower()
    assert "0.0%" in primary_first_try


def test_aggregate_with_model_filter_excludes_co_requested_models(tmp_path):
    """DISS-001 (adversarial-review iter-1): `--model X` MUST NOT credit
    `attempts` to co-requested models. CLI-contract pin — without this
    gate, filtering by the primary surfaces the rescuer (and vice
    versa) in `per_model` with nonzero `attempts`."""
    from loa_cheval.health import aggregate_substrate_health

    now = datetime(2026, 5, 14, 13, 0, 0, tzinfo=timezone.utc)
    log = _write_log(tmp_path, [
        _make_modelinv_envelope({
            "models_requested": [
                "anthropic:claude-opus-4-7",
                "anthropic:claude-opus-4-6",
            ],
            "models_succeeded": ["anthropic:claude-opus-4-6"],
            "models_failed": [{
                "model": "anthropic:claude-opus-4-7", "provider": "anthropic",
                "error_class": "EMPTY_CONTENT", "message_redacted": "x",
            }],
            "operator_visible_warn": True,
            "final_model_id": "anthropic:claude-opus-4-6",
        }, timestamp="2026-05-14T12:00:00Z"),
    ])

    # Filter on the failing primary — co-requested rescuer must not get
    # `attempts` credit in the filtered output.
    result_primary = aggregate_substrate_health(
        log, now=now, model_filter="anthropic:claude-opus-4-7",
    )
    primary = result_primary["per_model"]["anthropic:claude-opus-4-7"]
    assert primary["attempts"] == 1
    # The rescuer's bucket may still be present via the pre-existing
    # final_model bucketing, but its `attempts` MUST be zero under the
    # filter (the new metric is gated).
    rescuer = result_primary["per_model"].get("anthropic:claude-opus-4-6")
    if rescuer is not None:
        assert rescuer["attempts"] == 0, (
            "rescuer leaked into filtered per-models_requested attribution"
        )
        assert rescuer["first_try_success"] == 0

    # And the inverse: filter on the rescuer — primary must not get
    # `attempts` credit in the filtered output.
    result_rescuer = aggregate_substrate_health(
        log, now=now, model_filter="anthropic:claude-opus-4-6",
    )
    primary_via_rescuer = result_rescuer["per_model"].get(
        "anthropic:claude-opus-4-7",
    )
    if primary_via_rescuer is not None:
        assert primary_via_rescuer["attempts"] == 0, (
            "primary leaked into filtered per-models_requested attribution"
        )

    # Unfiltered: existing behavior preserved — both models get attempts.
    result_all = aggregate_substrate_health(log, now=now)
    assert result_all["per_model"]["anthropic:claude-opus-4-7"]["attempts"] == 1
    assert result_all["per_model"]["anthropic:claude-opus-4-6"]["attempts"] == 1
