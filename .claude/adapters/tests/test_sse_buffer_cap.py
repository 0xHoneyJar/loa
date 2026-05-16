"""cycle-103 sprint-3 T3.5 — SSE buffer + per-event accumulator caps.

Pins AC-3.5: SSE iterators raise `ProviderStreamError("transient", ...)`
when buffer exceeds MAX_SSE_BUFFER_BYTES (4 MiB) without an event
terminator. Per-event accumulators (text_parts / arguments_parts) raise
the same when cumulative bytes exceed MAX_TEXT_PART_BYTES (1 MiB) or
MAX_ARGS_PART_BYTES (256 KiB). Adapter layer dispatches via
`dispatch_provider_stream_error` to typed exception (transient →
ConnectionLostError).
"""

from __future__ import annotations

import sys
from pathlib import Path
from typing import Iterator

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from loa_cheval.providers.anthropic_streaming import (  # noqa: E402
    _iter_sse_events,
    parse_anthropic_stream,
)
from loa_cheval.providers.openai_streaming import (  # noqa: E402
    _iter_sse_events_raw_data,
    parse_openai_chat_stream,
)
from loa_cheval.providers.streaming_caps import (  # noqa: E402
    MAX_ARGS_PART_BYTES,
    MAX_SSE_BUFFER_BYTES,
    MAX_TEXT_PART_BYTES,
    accumulate_capped,
    check_buffer_cap,
)
from loa_cheval.types import (  # noqa: E402
    ConnectionLostError,
    ProviderStreamError,
    dispatch_provider_stream_error,
)


def _iter_bytes(chunks: list) -> Iterator[bytes]:
    """Iterator stub matching httpx.Response.iter_bytes()."""
    for c in chunks:
        yield c


# ---------------------------------------------------------------------------
# check_buffer_cap — unit
# ---------------------------------------------------------------------------


class TestCheckBufferCap:
    def test_under_cap_no_raise(self) -> None:
        check_buffer_cap(MAX_SSE_BUFFER_BYTES - 1)
        check_buffer_cap(MAX_SSE_BUFFER_BYTES)  # boundary exact = allowed

    def test_over_cap_raises_transient(self) -> None:
        with pytest.raises(ProviderStreamError) as excinfo:
            check_buffer_cap(MAX_SSE_BUFFER_BYTES + 1)
        assert excinfo.value.category == "transient"
        assert "SSE buffer exceeded" in excinfo.value.message_detail


# ---------------------------------------------------------------------------
# accumulate_capped — unit
# ---------------------------------------------------------------------------


class TestAccumulateCapped:
    def test_appends_under_cap(self) -> None:
        parts: list = []
        accumulate_capped(parts, "hello", cap=1024, kind="text")
        assert parts == ["hello"]

    def test_raises_over_cap(self) -> None:
        parts: list = []
        # Each delta is 500 bytes; the third trips the 1024-byte cap.
        accumulate_capped(parts, "a" * 500, cap=1024, kind="text")
        accumulate_capped(parts, "b" * 500, cap=1024, kind="text")
        with pytest.raises(ProviderStreamError) as excinfo:
            accumulate_capped(parts, "c" * 500, cap=1024, kind="text")
        assert excinfo.value.category == "transient"
        assert "Per-event accumulator 'text'" in excinfo.value.message_detail

    def test_empty_delta_is_noop_for_bytes(self) -> None:
        parts: list = []
        for _ in range(10):
            accumulate_capped(parts, "", cap=10, kind="text")
        assert len(parts) == 10
        assert sum(len(p) for p in parts) == 0

    def test_kind_in_error_message(self) -> None:
        parts: list = []
        with pytest.raises(ProviderStreamError) as excinfo:
            accumulate_capped(parts, "x" * 100, cap=10, kind="arguments")
        assert "'arguments'" in excinfo.value.message_detail


# ---------------------------------------------------------------------------
# _iter_sse_events (Anthropic) — buffer cap
# ---------------------------------------------------------------------------


