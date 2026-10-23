"""cycle-129 FR-7 (SDD D-7.3; sprint-257 Task 3.2, AC-3.2) — thinking traces from local
reasoning models on the OpenAI paths.

* Streamed `delta.reasoning_content` deltas count as progress for the recovery tracker
  (they satisfy the first-token deadline) and never reach `content`; they land in
  `thinking`.
* Leading `<think>…</think>` blocks and an unterminated leading `<think>` are stripped
  from the content before qualification on the streaming and the non-streaming path;
  `thinking_stripped` is recorded in the result metadata (cheval copies it to MODELINV).
* The model's `streaming_recovery` block reaches the stream parser.
"""

from __future__ import annotations

import json
import sys
from contextlib import contextmanager
from pathlib import Path
from typing import Any, Dict, Iterator, List

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from loa_cheval.providers import openai_adapter as oa  # noqa: E402
from loa_cheval.providers.openai_adapter import OpenAIAdapter  # noqa: E402
from loa_cheval.providers.openai_streaming import parse_openai_chat_stream, strip_thinking_blocks  # noqa: E402
from loa_cheval.streaming import StreamingRecoveryAbort  # noqa: E402
from loa_cheval.types import CompletionRequest, ModelConfig, ProviderConfig  # noqa: E402


def _sse(*payloads: Dict[str, Any]) -> List[bytes]:
    return [f"data: {json.dumps(p)}\n\n".encode() for p in payloads] + [b"data: [DONE]\n\n"]


def _delta(**delta: Any) -> Dict[str, Any]:
    return {"choices": [{"delta": delta, "finish_reason": None}], "model": "m"}


class _Clock:
    """Advances `step` seconds on every read — each SSE event costs `step` seconds."""

    def __init__(self, step: float):
        self.t = 0.0
        self.step = step

    def __call__(self) -> float:
        self.t += self.step
        return self.t


SLOW = {"streaming_recovery": {"first_token_deadline_s": 5}}


def test_reasoning_deltas_keep_the_tracker_alive_and_never_reach_content():
    chunks = _sse(
        _delta(reasoning_content="Let me look at the diff. "),
        _delta(reasoning_content="The loop is off by one. "),
        _delta(reasoning_content="So the finding is the bound."),
        _delta(content='{"findings": []}'),
        {"choices": [{"delta": {}, "finish_reason": "stop"}], "model": "m"},
    )
    # every event costs 3 s against a 5 s first-token deadline: content arrives at ~15 s
    result = parse_openai_chat_stream(iter(chunks), provider="local", model_data=SLOW, now_provider=_Clock(3.0))
    assert result.content == '{"findings": []}'
    assert "off by one" in (result.thinking or "")
    assert "Let me look" not in result.content
    assert result.metadata["thinking_stripped"] is True
    assert result.metadata["streaming_recovery"]["config_applied"]["first_token_deadline_s"] == 5.0


def test_control_without_reasoning_progress_the_deadline_fires():
    chunks = _sse(
        {"choices": [], "model": "m"},     # keep-alive-shaped frames: no content, no reasoning
        {"choices": [], "model": "m"},
        {"choices": [], "model": "m"},
        _delta(content='{"findings": []}'),
    )
    with pytest.raises(StreamingRecoveryAbort) as info:
        parse_openai_chat_stream(iter(chunks), provider="local", model_data=SLOW, now_provider=_Clock(3.0))
    assert info.value.reason == "first_token_deadline"


def test_reasoning_alias_key_and_no_empty_content_abort():
    # 300 reasoning deltas exceed the 200-token empty-content window if they were fed as content
    many = [_delta(reasoning="step ") for _ in range(300)]
    chunks = _sse(*many, _delta(content="answer"))
    result = parse_openai_chat_stream(iter(chunks), provider="local", now_provider=_Clock(0.001))
    assert result.content == "answer"
    assert result.thinking.startswith("step step")


