"""cycle-126 Sprint 1 Task 1.3 (PRD FR-1.4, SDD D-1.4) — `count_tokens` asks
`POST /v1/messages/count_tokens` with exactly the prompt the request would
send (system split, tools, beta flags) and falls back to None on anything
that is not a positive integer answer.
"""
from __future__ import annotations

import sys
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from loa_cheval.providers import anthropic_adapter as aa  # noqa: E402
from loa_cheval.types import CompletionRequest, ModelConfig, ProviderConfig  # noqa: E402


def _adapter(params=None, auth="sk-ant-test"):
    cfg = ProviderConfig(name="anthropic", type="anthropic", endpoint="https://api.example.invalid/v1", auth=auth,
                         models={"m": ModelConfig(capabilities=["chat", "tools"], context_window=200_000, params=params or {})})
    return aa.AnthropicAdapter(cfg)


REQ = CompletionRequest(messages=[{"role": "system", "content": "be terse"}, {"role": "user", "content": "hi"}], model="m",
                        tools=[{"type": "function", "function": {"name": "t", "description": "d", "parameters": {"type": "object"}}}])


def test_count_tokens_sends_the_request_shape_and_returns_the_count():
    seen = {}

    def fake_post(url, headers, body, **kw):
        seen.update(url=url, headers=headers, body=body)
        return 200, {"input_tokens": 1234}

    with patch.object(aa, "http_post", fake_post):
        assert _adapter(params={"beta_headers": ["context-1m-2025-08-07"]}).count_tokens(REQ) == 1234
    assert seen["url"] == "https://api.example.invalid/v1/messages/count_tokens"
    assert seen["body"]["model"] == "m" and seen["body"]["system"] == "be terse"
    assert seen["body"]["messages"] == [{"role": "user", "content": "hi"}]
    assert seen["body"]["tools"][0]["name"] == "t" and "max_tokens" not in seen["body"]
    assert seen["headers"]["anthropic-beta"] == "context-1m-2025-08-07" and seen["headers"]["x-api-key"] == "sk-ant-test"


def test_count_tokens_falls_back_to_none():
    with patch.object(aa, "http_post", lambda *a, **k: (400, {"error": {"message": "nope"}})):
        assert _adapter().count_tokens(REQ) is None
    with patch.object(aa, "http_post", lambda *a, **k: (200, {"input_tokens": "1234"})):
        assert _adapter().count_tokens(REQ) is None
    with patch.object(aa, "http_post", lambda *a, **k: (200, {"input_tokens": 0})):
        assert _adapter().count_tokens(REQ) is None

    def boom(*a, **k):
        raise OSError("connection reset")

    with patch.object(aa, "http_post", boom):
        assert _adapter().count_tokens(REQ) is None
    # no credential → no call, None (the heuristic stays; nothing is logged with a value)
    posted = []
    with patch.object(aa, "http_post", lambda *a, **k: posted.append(a) or (200, {"input_tokens": 5})):
        assert _adapter(auth=None).count_tokens(REQ) is None
    assert posted == []
