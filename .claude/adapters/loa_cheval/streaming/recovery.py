"""cycle-109 Sprint 4 T4.6 — streaming-with-recovery tracker.

Per SDD §5.4.4 IMP-014. Three thresholds — first_token_deadline,
empty_content_window, cot_budget — detect stream pathologies and emit
typed abort decisions.

The tracker is stream-position-aware: callers feed it tokens as they
arrive (or call ``check_deadline`` periodically while waiting). The
tracker returns a decision when one of the thresholds fires.

Pure module — no I/O, no global state. Time is passed in via
``now_s`` (test injection avoids real wall-clock dependency).
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import Optional


# ---------------------------------------------------------------------------
# Defaults (operator-overridable via model-config.yaml)
# ---------------------------------------------------------------------------

DEFAULT_FIRST_TOKEN_DEADLINE_S = 30.0
"""Standard non-reasoning model default: 30 seconds without a token →
abort. Tightened on networks where 30s is plenty."""

DEFAULT_FIRST_TOKEN_DEADLINE_REASONING_S = 60.0
"""Reasoning-class model default: 60 seconds. Reasoning models emit a
longer pre-content thinking block; the deadline is correspondingly
relaxed."""

DEFAULT_EMPTY_CONTENT_WINDOW_TOKENS = 200
"""KF-002 class detection: if the first 200 tokens are all empty or
pure whitespace, the stream has bottomed out and we abort to surface
the failure to the operator."""

DEFAULT_COT_BUDGET_TOKENS = 500
"""Reasoning-class CoT budget: model is allowed up to 500 tokens of
thinking before any visible content; beyond that, the stream has
runaway-CoT-without-content and we abort."""


# CoT detection patterns — match the model's pre-content
# "thinking out loud" / scratchpad emission. Cased per common shapes
# the major providers produce (Anthropic <thinking>, OpenAI inline
# narration, Gemini prefix narration). Word-boundary anchored on
# either start-of-token OR whitespace so continuation tokens like
# "more thinking" stay in CoT mode, but a transition into structured
# output (JSON, markdown, severity markers) flips visible-content.
_COT_PROSE_RE = re.compile(
    r"(?:^|\s)(?:thinking|let me|i'?ll|first[,]?\s+i)\b",
    re.IGNORECASE,
)
_COT_TAG_RE = re.compile(r"<thinking>", re.IGNORECASE)

# Structured-answer markers — when these appear in a token, the model
# has transitioned out of CoT mode into actual content emission. Cased
# for canonical shapes used by review/audit/red-team outputs.
_ANSWER_MARKER_RES = (
    re.compile(r"^\s*\{"),                              # JSON object opener
    re.compile(r"^\s*\["),                              # JSON array opener
    re.compile(r"^\s*##"),                              # markdown heading
    re.compile(r"^\s*[A-Z][A-Z_]{2,}\s*:"),             # SEVERITY: / BLOCKER: / etc.
    re.compile(r"^\s*```"),                             # code fence
    re.compile(r"</thinking>", re.IGNORECASE),          # explicit CoT close
)


# ---------------------------------------------------------------------------
# Decision types
# ---------------------------------------------------------------------------

StreamingRecoveryReason = str  # "first_token_deadline" / "empty_content_window" / "cot_budget_exhausted"


@dataclass
class StreamingRecoveryConfig:
    """Per-call config; populated from model-config.yaml per-model
    ``streaming_recovery`` block."""

    first_token_deadline_s: float = DEFAULT_FIRST_TOKEN_DEADLINE_S
    empty_content_window_tokens: int = DEFAULT_EMPTY_CONTENT_WINDOW_TOKENS
    cot_budget_tokens: int = DEFAULT_COT_BUDGET_TOKENS
    reasoning_class: bool = False
    """When True, first_token_deadline_s defaults to 60s and cot_budget
    enforcement is enabled. Non-reasoning calls skip CoT-budget."""

    @classmethod
    def for_model(cls, model_data: dict, reasoning_class: bool = False) -> "StreamingRecoveryConfig":
        """Build a config from a model-config.yaml model entry's
        ``streaming_recovery`` sub-block. Falls back to defaults."""
        sr = (model_data or {}).get("streaming_recovery") or {}
        first_deadline = sr.get(
            "first_token_deadline_s",
            DEFAULT_FIRST_TOKEN_DEADLINE_REASONING_S if reasoning_class
            else DEFAULT_FIRST_TOKEN_DEADLINE_S,
        )
        return cls(
            first_token_deadline_s=float(first_deadline),
            empty_content_window_tokens=int(sr.get(
                "empty_content_window_tokens",
                DEFAULT_EMPTY_CONTENT_WINDOW_TOKENS,
            )),
            cot_budget_tokens=int(sr.get(
                "cot_budget_tokens",
                DEFAULT_COT_BUDGET_TOKENS,
            )),
            reasoning_class=reasoning_class,
        )


@dataclass
class StreamingRecoveryDecision:
    """Output of the tracker: whether to abort + why + observability."""

    abort: bool
    reason: Optional[StreamingRecoveryReason] = None
    tokens_before_abort: Optional[int] = None

    @classmethod
    def proceed(cls) -> "StreamingRecoveryDecision":
        return cls(abort=False)

    @classmethod
    def abort_with(
        cls, reason: StreamingRecoveryReason, tokens: int,
    ) -> "StreamingRecoveryDecision":
        return cls(abort=True, reason=reason, tokens_before_abort=tokens)


# ---------------------------------------------------------------------------
# Tracker — feed tokens as they arrive
# ---------------------------------------------------------------------------


@dataclass
class StreamingRecoveryTracker:
    """Stateful per-stream tracker. Initialize with config + start_time_s,
    then call ``on_token(text, now_s)`` for each token / ``check_deadline(now_s)``
    while waiting."""

    config: StreamingRecoveryConfig
    start_time_s: float
    tokens_seen: int = 0
    first_token_time_s: Optional[float] = None
    visible_content_seen: bool = False
    cot_prefix_buffer: str = ""

    def check_deadline(self, now_s: float) -> StreamingRecoveryDecision:
        """Call periodically while waiting for the first token. Returns
        abort decision if first_token_deadline elapsed without a token."""
        if self.first_token_time_s is not None:
            return StreamingRecoveryDecision.proceed()
        elapsed = now_s - self.start_time_s
        if elapsed >= self.config.first_token_deadline_s:
            return StreamingRecoveryDecision.abort_with(
                "first_token_deadline", tokens=0,
            )
        return StreamingRecoveryDecision.proceed()

    def on_token(self, text: str, now_s: float) -> StreamingRecoveryDecision:
        """Feed one token (or token-batch) of text. Returns abort
        decision when one of the empty-content or CoT-budget thresholds
        fires.

        State machine:
          - `visible_content_seen` starts False.
          - First non-empty token: if it matches CoT-prefix regex →
            engage CoT mode (in_cot_mode=True); else visible_content_seen=True.
          - Once in CoT mode: subsequent tokens stay in CoT until a
            structured-answer marker appears (JSON/array opener, ##
            heading, SEVERITY: marker, ``` fence, </thinking>).
          - Empty-content window: first N tokens all empty AND no
            visible content → abort.
          - CoT budget (reasoning-class only): tokens emitted in CoT
            mode exceed budget → abort.
        """
        if self.first_token_time_s is None:
            self.first_token_time_s = now_s
        self.tokens_seen += 1

        is_empty = not text or text.strip() == ""

        # State transition logic — only when we haven't seen visible
        # content yet AND token is non-empty
        if not is_empty and not self.visible_content_seen:
            if self._looks_like_answer_marker(text):
                # Structured-answer marker — exit CoT, mark visible
                self.visible_content_seen = True
            elif self._looks_like_cot(text):
                # CoT-shaped token (start OR continuation containing
                # thinking/let me/i'll/first I or <thinking>) —
                # accumulate into CoT buffer
                self.cot_prefix_buffer += text
            else:
                # Non-empty, not CoT, not structured marker — treat as
                # visible content (e.g., bare prose answer like
                # "Actual answer: 42")
                self.visible_content_seen = True

        # Empty-content window: first N tokens all empty/CoT-only → abort
        if (
            not self.visible_content_seen
            and self.tokens_seen >= self.config.empty_content_window_tokens
            and not self.cot_prefix_buffer
        ):
            return StreamingRecoveryDecision.abort_with(
                "empty_content_window",
                tokens=self.tokens_seen,
            )

        # CoT-budget: reasoning-class models that runaway-CoT without
        # visible content beyond budget → abort. We count TOKENS-IN-COT
        # rather than total tokens-seen so empty prefix doesn't trigger
        # this prematurely.
        if (
            self.config.reasoning_class
            and not self.visible_content_seen
            and self.cot_prefix_buffer
            and self.tokens_seen > self.config.cot_budget_tokens
        ):
            return StreamingRecoveryDecision.abort_with(
                "cot_budget_exhausted",
                tokens=self.tokens_seen,
            )

        return StreamingRecoveryDecision.proceed()

    def _looks_like_cot(self, text: str) -> bool:
        """True iff ``text`` contains a CoT-prefix word (word-boundary
        match anywhere in the token text)."""
        if _COT_TAG_RE.search(text):
            return True
        if _COT_PROSE_RE.search(text):
            return True
        return False

    def _looks_like_answer_marker(self, text: str) -> bool:
        """True iff ``text`` contains a structured-answer marker
        indicating the model has transitioned out of CoT into actual
        content emission."""
        for pat in _ANSWER_MARKER_RES:
            if pat.search(text):
                return True
        return False
