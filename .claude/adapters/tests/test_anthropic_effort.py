"""cycle-114 FR-2 — `effort` → `output_config.effort` on the Anthropic adapter.

The adapter must serialize CompletionRequest.effort as
`body["output_config"]["effort"]` and MUST NEVER emit a `thinking` block
(Opus 4.7/4.8 reject manual `thinking.budget_tokens` with HTTP 400). When
effort is unset the body must be byte-identical to the pre-cycle-114 shape.

Body construction happens in `complete()` before the streaming/non-streaming
dispatch, so we intercept `_complete_nonstreaming` (forced via the kill switch)
to capture the exact body the adapter built.
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from loa_cheval.providers.anthropic_adapter import AnthropicAdapter  # noqa: E402
from loa_cheval.types import (  # noqa: E402
    CompletionRequest,
    InvalidInputError,
    ModelConfig,
    ProviderConfig,
)


def _make_config() -> ProviderConfig:
    return ProviderConfig(
        name="anthropic",
        type="anthropic",
        endpoint="https://api.anthropic.com/v1",
        auth="sk-ant-test",
        connect_timeout=10.0,
        read_timeout=30.0,
        models={
            "claude-opus-4-8": ModelConfig(
                capabilities=["chat"],
                context_window=200000,
                params={"temperature_supported": False},
            ),
        },
    )


def _capture_body(monkeypatch, request: CompletionRequest) -> dict:
    """Force the non-streaming path and capture the body `complete()` builds."""
    monkeypatch.setenv("LOA_CHEVAL_DISABLE_STREAMING", "1")
    adapter = AnthropicAdapter(_make_config())
    captured: dict = {}

    def _fake_ns(url, headers, body):
        captured["body"] = body
        return "sentinel-result"

    monkeypatch.setattr(adapter, "_complete_nonstreaming", _fake_ns)
    adapter.complete(request)
    return captured["body"]


def _req(**kw) -> CompletionRequest:
    base = dict(
        messages=[{"role": "user", "content": "hi"}],
        model="claude-opus-4-8",
        max_tokens=1024,
    )
    base.update(kw)
    return CompletionRequest(**base)


def test_effort_xhigh_sets_output_config_and_no_thinking(monkeypatch):
    body = _capture_body(monkeypatch, _req(effort="xhigh"))
    assert body["output_config"]["effort"] == "xhigh"
    # NFR-4: never emit a thinking block for effort (400 on 4.7/4.8).
    assert "thinking" not in body


def test_effort_unset_omits_output_config(monkeypatch):
    body = _capture_body(monkeypatch, _req())
    assert "output_config" not in body
    assert "thinking" not in body


def test_effort_from_metadata_when_field_absent(monkeypatch):
    body = _capture_body(monkeypatch, _req(metadata={"effort": "low"}))
    assert body["output_config"]["effort"] == "low"


def test_effort_field_takes_precedence_over_metadata(monkeypatch):
    body = _capture_body(monkeypatch, _req(effort="max", metadata={"effort": "low"}))
    assert body["output_config"]["effort"] == "max"


@pytest.mark.parametrize("level", ["low", "medium", "high", "xhigh", "max"])
def test_all_valid_effort_levels_accepted(monkeypatch, level):
    body = _capture_body(monkeypatch, _req(effort=level))
    assert body["output_config"]["effort"] == level


def test_invalid_effort_raises_invalid_input(monkeypatch):
    monkeypatch.setenv("LOA_CHEVAL_DISABLE_STREAMING", "1")
    adapter = AnthropicAdapter(_make_config())
    with pytest.raises(InvalidInputError):
        adapter.complete(_req(effort="turbo"))
