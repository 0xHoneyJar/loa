"""Sprint 4A — Anthropic streaming parser tests (AC-4A.4 + AC-4A.6).

Tests `parse_anthropic_stream()` against canonical SSE event sequences.
No network calls; all events are constructed in-process from fixture bytes.
"""
from __future__ import annotations

import json
import os
import sys
from typing import Iterator, List

import pytest

HERE = os.path.dirname(os.path.abspath(__file__))
ADAPTERS_ROOT = os.path.dirname(HERE)
if ADAPTERS_ROOT not in sys.path:
    sys.path.insert(0, ADAPTERS_ROOT)

from loa_cheval.providers.anthropic_streaming import (  # noqa: E402
    parse_anthropic_stream,
    _iter_sse_events,
    _parse_sse_event,
)


# --- Helpers ---


def _sse_event(event_name: str, data: dict) -> bytes:
    """Build an SSE event in Anthropic's wire format."""
    return (f"event: {event_name}\ndata: {json.dumps(data)}\n\n").encode("utf-8")


def _chunkify(blob: bytes, chunk_size: int = 64) -> Iterator[bytes]:
    """Split a blob into small chunks to exercise the buffering path."""
    for i in range(0, len(blob), chunk_size):
        yield blob[i : i + chunk_size]


# --- Canonical: text response ---


def test_text_response_assembles_content():
    """Single text block with two delta chunks → content joined correctly."""
    blob = (
        _sse_event(
            "message_start",
            {
                "type": "message_start",
                "message": {
                    "id": "msg_01",
                    "role": "assistant",
                    "model": "claude-opus-4-7",
                    "content": [],
                    "usage": {"input_tokens": 42, "output_tokens": 1},
                },
            },
        )
        + _sse_event(
            "content_block_start",
            {"type": "content_block_start", "index": 0, "content_block": {"type": "text", "text": ""}},
        )
        + _sse_event(
            "content_block_delta",
            {"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": "Hello"}},
        )
        + _sse_event(
            "content_block_delta",
            {"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": ", world"}},
        )
        + _sse_event("content_block_stop", {"type": "content_block_stop", "index": 0})
        + _sse_event(
            "message_delta",
            {"type": "message_delta", "delta": {"stop_reason": "end_turn"}, "usage": {"output_tokens": 12}},
        )
        + _sse_event("message_stop", {"type": "message_stop"})
    )

    result = parse_anthropic_stream(iter([blob]))

    assert result.content == "Hello, world"
    assert result.thinking is None
    assert result.tool_calls is None
    assert result.model == "claude-opus-4-7"
    assert result.usage.input_tokens == 42
    assert result.usage.output_tokens == 12
    assert result.usage.source == "actual"
    assert result.metadata["streaming"] is True
    assert result.metadata["stop_reason"] == "end_turn"


def test_text_response_survives_arbitrary_chunking():
    """Bytes split mid-event still produce correct content (buffering test)."""
    blob = (
        _sse_event(
            "message_start",
            {"type": "message_start", "message": {"model": "x", "usage": {"input_tokens": 1, "output_tokens": 1}}},
        )
        + _sse_event(
            "content_block_start",
            {"type": "content_block_start", "index": 0, "content_block": {"type": "text", "text": ""}},
        )
        + _sse_event(
            "content_block_delta",
            {"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": "ABCDEFGHIJ"}},
        )
        + _sse_event(
            "message_delta",
            {"type": "message_delta", "delta": {"stop_reason": "end_turn"}, "usage": {"output_tokens": 5}},
        )
        + _sse_event("message_stop", {"type": "message_stop"})
    )

    # Chunk into 7-byte pieces to ensure split mid-event.
    result = parse_anthropic_stream(_chunkify(blob, chunk_size=7))

    assert result.content == "ABCDEFGHIJ"


