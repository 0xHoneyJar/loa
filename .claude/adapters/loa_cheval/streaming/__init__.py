"""cycle-109 Sprint 4 T4.6 — streaming-with-recovery thresholds (IMP-014).

Three thresholds detect stream pathologies and abort with typed exit
codes per SDD §5.4.4:

  1. first_token_deadline_s — abort if no token arrives within N seconds
     (default 30s; 60s for reasoning-class models that emit longer
     pre-content thinking).
  2. empty_content_window_tokens — abort if the first N tokens are all
     empty/whitespace (default 200; KF-002 class detection — a model
     that emits empty content is producing nothing useful).
  3. cot_budget_tokens — abort if reasoning-class model spends more
     than N tokens on Chain-of-Thought before any visible content
     (default 500 for reasoning-class; not enforced on non-reasoning).
     CoT detection: regex on emitted text matches `^(thinking|let me|
     i'll|first[,]?\\s+i)` OR `<thinking>` opening tag.

All thresholds are configurable per-model via:
  model-config.yaml::providers.<p>.models.<m>.streaming_recovery.{
    first_token_deadline_s, empty_content_window_tokens, cot_budget_tokens
  }
"""

from .recovery import (
    StreamingRecoveryConfig,
    StreamingRecoveryDecision,
    StreamingRecoveryReason,
    StreamingRecoveryTracker,
    DEFAULT_FIRST_TOKEN_DEADLINE_S,
    DEFAULT_FIRST_TOKEN_DEADLINE_REASONING_S,
    DEFAULT_EMPTY_CONTENT_WINDOW_TOKENS,
    DEFAULT_COT_BUDGET_TOKENS,
)


__all__ = [
    "StreamingRecoveryConfig",
    "StreamingRecoveryDecision",
    "StreamingRecoveryReason",
    "StreamingRecoveryTracker",
    "DEFAULT_FIRST_TOKEN_DEADLINE_S",
    "DEFAULT_FIRST_TOKEN_DEADLINE_REASONING_S",
    "DEFAULT_EMPTY_CONTENT_WINDOW_TOKENS",
    "DEFAULT_COT_BUDGET_TOKENS",
]
