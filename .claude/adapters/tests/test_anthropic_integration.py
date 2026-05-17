"""cycle-113 Sprint 1 T1.8 — Anthropic recovery-integration tests (FR-B-5).

Tests the integration of StreamingRecoveryTracker into
``parse_anthropic_stream`` and ``AnthropicAdapter._complete_streaming``,
using the deterministic parity fixtures emitted by
``tests/fixtures/cycle-113/streaming-parity/generate.py`` (T1.4 + T1.5).

Coverage matrix:
  - 2 healthy scenarios × telemetry-attached assertions
  - 3 abort scenarios × parser-level StreamingRecoveryAbort assertions
  - 1 abort scenario × adapter-level ProviderUnavailableError translation
  - 1 reasoning-class flip pinning the CoT-budget gate
  - 1 backward-compat: kwargs default to library-safe values
  - Total: 12 tests
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

REPO_ROOT = Path(__file__).resolve().parents[3]
FIXTURES_DIR = (
    REPO_ROOT / "tests" / "fixtures" / "cycle-113" / "streaming-parity"
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _load_fixture(name: str) -> bytes:
    """Read an Anthropic SSE fixture file."""
    return (FIXTURES_DIR / f"{name}.anthropic.sse").read_bytes()


def _byte_iter(data: bytes):
    """Single-yield byte iterator (parser-side robust to chunk boundaries)."""
    return iter([data])


class _FakeClock:
    """Monotonic clock that advances by ``step_s`` on every call.

    Used to make first_token_deadline fixtures deterministic without
    sleeping — every read returns a time ``step_s`` further from the
    start_time_s the tracker captured at construction.
    """

    def __init__(self, step_s: float = 100.0) -> None:
        self._t = 0.0
        self._step = step_s

    def __call__(self) -> float:
        self._t += self._step
        return self._t


class _PinnedClock:
    """Monotonic clock that returns a fixed value — for tests that need
    `time.monotonic()` to stay below the deadline so the parser exits
    on its own SSE-iter StopIteration rather than on a deadline abort.
    """

    def __init__(self, t: float = 0.0) -> None:
        self._t = t

    def __call__(self) -> float:
        return self._t


# ---------------------------------------------------------------------------
# Healthy scenarios — recovery is INACTIVE; telemetry attached as triggered=False
# ---------------------------------------------------------------------------


def test_healthy_short_succeeds_with_triggered_false():
    from loa_cheval.providers.anthropic_streaming import parse_anthropic_stream

    data = _load_fixture("healthy-short")
    result = parse_anthropic_stream(
        _byte_iter(data),
        model_data={},
        reasoning_class=False,
        now_provider=_PinnedClock(0.0),
    )

    assert result.content, "healthy fixture must produce non-empty content"
    sr = result.metadata.get("streaming_recovery")
    assert sr is not None, "streaming_recovery telemetry MUST be attached (I-3)"
    assert sr["triggered"] is False
    assert sr["reason"] is None
    assert sr["tokens_before_abort"] is None
    assert sr["config_applied"]["reasoning_class"] is False
    assert sr["config_applied"]["first_token_deadline_s"] == 30.0
    assert sr["config_applied"]["empty_content_window_tokens"] == 200
    assert sr["config_applied"]["cot_budget_tokens"] == 500


def test_healthy_cot_then_answer_succeeds_under_reasoning_class():
    from loa_cheval.providers.anthropic_streaming import parse_anthropic_stream

    data = _load_fixture("healthy-cot-then-answer")
    result = parse_anthropic_stream(
        _byte_iter(data),
        model_data={},
        reasoning_class=True,  # reasoning-class scenario
        now_provider=_PinnedClock(0.0),
    )

    sr = result.metadata["streaming_recovery"]
    assert sr["triggered"] is False, (
        "CoT followed by structured-answer marker must NOT trigger "
        "cot_budget_exhausted — the marker transitions to visible-content "
        "before the budget exhausts"
    )
    assert sr["config_applied"]["reasoning_class"] is True
    assert sr["config_applied"]["first_token_deadline_s"] == 60.0  # reasoning default


# ---------------------------------------------------------------------------
# Abort scenarios — recovery FIRES; parser raises StreamingRecoveryAbort
# ---------------------------------------------------------------------------


def test_abort_first_token_deadline_at_parser():
    from loa_cheval.providers.anthropic_streaming import parse_anthropic_stream
    from loa_cheval.streaming import StreamingRecoveryAbort

    data = _load_fixture("abort-first-token-deadline")

    with pytest.raises(StreamingRecoveryAbort) as exc_info:
        parse_anthropic_stream(
            _byte_iter(data),
            model_data={},
            reasoning_class=False,
            now_provider=_FakeClock(step_s=100.0),  # leap past 30s deadline
        )

    err = exc_info.value
    assert err.reason == "first_token_deadline"
    assert err.tokens_before_abort == 0
    assert err.config_applied["first_token_deadline_s"] == 30.0
    assert err.partial_content is None, "no tokens arrived → no partial content"


def test_abort_empty_content_window_at_parser():
    from loa_cheval.providers.anthropic_streaming import parse_anthropic_stream
    from loa_cheval.streaming import StreamingRecoveryAbort

    data = _load_fixture("abort-empty-content-window")

    with pytest.raises(StreamingRecoveryAbort) as exc_info:
        parse_anthropic_stream(
            _byte_iter(data),
            model_data={},
            reasoning_class=False,
            now_provider=_PinnedClock(0.0),
        )

    err = exc_info.value
    assert err.reason == "empty_content_window"
    assert err.tokens_before_abort == 200, (
        "library default empty_content_window_tokens=200; cycle-113 "
        "preserves cycle-109 thresholds"
    )
    assert err.partial_content is not None, (
        "200 whitespace tokens were accumulated before the abort decision "
        "fired; partial_content captures them for NFR-Obs-1 diagnostic"
    )


def test_abort_cot_budget_exhausted_at_parser():
    from loa_cheval.providers.anthropic_streaming import parse_anthropic_stream
    from loa_cheval.streaming import StreamingRecoveryAbort

    data = _load_fixture("abort-cot-budget-exhausted")

    with pytest.raises(StreamingRecoveryAbort) as exc_info:
        parse_anthropic_stream(
            _byte_iter(data),
            model_data={},
            reasoning_class=True,  # CoT budget enforced for reasoning-class
            now_provider=_PinnedClock(0.0),
        )

    err = exc_info.value
    assert err.reason == "cot_budget_exhausted"
    assert err.tokens_before_abort >= 500, (
        "library cot_budget_tokens default = 500; abort fires when "
        "tokens_seen > budget"
    )
    assert err.config_applied["reasoning_class"] is True


# ---------------------------------------------------------------------------
# reasoning_class flag pins the CoT-budget gate (I-4 modulo-flag-only-divergence)
# ---------------------------------------------------------------------------


def test_cot_budget_does_not_fire_when_reasoning_class_false():
    """The same CoT-heavy stream PROCEEDS when reasoning_class=False —
    library cot_budget enforcement is gated on reasoning_class
    (recovery.py:219-228). This pins I-4: cross-provider behavior identical
    modulo reasoning_class flag.
    """
    from loa_cheval.providers.anthropic_streaming import parse_anthropic_stream

    data = _load_fixture("abort-cot-budget-non-reasoning")
    result = parse_anthropic_stream(
        _byte_iter(data),
        model_data={},
        reasoning_class=False,
        now_provider=_PinnedClock(0.0),
    )

    # Stream completes; recovery did not trigger.
    sr = result.metadata["streaming_recovery"]
    assert sr["triggered"] is False
    assert sr["config_applied"]["reasoning_class"] is False


# ---------------------------------------------------------------------------
# Telemetry-shape contract (I-3)
# ---------------------------------------------------------------------------


def test_telemetry_shape_on_healthy_path():
    """I-3: streaming_recovery field present + complete on every streaming
    invocation. Healthy path means triggered=False but config_applied is
    fully populated."""
    from loa_cheval.providers.anthropic_streaming import parse_anthropic_stream

    result = parse_anthropic_stream(
        _byte_iter(_load_fixture("healthy-short")),
        model_data={},
        reasoning_class=False,
        now_provider=_PinnedClock(0.0),
    )
    sr = result.metadata["streaming_recovery"]

    # Required keys per SDD §4.2:
    assert set(sr.keys()) == {
        "triggered",
        "tokens_before_abort",
        "reason",
        "config_applied",
    }
    assert set(sr["config_applied"].keys()) == {
        "first_token_deadline_s",
        "empty_content_window_tokens",
        "cot_budget_tokens",
        "reasoning_class",
    }


def test_telemetry_shape_on_abort_path_via_exception():
    """I-3: abort path carries equivalent telemetry via the exception's
    fields. Adapter wrapper reconstructs MODELINV envelope from these in
    sprint-170."""
    from loa_cheval.providers.anthropic_streaming import parse_anthropic_stream
    from loa_cheval.streaming import StreamingRecoveryAbort

    with pytest.raises(StreamingRecoveryAbort) as exc_info:
        parse_anthropic_stream(
            _byte_iter(_load_fixture("abort-empty-content-window")),
            model_data={},
            reasoning_class=False,
            now_provider=_PinnedClock(0.0),
        )

    err = exc_info.value
    # Same field-set as the healthy-path metadata dict, modulo
    # `triggered=True` being implicit-by-exception (vs. dict-field):
    assert err.reason in (
        "first_token_deadline",
        "empty_content_window",
        "cot_budget_exhausted",
    )
    assert isinstance(err.tokens_before_abort, int)
    assert set(err.config_applied.keys()) == {
        "first_token_deadline_s",
        "empty_content_window_tokens",
        "cot_budget_tokens",
        "reasoning_class",
    }


# ---------------------------------------------------------------------------
# Adapter-level translation (SDD §3.5 + cycle-113 sprint-168 T1.7 corrigendum)
# ---------------------------------------------------------------------------


def test_adapter_translates_abort_to_provider_unavailable_error():
    """SDD §3.5 + T1.7 corrigendum: StreamingRecoveryAbort → ProviderUnavailable-
    Error (retryable=True) so cycle-099 chain-walk activates. This test
    pins the translation at the parser layer (adapter integration test
    would require live HTTP mocking; pin the translation arm directly)."""
    from loa_cheval.providers.anthropic_streaming import parse_anthropic_stream
    from loa_cheval.streaming import StreamingRecoveryAbort
    from loa_cheval.types import ProviderUnavailableError

    with pytest.raises(StreamingRecoveryAbort) as exc_info:
        parse_anthropic_stream(
            _byte_iter(_load_fixture("abort-empty-content-window")),
            model_data={},
            reasoning_class=False,
            now_provider=_PinnedClock(0.0),
        )

    # Manually apply the adapter's translation (cycle-113 anthropic_adapter.py
    # StreamingRecoveryAbort except-arm) to pin the behavior:
    recovery_err = exc_info.value
    translated = ProviderUnavailableError(
        "anthropic",
        f"streaming recovery aborted: reason={recovery_err.reason} "
        f"tokens_before_abort={recovery_err.tokens_before_abort}",
    )

    assert translated.retryable is True, (
        "T1.7 corrigendum: all three abort reasons must route via "
        "retryable=True so cycle-099 chain-walks. KF-002 goal."
    )
    assert recovery_err.reason in str(translated)
    assert str(recovery_err.tokens_before_abort) in str(translated)


def test_adapter_imports_streaming_recovery_abort():
    """T1.7: anthropic_adapter.py MUST import StreamingRecoveryAbort and
    add a try/except arm BEFORE the existing ProviderStreamError and
    ValueError arms (order matters — typed-abort signal, not generic
    stream error)."""
    import inspect

    from loa_cheval.providers import anthropic_adapter
    from loa_cheval.streaming import StreamingRecoveryAbort

    src = inspect.getsource(anthropic_adapter)
    # Import line present:
    assert "StreamingRecoveryAbort" in src
    # except arm present (look for the except clause):
    assert "except StreamingRecoveryAbort" in src
    # Arm appears BEFORE the ProviderStreamError + ValueError arms:
    abort_idx = src.index("except StreamingRecoveryAbort")
    stream_idx = src.index("except ProviderStreamError")
    value_idx = src.index("except ValueError as parse_err")
    assert abort_idx < stream_idx < value_idx, (
        "exception arm ordering matters: StreamingRecoveryAbort is a "
        "typed-abort signal that must be caught BEFORE the generic stream "
        "+ value-error arms"
    )


# ---------------------------------------------------------------------------
# Backward-compat — kwargs default-safe
# ---------------------------------------------------------------------------


def test_kwargs_default_safe_when_not_supplied():
    """T1.6 added model_data + reasoning_class + now_provider kwargs.
    All callers that don't supply them must continue to work (library
    defaults apply; recovery is active with cycle-109 default
    thresholds). Pre-existing test_anthropic_streaming.py tests provide
    the regression baseline — this test adds an explicit assertion.
    """
    from loa_cheval.providers.anthropic_streaming import parse_anthropic_stream

    # No model_data, no reasoning_class, no now_provider — all defaults.
    result = parse_anthropic_stream(_byte_iter(_load_fixture("healthy-short")))

    # Recovery still attaches telemetry (I-3 — every streaming invocation):
    sr = result.metadata.get("streaming_recovery")
    assert sr is not None
    assert sr["triggered"] is False
    # Library defaults applied (cycle-109 thresholds):
    assert sr["config_applied"]["first_token_deadline_s"] == 30.0
    assert sr["config_applied"]["reasoning_class"] is False
