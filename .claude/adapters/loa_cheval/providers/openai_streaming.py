"""OpenAI streaming-response parsers — Sprint 4A (cycle-102, AC-4.5e).

OpenAI exposes two SSE response shapes:

1. `/v1/chat/completions` — classic ChatCompletion chunks. Each chunk is
   `data: {"choices":[{"delta":{"content":"...","tool_calls":[...]},
   "finish_reason":null}],...}` terminated by `data: [DONE]`.

2. `/v1/responses` — typed event stream (cycle-095 Sprint 1). Events like
   `response.created`, `response.output_item.added`,
   `response.output_text.delta`, `response.function_call_arguments.delta`,
   `response.completed`. Each `data:` line carries one event object.

Both parsers consume a byte-iterator from `base.http_post_stream` and
return a canonical `CompletionResult`. Text content, tool calls, reasoning
summaries, refusals, and usage metadata are all surfaced through the same
field set the non-streaming parsers already produce.

The Sprint 1F `text.format=text` request-body parameter is orthogonal to
streaming — it stays on the streaming request unchanged. Test:
`text.format=text` continues to force a visible-text item even when
reasoning exhausts max_output_tokens (KF-002 layer 1 mitigation).
"""
from __future__ import annotations

import json
import logging
from typing import Any, Dict, Iterator, List, Optional

from loa_cheval.types import CompletionResult, Usage

logger = logging.getLogger("loa_cheval.providers.openai_streaming")


# --- /v1/chat/completions streaming parser ---


def parse_openai_chat_stream(
    byte_iter: Iterator[bytes],
    *,
    provider: str = "openai",
) -> CompletionResult:
    """Parse OpenAI /v1/chat/completions SSE stream.

    Chunk shape (one per `data:` line):
        {"id":"...","choices":[{"index":0,"delta":{"content":"Hello"},
          "finish_reason":null}],"model":"...","usage":null}

    Terminator: `data: [DONE]`

    Tool-call assembly: each `delta.tool_calls[i]` may carry partial
    fragments — `function.name` appears once on the first delta, then
    `function.arguments` arrives as concatenated chunks across subsequent
    deltas. Index-keyed accumulator handles parallel tool calls.

    Usage: final chunk may contain `usage: {...}` (per OpenAI's
    `stream_options: {include_usage: true}` request body — most LLM SDKs
    request this by default for cost accounting).
    """
    text_parts: List[str] = []
    # tool_calls accumulator keyed by index. Each entry:
    #   {"id": str, "name": str, "arguments_parts": [str, ...]}
    tool_calls_by_index: Dict[int, Dict[str, Any]] = {}
    finish_reason: Optional[str] = None
    final_model: Optional[str] = None
    usage_data: Dict[str, Any] = {}

    for chunk in _iter_chat_stream_chunks(byte_iter):
        if chunk is None or chunk == "[DONE]":
            continue
        try:
            payload = json.loads(chunk)
        except json.JSONDecodeError:
            # Sprint 4A cycle-3 (BF-006): fail-closed on malformed data frames.
            # Under uncertainty about whether the stream is intact, halt rather
            # than forward partial — mirrors the cycle-098 fail-closed pattern.
            # Keep-alive lines (`:`-prefixed comments) never reach this branch
            # because the SSE parser strips them upstream; only legitimate
            # `data:` payloads land here, and a malformed payload almost always
            # indicates protocol corruption or truncation.
            raise ValueError(
                f"OpenAI streaming malformed data frame: {chunk[:200]!r}"
            )

        # Sprint 4A cycle-3 (BF-002): top-level `{"error":...}` frame detection.
        # Without this, an OpenAI error frame (no `choices` array) would be
        # silently skipped by the `if not choices: continue` arm below, and
        # the parser would return an empty CompletionResult flagged as
        # successful — the cycle-102 ghost manifesting one layer wider in
        # the very substrate built to surface it. Fail-loud invariant.
        if isinstance(payload.get("error"), dict):
            err = payload["error"]
            raise ValueError(
                f"OpenAI streaming error frame: type={err.get('type')!r} "
                f"code={err.get('code')!r} message={err.get('message')!r}"
            )

        final_model = payload.get("model") or final_model

        # OpenAI's stream_options.include_usage path attaches usage on the
        # final chunk with an empty `choices` array.
        if payload.get("usage"):
            usage_data = payload["usage"]

        choices = payload.get("choices") or []
        if not choices:
            continue
        choice = choices[0] or {}
        if choice.get("finish_reason"):
            finish_reason = choice["finish_reason"]

        delta = choice.get("delta") or {}

        # Text content
        content = delta.get("content")
        if content:
            text_parts.append(content)

        # Refusal (Responses API style; rare on /chat/completions but possible)
        refusal = delta.get("refusal")
        if refusal:
            text_parts.append(refusal)

        # Tool calls
        for tc in delta.get("tool_calls", []) or []:
            idx = tc.get("index", 0)
            entry = tool_calls_by_index.setdefault(
                idx, {"id": "", "name": "", "arguments_parts": []}
            )
            if tc.get("id"):
                entry["id"] = tc["id"]
            fn = tc.get("function") or {}
            if fn.get("name"):
                entry["name"] = fn["name"]
            if fn.get("arguments") is not None:
                entry["arguments_parts"].append(fn["arguments"])

    content = "".join(text_parts)

    tool_calls: List[Dict[str, Any]] = []
    for idx in sorted(tool_calls_by_index.keys()):
        entry = tool_calls_by_index[idx]
        args_str = "".join(entry.get("arguments_parts", []))
        if not args_str:
            args_str = "{}"
        tool_calls.append(
            {
                "id": entry.get("id", ""),
                "function": {
                    "name": entry.get("name", ""),
                    "arguments": args_str,
                },
                "type": "function",
            }
        )

    usage = Usage(
        input_tokens=usage_data.get("prompt_tokens", 0) or 0,
        output_tokens=usage_data.get("completion_tokens", 0) or 0,
        reasoning_tokens=(usage_data.get("completion_tokens_details") or {}).get(
            "reasoning_tokens", 0
        ) or 0,
        source="actual" if usage_data else "estimated",
    )

    metadata: Dict[str, Any] = {"streaming": True}
    if finish_reason:
        metadata["finish_reason"] = finish_reason

    return CompletionResult(
        content=content,
        tool_calls=tool_calls if tool_calls else None,
        thinking=None,  # /chat/completions does not stream reasoning visibly.
        usage=usage,
        model=final_model or "unknown",
        latency_ms=0,  # adapter re-attaches.
        provider=provider,
        metadata=metadata,
    )