class TestAnthropicBufferCap:
    def test_under_cap_completes(self) -> None:
        payload = b'event: ping\ndata: {"type":"ping"}\n\n'
        events = list(_iter_sse_events(_iter_bytes([payload])))
        assert len(events) == 1

    def test_buffer_cap_exceeded_raises(self) -> None:
        # One chunk of 5 MB with NO event terminator → buffer cap trips
        # before any event is yielded.
        big_chunk = b"x" * (MAX_SSE_BUFFER_BYTES + 1024)
        with pytest.raises(ProviderStreamError) as excinfo:
            list(_iter_sse_events(_iter_bytes([big_chunk])))
        assert excinfo.value.category == "transient"

    def test_buffer_cap_via_dispatch_becomes_connection_lost(self) -> None:
        # Pin the adapter-side dispatch behavior. The retry layer only
        # understands typed exceptions; this proves the cap-raised
        # ProviderStreamError translates correctly.
        big_chunk = b"x" * (MAX_SSE_BUFFER_BYTES + 1024)
        with pytest.raises(ConnectionLostError):
            try:
                list(_iter_sse_events(_iter_bytes([big_chunk])))
            except ProviderStreamError as stream_err:
                raise dispatch_provider_stream_error(
                    stream_err, provider="anthropic"
                ) from stream_err


# ---------------------------------------------------------------------------
# _iter_sse_events_raw_data (OpenAI) — buffer cap
# ---------------------------------------------------------------------------


class TestOpenAIBufferCap:
    def test_under_cap_completes(self) -> None:
        payload = b'event: response.created\ndata: {"type":"response.created"}\n\n'
        events = list(_iter_sse_events_raw_data(_iter_bytes([payload])))
        assert len(events) == 1

    def test_buffer_cap_exceeded_raises(self) -> None:
        big_chunk = b"y" * (MAX_SSE_BUFFER_BYTES + 1024)
        with pytest.raises(ProviderStreamError) as excinfo:
            list(_iter_sse_events_raw_data(_iter_bytes([big_chunk])))
        assert excinfo.value.category == "transient"


# ---------------------------------------------------------------------------
# Per-event accumulator caps — end-to-end via parser
# ---------------------------------------------------------------------------


