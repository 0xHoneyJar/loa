"""cycle-126 Sprint 1 Task 1.1 / 1.2 (PRD FR-1.1, SDD D-1.1 / D-1.1b / D-1.4)
— the 600,000-token request end to end through cheval's in-process dispatch
(the pattern of test_input_size_consumers.py: real gate, fake transport):

  default policy            → preempt at the probed bound (basis probed)
  opt-in, low estimate      → warn + dispatch, envelope ceiling_unverified
  opt-in, high estimate     → preempt with the calibration command
  opt-in, count endpoint    → the count is authoritative (warn)
  legacy transport          → the 36K wall still owns the walk gate
  LOA_CHEVAL_LEGACY_CEILING → today's literal + preempt, no I1 shrink
  calibrated entry          → its calibrated value
  provider limit (opt-in)   → CEILING_UNVERIFIED_LIMIT, NO chain walk, an
                              observed-bound row, preempt on the next call
  provider limit (default)  → PROVIDER_CONTEXT_LIMIT, no walk, recorded
  429 while unverified      → RATE_LIMIT_UNVERIFIED, no walk, bound unchanged
  170K on a 200K entry      → max_tokens shrunk 64,000 → 30,000, recorded
"""
from __future__ import annotations

import sys
import types
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import cheval  # type: ignore[import-not-found]  # noqa: E402
from loa_cheval.providers.base import estimate_tokens  # noqa: E402
from loa_cheval.routing.ceiling import load_observed, observed_for, observed_store_path  # noqa: E402
from loa_cheval.types import (  # noqa: E402
    CompletionResult,
    ProviderContextLimitError,
    RateLimitError,
    Usage,
)

PROBED = 180_000
CAL = {"source": "kf_derived", "calibrated_at": None, "stale_after_days": 90}
UNIT_ASCII = "lorem ipsum dolor sit amet consectetur "
UNIT_CJK = "東京都は日本の首都であり、政治・経済の中心地である。"


def _prompt_of_tokens(n: int, unit: str = UNIT_ASCII) -> str:
    probe = unit * 500
    per_unit = estimate_tokens([{"role": "user", "content": probe}]) / 500
    reps = int(n / per_unit) + 1
    while reps > 0 and estimate_tokens([{"role": "user", "content": unit * reps}]) > n:
        reps -= 1
    return unit * reps


def _entry(context_window=1_000_000, ceiling=PROBED, cal=CAL, chain=None):
    e = {"capabilities": ["chat"], "context_window": context_window, "max_output_tokens": 128_000,
         "effective_input_ceiling": ceiling, "probed_ceiling": PROBED, "ceiling_calibration": dict(cal)}
    if chain:
        e["fallback_chain"] = chain
    return e


def _config(head=None):
    return {
        "aliases": {"opus": "anthropic:claude-opus-5"},
        "providers": {"anthropic": {"type": "anthropic", "endpoint": "https://api.anthropic.com/v1", "auth": "dummy",
                                    "models": {"claude-opus-5": head or _entry(chain=["anthropic:claude-opus-4-8"]),
                                               "claude-opus-4-8": _entry()}}},
        "feature_flags": {"metering": False},
    }


def _args(prompt: str):
    a = types.SimpleNamespace()
    a.agent = "flatline-reviewer"; a.role = None; a.skill = None; a.sprint_kind = None; a.input = None
    a.prompt = prompt; a.system = None; a.model = None; a.max_tokens = None; a.effort = None
    a.output_format = "text"; a.json_errors = True; a.timeout = 30; a.include_thinking = False
    a.async_mode = False; a.poll_id = None; a.cancel_id = None; a.dry_run = False; a.print_config = False
    a.validate_bindings = False; a.mock_fixture_dir = None; a.max_input_tokens = None
    return a


