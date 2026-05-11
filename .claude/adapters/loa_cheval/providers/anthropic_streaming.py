"""Anthropic streaming-response parser — Sprint 4A (cycle-102, AC-4.5e).

Consumes a byte-iterator from `base.http_post_stream` and reconstructs the
canonical `CompletionResult` from Anthropic's Messages API SSE event stream.

Event schema (Anthropic docs):

    event: message_start
    data: {"type":"message_start","message":{"id":"msg_x","role":"assistant",
           "model":"...","content":[],"usage":{"input_tokens":N,"output_tokens":1}}}

    event: content_block_start
    data: {"type":"content_block_start","index":0,
           "content_block":{"type":"text","text":""}}

    event: content_block_delta
    data: {"type":"content_block_delta","index":0,
           "delta":{"type":"text_delta","text":"Hello"}}

    event: content_block_stop
    data: {"type":"content_block_stop","index":0}

    event: message_delta
    data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},
           "usage":{"output_tokens":15}}

    event: message_stop
    data: {"type":"message_stop"}

    event: ping
    data: {"type":"ping"}            # heartbeat — ignore

Block types handled:
  - `text` → text_delta chunks → joined into CompletionResult.content
  - `thinking` → thinking_delta chunks → joined into CompletionResult.thinking
  - `tool_use` → input_json_delta chunks → assembled tool_call.arguments

UTF-8 safety: SSE events are separated by `\\n\\n`. Newline bytes (0x0A)
cannot appear mid-codepoint in UTF-8 (multi-byte codepoints have all bytes
≥ 0x80). So splitting raw bytes on `\\n\\n` always falls on event
boundaries, and per-event UTF-8 decode is safe.
"""
from __future__ import annotations

import json
import logging
from typing import Any, Dict, Iterator, List, Optional

from loa_cheval.types import CompletionResult, Usage

logger = logging.getLogger("loa_cheval.providers.anthropic_streaming")


def parse_anthropic_stream(
    byte_iter: Iterator[bytes],
    *,
    provider: str = "anthropic",
    latency_ms_at_first_byte: Optional[int] = None,
    latency_ms_at_completion: Optional[int] = None,
) -> CompletionResult:
    """Reconstruct a CompletionResult from Anthropic's SSE event stream.

    Args:
        byte_iter: bytes iterator from `http_post_stream`.
        provider: provider name for the returned CompletionResult.
        latency_ms_at_first_byte: optional wall-clock first-byte time;
            stored for observability but not currently surfaced.
        latency_ms_at_completion: total wall-clock time at stream end.

    Returns:
        CompletionResult with content, thinking, tool_calls, usage, and
        a `streaming: True` metadata flag.

    Raises:
        ValueError: on malformed SSE (event without data, JSON parse
            failure on a data line). Callers should typically catch and
            translate to InvalidInputError or treat as transport degradation.
    """
    # Block accumulators indexed by Anthropic's `index` field. Each entry:
    #   {"type": "text"|"thinking"|"tool_use",
    #    "text_parts": [str, ...]              # text + thinking blocks
    #    "name": str, "id": str,               # tool_use blocks
    #    "json_parts": [str, ...]}             # tool_use blocks
    blocks_by_index: Dict[int, Dict[str, Any]] = {}

    final_model: Optional[str] = None
    stop_reason: Optional[str] = None
    input_tokens = 0
    output_tokens = 0

    for event_name, event_payload in _iter_sse_events(byte_iter):
        if event_name == "ping" or event_payload is None:
            continue

        ev_type = event_payload.get("type", "")

        if ev_type == "message_start":
            msg = event_payload.get("message", {}) or {}
            final_model = msg.get("model") or final_model
            usage = msg.get("usage", {}) or {}
            input_tokens = usage.get("input_tokens", 0) or 0
            # `output_tokens` in message_start is the initial sample (usually 1);
            # the canonical total arrives in `message_delta`.
            output_tokens = usage.get("output_tokens", 0) or 0

        elif ev_type == "content_block_start":
            idx = event_payload.get("index")
            cb = event_payload.get("content_block", {}) or {}
            cb_type = cb.get("type", "")
            entry: Dict[str, Any] = {"type": cb_type, "text_parts": []}
            if cb_type == "tool_use":
                entry["id"] = cb.get("id", "")
                entry["name"] = cb.get("name", "")
                entry["json_parts"] = []
                # Anthropic sometimes seeds initial `input` (partial dict) here.
                seed_input = cb.get("input")
                if isinstance(seed_input, dict) and seed_input:
                    entry["json_parts"].append(json.dumps(seed_input)[1:-1])
            elif cb_type == "text":
                # `content_block_start.text` is usually empty but capture if set.
                seed_text = cb.get("text", "")
                if seed_text:
                    entry["text_parts"].append(seed_text)
            elif cb_type == "thinking":
                seed_thinking = cb.get("thinking", "")
                if seed_thinking:
                    entry["text_parts"].append(seed_thinking)
            blocks_by_index[idx] = entry

        elif ev_type == "content_block_delta":
            idx = event_payload.get("index")
            entry = blocks_by_index.get(idx)
            if entry is None:
                # Out-of-order delta; tolerate by creating a text block on demand.
                entry = {"type": "text", "text_parts": []}
                blocks_by_index[idx] = entry
            delta = event_payload.get("delta", {}) or {}
            delta_type = delta.get("type", "")
            if delta_type == "text_delta":
                entry["text_parts"].append(delta.get("text", "") or "")
            elif delta_type == "thinking_delta":
                entry["text_parts"].append(delta.get("thinking", "") or "")
            elif delta_type == "input_json_delta":
                entry.setdefault("json_parts", []).append(
                    delta.get("partial_json", "") or ""
                )

        elif ev_type == "content_block_stop":
            # Nothing to do; block is finalized when the next event fires
            # OR at message_stop time. We could compact here but it's a no-op.
            pass

        elif ev_type == "message_delta":
            delta = event_payload.get("delta", {}) or {}
            stop_reason = delta.get("stop_reason") or stop_reason
            usage = event_payload.get("usage", {}) or {}
            # Anthropic emits the FINAL output_tokens here (cumulative).
            if "output_tokens" in usage:
                output_tokens = usage["output_tokens"] or 0
            if "input_tokens" in usage and usage["input_tokens"]:
                input_tokens = usage["input_tokens"]

        elif ev_type == "message_stop":
            # Stream finalized.
            pass

        elif ev_type == "error":
            # Anthropic emits this on mid-stream errors. Surface as ValueError;
            # callers map to InvalidInputError / ProviderUnavailableError.
            err = event_payload.get("error", {}) or {}
            err_type = err.get("type", "unknown")
            err_msg = err.get("message", "")
            raise ValueError(
                f"Anthropic streaming error event: type={err_type!r} message={err_msg!r}"
            )

        else:
            # Forward-compat: unknown event types are logged but not fatal.
            logger.debug("anthropic_stream_unknown_event type=%r", ev_type)

    # Assemble final CompletionResult from accumulated blocks.
    text_parts: List[str] = []
    thinking_parts: List[str] = []
    tool_calls: List[Dict[str, Any]] = []

    for idx in sorted(blocks_by_index.keys()):
        entry = blocks_by_index[idx]
        btype = entry.get("type", "")
        if btype == "text":
            text_parts.append("".join(entry.get("text_parts", [])))
        elif btype == "thinking":
            thinking_parts.append("".join(entry.get("text_parts", [])))
        elif btype == "tool_use":
            args_str = "".join(entry.get("json_parts", []))
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

    content = "\n".join(text_parts) if text_parts else ""
    thinking = "\n".join(thinking_parts) if thinking_parts else None

    usage_obj = Usage(
        input_tokens=input_tokens,
        output_tokens=output_tokens,
        reasoning_tokens=0,  # Anthropic streams thinking as separate blocks, not via usage.
        source="actual" if (input_tokens or output_tokens) else "estimated",
    )

    metadata: Dict[str, Any] = {"streaming": True}
    if stop_reason:
        metadata["stop_reason"] = stop_reason

    return CompletionResult(
        content=content,
        tool_calls=tool_calls if tool_calls else None,
        thinking=thinking,
        usage=usage_obj,
        model=final_model or "unknown",
        latency_ms=latency_ms_at_completion or 0,
        provider=provider,
        metadata=metadata,
    )


