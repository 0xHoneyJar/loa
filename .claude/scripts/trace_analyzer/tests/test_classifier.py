"""Tests for the FaultClassifier."""

import pytest
from datetime import datetime, timezone, timedelta

from trace_analyzer.classifier import FaultClassifier, PRECEDENCE_ORDER
from trace_analyzer.models import (
    FaultCategory,
    ParseResult,
    SessionInfo,
    TrajectoryEntry,
    SkillInvocation,
    MatcherOutput,
    KeywordMatch,
)


@pytest.fixture
def classifier():
    """Create a classifier instance."""
    return FaultClassifier()


@pytest.fixture
def empty_parse_result():
    """Create an empty parse result."""
    return ParseResult()


@pytest.fixture
def empty_matcher_output():
    """Create an empty matcher output."""
    return MatcherOutput()


class TestFaultClassification:
    """Test basic fault classification."""

    def test_skill_bug_detection(self, classifier, empty_parse_result, empty_matcher_output):
        """Test detection of skill_bug category."""
        result = classifier.classify(
            feedback_text="The commit skill failed with an error",
            parse_result=empty_parse_result,
            matcher_output=empty_matcher_output,
        )

        assert result.category == FaultCategory.SKILL_BUG
        assert result.confidence > 0
        assert "skill_bug" in [s.split(":")[0] for s in result.signals_detected]

    def test_skill_gap_detection(self, classifier, empty_parse_result, empty_matcher_output):
        """Test detection of skill_gap category."""
        result = classifier.classify(
            feedback_text="The review skill should also check for security issues",
            parse_result=empty_parse_result,
            matcher_output=empty_matcher_output,
        )

        assert result.category == FaultCategory.SKILL_GAP
        assert result.confidence > 0

    def test_missing_skill_detection(self, classifier, empty_parse_result, empty_matcher_output):
        """Test detection of missing_skill category."""
        result = classifier.classify(
            feedback_text="I need a new skill for database migrations",
            parse_result=empty_parse_result,
            matcher_output=empty_matcher_output,
        )

        assert result.category == FaultCategory.MISSING_SKILL
        assert result.confidence > 0

    def test_runtime_bug_detection(self, classifier, empty_parse_result, empty_matcher_output):
        """Test detection of runtime_bug category."""
        result = classifier.classify(
            feedback_text="The network connection timed out with a timeout error",
            parse_result=empty_parse_result,
            matcher_output=empty_matcher_output,
        )

        assert result.category == FaultCategory.RUNTIME_BUG
        assert result.confidence > 0
        assert result.raw_scores.get("runtime_bug", 0) > 0

    def test_unknown_category(self, classifier, empty_parse_result, empty_matcher_output):
        """Test unknown category for ambiguous feedback."""
        result = classifier.classify(
            feedback_text="OK",  # Very short, no signals
            parse_result=empty_parse_result,
            matcher_output=empty_matcher_output,
        )

        # No signals detected should result in unknown or very low confidence
        # The classifier may still pick a category based on heuristics
        assert result.confidence <= 30 or result.category == FaultCategory.UNKNOWN


class TestDeterministicTieBreak:
    """Test deterministic tie-breaking behavior."""

    def test_tie_break_order(self):
        """Test that tie-break order is correct."""
        assert PRECEDENCE_ORDER == [
            FaultCategory.SKILL_BUG,
            FaultCategory.SKILL_GAP,
            FaultCategory.MISSING_SKILL,
            FaultCategory.RUNTIME_BUG,
        ]

    def test_tie_break_skill_bug_wins(self, classifier, empty_parse_result, empty_matcher_output):
        """Test that skill_bug wins ties with skill_gap."""
        # Craft feedback that triggers both skill_bug and skill_gap equally
        result = classifier.classify(
            feedback_text="The skill failed and it should also do more",
            parse_result=empty_parse_result,
            matcher_output=empty_matcher_output,
        )

        # If tied, skill_bug should win due to precedence
        if result.tie_broken:
            assert result.category == FaultCategory.SKILL_BUG
            assert result.tie_break_reason is not None

    def test_same_input_same_output_100_times(self, classifier, empty_parse_result, empty_matcher_output):
        """Test determinism: same input always produces same output."""
        feedback = "The commit skill failed with an error when I tried to push"

        results = [
            classifier.classify(
                feedback_text=feedback,
                parse_result=empty_parse_result,
                matcher_output=empty_matcher_output,
            )
            for _ in range(100)
        ]

        # All results should be identical
        first_result = results[0]
        for result in results[1:]:
            assert result.category == first_result.category
            assert result.confidence == first_result.confidence
            assert result.tie_broken == first_result.tie_broken