class TestAnthropicTextPartCap:
    def _build_oversized_text_stream(self, total_bytes: int) -> list:
        """Build an SSE stream that accumulates `total_bytes` of text in
        deltas under one content_block."""
        chunks: list = []
        chunks.append(
            b'event: message_start\n'
            b'data: {"type":"message_start","message":'
            b'{"id":"x","role":"assistant","model":"claude-opus-4.7",'
            b'"content":[],"usage":{"input_tokens":1,"output_tokens":1}}}\n\n'
        )
        chunks.append(
            b'event: content_block_start\n'
            b'data: {"type":"content_block_start","index":0,'
            b'"content_block":{"type":"text","text":""}}\n\n'
        )
        # Each delta is 64KB; emit total_bytes/64KB of them.
        delta_size = 64 * 1024
        num_deltas = (total_bytes // delta_size) + 1
        payload = "x" * delta_size
        for _ in range(num_deltas):
            chunks.append(
                f'event: content_block_delta\n'
                f'data: {{"type":"content_block_delta","index":0,'
                f'"delta":{{"type":"text_delta","text":"{payload}"}}}}\n\n'
                .encode("utf-8")
            )
        return chunks

    def test_text_part_cap_trips(self) -> None:
        # Build a stream that would accumulate > MAX_TEXT_PART_BYTES.
        chunks = self._build_oversized_text_stream(MAX_TEXT_PART_BYTES + 256 * 1024)
        with pytest.raises(ProviderStreamError) as excinfo:
            parse_anthropic_stream(_iter_bytes(chunks))
        assert excinfo.value.category == "transient"
        assert "'text'" in excinfo.value.message_detail

    def test_text_part_under_cap_succeeds(self) -> None:
        # Build a stream well under the cap.
        chunks = self._build_oversized_text_stream(128 * 1024)
        result = parse_anthropic_stream(_iter_bytes(chunks))
        assert len(result.content) >= 128 * 1024


class TestAnthropicArgsCap:
    def _build_oversized_args_stream(self, total_bytes: int) -> list:
        chunks: list = []
        chunks.append(
            b'event: message_start\n'
            b'data: {"type":"message_start","message":'
            b'{"id":"x","role":"assistant","model":"claude-opus-4.7",'
            b'"content":[],"usage":{"input_tokens":1,"output_tokens":1}}}\n\n'
        )
        chunks.append(
            b'event: content_block_start\n'
            b'data: {"type":"content_block_start","index":0,'
            b'"content_block":{"type":"tool_use","id":"tool_x","name":"f"}}\n\n'
        )
        delta_size = 16 * 1024
        num_deltas = (total_bytes // delta_size) + 1
        payload = "x" * delta_size
        for _ in range(num_deltas):
            chunks.append(
                f'event: content_block_delta\n'
                f'data: {{"type":"content_block_delta","index":0,'
                f'"delta":{{"type":"input_json_delta",'
                f'"partial_json":"{payload}"}}}}\n\n'
                .encode("utf-8")
            )
        return chunks

    def test_args_cap_trips(self) -> None:
        chunks = self._build_oversized_args_stream(MAX_ARGS_PART_BYTES + 64 * 1024)
        with pytest.raises(ProviderStreamError) as excinfo:
            parse_anthropic_stream(_iter_bytes(chunks))
        assert excinfo.value.category == "transient"
        assert "'arguments'" in excinfo.value.message_detail


class TestOpenAITextPartCap:
    def _build_oversized_chat_stream(self, total_bytes: int) -> list:
        chunks: list = []
        delta_size = 64 * 1024
        num_deltas = (total_bytes // delta_size) + 1
        payload = "x" * delta_size
        for _ in range(num_deltas):
            chunks.append(
                f'data: {{"id":"x","choices":[{{"index":0,'
                f'"delta":{{"content":"{payload}"}},"finish_reason":null}}]}}\n\n'
                .encode("utf-8")
            )
        chunks.append(b"data: [DONE]\n\n")
        return chunks

    def test_text_part_cap_trips(self) -> None:
        chunks = self._build_oversized_chat_stream(MAX_TEXT_PART_BYTES + 256 * 1024)
        with pytest.raises(ProviderStreamError) as excinfo:
            parse_openai_chat_stream(_iter_bytes(chunks))
        assert excinfo.value.category == "transient"
        assert "'text'" in excinfo.value.message_detail


# ---------------------------------------------------------------------------
# Boundary / regression — caps don't break normal-sized streams
# ---------------------------------------------------------------------------


class TestNormalStreamsUnaffected:
    def test_short_anthropic_stream(self) -> None:
        chunks = [
            b'event: message_start\n'
            b'data: {"type":"message_start","message":'
            b'{"id":"x","role":"assistant","model":"claude-opus-4.7",'
            b'"content":[],"usage":{"input_tokens":5,"output_tokens":1}}}\n\n',
            b'event: content_block_start\n'
            b'data: {"type":"content_block_start","index":0,'
            b'"content_block":{"type":"text","text":""}}\n\n',
            b'event: content_block_delta\n'
            b'data: {"type":"content_block_delta","index":0,'
            b'"delta":{"type":"text_delta","text":"Hello, world."}}\n\n',
            b'event: content_block_stop\n'
            b'data: {"type":"content_block_stop","index":0}\n\n',
            b'event: message_delta\n'
            b'data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},'
            b'"usage":{"output_tokens":3}}\n\n',
            b'event: message_stop\n'
            b'data: {"type":"message_stop"}\n\n',
        ]
        result = parse_anthropic_stream(_iter_bytes(chunks))
        assert result.content == "Hello, world."
        assert result.usage.output_tokens == 3

    def test_short_openai_chat_stream(self) -> None:
        chunks = [
            b'data: {"id":"x","model":"gpt-5.3","choices":[{"index":0,'
            b'"delta":{"content":"Hi"},"finish_reason":null}]}\n\n',
            b'data: {"id":"x","choices":[{"index":0,'
            b'"delta":{"content":" there"},"finish_reason":"stop"}]}\n\n',
            b"data: [DONE]\n\n",
        ]
        result = parse_openai_chat_stream(_iter_bytes(chunks))
        assert result.content == "Hi there"


# ---------------------------------------------------------------------------
# Constants — pin values from sprint.md L222
# ---------------------------------------------------------------------------


class TestCapConstants:
    def test_sse_buffer_cap_value(self) -> None:
        assert MAX_SSE_BUFFER_BYTES == 4 * 1024 * 1024

    def test_text_part_cap_value(self) -> None:
        assert MAX_TEXT_PART_BYTES == 1 * 1024 * 1024

    def test_args_part_cap_value(self) -> None:
        assert MAX_ARGS_PART_BYTES == 256 * 1024