@pytest.fixture(autouse=True)
def _quiet(monkeypatch):
    monkeypatch.setattr(cheval, "_load_persona", lambda *_a, **_kw: None)
    monkeypatch.setattr(cheval, "_load_persona_parts", lambda *_a, **_kw: (None, None))
    monkeypatch.setattr(cheval, "_check_feature_flags", lambda *_a, **_kw: None)
    for var in ("LOA_CHEVAL_DISABLE_INPUT_GATE", "LOA_CHEVAL_DISABLE_STREAMING", "LOA_CHEVAL_LEGACY_WIRE",
                "LOA_CHEVAL_LEGACY_CEILING", "LOA_CHEVAL_UNCALIBRATED_CEILING", "LOA_CHEVAL_MAX_INPUT_TOKENS"):
        monkeypatch.delenv(var, raising=False)


def _ok(model):
    return CompletionResult(content="ok", model=model, provider="anthropic", usage=Usage(input_tokens=1, output_tokens=1),
                            latency_ms=1, tool_calls=None, thinking=None, metadata={"streaming": True})


def _run(prompt, *, config=None, errors=None, adapter=None):
    """errors: exceptions raised by successive transport calls (then success)."""
    dispatched, queue, captured = [], list(errors or []), {}

    def _retry_side(_adapter, req, _cfg, budget_hook=None):
        dispatched.append(req)
        if queue:
            raise queue.pop(0)
        return _ok(req.model)

    def _fake_emit(level, event, payload, *_a, **_kw):
        captured.update(payload)

    with patch.object(cheval, "load_config", return_value=(config or _config(), {})), \
         patch.object(cheval, "resolve_execution", return_value=(
             MagicMock(temperature=None, capability_class=None),
             MagicMock(provider="anthropic", model_id="claude-opus-5"))), \
         patch.object(cheval, "_build_provider_config", return_value=MagicMock()), \
         patch.object(cheval, "get_adapter", return_value=adapter if adapter is not None else MagicMock()), \
         patch("loa_cheval.providers.retry.invoke_with_retry", side_effect=_retry_side), \
         patch("loa_cheval.audit_envelope.audit_emit", _fake_emit), \
         patch("loa_cheval.audit.modelinv.redact_payload_strings", side_effect=lambda x: x), \
         patch("loa_cheval.audit.modelinv.assert_no_secret_shapes_remain"):
        code = cheval.cmd_invoke(_args(prompt))
    return code, dispatched, captured


def _classes(captured):
    return [f.get("error_class") for f in captured.get("models_failed", [])]


def _cap(captured):
    return captured.get("capability_evaluation") or {}


SIX = _prompt_of_tokens(600_000)


def test_default_policy_preempts_600k_at_the_probed_bound(capsys):
    code, dispatched, cap = _run(SIX)
    err = capsys.readouterr().err
    assert code == cheval.EXIT_CODES["CONTEXT_TOO_LARGE"] and dispatched == []
    assert "PREFLIGHT_PREEMPT" in _classes(cap)
    ce = _cap(cap)
    assert ce["preflight_decision"] == "preempt" and ce["input_ceiling"]["value"] == PROBED and ce["input_ceiling"]["basis"] == "probed"
    assert ce["ceiling_policy"] == "probed" and ce["estimator"]["uncertainty"] == "low"
    assert "[preflight] preempt" in err and '"ceiling_basis": "probed"' in err


def test_opt_in_low_estimate_warns_and_dispatches(monkeypatch, capsys):
    monkeypatch.setenv("LOA_CHEVAL_UNCALIBRATED_CEILING", "derived")
    code, dispatched, cap = _run(SIX)
    err = capsys.readouterr().err
    assert code == cheval.EXIT_CODES["SUCCESS"], err
    assert len(dispatched) == 1 and dispatched[0].max_tokens == 64_000
    ce = _cap(cap)
    assert ce["preflight_decision"] == "warn" and ce["ceiling_unverified"] is True
    assert ce["input_ceiling"]["basis"] == "derived" and ce["input_ceiling"]["value"] == 1_000_000 - 64_000
    assert "[preflight] warn" in err and "ceiling-probe-live.py --model claude-opus-5" in err
    assert cap.get("operator_visible_warn") is True