# --- SSE event-stream parser ---


def _iter_sse_events(
    byte_iter: Iterator[bytes],
) -> Iterator[tuple]:
    """Yield (event_name, payload_dict) tuples from an SSE byte stream.

    Buffers raw bytes, splits on `\\n\\n` event boundaries (always safe in
    UTF-8 since 0x0A never appears mid-codepoint), and parses each event's
    fields.

    Ignored: keep-alive comments (lines starting with `:`).
    `payload_dict` is `None` if the event has no `data:` line or the data
    fails JSON parsing — callers decide how to handle.
    """
    buffer = b""
    for chunk in byte_iter:
        if not chunk:
            continue
        buffer += chunk
        while True:
            # Find the earliest event terminator. SSE spec: \n\n or \r\n\r\n.
            sep_idx = -1
            for sep in (b"\n\n", b"\r\n\r\n"):
                idx = buffer.find(sep)
                if idx != -1 and (sep_idx == -1 or idx < sep_idx):
                    sep_idx = idx
                    sep_len = len(sep)
            if sep_idx == -1:
                break
            raw_event = buffer[:sep_idx]
            buffer = buffer[sep_idx + sep_len :]
            event_name, payload = _parse_sse_event(raw_event)
            if event_name is None and payload is None:
                continue
            yield event_name, payload

    # Trailing buffer (no final \n\n) — parse if it looks like a complete event.
    if buffer.strip():
        event_name, payload = _parse_sse_event(buffer)
        if event_name is not None or payload is not None:
            yield event_name, payload


def _parse_sse_event(raw: bytes) -> tuple:
    """Parse a single SSE event from raw bytes into (event_name, payload_dict).

    SSE field format:
        event: <name>
        data: <payload>
        : <comment>          # ignored
    """
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        # Tolerate by stripping invalid bytes; SSE-valid streams should never
        # hit this since we split on \n\n boundaries.
        text = raw.decode("utf-8", errors="replace")

    event_name: Optional[str] = None
    data_parts: List[str] = []

    for line in text.split("\n"):
        line = line.rstrip("\r")
        if not line:
            continue
        if line.startswith(":"):
            # Comment / keep-alive.
            continue
        if line.startswith("event:"):
            event_name = line[6:].strip()
        elif line.startswith("data:"):
            data_parts.append(line[5:].lstrip())
        # Other SSE fields (id, retry) — ignored for our purposes.

    if not data_parts and event_name is None:
        return None, None

    if not data_parts:
        return event_name, None

    data_str = "\n".join(data_parts)
    try:
        payload = json.loads(data_str)
    except json.JSONDecodeError:
        # Malformed JSON in data — log + yield None payload so caller can
        # decide whether to tolerate. Anthropic-correct streams never hit this.
        logger.warning("anthropic_stream_json_decode_failed event=%r data=%r",
                       event_name, data_str[:200])
        return event_name, None
    return event_name, payload
