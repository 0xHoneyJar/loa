"""Sprint 4A — OpenAI streaming parser tests (AC-4A.4 + AC-4A.6).

Covers both endpoint families:
  - /v1/chat/completions — classic SSE chunks ending in `data: [DONE]`
  - /v1/responses — typed event stream
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

from loa_cheval.providers.openai_streaming import (  # noqa: E402
    parse_openai_chat_stream,
    parse_openai_responses_stream,
)


# --- Helpers ---


def _chat_chunk(payload: dict) -> bytes:
    return (f"data: {json.dumps(payload)}\n\n").encode("utf-8")


def _chat_done() -> bytes:
    return b"data: [DONE]\n\n"


def _responses_event(event_name: str, payload: dict) -> bytes:
    return (f"event: {event_name}\ndata: {json.dumps(payload)}\n\n").encode("utf-8")


def _chunkify(blob: bytes, chunk_size: int = 64) -> Iterator[bytes]:
    for i in range(0, len(blob), chunk_size):
        yield blob[i : i + chunk_size]


# --- /v1/chat/completions ---


class TestChatCompletionsStreaming:
    def test_text_response_assembles_content(self):
        """3-chunk text streaming with final usage chunk and [DONE]."""
        blob = (
            _chat_chunk(
                {
                    "id": "chatcmpl_01",
                    "model": "gpt-4o-mini",
                    "choices": [{"index": 0, "delta": {"role": "assistant"}, "finish_reason": None}],
                }
            )
            + _chat_chunk(
                {
                    "model": "gpt-4o-mini",
                    "choices": [{"index": 0, "delta": {"content": "Hello"}, "finish_reason": None}],
                }
            )
            + _chat_chunk(
                {
                    "model": "gpt-4o-mini",
                    "choices": [{"index": 0, "delta": {"content": ", world"}, "finish_reason": None}],
                }
            )
            + _chat_chunk(
                {
                    "model": "gpt-4o-mini",
                    "choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}],
                }
            )
            + _chat_chunk(
                {
                    "model": "gpt-4o-mini",
                    "choices": [],
                    "usage": {
                        "prompt_tokens": 12,
                        "completion_tokens": 3,
                        "completion_tokens_details": {"reasoning_tokens": 0},
                    },
                }
            )
            + _chat_done()
        )

        result = parse_openai_chat_stream(iter([blob]))

        assert result.content == "Hello, world"
        assert result.usage.input_tokens == 12
        assert result.usage.output_tokens == 3
        assert result.model == "gpt-4o-mini"
        assert result.metadata["streaming"] is True
        assert result.metadata["finish_reason"] == "stop"

    def test_text_response_survives_chunking_at_arbitrary_boundaries(self):
        """Chunks split mid-event still produce correct content."""
        blob = (
            _chat_chunk(
                {
                    "model": "gpt-4o-mini",
                    "choices": [{"index": 0, "delta": {"content": "ABCDEFGHIJ"}, "finish_reason": None}],
                }
            )
            + _chat_chunk(
                {
                    "model": "gpt-4o-mini",
                    "choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}],
                }
            )
            + _chat_done()
        )

        result = parse_openai_chat_stream(_chunkify(blob, chunk_size=11))

        assert result.content == "ABCDEFGHIJ"

    def test_tool_call_arguments_assemble_across_deltas(self):
        """tool_calls[0].function.arguments split across 3 deltas → joined string."""
        blob = (
            _chat_chunk(
                {
                    "model": "gpt-4o-mini",
                    "choices": [
                        {
                            "index": 0,
                            "delta": {
                                "tool_calls": [
                                    {
                                        "index": 0,
                                        "id": "call_abc123",
                                        "type": "function",
                                        "function": {"name": "get_weather", "arguments": ""},
                                    }
                                ]
                            },
                            "finish_reason": None,
                        }
                    ],
                }
            )
            + _chat_chunk(
                {
                    "model": "gpt-4o-mini",
                    "choices": [
                        {
                            "index": 0,
                            "delta": {
                                "tool_calls": [
                                    {
                                        "index": 0,
                                        "function": {"arguments": '{"location":'},
                                    }
                                ]
                            },
                        }
                    ],
                }
            )
            + _chat_chunk(
                {
                    "model": "gpt-4o-mini",
                    "choices": [
                        {
                            "index": 0,
                            "delta": {
                                "tool_calls": [
                                    {
                                        "index": 0,
                                        "function": {"arguments": ' "NYC"}'},
                                    }
                                ]
                            },
                            "finish_reason": "tool_calls",
                        }
                    ],
                }
            )
            + _chat_done()
        )

        result = parse_openai_chat_stream(iter([blob]))

        assert result.tool_calls is not None
        assert len(result.tool_calls) == 1
        tool = result.tool_calls[0]
        assert tool["id"] == "call_abc123"
        assert tool["function"]["name"] == "get_weather"
        assert json.loads(tool["function"]["arguments"]) == {"location": "NYC"}

    def test_parallel_tool_calls_indexed_separately(self):
        """Two parallel tool calls (different indices) assemble independently."""
        blob = (
            _chat_chunk(
                {
                    "model": "gpt-4o-mini",
                    "choices": [
                        {
                            "index": 0,
                            "delta": {
                                "tool_calls": [
                                    {
                                        "index": 0,
                                        "id": "call_0",
                                        "type": "function",
                                        "function": {"name": "tool_a", "arguments": "{}"},
                                    },
                                    {
                                        "index": 1,
                                        "id": "call_1",
                                        "type": "function",
                                        "function": {"name": "tool_b", "arguments": "{}"},
                                    },
                                ]
                            },
                            "finish_reason": "tool_calls",
                        }
                    ],
                }
            )
            + _chat_done()
        )

        result = parse_openai_chat_stream(iter([blob]))

        assert result.tool_calls is not None
        assert len(result.tool_calls) == 2
        assert {t["function"]["name"] for t in result.tool_calls} == {"tool_a", "tool_b"}

    def test_done_terminator_handled_gracefully(self):
        """`data: [DONE]` is the SSE terminator — must not crash JSON parsing."""
        blob = (
            _chat_chunk(
                {
                    "model": "gpt-4o-mini",
                    "choices": [{"index": 0, "delta": {"content": "ok"}, "finish_reason": "stop"}],
                }
            )
            + _chat_done()
        )

        result = parse_openai_chat_stream(iter([blob]))

        assert result.content == "ok"

    def test_top_level_error_frame_raises_value_error(self):
        """Sprint 4A cycle-3 (BF-002): `{"error":{...}}` top-level frame
        without `choices` array must raise — not silently return empty
        CompletionResult. The cycle-102 ghost ('empty content as successful')
        cannot be allowed to manifest in the streaming substrate.
        """
        blob = (
            _chat_chunk(
                {
                    "error": {
                        "type": "invalid_request_error",
                        "code": "context_length_exceeded",
                        "message": "This model's maximum context length is 128000 tokens.",
                    }
                }
            )
            + _chat_done()
        )

        with pytest.raises(ValueError, match="OpenAI streaming error frame"):
            parse_openai_chat_stream(iter([blob]))

    def test_malformed_data_frame_raises_value_error(self):
        """Sprint 4A cycle-3 (BF-006): malformed JSON in a data frame must
        raise rather than silently skip. Mirrors anthropic_streaming change.
        """
        blob = b"data: {not valid json\n\n" + _chat_done()
        with pytest.raises(ValueError, match="malformed data frame"):
            parse_openai_chat_stream(iter([blob]))


# --- /v1/responses ---


class TestResponsesStreaming:
    def test_text_response_assembles_content(self):
        """Typed-event stream: response.created → message item → text deltas → completed."""
        blob = (
            _responses_event(
                "response.created",
                {
                    "type": "response.created",
                    "response": {"id": "resp_01", "model": "gpt-5.5-pro"},
                },
            )
            + _responses_event(
                "response.output_item.added",
                {
                    "type": "response.output_item.added",
                    "output_index": 0,
                    "item": {"id": "msg_001", "type": "message", "role": "assistant"},
                },
            )
            + _responses_event(
                "response.output_text.delta",
                {
                    "type": "response.output_text.delta",
                    "item_id": "msg_001",
                    "delta": "Hello",
                },
            )
            + _responses_event(
                "response.output_text.delta",
                {
                    "type": "response.output_text.delta",
                    "item_id": "msg_001",
                    "delta": ", world",
                },
            )
            + _responses_event(
                "response.completed",
                {
                    "type": "response.completed",
                    "response": {
                        "model": "gpt-5.5-pro",
                        "usage": {
                            "input_tokens": 20,
                            "output_tokens": 5,
                            "output_tokens_details": {"reasoning_tokens": 0},
                        },
                    },
                },
            )
        )

        result = parse_openai_responses_stream(iter([blob]))

        assert result.content == "Hello, world"
        assert result.model == "gpt-5.5-pro"
        assert result.usage.input_tokens == 20
        assert result.usage.output_tokens == 5
        assert result.metadata["streaming"] is True

    def test_function_call_arguments_assemble(self):
        """function_call_arguments.delta chunks → tool_call.function.arguments string."""
        blob = (
            _responses_event(
                "response.created",
                {"type": "response.created", "response": {"id": "resp_02", "model": "gpt-5.5-pro"}},
            )
            + _responses_event(
                "response.output_item.added",
                {
                    "type": "response.output_item.added",
                    "output_index": 0,
                    "item": {
                        "id": "fc_001",
                        "type": "function_call",
                        "call_id": "call_xyz",
                        "name": "get_weather",
                    },
                },
            )
            + _responses_event(
                "response.function_call_arguments.delta",
                {
                    "type": "response.function_call_arguments.delta",
                    "item_id": "fc_001",
                    "delta": '{"location":',
                },
            )
            + _responses_event(
                "response.function_call_arguments.delta",
                {
                    "type": "response.function_call_arguments.delta",
                    "item_id": "fc_001",
                    "delta": ' "SF"}',
                },
            )
            + _responses_event(
                "response.completed",
                {
                    "type": "response.completed",
                    "response": {
                        "model": "gpt-5.5-pro",
                        "usage": {"input_tokens": 15, "output_tokens": 8},
                    },
                },
            )
        )

        result = parse_openai_responses_stream(iter([blob]))

        assert result.tool_calls is not None
        assert len(result.tool_calls) == 1
        tool = result.tool_calls[0]
        assert tool["id"] == "call_xyz"
        assert tool["function"]["name"] == "get_weather"
        assert json.loads(tool["function"]["arguments"]) == {"location": "SF"}

    def test_reasoning_summary_carried_in_thinking(self):
        """response.reasoning_summary_text.delta → CompletionResult.thinking."""
        blob = (
            _responses_event(
                "response.created",
                {"type": "response.created", "response": {"id": "resp_03", "model": "gpt-5.5-pro"}},
            )
            + _responses_event(
                "response.output_item.added",
                {
                    "type": "response.output_item.added",
                    "output_index": 0,
                    "item": {"id": "rsn_001", "type": "reasoning"},
                },
            )
            + _responses_event(
                "response.reasoning_summary_text.delta",
                {
                    "type": "response.reasoning_summary_text.delta",
                    "item_id": "rsn_001",
                    "delta": "Considering the question...",
                },
            )
            + _responses_event(
                "response.output_item.added",
                {
                    "type": "response.output_item.added",
                    "output_index": 1,
                    "item": {"id": "msg_002", "type": "message"},
                },
            )
            + _responses_event(
                "response.output_text.delta",
                {
                    "type": "response.output_text.delta",
                    "item_id": "msg_002",
                    "delta": "The answer.",
                },
            )
            + _responses_event(
                "response.completed",
                {
                    "type": "response.completed",
                    "response": {
                        "model": "gpt-5.5-pro",
                        "usage": {
                            "input_tokens": 40,
                            "output_tokens": 15,
                            "output_tokens_details": {"reasoning_tokens": 10},
                        },
                    },
                },
            )
        )

        result = parse_openai_responses_stream(iter([blob]))

        assert result.thinking == "Considering the question..."
        assert result.content == "The answer."
        assert result.usage.reasoning_tokens == 10

    def test_refusal_sets_metadata_flag_and_replaces_content(self):
        """response.refusal.delta → metadata.refused=True; content is the refusal."""
        blob = (
            _responses_event(
                "response.created",
                {"type": "response.created", "response": {"id": "resp_04", "model": "gpt-5.5-pro"}},
            )
            + _responses_event(
                "response.output_item.added",
                {
                    "type": "response.output_item.added",
                    "output_index": 0,
                    "item": {"id": "msg_003", "type": "message"},
                },
            )
            + _responses_event(
                "response.refusal.delta",
                {
                    "type": "response.refusal.delta",
                    "item_id": "msg_003",
                    "delta": "I can't help with that.",
                },
            )
            + _responses_event(
                "response.completed",
                {
                    "type": "response.completed",
                    "response": {
                        "model": "gpt-5.5-pro",
                        "usage": {"input_tokens": 10, "output_tokens": 5},
                    },
                },
            )
        )

        result = parse_openai_responses_stream(iter([blob]))

        assert result.metadata.get("refused") is True
        assert result.content == "I can't help with that."

    def test_truncation_sets_metadata(self):
        """incomplete_details.reason → metadata.truncated=True."""
        blob = (
            _responses_event(
                "response.created",
                {"type": "response.created", "response": {"id": "resp_05", "model": "gpt-5.5-pro"}},
            )
            + _responses_event(
                "response.output_item.added",
                {
                    "type": "response.output_item.added",
                    "output_index": 0,
                    "item": {"id": "msg_004", "type": "message"},
                },
            )
            + _responses_event(
                "response.output_text.delta",
                {
                    "type": "response.output_text.delta",
                    "item_id": "msg_004",
                    "delta": "partial...",
                },
            )
            + _responses_event(
                "response.completed",
                {
                    "type": "response.completed",
                    "response": {
                        "model": "gpt-5.5-pro",
                        "incomplete_details": {"reason": "max_output_tokens"},
                        "usage": {"input_tokens": 10, "output_tokens": 8},
                    },
                },
            )
        )

        result = parse_openai_responses_stream(iter([blob]))

        assert result.metadata.get("truncated") is True
        assert result.metadata.get("truncation_reason") == "max_output_tokens"
        assert result.content == "partial..."

    def test_failed_event_raises_value_error(self):
        """response.failed surfaces as ValueError."""
        blob = (
            _responses_event(
                "response.created",
                {"type": "response.created", "response": {"id": "resp_06"}},
            )
            + _responses_event(
                "response.failed",
                {
                    "type": "response.failed",
                    "response": {
                        "error": {"code": "server_error", "message": "transient backend failure"}
                    },
                },
            )
        )

        with pytest.raises(ValueError, match="server_error"):
            parse_openai_responses_stream(iter([blob]))