def _iter_chat_stream_chunks(byte_iter: Iterator[bytes]) -> Iterator[Optional[str]]:
    """Yield each `data:` line value from an OpenAI /chat/completions SSE stream.

    Returns strings (not parsed JSON) so the caller can short-circuit on
    `[DONE]`. Yields `None` for events with no data line (which OpenAI
    sometimes emits as keep-alives or empty `event: error` markers).
    """
    for event_name, payload in _iter_sse_events_raw_data(byte_iter):
        # /chat/completions uses bare `data: {...}` events without explicit
        # `event:` lines, so event_name is typically None and payload is
        # the raw data string. _iter_sse_events_raw_data gives us strings
        # not parsed JSON.
        if payload is None:
            continue
        if payload == "[DONE]":
            yield "[DONE]"
            continue
        yield payload


def _iter_sse_events_raw_data(byte_iter: Iterator[bytes]):
    """SSE parser that yields raw data strings (not parsed JSON).

    Mirrors `_iter_sse_events` in anthropic_streaming.py but defers JSON
    parsing to the caller — OpenAI's `data: [DONE]` terminator is not
    valid JSON, so the bare-data path is mandatory for /chat/completions.
    """
    buffer = b""
    for chunk in byte_iter:
        if not chunk:
            continue
        buffer += chunk
        while True:
            sep_idx = -1
            sep_len = 0
            for sep in (b"\n\n", b"\r\n\r\n"):
                idx = buffer.find(sep)
                if idx != -1 and (sep_idx == -1 or idx < sep_idx):
                    sep_idx = idx
                    sep_len = len(sep)
            if sep_idx == -1:
                break
            raw_event = buffer[:sep_idx]
            buffer = buffer[sep_idx + sep_len :]
            event_name, data_str = _parse_sse_event_raw_data(raw_event)
            yield event_name, data_str

    if buffer.strip():
        event_name, data_str = _parse_sse_event_raw_data(buffer)
        if event_name is not None or data_str is not None:
            yield event_name, data_str


def _parse_sse_event_raw_data(raw: bytes):
    """Parse a single SSE event into (event_name, data_str)."""
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        text = raw.decode("utf-8", errors="replace")

    event_name: Optional[str] = None
    data_parts: List[str] = []
    for line in text.split("\n"):
        line = line.rstrip("\r")
        if not line or line.startswith(":"):
            continue
        if line.startswith("event:"):
            event_name = line[6:].strip()
        elif line.startswith("data:"):
            data_parts.append(line[5:].lstrip())

    if not data_parts and event_name is None:
        return None, None
    if not data_parts:
        return event_name, None
    return event_name, "\n".join(data_parts)


