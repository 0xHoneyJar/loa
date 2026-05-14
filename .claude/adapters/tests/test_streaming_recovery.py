"""cycle-109 Sprint 4 T4.6 — streaming-with-recovery tests (IMP-014).

Three thresholds:
  1. first_token_deadline_s — abort if no token within N seconds.
  2. empty_content_window_tokens — abort if first N tokens all empty.
  3. cot_budget_tokens — abort if reasoning-class spends >N tokens on CoT.
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))


# ---------------------------------------------------------------------------
# StreamingRecoveryConfig
# ---------------------------------------------------------------------------


def test_default_config_uses_30s_first_token_deadline_for_non_reasoning():
    from loa_cheval.streaming import StreamingRecoveryConfig

    cfg = StreamingRecoveryConfig.for_model({}, reasoning_class=False)
    assert cfg.first_token_deadline_s == 30.0


def test_default_config_uses_60s_first_token_deadline_for_reasoning():
    from loa_cheval.streaming import StreamingRecoveryConfig

    cfg = StreamingRecoveryConfig.for_model({}, reasoning_class=True)
    assert cfg.first_token_deadline_s == 60.0


def test_default_config_empty_content_window_200_tokens():
    from loa_cheval.streaming import StreamingRecoveryConfig

    cfg = StreamingRecoveryConfig.for_model({})
    assert cfg.empty_content_window_tokens == 200


def test_default_config_cot_budget_500_tokens():
    from loa_cheval.streaming import StreamingRecoveryConfig

    cfg = StreamingRecoveryConfig.for_model({})
    assert cfg.cot_budget_tokens == 500


def test_model_config_yaml_overrides_defaults():
    from loa_cheval.streaming import StreamingRecoveryConfig

    cfg = StreamingRecoveryConfig.for_model({
        "streaming_recovery": {
            "first_token_deadline_s": 15,
            "empty_content_window_tokens": 100,
            "cot_budget_tokens": 1000,
        },
    })
    assert cfg.first_token_deadline_s == 15.0
    assert cfg.empty_content_window_tokens == 100
    assert cfg.cot_budget_tokens == 1000


# ---------------------------------------------------------------------------
# Threshold 1: first_token_deadline_s
# ---------------------------------------------------------------------------


def test_first_token_deadline_fires_after_elapsed():
    from loa_cheval.streaming import StreamingRecoveryConfig, StreamingRecoveryTracker

    cfg = StreamingRecoveryConfig(first_token_deadline_s=5.0)
    tracker = StreamingRecoveryTracker(config=cfg, start_time_s=100.0)

    # 4s elapsed: proceed
    decision = tracker.check_deadline(now_s=104.0)
    assert decision.abort is False

    # 6s elapsed: abort
    decision = tracker.check_deadline(now_s=106.0)
    assert decision.abort is True
    assert decision.reason == "first_token_deadline"
    assert decision.tokens_before_abort == 0


def test_first_token_deadline_does_not_fire_after_first_token():
    from loa_cheval.streaming import StreamingRecoveryConfig, StreamingRecoveryTracker

    cfg = StreamingRecoveryConfig(first_token_deadline_s=5.0)
    tracker = StreamingRecoveryTracker(config=cfg, start_time_s=100.0)
    tracker.on_token("hello", now_s=102.0)
    # Even at t=200s, no first-token-deadline abort because the first
    # token already arrived
    decision = tracker.check_deadline(now_s=200.0)
    assert decision.abort is False


# ---------------------------------------------------------------------------
# Threshold 2: empty_content_window
# ---------------------------------------------------------------------------


def test_empty_content_window_fires_when_first_N_tokens_empty():
    from loa_cheval.streaming import StreamingRecoveryConfig, StreamingRecoveryTracker

    cfg = StreamingRecoveryConfig(empty_content_window_tokens=5)
    tracker = StreamingRecoveryTracker(config=cfg, start_time_s=0.0)
    # First 4 empty tokens — proceed
    for _ in range(4):
        d = tracker.on_token("   ", now_s=1.0)
        assert d.abort is False
    # 5th empty token → abort
    d = tracker.on_token("", now_s=1.0)
    assert d.abort is True
    assert d.reason == "empty_content_window"
    assert d.tokens_before_abort == 5


def test_empty_content_window_does_not_fire_when_visible_content_arrives():
    from loa_cheval.streaming import StreamingRecoveryConfig, StreamingRecoveryTracker

    cfg = StreamingRecoveryConfig(empty_content_window_tokens=5)
    tracker = StreamingRecoveryTracker(config=cfg, start_time_s=0.0)
    # First 3 empty
    for _ in range(3):
        tracker.on_token(" ", now_s=1.0)
    # Visible content
    d = tracker.on_token("Hello, world!", now_s=1.0)
    assert d.abort is False
    # Now even more empty tokens past the window don't abort
    for _ in range(20):
        d = tracker.on_token("", now_s=1.0)
        assert d.abort is False


# ---------------------------------------------------------------------------
# Threshold 3: cot_budget (reasoning-class only)
# ---------------------------------------------------------------------------


def test_cot_budget_fires_for_reasoning_class_after_runaway():
    from loa_cheval.streaming import StreamingRecoveryConfig, StreamingRecoveryTracker

    cfg = StreamingRecoveryConfig(
        cot_budget_tokens=5,
        empty_content_window_tokens=999,  # disable empty-window
        reasoning_class=True,
    )
    tracker = StreamingRecoveryTracker(config=cfg, start_time_s=0.0)
    # CoT-shaped tokens (matches the regex)
    for _ in range(5):
        d = tracker.on_token("thinking about it... ", now_s=1.0)
        assert d.abort is False
    # 6th CoT token → exceeds budget
    d = tracker.on_token("more thinking", now_s=1.0)
    assert d.abort is True
    assert d.reason == "cot_budget_exhausted"


def test_cot_budget_does_not_fire_for_non_reasoning_class():
    """Non-reasoning models can emit as much CoT-shaped content as
    they want — the budget is only enforced on reasoning-class."""
    from loa_cheval.streaming import StreamingRecoveryConfig, StreamingRecoveryTracker

    cfg = StreamingRecoveryConfig(
        cot_budget_tokens=5,
        empty_content_window_tokens=999,
        reasoning_class=False,  # NOT reasoning
    )
    tracker = StreamingRecoveryTracker(config=cfg, start_time_s=0.0)
    for _ in range(100):
        d = tracker.on_token("thinking ", now_s=1.0)
        assert d.abort is False


def test_cot_budget_does_not_fire_when_visible_content_arrives():
    from loa_cheval.streaming import StreamingRecoveryConfig, StreamingRecoveryTracker

    cfg = StreamingRecoveryConfig(
        cot_budget_tokens=5,
        empty_content_window_tokens=999,
        reasoning_class=True,
    )
    tracker = StreamingRecoveryTracker(config=cfg, start_time_s=0.0)
    # 3 CoT tokens
    for _ in range(3):
        tracker.on_token("thinking ", now_s=1.0)
    # Visible content
    tracker.on_token("Actual answer: 42", now_s=1.0)
    # 1000 more tokens, no abort
    for _ in range(1000):
        d = tracker.on_token("more content", now_s=1.0)
        assert d.abort is False


# ---------------------------------------------------------------------------
# CoT detection regex
# ---------------------------------------------------------------------------


def test_cot_thinking_tag_detected():
    """<thinking> opening tag triggers CoT detection."""
    from loa_cheval.streaming import StreamingRecoveryConfig, StreamingRecoveryTracker

    cfg = StreamingRecoveryConfig(
        cot_budget_tokens=2,
        empty_content_window_tokens=999,
        reasoning_class=True,
    )
    tracker = StreamingRecoveryTracker(config=cfg, start_time_s=0.0)
    tracker.on_token("<thinking>", now_s=1.0)
    tracker.on_token("<thinking>", now_s=1.0)
    d = tracker.on_token("<thinking>", now_s=1.0)
    assert d.abort is True
    assert d.reason == "cot_budget_exhausted"


def test_cot_prose_prefixes_detected():
    """Common CoT prose prefixes (thinking / let me / i'll / first I)
    trigger CoT detection. Word-boundary anchored — matches at start
    OR after whitespace anywhere in the token (continuation tokens
    like 'more thinking' should still match). Negative control: real
    content does NOT match."""
    from loa_cheval.streaming.recovery import _COT_PROSE_RE

    # Positive — start-anchored
    assert _COT_PROSE_RE.search("thinking about this...")
    assert _COT_PROSE_RE.search("Let me consider")
    assert _COT_PROSE_RE.search("I'll start by")
    assert _COT_PROSE_RE.search("First, I will")
    # Positive — continuation (word-boundary inside token)
    assert _COT_PROSE_RE.search("more thinking about it")
    # Negative — real content
    assert not _COT_PROSE_RE.search("The answer is 42")
    assert not _COT_PROSE_RE.search("BLOCKER: shell-injection")
    assert not _COT_PROSE_RE.search("def hello():")
    assert not _COT_PROSE_RE.search("Actual answer: 42")


# ---------------------------------------------------------------------------
# Decision shape
# ---------------------------------------------------------------------------


def test_decision_proceed_factory():
    from loa_cheval.streaming import StreamingRecoveryDecision

    d = StreamingRecoveryDecision.proceed()
    assert d.abort is False
    assert d.reason is None
    assert d.tokens_before_abort is None


def test_decision_abort_with_factory():
    from loa_cheval.streaming import StreamingRecoveryDecision

    d = StreamingRecoveryDecision.abort_with("first_token_deadline", tokens=0)
    assert d.abort is True
    assert d.reason == "first_token_deadline"
    assert d.tokens_before_abort == 0
