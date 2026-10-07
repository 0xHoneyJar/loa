"""cycle-127 sprint-251 review r251-1 C1 — transport-aware self-healing.

A calibration governs the input bound on every route (basis ``calibrated``),
but ``input_bound`` is consumed by the HTTP adapter: when the calibration was
measured on a FOREIGN transport (``ceiling_calibration.transport`` present and
not the HTTP one — today ``claude-headless``), a verified observed provider
limit (``.run/ceiling-observed.json``, the context classes only) may tighten
it to ``observed − 1`` (basis ``observed``, ``calibrated`` kept True so the
envelope and ``/loa`` can say "calibrated N (transport), observed M below on
this route"). A same-transport (``api``) or transport-less calibration is
authoritative and observations never lower it (cycle-126 behaviour).
"""
from __future__ import annotations

import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from loa_cheval.routing.ceiling import (  # noqa: E402
    GateEstimate,
    calibration_transport,
    gate,
    input_bound,
    is_foreign_transport_calibration,
)


def _entry(transport=None):
    cal = {"source": "operator_set", "calibrated_at": "2026-10-07T09:29:07Z", "stale_after_days": 90}
    if transport is not None:
        cal["transport"] = transport
    return {
        "context_window": 1_000_000,
        "max_output_tokens": 128_000,
        "effective_input_ceiling": 936_000,
        "probed_ceiling": 936_000,
        "ceiling_calibration": cal,
    }


@pytest.fixture(autouse=True)
def _clean_env(monkeypatch):
    for k in ("LOA_CHEVAL_LEGACY_CEILING", "LOA_CHEVAL_UNCALIBRATED_CEILING", "LOA_CHEVAL_MAX_INPUT_TOKENS"):
        monkeypatch.delenv(k, raising=False)


def test_foreign_transport_calibration_is_tightened_by_an_observed_limit_below_it():
    d = input_bound(_entry("claude-headless"), max_tokens=64_000, observed=500_001)
    assert d.value == 500_000 and d.basis == "observed"
    assert d.calibrated is True, "the decision still says the entry is calibrated"
    assert d.calibration_transport == "claude-headless"


def test_foreign_transport_calibration_stands_when_the_observation_is_above_it():
    d = input_bound(_entry("claude-headless"), max_tokens=64_000, observed=990_000)
    assert d.value == 936_000 and d.basis == "calibrated" and d.calibrated is True
    assert input_bound(_entry("claude-headless"), max_tokens=64_000).basis == "calibrated"


@pytest.mark.parametrize("transport", [None, "api", "API", "http", " api "])
def test_same_or_absent_transport_calibration_is_never_lowered_by_an_observation(transport):
    d = input_bound(_entry(transport), max_tokens=64_000, observed=500_001)
    assert d.value == 936_000 and d.basis == "calibrated" and d.calibrated is True


def test_transport_helpers():
    assert calibration_transport(_entry("claude-headless")) == "claude-headless"
    assert calibration_transport(_entry()) is None
    assert calibration_transport({"ceiling_calibration": "junk"}) is None
    assert is_foreign_transport_calibration(_entry("claude-headless")) is True
    for t in (None, "api", "http", ""):
        assert is_foreign_transport_calibration(_entry(t)) is False
    # an uncalibrated entry is never a "foreign calibration"
    unc = _entry("claude-headless")
    unc["ceiling_calibration"]["calibrated_at"] = None
    assert is_foreign_transport_calibration(unc) is False


def test_i1_and_the_guard_still_apply_below_a_tightened_foreign_calibration(monkeypatch):
    # I1 below the observation: the window minus a big output budget wins
    d = input_bound(_entry("claude-headless"), max_tokens=600_000, observed=500_001)
    assert d.value == 400_000 and d.basis == "i1"
    monkeypatch.setenv("LOA_CHEVAL_MAX_INPUT_TOKENS", "100000")
    assert input_bound(_entry("claude-headless"), max_tokens=64_000, observed=500_001).basis == "guard"


def test_gate_preempts_at_the_observed_bound_and_the_envelope_names_the_transport():
    out = gate(_entry("claude-headless"), estimate=GateEstimate(tokens=600_000), requested_max_tokens=64_000,
               observed=500_001)
    assert out.action == "preempt" and out.basis == "observed" and out.bound == 500_000
    env = out.as_envelope()["input_ceiling"]
    assert env["calibrated"] is True and env["observed"] == 500_001
    assert env["calibration_transport"] == "claude-headless"
    # same-transport calibration: the observation does not lower the bound
    same = gate(_entry("api"), estimate=GateEstimate(tokens=600_000), requested_max_tokens=64_000, observed=500_001)
    assert same.bound == 936_000 and same.basis == "calibrated"
    assert same.action == "warn", "no count above half a calibrated bound: dispatch with warn (r251-1 C7)"


def test_the_live_opus55_entry_is_a_foreign_transport_calibration():
    import yaml

    cfg = yaml.safe_load((ROOT.parent / "defaults" / "model-config.yaml").read_text())
    entry = cfg["providers"]["anthropic"]["models"]["claude-opus-5-5"]
    cal = entry.get("ceiling_calibration") or {}
    if not cal.get("calibrated_at") or cal.get("transport") in (None, "api"):
        pytest.skip("the live entry is not a foreign-transport calibration")
    ceiling = entry["effective_input_ceiling"]
    below = ceiling - 100_000
    d = input_bound(entry, max_tokens=64_000, observed=below + 1)
    assert d.value == below and d.basis == "observed" and d.calibrated is True
    assert input_bound(entry, max_tokens=64_000).value == ceiling