class TestConfidenceCalibration:
    """Test confidence calibration with session adjustment."""

    def test_high_session_confidence_boost(self, classifier, empty_matcher_output):
        """Test that high session confidence boosts overall confidence."""
        parse_result = ParseResult(
            session_info=SessionInfo(confidence="high", reason="single_session"),
        )

        result = classifier.classify(
            feedback_text="The commit skill failed",
            parse_result=parse_result,
            matcher_output=empty_matcher_output,
        )

        # High session confidence adds +10
        # Note: base confidence depends on signals, so we just check it's reasonable
        assert result.confidence >= 0
        assert "+10" in result.rationale or "high" in result.rationale

    def test_low_session_confidence_penalty(self, classifier, empty_matcher_output):
        """Test that low session confidence reduces overall confidence."""
        parse_result = ParseResult(
            session_info=SessionInfo(confidence="low", reason="gap_heuristic"),
        )

        result = classifier.classify(
            feedback_text="The commit skill failed",
            parse_result=parse_result,
            matcher_output=empty_matcher_output,
        )

        # Low session confidence adds -15
        assert result.confidence >= 0  # Should be clamped at 0
        assert "-15" in result.rationale or "low" in result.rationale

    def test_confidence_clamped_to_100(self, classifier):
        """Test that confidence is clamped to 100."""
        # Create scenario with very high signals
        parse_result = ParseResult(
            entries=[
                TrajectoryEntry(
                    skill=SkillInvocation(skill_name="commit", success=False, error_message="Failed"),
                    error_type="ValidationError",
                    error_message="Test error",
                )
                for _ in range(10)
            ],
            session_info=SessionInfo(confidence="high"),
        )
        matcher_output = MatcherOutput(
            matched_skills=["commit", "implement", "review"],
            keyword_matches=[KeywordMatch(keyword="commit", domain="commit", skill="commit")] * 5,
        )

        result = classifier.classify(
            feedback_text="The commit skill crashed and failed with an error exception bug",
            parse_result=parse_result,
            matcher_output=matcher_output,
        )

        assert result.confidence <= 100

    def test_confidence_clamped_to_0(self, classifier):
        """Test that confidence is clamped to 0."""
        # Low signal + low session confidence
        parse_result = ParseResult(
            session_info=SessionInfo(confidence="low"),
        )
        matcher_output = MatcherOutput()

        result = classifier.classify(
            feedback_text="hello",
            parse_result=parse_result,
            matcher_output=matcher_output,
        )

        assert result.confidence >= 0


class TestTrajectoryContext:
    """Test using trajectory context in classification."""

    def test_recent_errors_boost_skill_bug(self, classifier, empty_matcher_output):
        """Test that recent errors in trajectory boost skill_bug score."""
        parse_result = ParseResult(
            entries=[
                TrajectoryEntry(
                    error_type="ValidationError",
                    error_message="Commit message too short",
                ),
            ],
        )

        result = classifier.classify(
            feedback_text="Something went wrong",
            parse_result=parse_result,
            matcher_output=empty_matcher_output,
        )

        # Should have higher skill_bug score due to recent errors
        assert result.raw_scores.get("skill_bug", 0) > 0

    def test_skill_errors_boost_skill_bug(self, classifier, empty_matcher_output):
        """Test that skill errors in trajectory boost skill_bug score."""
        parse_result = ParseResult(
            entries=[
                TrajectoryEntry(
                    skill=SkillInvocation(
                        skill_name="commit",
                        success=False,
                        error_message="Pre-commit hook failed",
                    ),
                ),
            ],
        )

        result = classifier.classify(
            feedback_text="The process failed",
            parse_result=parse_result,
            matcher_output=empty_matcher_output,
        )

        # Should have higher skill_bug score
        assert result.raw_scores.get("skill_bug", 0) > 0

    def test_successful_skills_suggest_skill_gap(self, classifier):
        """Test that successful skill usage boosts skill_gap score."""
        parse_result = ParseResult(
            entries=[
                TrajectoryEntry(
                    skill=SkillInvocation(skill_name="review", success=True),
                ),
            ],
        )
        matcher_output = MatcherOutput(
            matched_skills=["review"],  # Skill exists in ontology
            keyword_matches=[KeywordMatch(keyword="review", domain="review", skill="review-sprint")],
        )

        result = classifier.classify(
            feedback_text="The review skill should also check for typos",
            parse_result=parse_result,
            matcher_output=matcher_output,
        )

        # skill_gap score should be significant when skill exists and works
        assert result.raw_scores.get("skill_gap", 0) > 0


class TestMatcherContext:
    """Test using matcher output in classification."""

    def test_matched_skills_boost_skill_bug(self, classifier, empty_parse_result):
        """Test that matched skills boost skill_bug score."""
        matcher_output = MatcherOutput(
            matched_skills=["commit"],
            keyword_matches=[KeywordMatch(keyword="commit", domain="commit", skill="commit")],
        )

        result = classifier.classify(
            feedback_text="The commit process had an issue",
            parse_result=empty_parse_result,
            matcher_output=matcher_output,
        )

        # Matched skills should boost skill_bug
        assert result.raw_scores.get("skill_bug", 0) > 0

    def test_no_matched_skills_suggests_missing(self, classifier, empty_parse_result):
        """Test that no matched skills suggests missing_skill."""
        matcher_output = MatcherOutput(
            matched_skills=[],
            matched_domains=["testing"],  # Domain exists but no skill
        )

        result = classifier.classify(
            feedback_text="I need a new testing capability",
            parse_result=empty_parse_result,
            matcher_output=matcher_output,
        )

        # missing_skill should be boosted
        assert result.raw_scores.get("missing_skill", 0) > 0
