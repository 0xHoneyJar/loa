"""cycle-103 sprint-2 T2.1 — offline unit tests for the trial-result classifier.

These tests do NOT require API access. They exercise the pure-function
disposition logic of `classifier.py` so the AC-2.1 decision rule
("≥80% full_content at safe threshold") is mechanically pinned.

Run: pytest tests/replay/test_classifier.py -v
"""

from __future__ import annotations

import pytest

from tests.replay.classifier import (
    ClassificationResult,
    TrialOutcome,
    classify_trial,
    classify_replay_run,
    classify_matrix,
    find_safe_threshold,
)


# ----------------------------------------------------------------------------
# classify_trial — single-trial outcome
# ----------------------------------------------------------------------------


class TestClassifyTrial:
    def test_none_content_is_empty(self) -> None:
        assert classify_trial(None) == TrialOutcome.EMPTY

    def test_empty_string_is_empty(self) -> None:
        assert classify_trial("") == TrialOutcome.EMPTY

    def test_whitespace_only_is_empty(self) -> None:
        assert classify_trial("   \n\t  ") == TrialOutcome.EMPTY

    def test_short_content_with_keyword_is_partial(self) -> None:
        # "Below 50 visible tokens" → PARTIAL even if keyword present.
        # 50 tokens × 4 chars/token ≈ 200 chars threshold.
        short_with_kw = "cycle-103 was great."  # ~5 tokens
        assert classify_trial(short_with_kw) == TrialOutcome.PARTIAL

    def test_long_content_without_keyword_is_partial(self) -> None:
        # Long, but doesn't engage with seed content → PARTIAL (likely a
        # generic refusal or unrelated hallucination).
        long_off_topic = "a" * 500  # ~125 visible tokens
        assert classify_trial(long_off_topic) == TrialOutcome.PARTIAL

    def test_long_content_with_keyword_is_full(self) -> None:
        long_on_topic = (
            "The cycle-103 unification collapses three Node-side HTTP "
            "boundaries into one Python substrate at cheval. The M1, M2, "
            "and M3 cycle-exit invariants are all met. "
            "More architectural detail follows. " * 5
        )
        assert classify_trial(long_on_topic) == TrialOutcome.FULL

    def test_keyword_match_is_case_insensitive(self) -> None:
        long_uppercase = (
            "CYCLE-103 UNIFIES THE BOUNDARIES. " * 10
            + "Additional context to push token count above threshold. "
            * 5
        )
        # Make sure we cross the visible-token threshold first.
        assert len(long_uppercase) >= 200
        assert classify_trial(long_uppercase) == TrialOutcome.FULL

    @pytest.mark.parametrize(
        "keyword",
        ["cycle-103", "M1", "M2", "M3", "cheval", "delegate", "unification"],
    )
    def test_each_documented_keyword_qualifies(self, keyword: str) -> None:
        content = (
            f"Detailed technical writeup mentioning {keyword} and related "
            "architectural shifts. " * 10
        )
        assert classify_trial(content) == TrialOutcome.FULL


# ----------------------------------------------------------------------------
# classify_replay_run — n-trial aggregation
# ----------------------------------------------------------------------------


class TestClassifyReplayRun:
    def test_all_full_is_viable(self) -> None:
        result = classify_replay_run(30_000, [TrialOutcome.FULL] * 5)
        assert result.full == 5
        assert result.full_rate == 1.0
        assert result.structural_fix_viable is True

    def test_four_of_five_full_is_viable(self) -> None:
        # 4/5 = 0.80 — at the threshold.
        outcomes = [TrialOutcome.FULL] * 4 + [TrialOutcome.EMPTY]
        result = classify_replay_run(40_000, outcomes)
        assert result.full_rate == 0.80
        assert result.structural_fix_viable is True

    def test_three_of_five_full_is_not_viable(self) -> None:
        outcomes = [TrialOutcome.FULL] * 3 + [TrialOutcome.EMPTY] * 2
        result = classify_replay_run(40_000, outcomes)
        assert result.full_rate == 0.60
        assert result.structural_fix_viable is False

    def test_all_empty_is_not_viable(self) -> None:
        result = classify_replay_run(80_000, [TrialOutcome.EMPTY] * 5)
        assert result.full_rate == 0.0
        assert result.structural_fix_viable is False

    def test_mixed_outcomes_counted_correctly(self) -> None:
        outcomes = [
            TrialOutcome.FULL,
            TrialOutcome.PARTIAL,
            TrialOutcome.EMPTY,
            TrialOutcome.FULL,
            TrialOutcome.EMPTY,
        ]
        result = classify_replay_run(50_000, outcomes)
        assert result.full == 2
        assert result.partial == 1
        assert result.empty == 2
        assert result.trial_count == 5
        assert result.full_rate == 0.40
        assert result.structural_fix_viable is False

    def test_empty_outcomes_raises(self) -> None:
        with pytest.raises(ValueError, match="at least one trial"):
            classify_replay_run(30_000, [])

    def test_minimum_5_trials_is_AC_compliant(self) -> None:
        # AC-2.1 says n>=5. The classifier doesn't enforce this (it
        # computes a rate for any non-empty count) but documents the
        # AC mapping.
        result = classify_replay_run(30_000, [TrialOutcome.FULL] * 5)
        assert result.trial_count == 5


