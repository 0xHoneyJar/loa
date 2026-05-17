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
import time
from typing import Any, Dict, Iterator, List, Optional

from loa_cheval.providers.openai_streaming import (
    _iter_sse_events_raw_data,
    _iter_sse_events_raw_data_with_deadline,
)
from loa_cheval.providers.streaming_caps import (
    MAX_TEXT_PART_BYTES,
    accumulate_capped,
)
from loa_cheval.streaming import (
    StreamingRecoveryAbort,
    StreamingRecoveryConfig,
    StreamingRecoveryTracker,
)
from loa_cheval.types import CompletionResult, Usage

logger = logging.getLogger("loa_cheval.providers.google_streaming")


def parse_google_stream(
    byte_iter: Iterator[bytes],
    *,
    model_id: str = "unknown",
    provider: str = "google",
    input_text_length: int = 0,
    model_data: Optional[Dict[str, Any]] = None,
    reasoning_class: bool = False,
    now_provider: Any = time.monotonic,
) -> CompletionResult:
    """Reconstruct a CompletionResult from a Gemini `:streamGenerateContent?alt=sse`
    SSE event stream.

    `input_text_length` is used as a fallback token estimate when the
    final fragment omits `usageMetadata` — matches the conservative
    estimation path in `_parse_response`.

    cycle-113 sprint-169 T2.5: kwargs `model_data`, `reasoning_class`,
    `now_provider` wire the StreamingRecoveryTracker per SDD §3.4.
    Both `part.text` and `part.thought` deltas are fed to the tracker;
    the library's CoT-prefix regex is independent of `reasoning_class`,
    but flagging `reasoning_class=True` for Gemini thinking-tier models
    keeps parity with Anthropic/OpenAI (SDD §3.4). Raises
    ``StreamingRecoveryAbort`` per FR-B-3 / I-2.
    """
    # cycle-113 T2.5 — recovery tracker init (parity with T1.6/T2.2/T2.3).
    # Shares the openai_streaming.py deadline-shim because Google already
    # cross-imports the base SSE iterator (line 38) — keeps the shim copy
    # count at 3 (anthropic + openai-chat + openai-responses/google shared).
    #
    # cycle-113 sprint-169 review iter-2 BLOCKING finding (DISS-001):
    # the deadline-shim's `check_deadline()` fires BEFORE each
    # `yield next(byte_iter)`. If `next()` BLOCKS waiting for bytes
    # that never arrive — which is the real Google API's behavior on a
    # pre-first-token stall (no keepalives) — the deadline-shim's
    # check_deadline is never called again and first_token_deadline_s
    # does NOT fire at the parser layer.
    #
    # Production safety for true Google no-byte stalls is provided by
    # the TRANSPORT-LAYER timeout (cycle-102 Sprint 4A `http_post_stream`
    # configured httpx ReadTimeout). The recovery-layer first_token_deadline
    # at the parser is a BEST-EFFORT addition: it fires reliably for
    # Anthropic + OpenAI streams (which emit SSE keepalives during stalls)
    # but only fires for Google when the test harness injects clock
    # advancement OR keepalive bytes arrive (e.g., from a CDN sitting
    # in front of the API).
    #
    # The synthetic-keepalive parity fixture (T2.x-review commit
    # c13f0add) exercises the deadline-shim code path uniformly across
    # providers; production-stall behavior relies on the transport
    # layer. Sprint-170 / cycle-114 carry: add a transport-layer
    # integration test for true Google no-byte stalls and confirm
    # the chain-walk activates via transport-timeout → InvalidInputError
    # → ProviderUnavailableError path.
    recovery_config = StreamingRecoveryConfig.for_model(
        model_data or {}, reasoning_class=reasoning_class,
    )
    recovery_tracker = StreamingRecoveryTracker(
        config=recovery_config,
        start_time_s=now_provider(),
    )
    config_applied: Dict[str, Any] = {
        "first_token_deadline_s": recovery_config.first_token_deadline_s,
        "empty_content_window_tokens": recovery_config.empty_content_window_tokens,
        "cot_budget_tokens": recovery_config.cot_budget_tokens,
        "reasoning_class": recovery_config.reasoning_class,
    }
    partial_text_seen: List[str] = []

    text_parts: List[str] = []
    thinking_parts: List[str] = []
    finish_reason: Optional[str] = None
    final_model: Optional[str] = None
    usage_meta: Optional[Dict[str, Any]] = None
    safety_ratings: Optional[list] = None

    for _event_name, payload_str in _iter_sse_events_raw_data_with_deadline(
        byte_iter, recovery_tracker, config_applied, now_provider,
    ):
        if payload_str is None or payload_str == "[DONE]":
            continue
        try:
            data = json.loads(payload_str)
        except json.JSONDecodeError:
            # Sprint 4A cycle-4 (BB F-004): fail-loud parity with Anthropic
            # + OpenAI streaming parsers. Cycle-3 BF-006 fix updated those
            # two but missed Google here — the cross-provider parser
            # inconsistency is the most expensive bug class to debug
            # because the symptom (empty content from one provider only)
            # looks like a provider issue, not a substrate issue. Adapter
            # wrapper translates ValueError to InvalidInputError.
            raise ValueError(
                f"Google streaming malformed data frame: {payload_str[:200]!r}"
            )

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

        # Append part deltas. cycle-113 T2.5: feed tracker on BOTH text
        # and thought parts (SDD §3.4). The library's CoT-prefix regex
        # is independent of `reasoning_class`, but flagging
        # reasoning_class=True for Gemini thinking-tier keeps parity
        # with Anthropic/OpenAI behavior.
        content = cand.get("content") or {}
        for part in content.get("parts", []) or []:
            text = part.get("text", "")
            # Feed tracker even for empty strings (SDD §2.1).
            _recovery_feed_google(
                recovery_tracker, text, partial_text_seen,
                config_applied, now_provider,
            )
            if not text:
                continue
            if part.get("thought", False):
                accumulate_capped(
                    thinking_parts, text, cap=MAX_TEXT_PART_BYTES, kind="thinking"
                )
            else:
                accumulate_capped(
                    text_parts, text, cap=MAX_TEXT_PART_BYTES, kind="text"
                )

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
    # cycle-113 T2.5 / I-3: streaming_recovery telemetry on healthy path.
    # FR-B-3: thoughtsTokenCount is post-hoc observability; surfaced in
    # config_applied if available but NOT in the abort-decision path.
    sr_extra: Dict[str, Any] = dict(config_applied)
    if usage_meta and "thoughtsTokenCount" in usage_meta:
        sr_extra["thoughts_token_count"] = usage_meta["thoughtsTokenCount"] or 0
    metadata["streaming_recovery"] = {
        "triggered": False,
        "tokens_before_abort": None,
        "reason": None,
        "config_applied": sr_extra,
    }

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


# --- cycle-113 T2.5 — recovery feed helper ---


def _recovery_feed_google(
    tracker: StreamingRecoveryTracker,
    text: str,
    partial_text_seen: List[str],
    config_applied: Dict[str, Any],
    now_provider: Any,
) -> None:
    """Feed one Gemini part.text/part.thought delta into the recovery
    tracker. On abort: raise StreamingRecoveryAbort with partial
    snapshot. Parity with anthropic_streaming._recovery_feed and
    openai_streaming._recovery_feed_openai (SDD §3.1)."""
    if text:
        partial_text_seen.append(text)
    decision = tracker.on_token(text, now_provider())
    if decision.abort:
        raise StreamingRecoveryAbort(
            reason=decision.reason,
            tokens_before_abort=decision.tokens_before_abort,
            config_applied=config_applied,
            partial_content="".join(partial_text_seen),
        )