@pytest.mark.parametrize("raw, content, removed, stripped", [
    ("<think>plan</think>\n{\"a\": 1}", '{"a": 1}', "plan", True),
    ("  <THINK>one</THINK><think>two</think> answer", "answer", "one\ntwo", True),
    ("<think>never closed, the budget ran out", "", "never closed, the budget ran out", True),
    ('{"note": "the template uses <think> tags"}', '{"note": "the template uses <think> tags"}', "", False),
    ("answer first <think>late</think>", "answer first <think>late</think>", "", False),
    ("", "", "", False),
], ids=["block", "two-blocks-case", "unterminated", "inside-answer-kept", "not-leading-kept", "empty"])
def test_strip_thinking_blocks(raw, content, removed, stripped):
    assert strip_thinking_blocks(raw) == (content, removed, stripped)


def test_think_block_stripped_on_the_streaming_path():
    chunks = _sse(_delta(content="<think>reasoning "), _delta(content="here</think>\n"),
                  _delta(content='{"findings": [1]}'))
    result = parse_openai_chat_stream(iter(chunks), provider="local", now_provider=_Clock(0.01))
    assert result.content == '{"findings": [1]}'
    assert result.thinking == "reasoning here"
    assert result.metadata["thinking_stripped"] is True


def test_hosted_shaped_stream_records_thinking_stripped_false():
    chunks = _sse(_delta(content='{"findings": []}'))
    result = parse_openai_chat_stream(iter(chunks), provider="openai", now_provider=_Clock(0.01))
    assert result.content == '{"findings": []}'
    assert result.thinking is None
    assert result.metadata["thinking_stripped"] is False


# --- through the adapter -----------------------------------------------------------------------------------


def _adapter(**model_kwargs: Any) -> OpenAIAdapter:
    return OpenAIAdapter(ProviderConfig(
        name="local", type="openai_compat", endpoint="http://127.0.0.1:8000/v1", auth="", keyless=True,
        allow_insecure_endpoint="127.0.0.1",
        models={"m": ModelConfig(capabilities=["chat"], context_window=32768, endpoint_family="chat",
                                 dispatch_group="local", **model_kwargs)},
    ))


def _req() -> CompletionRequest:
    return CompletionRequest(messages=[{"role": "user", "content": "review"}], model="m", max_tokens=64)


@pytest.mark.parametrize("message, thinking", [
    ({"content": "<think>weighing it</think>{\"findings\": []}"}, "weighing it"),
    ({"content": "{\"findings\": []}", "reasoning_content": "weighing it"}, "weighing it"),
], ids=["inline-think", "reasoning_content"])
def test_non_streaming_path_strips_and_records(monkeypatch, message, thinking):
    monkeypatch.setenv("LOA_CHEVAL_DISABLE_STREAMING", "1")
    monkeypatch.setattr(oa, "http_post", lambda *a, **k: (200, {"choices": [{"message": message}], "model": "m",
                                                               "usage": {"prompt_tokens": 1, "completion_tokens": 1}}))
    result = _adapter().complete(_req())
    assert result.content == '{"findings": []}'
    assert result.thinking == thinking
    assert result.metadata["thinking_stripped"] is True


def test_adapter_passes_the_models_streaming_recovery_block(monkeypatch):
    monkeypatch.delenv("LOA_CHEVAL_DISABLE_STREAMING", raising=False)
    seen: Dict[str, Any] = {}
    real = oa.parse_openai_chat_stream

    def spy(byte_iter: Iterator[bytes], **kwargs: Any):
        seen.update(kwargs)
        return real(byte_iter, **kwargs)

    class _Resp:
        status_code = 200

        def iter_bytes(self):
            return iter(_sse(_delta(reasoning_content="hm"), _delta(content="ok")))

    @contextmanager
    def fake_stream(*a: Any, **k: Any):
        yield _Resp()

    monkeypatch.setattr(oa, "parse_openai_chat_stream", spy)
    monkeypatch.setattr(oa, "http_post_stream", fake_stream)
    result = _adapter(streaming_recovery={"first_token_deadline_s": 120}).complete(_req())
    assert seen["model_data"] == {"streaming_recovery": {"first_token_deadline_s": 120}}
    assert result.content == "ok" and result.metadata["thinking_stripped"] is True
