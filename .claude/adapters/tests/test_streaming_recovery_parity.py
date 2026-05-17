"""cycle-113 Sprint 2 T2.8 — cross-provider parity (FR-B-4 / NFR-Parity-1).

For each of the 6 SDD §6.1 scenarios, all four provider parsers
(Anthropic, OpenAI Chat, OpenAI Responses, Google) MUST reach the same
recovery decision: triggered/not-triggered AND identical reason.

The test is HERMETIC — uses deterministic fixtures emitted by
``tests/fixtures/cycle-113/streaming-parity/generate.py`` (T1.4/T1.5).
No live API calls, no wall-clock dependency (injected ``now_provider``
for deadline scenarios).

Token-count tolerance: ``tokens_before_abort`` may vary by ±2 across
providers because of SSE event-boundary noise (one provider batches
text in larger chunks than another). The token count expectation in
this test allows for that tolerance per SDD §6.2.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

REPO_ROOT = Path(__file__).resolve().parents[3]
FIXTURES_DIR = REPO_ROOT / "tests" / "fixtures" / "cycle-113" / "streaming-parity"


SCENARIO_NAMES = [
    "healthy-short",
    "healthy-cot-then-answer",
    "abort-first-token-deadline",
    "abort-empty-content-window",
    "abort-cot-budget-exhausted",
    "abort-cot-budget-non-reasoning",
]

PROVIDERS = ("anthropic", "openai-chat", "openai-responses", "google")


def _load_expected(name: str) -> dict:
    return json.loads((FIXTURES_DIR / f"{name}.expected.json").read_text())


def _load_fixture(name: str, provider_slug: str) -> bytes:
    return (FIXTURES_DIR / f"{name}.{provider_slug}.sse").read_bytes()


class _FakeClock:
    """Fast-forwarding clock for deadline scenarios."""

    def __init__(self, step_s: float = 100.0) -> None:
        self._t = 0.0
        self._step = step_s

    def __call__(self) -> float:
        self._t += self._step
        return self._t


class _PinnedClock:
    """Frozen clock for non-deadline scenarios."""

    def __init__(self, t: float = 0.0) -> None:
        self._t = t

    def __call__(self) -> float:
        return self._t


def _parse_one(provider_slug: str, byte_data: bytes, *,
               reasoning_class: bool, now_provider) -> dict:
    """Dispatch to the right parser per provider slug; return a
    decision dict mirroring StreamingRecoveryAbort.{reason, tokens} or
    {triggered: False, ...} on healthy."""
    from loa_cheval.streaming import StreamingRecoveryAbort

    byte_iter = iter([byte_data])

    if provider_slug == "anthropic":
        from loa_cheval.providers.anthropic_streaming import parse_anthropic_stream
        parser = parse_anthropic_stream
    elif provider_slug == "openai-chat":
        from loa_cheval.providers.openai_streaming import parse_openai_chat_stream
        parser = parse_openai_chat_stream
    elif provider_slug == "openai-responses":
        from loa_cheval.providers.openai_streaming import parse_openai_responses_stream
        parser = parse_openai_responses_stream
    elif provider_slug == "google":
        from loa_cheval.providers.google_streaming import parse_google_stream
        parser = parse_google_stream
    else:
        raise ValueError(f"unknown provider: {provider_slug}")

    try:
        result = parser(
            byte_iter,
            model_data={},
            reasoning_class=reasoning_class,
            now_provider=now_provider,
        )
        return {
            "triggered": False,
            "reason": None,
            "tokens_before_abort": None,
        }
    except StreamingRecoveryAbort as e:
        return {
            "triggered": True,
            "reason": e.reason,
            "tokens_before_abort": e.tokens_before_abort,
        }


@pytest.mark.parametrize("scenario_name", SCENARIO_NAMES)
def test_recovery_decision_matches_expected_across_all_providers(scenario_name):
    """For each scenario, all 4 providers MUST agree with the
    ``expected.json`` decision (triggered + reason). Token-count
    tolerance is ±2 per NFR-Parity-1."""
    expected = _load_expected(scenario_name)
    reasoning_class = bool(expected["reasoning_class"])
    expected_decision = expected["expected"]

    # Choose clock based on scenario: deadline scenarios need fast-forward,
    # all others need pinned-zero (so deadline doesn't accidentally fire).
    if scenario_name == "abort-first-token-deadline":
        clock_factory = lambda: _FakeClock(step_s=100.0)
    else:
        clock_factory = lambda: _PinnedClock(0.0)

    decisions = {}
    for provider in PROVIDERS:
        byte_data = _load_fixture(scenario_name, provider)
        decisions[provider] = _parse_one(
            provider, byte_data,
            reasoning_class=reasoning_class,
            now_provider=clock_factory(),
        )

    # triggered: all-or-nothing across providers (FR-B-4)
    triggered_values = {p: d["triggered"] for p, d in decisions.items()}
    assert len(set(triggered_values.values())) == 1, (
        f"scenario {scenario_name!r}: triggered values diverge: {triggered_values}"
    )

    # Verdict matches expected
    sample = next(iter(decisions.values()))
    assert sample["triggered"] == expected_decision["triggered"], (
        f"scenario {scenario_name!r}: triggered={sample['triggered']} "
        f"but expected.json says {expected_decision['triggered']}"
    )

    if not sample["triggered"]:
        # Healthy path — done.
        return

    # Abort path: all providers MUST agree on reason
    reasons = {p: d["reason"] for p, d in decisions.items()}
    assert len(set(reasons.values())) == 1, (
        f"scenario {scenario_name!r}: reasons diverge: {reasons}"
    )

    # Reason matches expected
    sample_reason = next(iter(reasons.values()))
    assert sample_reason == expected_decision["reason"], (
        f"scenario {scenario_name!r}: reason={sample_reason!r} "
        f"but expected.json says {expected_decision['reason']!r}"
    )

    # Token-count parity within ±2 of expected (NFR-Parity-1 tolerance)
    expected_tokens = expected_decision["tokens_before_abort"]
    if expected_tokens is not None:
        for provider, d in decisions.items():
            actual_tokens = d["tokens_before_abort"]
            assert actual_tokens is not None, (
                f"scenario {scenario_name!r}: {provider} aborted but "
                f"tokens_before_abort is None"
            )
            assert abs(actual_tokens - expected_tokens) <= 2, (
                f"scenario {scenario_name!r}: {provider} tokens="
                f"{actual_tokens} drift from expected {expected_tokens} > 2"
            )


def test_all_four_providers_imported_and_callable():
    """Sanity: confirm all 4 parsers are importable from their canonical
    locations. Catches refactor / rename breakages early."""
    from loa_cheval.providers.anthropic_streaming import parse_anthropic_stream
    from loa_cheval.providers.openai_streaming import (
        parse_openai_chat_stream,
        parse_openai_responses_stream,
    )
    from loa_cheval.providers.google_streaming import parse_google_stream

    assert callable(parse_anthropic_stream)
    assert callable(parse_openai_chat_stream)
    assert callable(parse_openai_responses_stream)
    assert callable(parse_google_stream)