def test_text_response_survives_utf8_multibyte_at_chunk_boundary():
    """Multi-byte UTF-8 codepoints split across chunks decode correctly.

    `\\n\\n` (0x0A 0x0A) cannot appear mid-codepoint in UTF-8, so the
    event-boundary split is always safe. This pins that invariant.
    """
    emoji_text = "Result: 🌟⭐✨"  # 3 multi-byte emoji
    blob = (
        _sse_event(
            "message_start",
            {"type": "message_start", "message": {"model": "x", "usage": {"input_tokens": 1, "output_tokens": 1}}},
        )
        + _sse_event(
            "content_block_start",
            {"type": "content_block_start", "index": 0, "content_block": {"type": "text", "text": ""}},
        )
        + _sse_event(
            "content_block_delta",
            {"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": emoji_text}},
        )
        + _sse_event("message_stop", {"type": "message_stop"})
    )

    # Chunk in 3-byte pieces to maximize mid-codepoint splits.
    result = parse_anthropic_stream(_chunkify(blob, chunk_size=3))

    assert result.content == emoji_text


# --- Canonical: thinking response ---


def test_thinking_block_assembles_thinking_field():
    """Extended-thinking blocks accumulate into CompletionResult.thinking."""
    blob = (
        _sse_event(
            "message_start",
            {"type": "message_start", "message": {"model": "claude-opus-4-7", "usage": {"input_tokens": 100, "output_tokens": 1}}},
        )
        + _sse_event(
            "content_block_start",
            {"type": "content_block_start", "index": 0, "content_block": {"type": "thinking", "thinking": ""}},
        )
        + _sse_event(
            "content_block_delta",
            {"type": "content_block_delta", "index": 0, "delta": {"type": "thinking_delta", "thinking": "Let me consider..."}},
        )
        + _sse_event(
            "content_block_delta",
            {"type": "content_block_delta", "index": 0, "delta": {"type": "thinking_delta", "thinking": " yes, that's right."}},
        )
        + _sse_event("content_block_stop", {"type": "content_block_stop", "index": 0})
        + _sse_event(
            "content_block_start",
            {"type": "content_block_start", "index": 1, "content_block": {"type": "text", "text": ""}},
        )
        + _sse_event(
            "content_block_delta",
            {"type": "content_block_delta", "index": 1, "delta": {"type": "text_delta", "text": "The answer is 42."}},
        )
        + _sse_event("message_stop", {"type": "message_stop"})
    )

    result = parse_anthropic_stream(iter([blob]))

    assert result.thinking == "Let me consider... yes, that's right."
    assert result.content == "The answer is 42."


# --- Canonical: tool-use response (AC-4A.4) ---


def test_tool_use_block_reconstructs_arguments_json():
    """input_json_delta chunks assemble into canonical tool_call.arguments string."""
    blob = (
        _sse_event(
            "message_start",
            {"type": "message_start", "message": {"model": "x", "usage": {"input_tokens": 10, "output_tokens": 1}}},
        )
        + _sse_event(
            "content_block_start",
            {
                "type": "content_block_start",
                "index": 0,
                "content_block": {"type": "tool_use", "id": "toolu_01", "name": "get_weather", "input": {}},
            },
        )
        + _sse_event(
            "content_block_delta",
            {
                "type": "content_block_delta",
                "index": 0,
                "delta": {"type": "input_json_delta", "partial_json": '{"location":'},
            },
        )
        + _sse_event(
            "content_block_delta",
            {
                "type": "content_block_delta",
                "index": 0,
                "delta": {"type": "input_json_delta", "partial_json": ' "NYC"}'},
            },
        )
        + _sse_event("content_block_stop", {"type": "content_block_stop", "index": 0})
        + _sse_event("message_stop", {"type": "message_stop"})
    )

    result = parse_anthropic_stream(iter([blob]))

    assert result.tool_calls is not None
    assert len(result.tool_calls) == 1
    tool = result.tool_calls[0]
    assert tool["type"] == "function"
    assert tool["id"] == "toolu_01"
    assert tool["function"]["name"] == "get_weather"
    # Arguments string is JSON-parseable
    parsed = json.loads(tool["function"]["arguments"])
    assert parsed == {"location": "NYC"}
    # Text content is empty (only tool_use block present)
    assert result.content == ""


