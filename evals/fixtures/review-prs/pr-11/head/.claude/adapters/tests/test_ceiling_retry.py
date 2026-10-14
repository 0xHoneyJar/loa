"""cycle-126 Sprint 1 Task 1.2 (PRD FR-1.1, SDD D-1.1b) — the retry layer's
single output-budget shrink on a provider context-limit error: the
`input + max_tokens > limit` shape is retried ONCE at the budget that fits
(never below the 4,096 floor); the input-only shape propagates at once; a
second context error after the shrink propagates (no third attempt). Nothing
here walks a chain — that is cheval's arm, tested end-to-end elsewhere.
"""
from __future__ import annotations

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from loa_cheval.providers import retry as retry_mod  # noqa: E402
from loa_cheval.types import (  # noqa: E402
    CompletionRequest,
    CompletionResult,
    ProviderContextLimitError,
    Usage,
)

CONFIG = {"retry": {"max_retries": 3, "base_delay_seconds": 0}}


class _Adapter:
    provider = "anthropic"
    auth_type = "http_api"

    def __init__(self, errors):
        self.errors = list(errors)
        self.seen = []

    def complete(self, request):
        self.seen.append(request.max_tokens)
        if self.errors:
            raise self.errors.pop(0)
        return CompletionResult(content="ok", model=request.model, provider="anthropic",
                                usage=Usage(input_tokens=1, output_tokens=1), latency_ms=1,
                                tool_calls=None, thinking=None, metadata={"streaming": True})


@pytest.fixture(autouse=True)
def _quiet_breaker(monkeypatch):
    monkeypatch.setattr("loa_cheval.routing.circuit_breaker.check_state", lambda *a, **k: "CLOSED")
    monkeypatch.setattr(retry_mod, "_record_failure", lambda *a, **k: None)
    monkeypatch.setattr(retry_mod, "_record_success", lambda *a, **k: None)
    monkeypatch.setattr(retry_mod.time, "sleep", lambda d: None)


def _req(max_tokens=64_000):
    return CompletionRequest(messages=[{"role": "user", "content": "x"}], model="m", max_tokens=max_tokens)


def _plus_output(input_tokens=190_000, max_tokens=64_000, limit=200_000):
    return ProviderContextLimitError("anthropic", f"HTTP 400 context-limit: input length and max_tokens exceed context limit: "
                                     f"{input_tokens} + {max_tokens} > {limit}", status=400,
                                     input_tokens=input_tokens, max_tokens=max_tokens, limit=limit)


def test_input_plus_output_shape_is_retried_once_at_the_budget_that_fits():
    adapter = _Adapter([_plus_output()])
    result = retry_mod.invoke_with_retry(adapter, _req(), CONFIG)
    assert adapter.seen == [64_000, 10_000], "one retry, at limit − input"
    assert result.metadata["max_tokens_shrunk"] == {"from": 64_000, "to": 10_000, "by": "provider_limit"}


def test_second_context_error_after_the_shrink_propagates_without_a_third_attempt():
    adapter = _Adapter([_plus_output(), _plus_output(input_tokens=195_000, max_tokens=10_000)])
    with pytest.raises(ProviderContextLimitError):
        retry_mod.invoke_with_retry(adapter, _req(), CONFIG)
    assert adapter.seen == [64_000, 10_000]


def test_input_only_shape_propagates_at_once():
    err = ProviderContextLimitError("anthropic", "HTTP 400 context-limit: prompt is too long: 213456 tokens > 200000 maximum",
                                    status=400, input_tokens=213_456, limit=200_000)
    adapter = _Adapter([err])
    with pytest.raises(ProviderContextLimitError) as info:
        retry_mod.invoke_with_retry(adapter, _req(), CONFIG)
    assert adapter.seen == [64_000] and info.value.input_tokens == 213_456 and info.value.code == "CONTEXT_TOO_LARGE"


def test_no_retry_below_the_floor_or_when_the_room_is_not_smaller():
    # room 2,000 < floor → propagate
    adapter = _Adapter([_plus_output(input_tokens=198_000, max_tokens=64_000, limit=200_000)])
    with pytest.raises(ProviderContextLimitError):
        retry_mod.invoke_with_retry(adapter, _req(), CONFIG)
    assert adapter.seen == [64_000]
    # a message whose numbers do not shrink the budget (stale / inconsistent) → propagate, no loop
    adapter = _Adapter([_plus_output(input_tokens=100_000, max_tokens=64_000, limit=200_000)])
    with pytest.raises(ProviderContextLimitError):
        retry_mod.invoke_with_retry(adapter, _req(), CONFIG)
    assert adapter.seen == [64_000]
