"""cycle-124 Sprint 1 Task 1.4 — AC-3.5 input-size matrix, cheval leg (SDD §3.2).

Drives estimated inputs of 120K / 160K / 180K / 200K / 900K tokens through
cheval's in-process dispatch with a fake adapter, under all four combinations
of LOA_CHEVAL_DISABLE_INPUT_GATE × LOA_CHEVAL_DISABLE_STREAMING, and asserts
WHICH gate fires first and that nothing above the ceiling is ever dispatched:

  gate on,  streaming on   → pre-flight preempts above 180K (exit 7, PREFLIGHT_PREEMPT)
  gate on,  streaming off  → the 36K legacy wall refuses the whole matrix (ROUTING_MISS
                             per hop ⇒ CHAIN_EXHAUSTED); above 180K the pre-flight
                             still fires first (CONTEXT_TOO_LARGE)
  gate off, streaming on   → no cheval gate; the request reaches the adapter,
                             whose enforce_context_window (1M − 64K) is the
                             next line of defence (900K + 64K < 1M passes it)
  gate off, streaming off  → same, with the 16K default

`--dry-run` returns before the gate and `--mock-fixture-dir` bypasses it, so
the in-process harness (test_preflight_preempt_modelinv.py pattern) is the
only vehicle that exercises the real gate (recorded in NOTES).
"""

from __future__ import annotations

import sys
import types
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import cheval  # type: ignore[import-not-found]  # noqa: E402
from loa_cheval.providers.base import enforce_context_window, estimate_tokens  # noqa: E402
from loa_cheval.types import (  # noqa: E402
    CompletionRequest,
    CompletionResult,
    ContextTooLargeError,
    ModelConfig,
    Usage,
)

CEILING = 180_000
LEGACY_WALL = 36_000
SIZES = [120_000, 160_000, 180_000, 200_000, 900_000]


def _prompt_of_tokens(n: int) -> str:
    """A prompt whose cheval estimate is the largest value ≤ n tokens (calibrated, not assumed).

    The 180K row sits exactly ON the ceiling, so the estimate must not overshoot.
    """
    unit = "lorem ipsum dolor sit amet consectetur "
    probe = unit * 1000
    per_unit = estimate_tokens([{"role": "user", "content": probe}]) / 1000
    reps = int(n / per_unit) + 1
    while reps > 0 and estimate_tokens([{"role": "user", "content": unit * reps}]) > n:
        reps -= 1
    return unit * reps


def _config():
    return {
        "aliases": {"opus": "anthropic:claude-opus-5"},
        "providers": {
            "anthropic": {
                "type": "anthropic",
                "endpoint": "https://api.anthropic.com/v1",
                "auth": "dummy",
                "models": {
                    "claude-opus-5": {
                        "capabilities": ["chat"],
                        "context_window": 1_000_000,
                        "max_output_tokens": 128_000,
                        "effective_input_ceiling": CEILING,
                        "ceiling_calibration": {"source": "kf_derived", "calibrated_at": None, "stale_after_days": 90},
                    },
                },
            },
        },
        "feature_flags": {"metering": False},
    }


def _args(prompt: str):
    args = types.SimpleNamespace()
    args.agent = "flatline-reviewer"
    args.role = None
    args.skill = None
    args.sprint_kind = None
    args.input = None
    args.prompt = prompt
    args.system = None
    args.model = None
    args.max_tokens = None
    args.effort = None
    args.output_format = "text"
    args.json_errors = True
    args.timeout = 30
    args.include_thinking = False
    args.async_mode = False
    args.poll_id = None
    args.cancel_id = None
    args.dry_run = False
    args.print_config = False
    args.validate_bindings = False
    args.mock_fixture_dir = None
    args.max_input_tokens = None
    return args


@pytest.fixture(autouse=True)
def _no_persona(monkeypatch):
    monkeypatch.setattr(cheval, "_load_persona", lambda *_a, **_kw: None)
    monkeypatch.setattr(cheval, "_load_persona_parts", lambda *_a, **_kw: (None, None))
    monkeypatch.setattr(cheval, "_check_feature_flags", lambda *_a, **_kw: None)


def _run(prompt: str, *, gate_off: bool, streaming_off: bool, monkeypatch):
    for var in ("LOA_CHEVAL_DISABLE_INPUT_GATE", "LOA_CHEVAL_DISABLE_STREAMING", "LOA_CHEVAL_LEGACY_WIRE"):
        monkeypatch.delenv(var, raising=False)
    if gate_off:
        monkeypatch.setenv("LOA_CHEVAL_DISABLE_INPUT_GATE", "1")
    if streaming_off:
        monkeypatch.setenv("LOA_CHEVAL_DISABLE_STREAMING", "1")
    dispatched = []

    def _retry_side(_adapter, req, _cfg, budget_hook=None):
        dispatched.append(req)
        return CompletionResult(content="ok", model="claude-opus-5", provider="anthropic",
                                usage=Usage(input_tokens=1, output_tokens=1), latency_ms=1,
                                tool_calls=None, thinking=None, metadata={"streaming": not streaming_off})

    captured: dict = {}

    def _fake_emit(level, event, payload, *_a, **_kw):
        captured.update(payload)

    with patch.object(cheval, "load_config", return_value=(_config(), {})), \
         patch.object(cheval, "resolve_execution", return_value=(
             MagicMock(temperature=0.7, capability_class=None),
             MagicMock(provider="anthropic", model_id="claude-opus-5"))), \
         patch.object(cheval, "_build_provider_config", return_value=MagicMock()), \
         patch.object(cheval, "get_adapter", return_value=MagicMock()), \
         patch("loa_cheval.providers.retry.invoke_with_retry", side_effect=_retry_side), \
         patch("loa_cheval.audit_envelope.audit_emit", _fake_emit), \
         patch("loa_cheval.audit.modelinv.redact_payload_strings", side_effect=lambda x: x), \
         patch("loa_cheval.audit.modelinv.assert_no_secret_shapes_remain"):
        code = cheval.cmd_invoke(_args(prompt))
    return code, dispatched, captured


