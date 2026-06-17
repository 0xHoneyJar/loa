"""Cycle-114 FR-12 — cache-token telemetry in the Anthropic streaming parser.

Surfacing only: assert the parser captures cache_read_input_tokens /
cache_creation_input_tokens onto Usage, and defaults to 0 when absent (NFR-2).
No network; SSE events constructed in-process.
"""
from __future__ import annotations

import json
import os
import sys
from typing import Iterator

HERE = os.path.dirname(os.path.abspath(__file__))
ADAPTERS_ROOT = os.path.dirname(HERE)
if ADAPTERS_ROOT not in sys.path:
    sys.path.insert(0, ADAPTERS_ROOT)

from loa_cheval.providers.anthropic_streaming import parse_anthropic_stream  # noqa: E402


def _sse_event(event_name: str, data: dict) -> bytes:
    return (f"event: {event_name}\ndata: {json.dumps(data)}\n\n").encode("utf-8")


def _chunkify(blob: bytes, chunk_size: int = 64) -> Iterator[bytes]:
    for i in range(0, len(blob), chunk_size):
        yield blob[i : i + chunk_size]


def _stream(usage_start: dict) -> bytes:
    return (
        _sse_event("message_start", {"type": "message_start", "message": {
            "id": "m", "role": "assistant", "model": "claude-opus-4-8",
            "content": [], "usage": usage_start}})
        + _sse_event("content_block_start", {"type": "content_block_start", "index": 0,
            "content_block": {"type": "text", "text": ""}})
        + _sse_event("content_block_delta", {"type": "content_block_delta", "index": 0,
            "delta": {"type": "text_delta", "text": "hi"}})
        + _sse_event("content_block_stop", {"type": "content_block_stop", "index": 0})
        + _sse_event("message_delta", {"type": "message_delta",
            "delta": {"stop_reason": "end_turn"}, "usage": {"output_tokens": 7}})
        + _sse_event("message_stop", {"type": "message_stop"})
    )


def test_cache_tokens_parsed_from_message_start():
    blob = _stream({"input_tokens": 42, "output_tokens": 1,
                    "cache_read_input_tokens": 1000, "cache_creation_input_tokens": 200})
    result = parse_anthropic_stream(_chunkify(blob))
    assert result.usage.cache_read_input_tokens == 1000
    assert result.usage.cache_creation_input_tokens == 200
    # existing fields unaffected
    assert result.usage.input_tokens == 42
    assert result.usage.output_tokens == 7


def test_cache_tokens_default_zero_when_absent():
    blob = _stream({"input_tokens": 42, "output_tokens": 1})
    result = parse_anthropic_stream(_chunkify(blob))
    assert result.usage.cache_read_input_tokens == 0
    assert result.usage.cache_creation_input_tokens == 0