def test_opt_in_high_estimate_preempts_with_the_calibration_command(monkeypatch, capsys):
    monkeypatch.setenv("LOA_CHEVAL_UNCALIBRATED_CEILING", "derived")
    code, dispatched, cap = _run(_prompt_of_tokens(600_000, UNIT_CJK))
    err = capsys.readouterr().err
    assert code == cheval.EXIT_CODES["CONTEXT_TOO_LARGE"] and dispatched == []
    assert _cap(cap)["estimator"]["uncertainty"] == "high" and "calibrate first" in err


def test_opt_in_count_endpoint_is_authoritative(monkeypatch):
    monkeypatch.setenv("LOA_CHEVAL_UNCALIBRATED_CEILING", "derived")

    class _Adapter:
        def count_tokens(self, request):
            return 611_000

    code, dispatched, cap = _run(_prompt_of_tokens(600_000, UNIT_CJK), adapter=_Adapter())
    assert code == cheval.EXIT_CODES["SUCCESS"] and len(dispatched) == 1
    ce = _cap(cap)
    assert ce["preflight_decision"] == "warn" and ce["estimator"] == {"method": "count_tokens", "chars": ce["estimator"]["chars"],
                                                                      "tokens": 611_000, "uncertainty": "none"}
    assert ce["estimated_input_tokens"] == 611_000


def test_legacy_transport_wall_still_owns_the_walk_gate(monkeypatch, capsys):
    monkeypatch.setenv("LOA_CHEVAL_UNCALIBRATED_CEILING", "derived")
    monkeypatch.setenv("LOA_CHEVAL_DISABLE_STREAMING", "1")
    code, dispatched, cap = _run(_prompt_of_tokens(100_000))
    err = capsys.readouterr().err
    assert dispatched == [] and code == cheval.EXIT_CODES["CHAIN_EXHAUSTED"], err
    misses = cap.get("models_failed", [])
    assert [f["error_class"] for f in misses] == ["ROUTING_MISS", "ROUTING_MISS"]
    assert all("> 36000 threshold" in f["message_redacted"] for f in misses), misses


def test_legacy_ceiling_kill_switch_is_todays_behaviour(monkeypatch, capsys):
    monkeypatch.setenv("LOA_CHEVAL_UNCALIBRATED_CEILING", "derived")
    monkeypatch.setenv("LOA_CHEVAL_LEGACY_CEILING", "1")
    code, dispatched, cap = _run(SIX)
    err = capsys.readouterr().err
    assert code == cheval.EXIT_CODES["CONTEXT_TOO_LARGE"] and dispatched == [] and "PREFLIGHT_PREEMPT" in _classes(cap)
    assert _cap(cap).get("input_ceiling") is None and '"ceiling_policy": "legacy"' in err
    # a 170K input on a 200K entry: no I1 shrink under the kill switch (today's request body)
    code, dispatched, cap = _run(_prompt_of_tokens(170_000), config=_config(head=_entry(context_window=200_000)))
    assert code == cheval.EXIT_CODES["SUCCESS"] and dispatched[0].max_tokens == 64_000
    assert _cap(cap).get("max_tokens_shrunk") is None


def test_calibrated_entry_uses_its_calibrated_value():
    cal = {"source": "empirical_probe", "calibrated_at": "2026-09-25T00:00:00Z", "stale_after_days": 90}
    code, dispatched, cap = _run(SIX, config=_config(head=_entry(ceiling=640_000, cal=cal)))
    assert code == cheval.EXIT_CODES["SUCCESS"] and len(dispatched) == 1
    assert _cap(cap)["input_ceiling"] == {"value": 640_000, "basis": "calibrated", "calibrated": True, "probed": PROBED,
                                          "derived": 1_000_000 - 64_000, "observed": None}