# --- /v1/responses streaming parser (cycle-095 Sprint 1 endpoint family) ---


def parse_openai_responses_stream(
    byte_iter: Iterator[bytes],
    *,
    provider: str = "openai",
) -> CompletionResult:
    """Parse OpenAI /v1/responses typed-event stream.

    Event types handled (subset relevant to current cheval shape):
      - response.created — initial event with response.id, model, etc.
      - response.output_item.added — new output item (message, tool_call,
        reasoning) with index + initial content_block
      - response.content_part.added / response.content_part.done —
        message content parts (text, refusal)
      - response.output_text.delta — text delta on a message item
      - response.refusal.delta — refusal delta
      - response.function_call_arguments.delta — tool-call argument delta
      - response.reasoning_summary_text.delta — reasoning summary delta
        (visible reasoning, not the invisible reasoning_tokens count)
      - response.completed — final event with usage + completion status
      - response.failed / response.incomplete — error / truncation paths

    See `_parse_responses_response` in openai_adapter.py for the
    six-shape normalizer this streaming parser must produce equivalent
    output for (PRD §3.1, SDD §5.4):
      1. Multi-block text
      2. Tool/function call
      3. Reasoning summary
      4. Refusal
      5. Empty output
      6. Truncated

    Sprint 1F `text.format=text` request param continues to force a
    visible text item even when reasoning exhausts the budget — the
    streaming response carries the same property.
    """
    # Per-output-item accumulator keyed by item.id (or fallback to index).
    # Each entry:
    #   {"type": "message"|"function_call"|"reasoning",
    #    "text_parts": [str, ...],          # message item, content type=output_text
    #    "refusal_parts": [str, ...],       # message item, content type=refusal
    #    "name": str, "call_id": str,       # function_call item
    #    "arguments_parts": [str, ...],     # function_call item
    #    "summary_text_parts": [str, ...]}  # reasoning item
    items_by_id: Dict[str, Dict[str, Any]] = {}
    # Preserve insertion order via separate list so output text is concatenated
    # in the order the items arrived.
    item_order: List[str] = []

    final_model: Optional[str] = None
    incomplete_reason: Optional[str] = None
    refusal_text_top: Optional[str] = None
    usage_data: Dict[str, Any] = {}

    for event_name, payload in _iter_sse_events_raw_data(byte_iter):
        if payload is None:
            continue
        if payload == "[DONE]":
            continue
        try:
            data = json.loads(payload)
        except json.JSONDecodeError:
            # Sprint 4A cycle-3 (BF-006): fail-closed on malformed data frames
            # (mirrors the chat-completions parser change above).
            raise ValueError(
                f"OpenAI /v1/responses streaming malformed data frame "
                f"event={event_name!r} payload={payload[:200]!r}"
            )

        # Sprint 4A cycle-3 (BF-002 parity): top-level error frame detection
        # for /v1/responses. Most OpenAI responses-API errors surface as a
        # typed `response.failed` event (handled below), but a connection-level
        # error frame at the protocol layer should also fail-loud.
        if isinstance(data.get("error"), dict):
            err = data["error"]
            raise ValueError(
                f"OpenAI /v1/responses streaming error frame: type={err.get('type')!r} "
                f"code={err.get('code')!r} message={err.get('message')!r}"
            )

        ev_type = data.get("type") or event_name or ""

        if ev_type == "response.created":
            resp = data.get("response") or {}
            final_model = resp.get("model") or final_model

        elif ev_type == "response.output_item.added":
            item = data.get("item") or {}
            item_id = item.get("id") or f"_idx_{len(items_by_id)}"
            item_type = item.get("type") or ""
            if item_id not in items_by_id:
                item_order.append(item_id)
            entry: Dict[str, Any] = {
                "type": item_type,
                "text_parts": [],
                "refusal_parts": [],
                "arguments_parts": [],
                "summary_text_parts": [],
            }
            if item_type in ("function_call", "tool_call"):
                entry["call_id"] = item.get("call_id") or item.get("id", "")
                entry["name"] = item.get("name", "")
                # Sometimes initial `arguments` is present (rare).
                init_args = item.get("arguments")
                if init_args:
                    entry["arguments_parts"].append(init_args)
            items_by_id[item_id] = entry

        elif ev_type == "response.output_text.delta":
            item_id = data.get("item_id")
            if item_id and item_id in items_by_id:
                items_by_id[item_id]["text_parts"].append(data.get("delta", "") or "")

        elif ev_type == "response.refusal.delta":
            item_id = data.get("item_id")
            if item_id and item_id in items_by_id:
                items_by_id[item_id]["refusal_parts"].append(data.get("delta", "") or "")

        elif ev_type == "response.function_call_arguments.delta":
            item_id = data.get("item_id")
            if item_id and item_id in items_by_id:
                items_by_id[item_id]["arguments_parts"].append(
                    data.get("delta", "") or ""
                )

        elif ev_type == "response.reasoning_summary_text.delta":
            item_id = data.get("item_id")
            if item_id and item_id in items_by_id:
                items_by_id[item_id]["summary_text_parts"].append(
                    data.get("delta", "") or ""
                )

        elif ev_type == "response.completed":
            resp = data.get("response") or {}
            final_model = resp.get("model") or final_model
            usage_data = resp.get("usage") or {}
            incomplete = resp.get("incomplete_details") or {}
            if isinstance(incomplete, dict) and incomplete.get("reason"):
                incomplete_reason = incomplete["reason"]

        elif ev_type == "response.incomplete":
            resp = data.get("response") or {}
            incomplete = resp.get("incomplete_details") or {}
            if isinstance(incomplete, dict) and incomplete.get("reason"):
                incomplete_reason = incomplete["reason"]
            if resp.get("usage"):
                usage_data = resp["usage"]

        elif ev_type == "response.failed":
            resp = data.get("response") or {}
            err = resp.get("error") or {}
            raise ValueError(
                f"OpenAI /v1/responses failure event: code={err.get('code')!r} "
                f"message={err.get('message')!r}"
            )

        elif ev_type in (
            "response.content_part.added",
            "response.content_part.done",
            "response.output_text.done",
            "response.output_item.done",
            "response.in_progress",
            "response.queued",
            "response.function_call_arguments.done",
            "response.reasoning_summary_text.done",
            "response.reasoning_summary_part.added",
            "response.reasoning_summary_part.done",
        ):
            # Boundary / status events — informational only.
            pass

        else:
            logger.debug("openai_responses_stream_unknown_event type=%r", ev_type)

    # Assemble final CompletionResult.
    text_parts: List[str] = []
    thinking_parts: List[str] = []
    tool_calls: List[Dict[str, Any]] = []
    metadata: Dict[str, Any] = {"streaming": True}

    for item_id in item_order:
        entry = items_by_id[item_id]
        itype = entry.get("type", "")
        if itype == "message":
            joined_text = "".join(entry.get("text_parts", []))
            joined_refusal = "".join(entry.get("refusal_parts", []))
            if joined_refusal:
                # Refusal on this item replaces text content per the
                # six-shape normalizer (matches non-streaming parser
                # behavior in openai_adapter._parse_responses_response).
                refusal_text_top = joined_refusal
            elif joined_text:
                text_parts.append(joined_text)
        elif itype in ("function_call", "tool_call"):
            args_str = "".join(entry.get("arguments_parts", []))
            if not args_str:
                args_str = "{}"
            tool_calls.append(
                {
                    "id": entry.get("call_id") or item_id,
                    "function": {
                        "name": entry.get("name", ""),
                        "arguments": args_str,
                    },
                    "type": "function",
                }
            )
        elif itype == "reasoning":
            summary = "".join(entry.get("summary_text_parts", []))
            if summary:
                thinking_parts.append(summary)

    if refusal_text_top is not None:
        content = refusal_text_top
        metadata["refused"] = True
    else:
        content = "\n\n".join(text_parts)

    if not content and not tool_calls:
        logger.warning("openai_responses_stream_empty_output model=%s", final_model)

    if incomplete_reason:
        metadata["truncated"] = True
        metadata["truncation_reason"] = incomplete_reason

    output_tokens = usage_data.get("output_tokens", 0) or 0
    reasoning_tokens = (
        (usage_data.get("output_tokens_details") or {}).get("reasoning_tokens", 0) or 0
    )
    usage = Usage(
        input_tokens=usage_data.get("input_tokens", 0) or 0,
        output_tokens=output_tokens,
        reasoning_tokens=reasoning_tokens,
        source="actual" if usage_data else "estimated",
    )

    return CompletionResult(
        content=content,
        tool_calls=tool_calls if tool_calls else None,
        thinking="\n".join(thinking_parts) if thinking_parts else None,
        usage=usage,
        model=final_model or "unknown",
        latency_ms=0,
        provider=provider,
        metadata=metadata,
    )