def _failed_classes(captured) -> set:
    return {f.get("error_class") for f in captured.get("models_failed", [])}


@pytest.mark.parametrize("size", SIZES)
def test_gate_on_streaming_on_preflight_owns_the_180k_line(size, monkeypatch, capsys):
    code, dispatched, captured = _run(_prompt_of_tokens(size), gate_off=False, streaming_off=False,
                                      monkeypatch=monkeypatch)
    err = capsys.readouterr().err
    if size <= CEILING:
        assert code == cheval.EXIT_CODES["SUCCESS"], err
        assert len(dispatched) == 1 and dispatched[0].max_tokens == 64_000
    else:
        assert code == cheval.EXIT_CODES["CONTEXT_TOO_LARGE"], err
        assert dispatched == [], "nothing above the ceiling may reach an adapter"
        assert "PREFLIGHT_PREEMPT" in _failed_classes(captured)
        assert "[preflight] preempt" in err


@pytest.mark.parametrize("size", SIZES)
def test_gate_on_streaming_off_legacy_wall_fires_first(size, monkeypatch, capsys):
    """Every size in the matrix is above 36K, so nothing is dispatched with streaming off.

    Gate order under the kill switch: the pre-flight (raw 180K ceiling) still
    runs first and owns inputs above 180K; the 36K legacy wall (the chain-walk
    gate) owns the 36K–180K band. Both refuse with exit 7 and no dispatch.
    """
    code, dispatched, captured = _run(_prompt_of_tokens(size), gate_off=False, streaming_off=True,
                                      monkeypatch=monkeypatch)
    err = capsys.readouterr().err
    assert dispatched == []
    if size > CEILING:
        assert code == cheval.EXIT_CODES["CONTEXT_TOO_LARGE"], err
        assert "PREFLIGHT_PREEMPT" in _failed_classes(captured)
    else:
        # The legacy wall is the chain-walk gate: it records a ROUTING_MISS
        # naming the 36K threshold for the hop and walks on (no stderr line
        # unless --verbose); with every hop skipped the call ends as
        # CHAIN_EXHAUSTED (exit 12), not CONTEXT_TOO_LARGE (exit 7) — the two
        # gates disagree on the exit code for the same refusal class
        # (observation recorded in the Sprint 1 report, not changed here).
        assert code == cheval.EXIT_CODES["CHAIN_EXHAUSTED"], err
        assert f"> {LEGACY_WALL} threshold" in err, err
        misses = [f for f in captured.get("models_failed", []) if f.get("error_class") == "ROUTING_MISS"]
        assert misses, captured.get("models_failed")
        assert any(f"> {LEGACY_WALL} threshold" in f.get("message_redacted", "") for f in misses), misses


def test_gate_on_streaming_off_small_prompt_passes_with_16k_default(monkeypatch, capsys):
    code, dispatched, _ = _run(_prompt_of_tokens(20_000), gate_off=False, streaming_off=True,
                               monkeypatch=monkeypatch)
    assert code == cheval.EXIT_CODES["SUCCESS"], capsys.readouterr().err
    assert dispatched[0].max_tokens == 16_000


@pytest.mark.parametrize("streaming_off", [False, True])
@pytest.mark.parametrize("size", SIZES)
def test_gate_off_dispatches_and_the_adapter_context_window_is_next(size, streaming_off, monkeypatch, capsys):
    code, dispatched, captured = _run(_prompt_of_tokens(size), gate_off=True, streaming_off=streaming_off,
                                      monkeypatch=monkeypatch)
    err = capsys.readouterr().err
    assert code == cheval.EXIT_CODES["SUCCESS"], err
    assert len(dispatched) == 1
    assert "PREFLIGHT_PREEMPT" not in _failed_classes(captured)
    req = dispatched[0]
    assert req.max_tokens == (16_000 if streaming_off else 64_000)
    # The adapter's enforce_context_window is the next gate: at 1M context the
    # whole matrix (≤ 900K + 64K) still fits, which is exactly why the 180K
    # pre-flight ceiling — not the context window — is the load-bearing gate.
    enforce_context_window(req, ModelConfig(capabilities=["chat"], context_window=1_000_000))
    # Against the old 200K envelope the same request only fails once
    # input + reserved output exceed the window — i.e. the context-window
    # gate is a coarse backstop, not the 180K operating ceiling.
    small = CompletionRequest(messages=req.messages, model=req.model, max_tokens=req.max_tokens)
    if size + req.max_tokens > 200_000:
        with pytest.raises(ContextTooLargeError):
            enforce_context_window(small, ModelConfig(capabilities=["chat"], context_window=200_000))
    else:
        enforce_context_window(small, ModelConfig(capabilities=["chat"], context_window=200_000))
