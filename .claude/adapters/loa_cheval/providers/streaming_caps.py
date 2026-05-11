"""cycle-103 sprint-3 T3.5 — shared streaming buffer/accumulator caps.

Defense against pathological / malicious streaming responses that drive
unbounded memory growth (a server emitting one event without a terminator,
or a single content delta of multi-gigabyte size). Caps surface as
`ProviderStreamError("transient", ...)` per T3.1's dispatch contract;
adapter layer routes through `dispatch_provider_stream_error` → typically
`ConnectionLostError` for the retry layer (AC-3.5).

Caps:
- MAX_SSE_BUFFER_BYTES: 4 MiB — the SSE event boundary scanner buffer.
  Crossed when a server emits 4MB+ without a `\\n\\n` terminator.
- MAX_TEXT_PART_BYTES: 1 MiB — per-block text/thinking accumulator.
  Crossed when a single content block grows past 1MB across deltas.
- MAX_ARGS_PART_BYTES: 256 KiB — per-tool-call arguments accumulator.
  Crossed when a single tool_use input_json_delta exceeds 256KB total.

Per-event-accumulator caps are checked AFTER appending a delta; the
helper `accumulate_capped` does the bookkeeping in one call.

Spec: sprint.md L222 (T3.5) + L205 (AC-3.5).
"""
from __future__ import annotations

from typing import List

from loa_cheval.types import ProviderStreamError


MAX_SSE_BUFFER_BYTES = 4 * 1024 * 1024
MAX_TEXT_PART_BYTES = 1 * 1024 * 1024
MAX_ARGS_PART_BYTES = 256 * 1024


def check_buffer_cap(buffer_len: int) -> None:
    """Raise `ProviderStreamError("transient", ...)` when SSE buffer cap
    is exceeded. Called inside the SSE iterators after each append.
    """
    if buffer_len > MAX_SSE_BUFFER_BYTES:
        raise ProviderStreamError(
            "transient",
            (
                f"SSE buffer exceeded {MAX_SSE_BUFFER_BYTES} bytes without "
                f"event terminator (buffered={buffer_len}). Likely "
                "pathological upstream or stuck connection."
            ),
        )


def accumulate_capped(
    parts: List[str],
    delta: str,
    *,
    cap: int,
    kind: str,
) -> None:
    """Append a string delta to `parts`, asserting the cumulative byte
    sum stays within `cap`. Raises `ProviderStreamError` if exceeded.

    Args:
        parts: existing list of string deltas (mutated in place).
        delta: new delta to append. Empty deltas are still tracked for
            consistency but contribute zero bytes.
        cap: byte cap (one of MAX_TEXT_PART_BYTES / MAX_ARGS_PART_BYTES).
        kind: short label for the error message ("text", "arguments",
            "reasoning_summary", etc.) — distinguishes which accumulator
            tripped without leaking accumulator content.
    """
    parts.append(delta or "")
    # `sum(len(...))` is O(n) per call, but each delta event triggers
    # one such walk over the post-append list. For n events totalling
    # M bytes this is O(M) overall — same as the underlying join. The
    # alternative (carry running totals) couples this helper to caller
    # state; not worth the complexity at current scales.
    total = 0
    for part in parts:
        total += len(part)
        if total > cap:
            raise ProviderStreamError(
                "transient",
                (
                    f"Per-event accumulator '{kind}' exceeded {cap} bytes "
                    f"(accumulated={total}). Likely pathological upstream "
                    "or runaway content."
                ),
            )
