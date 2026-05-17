#!/usr/bin/env python3
"""cycle-113 Sprint 1 T1.4 — parity-fixture generator (SDD §6.3).

Emits deterministic SSE byte fixtures + expected-result JSONs for the
six cross-provider parity scenarios from SDD §6.1, across four provider
SSE shapes (Anthropic, OpenAI Chat, OpenAI Responses, Google).

Deterministic by construction:
  - No randomness, no wall-clock reads.
  - SSE JSON payloads emitted with sorted keys + canonical separators.
  - JSON-Schema-style field ordering matches each provider's docstring.
  - Re-running on the same SCENARIOS yields byte-identical files
    (cycle-099 sprint-1D cross-runtime-parity precedent).

Usage::

    python3 generate.py                                    # emit all 4 providers
    python3 generate.py --provider anthropic               # only one provider
    python3 generate.py --provider anthropic openai-chat   # subset
    python3 generate.py --check                            # idempotency self-test

Per FR-B-4, the parity test compares the recovery decision the
StreamingRecoveryTracker reaches when fed each provider's variant of
the same logical token stream — the SSE shapes diverge but the
DECISION must converge (modulo a documented ±2-token tolerance).
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Iterable, List, Optional


# ---------------------------------------------------------------------------
# Provider SSE shapes (SDD §6.3 table)
# ---------------------------------------------------------------------------


def _sse_event(event_name: Optional[str], data: dict) -> bytes:
    """Build one SSE frame. ``event_name=None`` omits the event line
    (mimics ``data:``-only frames per OpenAI Chat shape)."""
    body = json.dumps(data, sort_keys=True, separators=(",", ":"))
    if event_name:
        return f"event: {event_name}\ndata: {body}\n\n".encode("utf-8")
    return f"data: {body}\n\n".encode("utf-8")


def _sse_done() -> bytes:
    """OpenAI Chat terminator (Anthropic + Google don't emit this)."""
    return b"data: [DONE]\n\n"


def _sse_keepalive_anthropic() -> bytes:
    """Anthropic keepalive event during stalls (no data delta)."""
    return b"event: ping\ndata: {}\n\n"


def _sse_keepalive_openai() -> bytes:
    """OpenAI keepalive is a bare comment line."""
    return b": keep-alive\n\n"


def _sse_keepalive_google() -> bytes:
    """Google emits no keepalives during stall — the stream just blocks.
    For first-token-deadline fixtures we encode this as an EMPTY byte
    payload; the test harness pairs the fixture with an injected
    monotonic-clock advance past the deadline."""
    return b""


# ---------------------------------------------------------------------------
# Anthropic emitter
# ---------------------------------------------------------------------------


def emit_anthropic_text_delta(text: str, *, index: int = 0) -> bytes:
    """Anthropic ``content_block_delta`` event with a ``text_delta`` payload.

    Shape (from anthropic_streaming.py docstring):
        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"..."}}
    """
    return _sse_event(
        "content_block_delta",
        {
            "delta": {"text": text, "type": "text_delta"},
            "index": index,
            "type": "content_block_delta",
        },
    )


def emit_anthropic_message_stop() -> bytes:
    """Anthropic stream terminator."""
    return _sse_event(
        "message_stop",
        {"type": "message_stop"},
    )


# ---------------------------------------------------------------------------
# OpenAI Chat-Completions emitter
# ---------------------------------------------------------------------------


def emit_openai_chat_text_delta(text: str) -> bytes:
    """OpenAI Chat-Completions ``choices[0].delta.content``.

    Shape:
        data: {"choices":[{"delta":{"content":"..."},"index":0}]}
    """
    return _sse_event(
        None,
        {
            "choices": [
                {"delta": {"content": text}, "index": 0},
            ],
        },
    )


def emit_openai_chat_stop() -> bytes:
    """OpenAI Chat ``[DONE]`` terminator."""
    return _sse_done()


# ---------------------------------------------------------------------------
# OpenAI Responses-API emitter
# ---------------------------------------------------------------------------


def emit_openai_responses_text_delta(text: str) -> bytes:
    """OpenAI Responses-API ``response.output_text.delta`` event.

    Shape (from openai_streaming.py):
        event: response.output_text.delta
        data: {"type":"response.output_text.delta","delta":"..."}
    """
    return _sse_event(
        "response.output_text.delta",
        {
            "delta": text,
            "type": "response.output_text.delta",
        },
    )


def emit_openai_responses_complete() -> bytes:
    """OpenAI Responses-API ``response.completed`` terminator."""
    return _sse_event(
        "response.completed",
        {"type": "response.completed"},
    )


# ---------------------------------------------------------------------------
# Google Gemini emitter
# ---------------------------------------------------------------------------


def emit_google_text_delta(text: str) -> bytes:
    """Google Gemini ``GenerateContentResponse`` fragment.

    Shape (from google_streaming.py):
        data: {"candidates":[{"content":{"parts":[{"text":"..."},...],"role":"model"},"index":0,"finishReason":null}],"modelVersion":"gemini-..."}
    """
    return _sse_event(
        None,
        {
            "candidates": [
                {
                    "content": {
                        "parts": [{"text": text}],
                        "role": "model",
                    },
                    "finishReason": None,
                    "index": 0,
                },
            ],
            "modelVersion": "gemini-1.5-pro-002",
        },
    )


def emit_google_stop() -> bytes:
    """Google ``finishReason: STOP`` terminator with usage metadata."""
    return _sse_event(
        None,
        {
            "candidates": [
                {
                    "content": {"parts": [], "role": "model"},
                    "finishReason": "STOP",
                    "index": 0,
                },
            ],
            "modelVersion": "gemini-1.5-pro-002",
            "usageMetadata": {
                "candidatesTokenCount": 0,
                "promptTokenCount": 0,
                "totalTokenCount": 0,
            },
        },
    )


# ---------------------------------------------------------------------------
# Per-provider stream builders
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class StreamBuilders:
    """Bundle of (text_delta_emitter, stream_terminator) per provider."""

    text_delta: Callable[[str], bytes]
    terminator: Callable[[], bytes]
    keepalive: Callable[[], bytes]


PROVIDER_BUILDERS = {
    "anthropic": StreamBuilders(
        text_delta=emit_anthropic_text_delta,
        terminator=emit_anthropic_message_stop,
        keepalive=_sse_keepalive_anthropic,
    ),
    "openai-chat": StreamBuilders(
        text_delta=emit_openai_chat_text_delta,
        terminator=emit_openai_chat_stop,
        keepalive=_sse_keepalive_openai,
    ),
    "openai-responses": StreamBuilders(
        text_delta=emit_openai_responses_text_delta,
        terminator=emit_openai_responses_complete,
        keepalive=_sse_keepalive_openai,
    ),
    "google": StreamBuilders(
        text_delta=emit_google_text_delta,
        terminator=emit_google_stop,
        keepalive=_sse_keepalive_google,
    ),
}


def build_stream(provider: str, tokens: Iterable[str], *,
                 keepalive_count: int = 0,
                 emit_terminator: bool = True) -> bytes:
    """Produce a complete SSE byte stream for the given provider.

    ``keepalive_count`` interleaves N keepalive frames at the START of
    the stream (used by first_token_deadline fixtures to simulate a
    server emitting keepalives but no content)."""
    if provider not in PROVIDER_BUILDERS:
        raise ValueError(f"unknown provider: {provider}")
    builder = PROVIDER_BUILDERS[provider]

    out = bytearray()
    for _ in range(keepalive_count):
        out.extend(builder.keepalive())
    for tok in tokens:
        out.extend(builder.text_delta(tok))
    if emit_terminator:
        out.extend(builder.terminator())
    return bytes(out)


# ---------------------------------------------------------------------------
# Scenario specs (SDD §6.1 table)
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class Scenario:
    name: str
    description: str
    tokens: tuple  # tuple of strings (logical token sequence)
    keepalive_count: int
    emit_terminator: bool
    expected_triggered: bool
    expected_reason: Optional[str]
    expected_tokens_before_abort: Optional[int]
    reasoning_class: bool
    notes: str = ""


# Per SDD §6.1: "the first 200 tokens" + "501 tokens of CoT" — the
# library's empty_content_window default is 200 and cot_budget default
# is 500. Fixtures use the SDD-stated values verbatim.

SCENARIOS: tuple = (
    Scenario(
        name="healthy-short",
        description="20 tokens starting with `## Findings\\n` (structured-answer marker).",
        tokens=tuple(["## Findings\n"] + [f"Token {i}" for i in range(2, 21)]),
        keepalive_count=0,
        emit_terminator=True,
        expected_triggered=False,
        expected_reason=None,
        expected_tokens_before_abort=None,
        reasoning_class=False,
    ),
    Scenario(
        name="healthy-cot-then-answer",
        description=(
            "100 CoT tokens (`thinking about this...`), then `</thinking>` "
            "close + `## Finding 1:` structured-answer marker."
        ),
        tokens=(
            tuple([f"thinking about this step {i}\n" for i in range(1, 100)])
            + ("</thinking>", "## Finding 1: ", "subject matter here")
        ),
        keepalive_count=0,
        emit_terminator=True,
        expected_triggered=False,
        expected_reason=None,
        expected_tokens_before_abort=None,
        reasoning_class=True,  # CoT scenario only meaningful for reasoning-class
    ),
    Scenario(
        name="abort-first-token-deadline",
        description=(
            "NO tokens; only keepalives until injected t>=31s past start. "
            "Test harness must advance `time.monotonic()` past "
            "first_token_deadline_s (30.0 default for non-reasoning)."
        ),
        tokens=(),
        keepalive_count=5,  # 5 keepalive frames; test injects elapsed time
        emit_terminator=False,  # no terminator — stream stalls forever
        expected_triggered=True,
        expected_reason="first_token_deadline",
        expected_tokens_before_abort=0,
        reasoning_class=False,
        notes=(
            "Test harness MUST inject now_s >= start_time_s + 30.0 between "
            "calls to check_deadline() to reproduce the abort. The fixture "
            "bytes alone do not encode time progression."
        ),
    ),
    Scenario(
        name="abort-empty-content-window",
        description=(
            "201 tokens of pure whitespace text deltas, no CoT prefix; "
            "first 200 tokens trigger empty_content_window."
        ),
        # 200 whitespace tokens to fill the window. The 201st would also
        # be whitespace but the tracker aborts at token 200, so it's
        # never reached.
        tokens=tuple([" " for _ in range(201)]),
        keepalive_count=0,
        emit_terminator=False,  # parser aborts before terminator
        expected_triggered=True,
        expected_reason="empty_content_window",
        expected_tokens_before_abort=200,
        reasoning_class=False,
    ),
    Scenario(
        name="abort-cot-budget-exhausted",
        description=(
            "501 tokens of CoT-shaped prose (`thinking ...`) with no "
            "structured-answer marker; reasoning-class triggers "
            "cot_budget_exhausted at token 501."
        ),
        tokens=tuple([f"thinking about step {i}\n" for i in range(1, 502)]),
        keepalive_count=0,
        emit_terminator=False,  # parser aborts before terminator
        expected_triggered=True,
        expected_reason="cot_budget_exhausted",
        expected_tokens_before_abort=501,
        reasoning_class=True,
    ),
    Scenario(
        name="abort-cot-budget-non-reasoning",
        description=(
            "501 tokens of CoT-shaped prose with reasoning_class=False; "
            "CoT-budget enforcement is reasoning-only, so this PROCEEDS "
            "(per recovery.py:219-228 — `if self.config.reasoning_class`)."
        ),
        tokens=tuple([f"thinking about step {i}\n" for i in range(1, 502)]),
        keepalive_count=0,
        emit_terminator=True,
        expected_triggered=False,
        expected_reason=None,
        expected_tokens_before_abort=None,
        reasoning_class=False,
        notes=(
            "Mirror of abort-cot-budget-exhausted with reasoning_class flipped. "
            "Confirms the library's reasoning-class-gated CoT-budget design "
            "(I-4: cross-provider behavior identical modulo reasoning_class)."
        ),
    ),
)


# ---------------------------------------------------------------------------
# File emission
# ---------------------------------------------------------------------------


PROVIDERS = ("anthropic", "openai-chat", "openai-responses", "google")


def fixture_path(out_dir: Path, scenario: str, provider: str) -> Path:
    return out_dir / f"{scenario}.{provider}.sse"


def expected_path(out_dir: Path, scenario: str) -> Path:
    return out_dir / f"{scenario}.expected.json"


def write_scenario(out_dir: Path, scenario: Scenario,
                   providers: Iterable[str]) -> List[Path]:
    """Emit fixtures + expected-result JSON for ``scenario`` across
    ``providers``. Returns list of written paths."""
    written: List[Path] = []

    for provider in providers:
        data = build_stream(
            provider,
            scenario.tokens,
            keepalive_count=scenario.keepalive_count,
            emit_terminator=scenario.emit_terminator,
        )
        p = fixture_path(out_dir, scenario.name, provider)
        p.write_bytes(data)
        written.append(p)

    # Expected result is provider-independent (the whole point of the
    # parity test is that all providers reach the same decision).
    expected = {
        "name": scenario.name,
        "description": scenario.description,
        "reasoning_class": scenario.reasoning_class,
        "expected": {
            "triggered": scenario.expected_triggered,
            "reason": scenario.expected_reason,
            "tokens_before_abort": scenario.expected_tokens_before_abort,
        },
        "notes": scenario.notes,
    }
    ep = expected_path(out_dir, scenario.name)
    ep.write_text(
        json.dumps(expected, sort_keys=True, indent=2) + "\n",
        encoding="utf-8",
    )
    written.append(ep)

    return written


def emit_all(out_dir: Path, providers: Iterable[str]) -> List[Path]:
    out_dir.mkdir(parents=True, exist_ok=True)
    written: List[Path] = []
    for scenario in SCENARIOS:
        written.extend(write_scenario(out_dir, scenario, providers))
    return written


# ---------------------------------------------------------------------------
# Idempotency self-test
# ---------------------------------------------------------------------------


def check_idempotency(out_dir: Path, providers: Iterable[str]) -> bool:
    """Verify re-running the generator produces byte-identical output
    (cycle-099 sprint-1D parity-test precedent — determinism is the
    parity-test's load-bearing invariant)."""
    import hashlib
    import tempfile

    providers = list(providers)

    # Hash current on-disk fixtures.
    expected_hashes: dict = {}
    if out_dir.exists():
        for scenario in SCENARIOS:
            for provider in providers:
                p = fixture_path(out_dir, scenario.name, provider)
                if p.exists():
                    expected_hashes[p.name] = hashlib.sha256(p.read_bytes()).hexdigest()
            ep = expected_path(out_dir, scenario.name)
            if ep.exists():
                expected_hashes[ep.name] = hashlib.sha256(ep.read_bytes()).hexdigest()

    # Re-emit into a temp directory and compare hashes.
    with tempfile.TemporaryDirectory() as tmp_root:
        tmp = Path(tmp_root) / "regen"
        emit_all(tmp, providers)
        ok = True
        for path in sorted(tmp.iterdir()):
            actual = hashlib.sha256(path.read_bytes()).hexdigest()
            expected = expected_hashes.get(path.name)
            if expected is None:
                print(f"  [NEW]      {path.name} (no on-disk version)")
            elif expected != actual:
                print(f"  [DIVERGED] {path.name}")
                print(f"    on-disk: {expected}")
                print(f"    regen:   {actual}")
                ok = False
            else:
                print(f"  [OK]       {path.name}")
    return ok


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


DEFAULT_OUT_DIR = Path(__file__).resolve().parent


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        description="cycle-113 streaming-parity fixture generator (SDD §6.3)",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_OUT_DIR,
        help="Output directory (default: this script's directory)",
    )
    parser.add_argument(
        "--provider",
        nargs="+",
        choices=PROVIDERS,
        default=PROVIDERS,
        help="Subset of providers to emit (default: all 4)",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Idempotency self-test: re-emit and compare to existing files",
    )
    parser.add_argument(
        "--list-scenarios",
        action="store_true",
        help="List scenarios + expected results; emit nothing",
    )
    args = parser.parse_args(argv)

    if args.list_scenarios:
        for s in SCENARIOS:
            print(f"{s.name}: reasoning_class={s.reasoning_class}")
            print(f"  description: {s.description}")
            print(
                f"  expected: triggered={s.expected_triggered} "
                f"reason={s.expected_reason} "
                f"tokens={s.expected_tokens_before_abort}"
            )
            if s.notes:
                print(f"  notes: {s.notes}")
        return 0

    if args.check:
        ok = check_idempotency(args.output, args.provider)
        return 0 if ok else 1

    written = emit_all(args.output, args.provider)
    print(f"Emitted {len(written)} files under {args.output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
