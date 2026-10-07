"""cycle-127 sprint-251 review r251-1 C7 (HIGH) — the units gap.

A calibrated bound is in provider-MEASURED tokens; cheval's pre-dispatch
estimate (chars/3.5, or cl100k) under-counts the Opus 4.7+ tokenizer by
≈1.4–1.8×. For a CALIBRATED entry the provider count therefore replaces the
estimate from half the bound (``CALIBRATED_COUNT_NEAR_BOUND = 0.5``, not
0.9); the count is authoritative; when no count is available the gate
dispatches with ``warn`` and says the estimate is uncertain. Uncalibrated
entries keep the 0.9 trigger.
"""
from __future__ import annotations

import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from loa_cheval.routing import ceiling as C  # noqa: E402
from loa_cheval.routing.ceiling import GateEstimate, gate  # noqa: E402

BOUND = 936_000


def _calibrated():
    return {"context_window": 1_000_000, "max_output_tokens": 128_000, "effective_input_ceiling": BOUND,
            "probed_ceiling": BOUND, "model_id": "claude-opus-5-5",
            "ceiling_calibration": {"source": "operator_set", "calibrated_at": "2026-10-07T09:29:07Z",
                                    "stale_after_days": 90, "transport": "claude-headless",
                                    "measured_input_tokens": 972_887}}


def _uncalibrated():
    return {"context_window": 1_000_000, "max_output_tokens": 128_000, "effective_input_ceiling": 400_000,
            "probed_ceiling": 400_000,
            "ceiling_calibration": {"source": "conservative_default", "calibrated_at": None, "stale_after_days": 90}}


class _Spy:
    def __init__(self, value):
        self.value, self.calls = value, 0

    def __call__(self):
        self.calls += 1
        return self.value


@pytest.fixture(autouse=True)
def _clean_env(monkeypatch):
    for k in ("LOA_CHEVAL_LEGACY_CEILING", "LOA_CHEVAL_UNCALIBRATED_CEILING", "LOA_CHEVAL_MAX_INPUT_TOKENS"):
        monkeypatch.delenv(k, raising=False)


def test_the_trigger_constants():
    assert C.COUNT_NEAR_BOUND == 0.9
    assert C.CALIBRATED_COUNT_NEAR_BOUND == 0.5


def test_calibrated_entry_counts_from_half_the_bound_and_the_count_preempts():
    spy = _Spy(int(1.1 * BOUND))
    out = gate(_calibrated(), estimate=GateEstimate(tokens=int(0.6 * BOUND)), requested_max_tokens=64_000, counter=spy)
    assert spy.calls == 1
    assert out.action == "preempt", out.reason
    assert out.estimate.method == "count_tokens" and out.estimate.tokens == int(1.1 * BOUND)


def test_calibrated_entry_dispatches_on_a_count_under_the_bound():
    spy = _Spy(int(0.7 * BOUND))
    out = gate(_calibrated(), estimate=GateEstimate(tokens=int(0.6 * BOUND)), requested_max_tokens=64_000, counter=spy)
    assert out.action == "dispatch" and out.estimate.method == "count_tokens"


@pytest.mark.parametrize("counter", [None, _Spy(None)], ids=["no-counter", "count-failed"])
def test_calibrated_entry_without_a_count_warns_that_the_estimate_is_uncertain(counter):
    out = gate(_calibrated(), estimate=GateEstimate(tokens=int(0.6 * BOUND)), requested_max_tokens=64_000,
               counter=counter)
    assert out.action == "warn", out.reason
    assert "uncertain" in out.reason and "provider-measured" in out.reason
    assert out.estimate.method == "heuristic"


def test_calibrated_entry_below_half_the_bound_never_counts():
    spy = _Spy(int(1.1 * BOUND))
    out = gate(_calibrated(), estimate=GateEstimate(tokens=int(0.4 * BOUND)), requested_max_tokens=64_000, counter=spy)
    assert spy.calls == 0 and out.action == "dispatch"


def test_uncalibrated_entry_keeps_the_0_9_trigger():
    spy = _Spy(10**7)
    out = gate(_uncalibrated(), estimate=GateEstimate(tokens=int(0.6 * 400_000)), requested_max_tokens=64_000,
               counter=spy)
    assert spy.calls == 0 and out.action == "dispatch"
    out = gate(_uncalibrated(), estimate=GateEstimate(tokens=int(0.95 * 400_000)), requested_max_tokens=64_000,
               counter=spy)
    assert spy.calls == 1 and out.action == "preempt"
    # no count in the 0.5–0.9 band of an uncalibrated entry: plain dispatch, no warn
    out = gate(_uncalibrated(), estimate=GateEstimate(tokens=int(0.6 * 400_000)), requested_max_tokens=64_000)
    assert out.action == "dispatch"
