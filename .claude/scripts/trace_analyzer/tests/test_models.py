"""Tests for Pydantic data models."""

import pytest
from datetime import datetime, timezone

from trace_analyzer.models import (
    TrajectoryEntry,
    SkillInvocation,
    ToolInvocation,
    SessionInfo,
    ParseResult,
    FaultCategory,
    ClassifierOutput,
    TraceAnalysisResult,
    SAFE_OUTPUT_FIELDS,
    PII_RISK_FIELDS,
)


class TestTrajectoryEntry:
    """Test TrajectoryEntry model."""

    def test_minimal_entry(self):
        """Test creating entry with minimal fields."""
        entry = TrajectoryEntry()
        assert entry.timestamp is None
        assert entry.session_id is None

    def test_full_entry(self):
        """Test creating entry with all fields."""
        entry = TrajectoryEntry(
            timestamp=datetime.now(timezone.utc),
            session_id="test-123",
            entry_type="skill",
            skill=SkillInvocation(skill_name="commit"),
        )
        assert entry.session_id == "test-123"
        assert entry.skill.skill_name == "commit"

    def test_extra_fields_ignored(self):
        """Test that extra fields are ignored (security)."""
        # This should NOT raise an error, but extra fields should be dropped
        entry = TrajectoryEntry.model_validate({
            "session_id": "test",
            "unknown_field": "should be ignored",
            "another_extra": {"nested": "data"},
        })
        assert entry.session_id == "test"
        assert not hasattr(entry, "unknown_field")
        assert not hasattr(entry, "another_extra")


class TestSkillInvocation:
    """Test SkillInvocation model."""

    def test_minimal_skill(self):
        """Test creating skill with just name."""
        skill = SkillInvocation(skill_name="commit")
        assert skill.skill_name == "commit"
        assert skill.success is None

    def test_skill_with_error(self):
        """Test skill with error."""
        skill = SkillInvocation(
            skill_name="commit",
            success=False,
            error_message="Pre-commit hook failed",
        )
        assert skill.success is False
        assert skill.error_message == "Pre-commit hook failed"


class TestToolInvocation:
    """Test ToolInvocation model."""

    def test_tool_invocation(self):
        """Test creating tool invocation."""
        tool = ToolInvocation(
            tool_name="Read",
            args={"file_path": "/test/file.py"},
            result="file contents...",
        )
        assert tool.tool_name == "Read"
        assert tool.args["file_path"] == "/test/file.py"


class TestSessionInfo:
    """Test SessionInfo model."""

    def test_default_session_info(self):
        """Test default session info."""
        info = SessionInfo()
        assert info.confidence == "low"
        assert info.reason == ""

    def test_high_confidence(self):
        """Test high confidence session."""
        info = SessionInfo(
            confidence="high",
            reason="single_session",
            session_ids=["abc123"],
        )
        assert info.confidence == "high"
        assert len(info.session_ids) == 1


class TestParseResult:
    """Test ParseResult model."""

    def test_empty_parse_result(self):
        """Test empty parse result."""
        result = ParseResult()
        assert len(result.entries) == 0
        assert result.corrupt_lines == 0
        assert result.parser_used == "jsonl"

    def test_partial_parse(self):
        """Test partial parse result."""
        result = ParseResult(
            entries=[TrajectoryEntry(session_id="test")],
            corrupt_lines=5,
            total_lines=10,
            partial_parse=True,
        )
        assert len(result.entries) == 1
        assert result.partial_parse is True


class TestFaultCategory:
    """Test FaultCategory enum."""

    def test_category_values(self):
        """Test category string values."""
        assert FaultCategory.SKILL_BUG.value == "skill_bug"
        assert FaultCategory.SKILL_GAP.value == "skill_gap"
        assert FaultCategory.MISSING_SKILL.value == "missing_skill"
        assert FaultCategory.RUNTIME_BUG.value == "runtime_bug"
        assert FaultCategory.UNKNOWN.value == "unknown"


class TestClassifierOutput:
    """Test ClassifierOutput model."""

    def test_default_output(self):
        """Test default classifier output."""
        output = ClassifierOutput()
        assert output.category == FaultCategory.UNKNOWN
        assert output.confidence == 0
        assert output.tie_broken is False

    def test_confidence_clamping(self):
        """Test that confidence is clamped to 0-100."""
        # pydantic should clamp values
        output = ClassifierOutput(confidence=50)
        assert 0 <= output.confidence <= 100

    def test_tie_break_info(self):
        """Test tie break information."""
        output = ClassifierOutput(
            category=FaultCategory.SKILL_BUG,
            confidence=70,
            tie_broken=True,
            tie_break_reason="Precedence: skill_bug > skill_gap",
            tie_break_scores={"skill_bug": 0.7, "skill_gap": 0.7},
        )
        assert output.tie_broken is True
        assert "skill_bug" in output.tie_break_reason


class TestTraceAnalysisResult:
    """Test TraceAnalysisResult model."""

    def test_minimal_result(self):
        """Test minimal result."""
        result = TraceAnalysisResult()
        assert result.category == FaultCategory.UNKNOWN
        assert result.confidence == 0
        assert result.version == "1.0.0"

    def test_timeout_result(self):
        """Test timeout result."""
        result = TraceAnalysisResult(
            timeout=True,
            timeout_at_stage="parser",
        )
        assert result.timeout is True
        assert result.timeout_at_stage == "parser"

    def test_redaction_tracking(self):
        """Test redaction tracking fields."""
        result = TraceAnalysisResult(
            redaction_applied=True,
            redaction_fields=["recent_errors", "partial_results.error"],
        )
        assert result.redaction_applied is True
        assert len(result.redaction_fields) == 2


class TestFieldAllowlists:
    """Test field allowlists for security."""

    def test_safe_fields_defined(self):
        """Test that safe output fields are defined."""
        assert "category" in SAFE_OUTPUT_FIELDS
        assert "confidence" in SAFE_OUTPUT_FIELDS
        assert "version" in SAFE_OUTPUT_FIELDS

    def test_pii_fields_defined(self):
        """Test that PII risk fields are defined."""
        assert "error_message" in PII_RISK_FIELDS
        assert "stack_trace" in PII_RISK_FIELDS
        assert "user_message" in PII_RISK_FIELDS

    def test_no_overlap(self):
        """Test that safe and PII fields don't overlap."""
        overlap = SAFE_OUTPUT_FIELDS & PII_RISK_FIELDS
        assert len(overlap) == 0, f"Overlap found: {overlap}"
