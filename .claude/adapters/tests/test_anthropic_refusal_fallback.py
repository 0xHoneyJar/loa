"""issue #1102 — Fable/Anthropic refusal must walk the chain, not silently pass.

A Claude Fable refusal returns HTTP 200 with non-empty prose content and
``stop_reason: "refusal"``. Before this fix nothing raised on that, so the
within-company chain-walk arm (``cheval.py`` ``except _EmptyContentError``)
was never reached and the flatline arbiter applied zero decisions while
reporting success.

These tests pin: (1) the ``_is_refusal`` helper, (2) both adapter paths
(streaming default + non-streaming kill-switch) raising a retryable
``EmptyContentError`` on refusal, (3) a regression guard that non-refusal
stop_reasons do NOT raise, and (4) the chain-walk contract the fix relies on
(the existing ``cheval.py`` arm catches the SAME class and ``continue``s).
"""

from __future__ import annotations

import json
import sys
from contextlib import contextmanager
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from loa_cheval.providers.anthropic_adapter import AnthropicAdapter  # noqa: E402
from loa_cheval.routing import EmptyContentError  # noqa: E402
from loa_cheval.types import (  # noqa: E402
    CompletionRequest,
    ModelConfig,
    ProviderConfig,
)

MODEL = "claude-fable-5"


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


def _make_config() -> ProviderConfig:
    return ProviderConfig(
        name="anthropic",
        type="anthropic",
        endpoint="https://api.anthropic.com/v1",
        auth="sk-ant-test",
        connect_timeout=10.0,
        read_timeout=30.0,
        models={MODEL: ModelConfig(capabilities=["chat"], context_window=200000)},
    )


def _make_request() -> CompletionRequest:
    return CompletionRequest(
        messages=[{"role": "user", "content": "arbiter prompt"}],
        model=MODEL,
        temperature=0.0,
        max_tokens=1024,
    )


def _nonstreaming_response(stop_reason) -> dict:
    """Anthropic non-streaming body: HTTP 200 + prose + stop_reason."""
    return {
        "id": "msg_refusal",
        "model": MODEL,
        "role": "assistant",
        "content": [{"type": "text", "text": "I can't help with that."}],
        "stop_reason": stop_reason,
        "usage": {"input_tokens": 50, "output_tokens": 8},
    }


def _sse_blob(stop_reason: str) -> bytes:
    """A complete Anthropic SSE sequence carrying prose + the given stop_reason."""

    def ev(name: str, data: dict) -> bytes:
        return (f"event: {name}\ndata: {json.dumps(data)}\n\n").encode("utf-8")

    return (
        ev(
            "message_start",
            {
                "type": "message_start",
                "message": {
                    "id": "msg_r",
                    "role": "assistant",
                    "model": MODEL,
                    "content": [],
                    "usage": {"input_tokens": 50, "output_tokens": 1},
                },
            },
        )
        + ev(
            "content_block_start",
            {"type": "content_block_start", "index": 0, "content_block": {"type": "text", "text": ""}},
        )
        + ev(
            "content_block_delta",
            {"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": "I can't help with that."}},
        )
        + ev("content_block_stop", {"type": "content_block_stop", "index": 0})
        + ev(
            "message_delta",
            {"type": "message_delta", "delta": {"stop_reason": stop_reason}, "usage": {"output_tokens": 8}},
        )
        + ev("message_stop", {"type": "message_stop"})
    )


def _mock_stream(blob: bytes):
    resp = MagicMock()
    resp.status_code = 200
    resp.http_version = "HTTP/2"
    resp.iter_bytes = MagicMock(return_value=iter([blob]))

    @contextmanager
    def fake_http_post_stream(*args, **kwargs):
        yield resp

    return fake_http_post_stream


# ---------------------------------------------------------------------------
# _is_refusal pure helper
# ---------------------------------------------------------------------------


def test_is_refusal_true_only_for_refusal():
    from loa_cheval.providers.anthropic_adapter import _is_refusal

    assert _is_refusal({"stop_reason": "refusal"}) is True


@pytest.mark.parametrize(
    "meta",
    [{"stop_reason": "end_turn"}, {"stop_reason": "max_tokens"}, {"stop_reason": "tool_use"}, {"stop_reason": None}, {}, None],
)
def test_is_refusal_false_otherwise(meta):
    from loa_cheval.providers.anthropic_adapter import _is_refusal

    assert _is_refusal(meta) is False


