"""Google Gemini streaming-response parser — Sprint 4A (cycle-102, AC-4.5e).

Consumes a byte-iterator from `base.http_post_stream` and reconstructs the
canonical `CompletionResult` from Gemini's `:streamGenerateContent?alt=sse`
SSE event stream.

Event shape: each `data:` line contains a JSON
`GenerateContentResponse` fragment. The full response is the
left-fold of all fragments. Final fragment carries `finishReason` and
populated `usageMetadata`.

Chunk shape (one per `data:` line):

    {"candidates":[{"content":{"parts":[{"text":"Hello"}],"role":"model"},
                   "index":0,"finishReason":null}],
     "modelVersion":"gemini-1.5-pro-002","usageMetadata":{...}}

Final chunk (after stream end):

    {"candidates":[{"content":{"parts":[]},"index":0,"finishReason":"STOP"}],
     "usageMetadata":{"promptTokenCount":N,"candidatesTokenCount":M,
                      "thoughtsTokenCount":K,"totalTokenCount":N+M+K},
     "modelVersion":"gemini-1.5-pro-002"}

Thinking parts are tagged `thought: true` on the part object — mirrors
the non-streaming parser's behavior in `google_adapter._parse_response`.

Safety / Recitation blocks: a fragment with `finishReason: "SAFETY"` or
`"RECITATION"` raises ValueError so the adapter can translate to
InvalidInputError (parity with non-streaming behavior).
"""
from __future__ import annotations

import json
import logging
from typing import Any, Dict, Iterator, List, Optional

from loa_cheval.providers.openai_streaming import _iter_sse_events_raw_data
from loa_cheval.types import CompletionResult, Usage

logger = logging.getLogger("loa_cheval.providers.google_streaming")


def parse_google_stream(
    byte_iter: Iterator[bytes],
    *,
    model_id: str = "unknown",
    provider: str = "google",
    input_text_length: int = 0,
) -> CompletionResult:
    """Reconstruct a CompletionResult from a Gemini `:streamGenerateContent?alt=sse`
    SSE event stream.

    `input_text_length` is used as a fallback token estimate when the
    final fragment omits `usageMetadata` — matches the conservative
    estimation path in `_parse_response`.
    """
    text_parts: List[str] = []
    thinking_parts: List[str] = []
    finish_reason: Optional[str] = None
    final_model: Optional[str] = None
    usage_meta: Optional[Dict[str, Any]] = None
    safety_ratings: Optional[list] = None

    for _event_name, payload_str in _iter_sse_events_raw_data(byte_iter):
        if payload_str is None or payload_str == "[DONE]":
            continue
        try:
            data = json.loads(payload_str)
        except json.JSONDecodeError:
            logger.warning(
                "google_stream_json_decode_failed data=%r", payload_str[:200]
            )
            continue

        final_model = data.get("modelVersion") or final_model

        if data.get("usageMetadata"):
            usage_meta = data["usageMetadata"]

        candidates = data.get("candidates") or []
        if not candidates:
            continue
        cand = candidates[0] or {}

        # Safety / Recitation: surface as ValueError; adapter translates.
        cand_finish = cand.get("finishReason") or ""
        if cand_finish == "SAFETY":
            safety_ratings = cand.get("safetyRatings") or []
            raise ValueError(
                "Response blocked by safety filters: "
                + ", ".join(
                    "%s=%s" % (r.get("category", "?"), r.get("probability", "?"))
                    for r in safety_ratings
                )
            )
        if cand_finish == "RECITATION":
            raise ValueError(
                "Response blocked due to recitation (potential copyright content)."
            )

        if cand_finish:
            finish_reason = cand_finish

        # Append part deltas
        content = cand.get("content") or {}
        for part in content.get("parts", []) or []:
            text = part.get("text", "")
            if not text:
                continue
            if part.get("thought", False):
                thinking_parts.append(text)
            else:
                text_parts.append(text)

    content = "".join(text_parts)
    thinking = "".join(thinking_parts) if thinking_parts else None

    # MAX_TOKENS warning matches non-streaming behavior
    if finish_reason == "MAX_TOKENS":
        logger.warning(
            "google_response_truncated model=%s reason=MAX_TOKENS",
            model_id,
        )

    # Handle unknown finish reasons gracefully (Flatline SKP-001 parity)
    known_reasons = {"STOP", "MAX_TOKENS", "SAFETY", "RECITATION", "OTHER", ""}
    if finish_reason and finish_reason not in known_reasons:
        logger.warning(
            "google_unknown_finish_reason model=%s reason=%s",
            model_id,
            finish_reason,
        )

    # Parse usage (parity with _parse_response)
    if usage_meta:
        input_tokens = usage_meta.get("promptTokenCount", 0) or 0
        output_tokens = usage_meta.get("candidatesTokenCount", 0) or 0
        reasoning_tokens = usage_meta.get("thoughtsTokenCount", 0) or 0

        if "thoughtsTokenCount" not in usage_meta and thinking_parts:
            logger.warning(
                "google_partial_usage model=%s missing=thoughtsTokenCount",
                model_id,
            )

        usage = Usage(
            input_tokens=input_tokens,
            output_tokens=output_tokens,
            reasoning_tokens=reasoning_tokens,
            source="actual",
        )
    else:
        logger.warning(
            "google_missing_usage model=%s using_estimate=true",
            model_id,
        )
        est_input = int(input_text_length / 3.5) if input_text_length else 0
        est_output = int(len(content) / 3.5) if content else 0
        usage = Usage(
            input_tokens=est_input,
            output_tokens=est_output,
            reasoning_tokens=0,
            source="estimated",
        )

    metadata: Dict[str, Any] = {"streaming": True}
    if finish_reason:
        metadata["finish_reason"] = finish_reason

    return CompletionResult(
        content=content,
        tool_calls=None,  # Streaming tool calls not yet supported (matches non-streaming behavior)
        thinking=thinking,
        usage=usage,
        model=final_model or model_id,
        latency_ms=0,  # adapter re-attaches
        provider=provider,
        metadata=metadata,
    )
