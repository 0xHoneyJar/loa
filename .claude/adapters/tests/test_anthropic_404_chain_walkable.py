"""cycle-124 Sprint 1 Task 1.3 (FR-3 / SDD §2.1) — HTTP 404 is chain-walkable.

A newly named primary id (`claude-opus-5`, `claude-fable-5-1`) that an
account does not serve yet returns HTTP 404 `not_found_error`. Before this
cycle every non-billing 4xx raised the TERMINAL InvalidInputError, so the
first use of a new id failed instead of falling to the 4.8 / 5 hop. 404 now
raises ProviderUnavailableError (retryable) on both transports; every other
non-billing 4xx stays terminal.
"""

from __future__ import annotations

import json
import sys
from contextlib import contextmanager
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from loa_cheval.providers.anthropic_adapter import AnthropicAdapter  # noqa: E402
from loa_cheval.types import (  # noqa: E402
    CompletionRequest,
    InvalidInputError,
    ModelConfig,
    ProviderConfig,
    ProviderUnavailableError,
)

MODEL = "claude-opus-5"


def _make_config() -> ProviderConfig:
    return ProviderConfig(
        name="anthropic",
        type="anthropic",
        endpoint="https://api.anthropic.com/v1",
        auth="sk-ant-test",
        connect_timeout=10.0,
        read_timeout=30.0,
        models={MODEL: ModelConfig(capabilities=["chat"], context_window=1_000_000)},
    )


def _make_request() -> CompletionRequest:
    return CompletionRequest(
        messages=[{"role": "user", "content": "probe"}],
        model=MODEL,
        temperature=0.0,
        max_tokens=64,
    )


def _error_body(err_type: str, message: str) -> dict:
    return {"type": "error", "error": {"type": err_type, "message": message}}


def _mock_error_stream(status: int, body: dict):
    resp = MagicMock()
    resp.status_code = status
    resp.http_version = "HTTP/2"
    resp.iter_bytes = MagicMock(return_value=iter([json.dumps(body).encode("utf-8")]))

    @contextmanager
    def fake_http_post_stream(*args, **kwargs):
        yield resp

    return fake_http_post_stream


NOT_FOUND = _error_body("not_found_error", f"model: {MODEL}")
BAD_PARAM = _error_body("invalid_request_error", "temperature: Extra inputs are not permitted")


def test_nonstreaming_404_walks_the_chain(monkeypatch):
    monkeypatch.setenv("LOA_CHEVAL_DISABLE_STREAMING", "1")
    adapter = AnthropicAdapter(_make_config())
    with patch("loa_cheval.providers.anthropic_adapter.http_post", return_value=(404, NOT_FOUND)):
        with pytest.raises(ProviderUnavailableError) as exc_info:
            adapter.complete(_make_request())
    err = exc_info.value
    assert err.retryable is True
    assert "404" in str(err)


def test_streaming_404_walks_the_chain(monkeypatch):
    monkeypatch.delenv("LOA_CHEVAL_DISABLE_STREAMING", raising=False)
    adapter = AnthropicAdapter(_make_config())
    with patch(
        "loa_cheval.providers.anthropic_adapter.http_post_stream",
        _mock_error_stream(404, NOT_FOUND),
    ):
        with pytest.raises(ProviderUnavailableError) as exc_info:
            adapter.complete(_make_request())
    assert exc_info.value.retryable is True
    assert "404" in str(exc_info.value)


@pytest.mark.parametrize("streaming", [False, True])
def test_other_4xx_stays_terminal(monkeypatch, streaming):
    """Only 404 changed: a parameter 400 is still InvalidInputError (no walk)."""
    if streaming:
        monkeypatch.delenv("LOA_CHEVAL_DISABLE_STREAMING", raising=False)
        seam = patch(
            "loa_cheval.providers.anthropic_adapter.http_post_stream",
            _mock_error_stream(400, BAD_PARAM),
        )
    else:
        monkeypatch.setenv("LOA_CHEVAL_DISABLE_STREAMING", "1")
        seam = patch("loa_cheval.providers.anthropic_adapter.http_post", return_value=(400, BAD_PARAM))
    adapter = AnthropicAdapter(_make_config())
    with seam:
        with pytest.raises(InvalidInputError) as exc_info:
            adapter.complete(_make_request())
    assert exc_info.value.retryable is False