def test_provider_limit_above_the_probed_bound_is_not_walked_and_lowers_the_bound(monkeypatch, capsys):
    monkeypatch.setenv("LOA_CHEVAL_UNCALIBRATED_CEILING", "derived")
    limit = ProviderContextLimitError("anthropic", "HTTP 400 context-limit: prompt is too long: 612000 tokens > 400000 maximum",
                                      status=400, input_tokens=612_000, limit=400_000)
    code, dispatched, cap = _run(SIX, errors=[limit])
    err = capsys.readouterr().err
    assert code == cheval.EXIT_CODES["CONTEXT_TOO_LARGE"]
    assert len(dispatched) == 1, "the fallback hop must NOT receive the same payload"
    assert _classes(cap) == ["CEILING_UNVERIFIED_LIMIT"]
    ce = _cap(cap)
    assert ce["calibration_needed"]["observed_input_tokens"] == 612_000 and ce["calibration_needed"]["provider_limit"] == 400_000
    assert ce["calibration_needed"]["calibrate"] == "python3 tools/ceiling-probe-live.py --model claude-opus-5 --write-catalog"
    assert "[preflight] calibration_needed" in err and '"calibration_needed": true' in err
    store = load_observed(observed_store_path())
    assert len(store["entries"]) == 1 and store["entries"][0]["error_class"] == "CEILING_UNVERIFIED_LIMIT"
    assert observed_for("anthropic", "claude-opus-5") == 400_001
    # the next call is bounded by the observation until calibration
    code, dispatched, cap = _run(SIX)
    assert code == cheval.EXIT_CODES["CONTEXT_TOO_LARGE"] and dispatched == []
    assert _cap(cap)["input_ceiling"]["basis"] == "observed" and _cap(cap)["input_ceiling"]["value"] == 400_000
    # but a request under it proceeds
    code, dispatched, _ = _run(_prompt_of_tokens(300_000))
    assert code == cheval.EXIT_CODES["SUCCESS"] and len(dispatched) == 1


def test_provider_limit_under_the_probed_bound_is_the_catalogs_error_and_still_not_walked():
    limit = ProviderContextLimitError("anthropic", "HTTP 400 context-limit: prompt is too long: 150000 tokens > 120000 maximum",
                                      status=400, input_tokens=150_000, limit=120_000)
    code, dispatched, cap = _run(_prompt_of_tokens(150_000), errors=[limit])
    assert code == cheval.EXIT_CODES["CONTEXT_TOO_LARGE"] and len(dispatched) == 1
    assert _classes(cap) == ["PROVIDER_CONTEXT_LIMIT"] and observed_for("anthropic", "claude-opus-5") == 120_001


def test_429_while_unverified_is_recorded_not_walked_and_never_lowers_the_bound(monkeypatch):
    monkeypatch.setenv("LOA_CHEVAL_UNCALIBRATED_CEILING", "derived")
    code, dispatched, cap = _run(SIX, errors=[RateLimitError("anthropic")])
    assert code == cheval.EXIT_CODES["RATE_LIMITED"] and len(dispatched) == 1
    assert _classes(cap) == ["RATE_LIMIT_UNVERIFIED"] and "calibration_needed" in _cap(cap)
    assert observed_for("anthropic", "claude-opus-5") is None and len(load_observed(observed_store_path())["entries"]) == 1
    # under the probed bound a 429 walks as before
    monkeypatch.delenv("LOA_CHEVAL_UNCALIBRATED_CEILING")
    code, dispatched, cap = _run(_prompt_of_tokens(100_000), errors=[RateLimitError("anthropic")])
    assert code == cheval.EXIT_CODES["SUCCESS"] and len(dispatched) == 2 and _classes(cap) == ["PROVIDER_OUTAGE"]