# ----------------------------------------------------------------------------
# classify_matrix — multi-size aggregation
# ----------------------------------------------------------------------------


class TestClassifyMatrix:
    def test_orders_by_input_size(self) -> None:
        raw = {
            80_000: [TrialOutcome.EMPTY] * 5,
            30_000: [TrialOutcome.FULL] * 5,
            50_000: [TrialOutcome.FULL] * 3 + [TrialOutcome.EMPTY] * 2,
        }
        matrix = classify_matrix(raw)
        assert list(matrix.keys()) == [30_000, 50_000, 80_000]

    def test_each_size_classified_independently(self) -> None:
        raw = {
            30_000: [TrialOutcome.FULL] * 5,
            40_000: [TrialOutcome.FULL] * 4 + [TrialOutcome.EMPTY],
            80_000: [TrialOutcome.EMPTY] * 5,
        }
        matrix = classify_matrix(raw)
        assert matrix[30_000].structural_fix_viable is True
        assert matrix[40_000].structural_fix_viable is True
        assert matrix[80_000].structural_fix_viable is False


# ----------------------------------------------------------------------------
# find_safe_threshold — operational ceiling for max_input_tokens
# ----------------------------------------------------------------------------


class TestFindSafeThreshold:
    def test_returns_largest_viable_size(self) -> None:
        matrix = classify_matrix(
            {
                30_000: [TrialOutcome.FULL] * 5,
                40_000: [TrialOutcome.FULL] * 5,
                50_000: [TrialOutcome.FULL] * 4 + [TrialOutcome.EMPTY],
                60_000: [TrialOutcome.FULL] * 2 + [TrialOutcome.EMPTY] * 3,
                80_000: [TrialOutcome.EMPTY] * 5,
            }
        )
        # 30K, 40K, 50K all viable; 60K + 80K not. Threshold = 50K.
        assert find_safe_threshold(matrix) == 50_000

    def test_no_viable_size_returns_none(self) -> None:
        # Vendor-side path: nothing crosses 80% at any size.
        matrix = classify_matrix(
            {
                30_000: [TrialOutcome.PARTIAL] * 5,
                40_000: [TrialOutcome.EMPTY] * 5,
                80_000: [TrialOutcome.EMPTY] * 5,
            }
        )
        assert find_safe_threshold(matrix) is None

    def test_all_viable_returns_max_size(self) -> None:
        # Best-case outcome: model works at every size — apply a generous
        # ceiling but still cap at the max we measured.
        matrix = classify_matrix(
            {size: [TrialOutcome.FULL] * 5 for size in (30_000, 40_000, 50_000, 60_000, 80_000)}
        )
        assert find_safe_threshold(matrix) == 80_000


# ----------------------------------------------------------------------------
# ClassificationResult invariant
# ----------------------------------------------------------------------------


class TestClassificationResultInvariant:
    def test_count_mismatch_raises(self) -> None:
        with pytest.raises(ValueError, match="trial_count"):
            ClassificationResult(
                input_tokens=30_000,
                trial_count=5,
                empty=0,
                partial=0,
                full=3,  # Doesn't sum to trial_count.
                full_rate=0.6,
                structural_fix_viable=False,
            )