def test_tool_use_with_no_arguments_emits_empty_json_object():
    """Tool call with no input_json_delta events → arguments default to '{}'."""
    blob = (
        _sse_event(
            "message_start",
            {"type": "message_start", "message": {"model": "x", "usage": {"input_tokens": 5, "output_tokens": 1}}},
        )
        + _sse_event(
            "content_block_start",
            {
                "type": "content_block_start",
                "index": 0,
                "content_block": {"type": "tool_use", "id": "toolu_02", "name": "noargs_tool", "input": {}},
            },
        )
        + _sse_event("content_block_stop", {"type": "content_block_stop", "index": 0})
        + _sse_event("message_stop", {"type": "message_stop"})
    )

    result = parse_anthropic_stream(iter([blob]))

    assert result.tool_calls[0]["function"]["arguments"] == "{}"


# --- Error handling ---


def test_error_event_raises_value_error():
    """Anthropic mid-stream `error` event surfaces as ValueError."""
    blob = (
        _sse_event(
            "message_start",
            {"type": "message_start", "message": {"model": "x", "usage": {"input_tokens": 1, "output_tokens": 1}}},
        )
        + _sse_event(
            "error",
            {"type": "error", "error": {"type": "overloaded_error", "message": "Anthropic is overloaded"}},
        )
    )

    with pytest.raises(ValueError, match="overloaded_error"):
        parse_anthropic_stream(iter([blob]))


def test_ping_events_are_ignored():
    """Heartbeat `ping` events do not contaminate the output."""
    blob = (
        _sse_event(
            "message_start",
            {"type": "message_start", "message": {"model": "x", "usage": {"input_tokens": 1, "output_tokens": 1}}},
        )
        + b"event: ping\ndata: {\"type\":\"ping\"}\n\n"
        + _sse_event(
            "content_block_start",
            {"type": "content_block_start", "index": 0, "content_block": {"type": "text", "text": ""}},
        )
        + b"event: ping\ndata: {\"type\":\"ping\"}\n\n"
        + _sse_event(
            "content_block_delta",
            {"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": "OK"}},
        )
        + _sse_event("message_stop", {"type": "message_stop"})
    )

    result = parse_anthropic_stream(iter([blob]))

    assert result.content == "OK"


def test_malformed_json_in_data_yields_none_payload_does_not_crash():
    """Malformed `data:` JSON → log + skip; subsequent valid events still parse."""
    blob = (
        b"event: message_start\ndata: {not json\n\n"
        + _sse_event(
            "content_block_start",
            {"type": "content_block_start", "index": 0, "content_block": {"type": "text", "text": ""}},
        )
        + _sse_event(
            "content_block_delta",
            {"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": "recovered"}},
        )
        + _sse_event("message_stop", {"type": "message_stop"})
    )

    result = parse_anthropic_stream(iter([blob]))

    # Malformed event skipped; text still recovers.
    assert result.content == "recovered"


# --- SSE parser unit tests ---


def test_sse_parser_handles_crlf_separator():
    """Some SSE servers use \\r\\n\\r\\n instead of \\n\\n."""
    blob = (
        b"event: message_start\r\ndata: {\"type\":\"message_start\",\"message\":{\"model\":\"x\",\"usage\":{\"input_tokens\":1,\"output_tokens\":1}}}\r\n\r\n"
        b"event: content_block_start\r\ndata: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}\r\n\r\n"
        b"event: content_block_delta\r\ndata: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"CRLF\"}}\r\n\r\n"
        b"event: message_stop\r\ndata: {\"type\":\"message_stop\"}\r\n\r\n"
    )

    result = parse_anthropic_stream(iter([blob]))

    assert result.content == "CRLF"


def test_sse_parser_ignores_comment_lines():
    """Lines starting with `:` are SSE comments / keep-alives — must be ignored."""
    event_name, payload = _parse_sse_event(
        b": keep-alive\nevent: message_start\ndata: {\"type\":\"message_start\"}\n"
    )
    assert event_name == "message_start"
    assert payload == {"type": "message_start"}
