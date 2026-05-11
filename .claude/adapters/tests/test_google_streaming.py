"""Sprint 4A — Google Gemini streaming parser tests (AC-4A.6)."""
from __future__ import annotations

import json
import os
import sys
from typing import Iterator

import pytest

HERE = os.path.dirname(os.path.abspath(__file__))
ADAPTERS_ROOT = os.path.dirname(HERE)
if ADAPTERS_ROOT not in sys.path:
    sys.path.insert(0, ADAPTERS_ROOT)

from loa_cheval.providers.google_streaming import parse_google_stream  # noqa: E402


def _sse_chunk(payload: dict) -> bytes:
    return (f"data: {json.dumps(payload)}\n\n").encode("utf-8")


def _chunkify(blob: bytes, chunk_size: int = 64) -> Iterator[bytes]:
    for i in range(0, len(blob), chunk_size):
        yield blob[i : i + chunk_size]


# --- Canonical text response ---


def test_text_response_assembles_across_fragments():
    """3 streaming fragments → joined content + usage from final fragment."""
    blob = (
        _sse_chunk(
            {
                "candidates": [
                    {
                        "content": {"parts": [{"text": "Hello"}], "role": "model"},
                        "index": 0,
                    }
                ],
                "modelVersion": "gemini-1.5-pro-002",
            }
        )
        + _sse_chunk(
            {
                "candidates": [
                    {
                        "content": {"parts": [{"text": ", world"}], "role": "model"},
                        "index": 0,
                    }
                ],
            }
        )
        + _sse_chunk(
            {
                "candidates": [
                    {
                        "content": {"parts": [], "role": "model"},
                        "index": 0,
                        "finishReason": "STOP",
                    }
                ],
                "usageMetadata": {
                    "promptTokenCount": 10,
                    "candidatesTokenCount": 5,
                    "thoughtsTokenCount": 0,
                    "totalTokenCount": 15,
                },
                "modelVersion": "gemini-1.5-pro-002",
            }
        )
    )

    result = parse_google_stream(iter([blob]), model_id="gemini-1.5-pro")

    assert result.content == "Hello, world"
    assert result.model == "gemini-1.5-pro-002"
    assert result.usage.input_tokens == 10
    assert result.usage.output_tokens == 5
    assert result.usage.source == "actual"
    assert result.metadata["streaming"] is True
    assert result.metadata["finish_reason"] == "STOP"


def test_text_response_survives_arbitrary_chunking():
    """Bytes split mid-event yield correct content."""
    blob = (
        _sse_chunk(
            {
                "candidates": [
                    {"content": {"parts": [{"text": "ABCDEFGHIJ"}], "role": "model"}, "index": 0}
                ],
                "modelVersion": "x",
            }
        )
        + _sse_chunk(
            {
                "candidates": [{"content": {"parts": []}, "finishReason": "STOP"}],
                "usageMetadata": {"promptTokenCount": 1, "candidatesTokenCount": 5},
                "modelVersion": "x",
            }
        )
    )

    result = parse_google_stream(_chunkify(blob, chunk_size=7), model_id="x")

    assert result.content == "ABCDEFGHIJ"


# --- Thinking parts ---


def test_thinking_parts_segregated_from_visible_content():
    """parts with thought:true land in thinking; the rest in content."""
    blob = _sse_chunk(
        {
            "candidates": [
                {
                    "content": {
                        "parts": [
                            {"text": "Let me think...", "thought": True},
                            {"text": "The answer is 42."},
                        ],
                        "role": "model",
                    },
                    "index": 0,
                    "finishReason": "STOP",
                }
            ],
            "usageMetadata": {
                "promptTokenCount": 8,
                "candidatesTokenCount": 4,
                "thoughtsTokenCount": 5,
            },
            "modelVersion": "gemini-3-pro",
        }
    )

    result = parse_google_stream(iter([blob]), model_id="gemini-3-pro")

    assert result.content == "The answer is 42."
    assert result.thinking == "Let me think..."
    assert result.usage.reasoning_tokens == 5


# --- Safety / Recitation blocks ---


def test_safety_block_raises_value_error():
    """finishReason=SAFETY surfaces as ValueError for adapter to translate."""
    blob = _sse_chunk(
        {
            "candidates": [
                {
                    "content": {"parts": []},
                    "finishReason": "SAFETY",
                    "safetyRatings": [
                        {"category": "HARM_CATEGORY_DANGEROUS", "probability": "HIGH"}
                    ],
                }
            ],
        }
    )

    with pytest.raises(ValueError, match="HARM_CATEGORY_DANGEROUS"):
        parse_google_stream(iter([blob]), model_id="gemini-x")


def test_recitation_block_raises_value_error():
    """finishReason=RECITATION → ValueError."""
    blob = _sse_chunk(
        {
            "candidates": [{"content": {"parts": []}, "finishReason": "RECITATION"}],
        }
    )

    with pytest.raises(ValueError, match="recitation"):
        parse_google_stream(iter([blob]), model_id="gemini-x")


# --- Missing usage metadata ---


def test_missing_usage_metadata_falls_back_to_estimate():
    """No usageMetadata in any fragment → estimated tokens from input_text_length."""
    blob = _sse_chunk(
        {
            "candidates": [
                {"content": {"parts": [{"text": "Brief reply"}]}, "finishReason": "STOP"}
            ],
            "modelVersion": "x",
        }
    )

    result = parse_google_stream(
        iter([blob]), model_id="x", input_text_length=350
    )

    assert result.usage.source == "estimated"
    # input_text_length=350 / 3.5 = 100 (heuristic)
    assert result.usage.input_tokens == 100
    # "Brief reply" = 11 chars / 3.5 = 3 (heuristic)
    assert result.usage.output_tokens == 3


def test_max_tokens_finish_reason_does_not_raise():
    """finishReason=MAX_TOKENS logs warning but returns truncated content."""
    blob = _sse_chunk(
        {
            "candidates": [
                {
                    "content": {"parts": [{"text": "incomplete answer"}]},
                    "finishReason": "MAX_TOKENS",
                }
            ],
            "usageMetadata": {"promptTokenCount": 5, "candidatesTokenCount": 64},
            "modelVersion": "x",
        }
    )

    result = parse_google_stream(iter([blob]), model_id="x")

    assert result.content == "incomplete answer"
    assert result.metadata["finish_reason"] == "MAX_TOKENS"


def test_malformed_data_frame_raises_value_error():
    """Sprint 4A cycle-4 (BB F-004): Google parser fail-loud parity with
    Anthropic + OpenAI. Cycle-3 BF-006 fix updated those two parsers but
    missed Google here — the cross-provider inconsistency was caught in
    BB cycle-2 review on PR #844.
    """
    blob = b"data: {not valid json from gemini}\n\n"
    with pytest.raises(ValueError, match="Google streaming malformed data frame"):
        parse_google_stream(iter([blob]), model_id="x")


def test_empty_candidates_list_yields_empty_content():
    """No candidates emitted (server-side issue) → empty content, no crash."""
    blob = _sse_chunk(
        {
            "candidates": [],
            "modelVersion": "x",
            "usageMetadata": {"promptTokenCount": 5, "candidatesTokenCount": 0},
        }
    )

    result = parse_google_stream(iter([blob]), model_id="x")

    assert result.content == ""
    assert result.usage.input_tokens == 5