# ---------------------------------------------------------------------------
# Non-streaming path (LOA_CHEVAL_DISABLE_STREAMING=1 kill switch)
# ---------------------------------------------------------------------------


def test_nonstreaming_refusal_raises_empty_content_error(monkeypatch):
    monkeypatch.setenv("LOA_CHEVAL_DISABLE_STREAMING", "1")
    adapter = AnthropicAdapter(_make_config())
    with patch(
        "loa_cheval.providers.anthropic_adapter.http_post",
        return_value=(200, _nonstreaming_response("refusal")),
    ):
        with pytest.raises(EmptyContentError) as exc_info:
            adapter.complete(_make_request())
    err = exc_info.value
    assert err.retryable is True
    assert err.code == "EMPTY_CONTENT"
    assert "stop_reason:refusal" in str(err)
    assert err.context["model_id"] == MODEL


@pytest.mark.parametrize("stop_reason", ["end_turn", "max_tokens", "tool_use", None])
def test_nonstreaming_non_refusal_does_not_raise(monkeypatch, stop_reason):
    monkeypatch.setenv("LOA_CHEVAL_DISABLE_STREAMING", "1")
    adapter = AnthropicAdapter(_make_config())
    with patch(
        "loa_cheval.providers.anthropic_adapter.http_post",
        return_value=(200, _nonstreaming_response(stop_reason)),
    ):
        result = adapter.complete(_make_request())
    assert result.content == "I can't help with that."
    assert result.metadata["streaming"] is False
    if stop_reason is not None:
        assert result.metadata["stop_reason"] == stop_reason


# ---------------------------------------------------------------------------
# Streaming path (default)
# ---------------------------------------------------------------------------


def test_streaming_refusal_raises_empty_content_error(monkeypatch):
    monkeypatch.delenv("LOA_CHEVAL_DISABLE_STREAMING", raising=False)
    adapter = AnthropicAdapter(_make_config())
    with patch(
        "loa_cheval.providers.anthropic_adapter.http_post_stream",
        _mock_stream(_sse_blob("refusal")),
    ):
        with pytest.raises(EmptyContentError) as exc_info:
            adapter.complete(_make_request())
    err = exc_info.value
    assert err.retryable is True
    assert err.code == "EMPTY_CONTENT"
    assert "stop_reason:refusal" in str(err)
    assert err.context["model_id"] == MODEL


def test_streaming_non_refusal_does_not_raise(monkeypatch):
    monkeypatch.delenv("LOA_CHEVAL_DISABLE_STREAMING", raising=False)
    adapter = AnthropicAdapter(_make_config())
    with patch(
        "loa_cheval.providers.anthropic_adapter.http_post_stream",
        _mock_stream(_sse_blob("end_turn")),
    ):
        result = adapter.complete(_make_request())
    assert result.metadata["streaming"] is True
    assert result.metadata["stop_reason"] == "end_turn"
    assert result.content == "I can't help with that."


# ---------------------------------------------------------------------------
# Chain-walk contract — the fix reuses the EXISTING arm, no new wiring
# ---------------------------------------------------------------------------


def test_refusal_error_is_retryable():
    err = EmptyContentError(provider="anthropic", model_id=MODEL, reason="stop_reason:refusal")
    assert err.retryable is True


def test_cheval_wrapper_catches_empty_content_and_continues():
    """Pin the contract the fix depends on: cheval imports the SAME class the
    adapter raises and ``continue``s the chain on it. A refactor that drops the
    arm or changes it to re-raise would silently re-open the silent-pass hole."""
    cheval_src = (ROOT / "cheval.py").read_text(encoding="utf-8")
    assert "EmptyContentError as _EmptyContentError" in cheval_src
    idx = cheval_src.index("except _EmptyContentError")
    # Scan the arm body up to the NEXT except-clause and assert it walks
    # (continues) rather than re-raising/aborting.
    next_except = cheval_src.index("except ", idx + len("except _EmptyContentError"))
    assert "continue" in cheval_src[idx:next_except]


def test_adapter_references_refusal_raise_in_source():
    """Source guard: the refusal trap exists in the adapter (both paths share
    the ``_is_refusal`` helper + the ``stop_reason:refusal`` reason)."""
    import inspect
    from loa_cheval.providers import anthropic_adapter

    src = inspect.getsource(anthropic_adapter)
    assert "_is_refusal" in src
    assert 'reason="stop_reason:refusal"' in src
