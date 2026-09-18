"""cycle-124 Sprint 1 audit (slice A): the non-streaming read timeout follows
the output budget. Under LOA_CHEVAL_DISABLE_STREAMING the default budget is
16K with thinking on; a flat 120 s read timeout turned a long answer into an
httpx.ReadTimeout retried four times, each attempt billed. The timeout is only
ever lengthened (25 tok/s, capped at 600 s) and only above the pre-cycle 4096.
"""

from __future__ import annotations

import sys
from pathlib import Path
from unittest.mock import patch

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from loa_cheval.providers.anthropic_adapter import AnthropicAdapter, _nonstreaming_read_timeout  # noqa: E402
from loa_cheval.types import CompletionRequest, ModelConfig, ProviderConfig  # noqa: E402


@pytest.mark.parametrize("configured, max_tokens, expected", [
    (120.0, 1024, 120.0),      # at or below the pre-cycle default: untouched
    (120.0, 4096, 120.0),
    (120.0, 16000, 600.0),     # 30 + 16000/25 = 670 -> capped at 600
    (120.0, 8000, 350.0),      # 30 + 8000/25
    (900.0, 16000, 900.0),     # never shortened
    (120.0, None, 120.0),      # malformed budget: configured value
    (120.0, "abc", 120.0),
])
def test_nonstreaming_read_timeout_table(configured, max_tokens, expected):
    assert _nonstreaming_read_timeout(configured, max_tokens) == expected


def _config(read_timeout: float = 120.0) -> ProviderConfig:
    return ProviderConfig(
        name="anthropic", type="anthropic", endpoint="https://api.anthropic.com/v1",
        auth="sk-ant-test", connect_timeout=10.0, read_timeout=read_timeout,
        models={"claude-opus-5": ModelConfig(capabilities=["chat"], context_window=1_000_000,
                                              params={"temperature_supported": False, "thinking_adaptive": True})},
    )


@pytest.mark.parametrize("max_tokens, expected", [(16000, 600.0), (1024, 120.0)])
def test_nonstreaming_call_passes_the_budget_aware_timeout(monkeypatch, max_tokens, expected):
    monkeypatch.setenv("LOA_CHEVAL_DISABLE_STREAMING", "1")
    monkeypatch.delenv("LOA_CHEVAL_LEGACY_WIRE", raising=False)
    adapter = AnthropicAdapter(_config())
    seen = {}

    def _fake_post(url, headers, body, connect_timeout, read_timeout):
        seen["read_timeout"] = read_timeout
        return 200, {"id": "m", "model": "claude-opus-5", "content": [{"type": "text", "text": "ok"}],
                     "stop_reason": "end_turn", "usage": {"input_tokens": 1, "output_tokens": 1}}

    with patch("loa_cheval.providers.anthropic_adapter.http_post", side_effect=_fake_post):
        adapter.complete(CompletionRequest(messages=[{"role": "user", "content": "hi"}],
                                           model="claude-opus-5", max_tokens=max_tokens))
    assert seen["read_timeout"] == expected