def test_170k_on_a_200k_entry_shrinks_the_output_budget_instead_of_failing(capsys):
    code, dispatched, cap = _run(_prompt_of_tokens(170_000), config=_config(head=_entry(context_window=200_000)))
    err = capsys.readouterr().err
    assert code == cheval.EXIT_CODES["SUCCESS"], err
    # the prompt calibrates to ≤ 170K tokens, so the room is 30K plus the calibration slack
    assert len(dispatched) == 1 and 30_000 <= dispatched[0].max_tokens <= 31_000
    shrunk = _cap(cap)["max_tokens_shrunk"]
    assert shrunk["from"] == 64_000 and shrunk["to"] == dispatched[0].max_tokens
    assert "[preflight] max_tokens shrunk 64000" in err


def test_unverified_status_is_per_hop_not_inherited_from_the_head(monkeypatch):
    """Review DISS-001: the head runs above its probed bound under the opt-in; it fails for a
    walkable reason; the fallback is CALIBRATED at 900K (so the same payload is verified there).
    An ordinary 429 on the fallback must walk / end as PROVIDER_OUTAGE — never as
    RATE_LIMIT_UNVERIFIED, and never write a calibration record."""
    monkeypatch.setenv("LOA_CHEVAL_UNCALIBRATED_CEILING", "derived")
    cal = {"source": "empirical_probe", "calibrated_at": "2026-09-25T00:00:00Z", "stale_after_days": 90}
    cfg = _config(head=_entry(chain=["anthropic:claude-opus-4-8"]))
    cfg["providers"]["anthropic"]["models"]["claude-opus-4-8"] = _entry(ceiling=900_000, cal=cal)
    from loa_cheval.types import ProviderUnavailableError
    code, dispatched, cap = _run(SIX, config=cfg, errors=[ProviderUnavailableError("anthropic", "503"), RateLimitError("anthropic")])
    assert len(dispatched) == 2, "the fallback hop is tried"
    classes = _classes(cap)
    assert "RATE_LIMIT_UNVERIFIED" not in classes and classes.count("PROVIDER_OUTAGE") == 2, classes
    assert "calibration_needed" not in _cap(cap)
    assert code == cheval.EXIT_CODES["CHAIN_EXHAUSTED"]
    assert len(load_observed(observed_store_path())["entries"]) == 0
    # the head's own envelope flag still says the head ran unverified
    assert _cap(cap)["ceiling_unverified"] is True
    # and a provider verdict on the CALIBRATED fallback is classed as the catalog's error, not unverified
    limit = ProviderContextLimitError("anthropic", "HTTP 400 context-limit: prompt is too long: 612000 tokens > 600000 maximum",
                                      status=400, input_tokens=612_000, limit=600_000)
    code, dispatched, cap = _run(SIX, config=cfg, errors=[ProviderUnavailableError("anthropic", "503"), limit])
    assert _classes(cap) == ["PROVIDER_OUTAGE", "PROVIDER_CONTEXT_LIMIT"] and len(dispatched) == 2


def test_calibration_exit_redacts_secret_shapes_in_the_recorded_message(capsys):
    """Audit sprint-247 (rejected payload, chunk b): the provider verdict's text is passed through the
    redaction helper before it lands in models_failed / stderr JSON — a secret-shaped fragment in a
    provider error body never reaches the envelope or the operator log."""
    leak = ProviderContextLimitError("anthropic", "HTTP 400 context-limit: prompt is too long (key sk-ant-api03-ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnop echoed)",
                                     status=400, input_tokens=150_000, limit=120_000)
    code, dispatched, cap = _run(_prompt_of_tokens(150_000), errors=[leak])
    err = capsys.readouterr().err
    assert code == cheval.EXIT_CODES["CONTEXT_TOO_LARGE"]
    recorded = [f for f in cap.get("models_failed", []) if f.get("error_class") == "PROVIDER_CONTEXT_LIMIT"][0]
    assert "sk-ant-api03-ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnop" not in recorded["message_redacted"]
    assert "sk-ant-api03-ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnop" not in err
    assert "context-limit" in recorded["message_redacted"], "the useful part of the message survives"
