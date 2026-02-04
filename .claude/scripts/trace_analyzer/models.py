"""
Pydantic Data Models for Trace Analyzer.

Models use extra="ignore" (not "allow") for security - unknown fields are dropped.
This prevents PII leakage through unexpected fields.
"""

from __future__ import annotations

from datetime import datetime
from enum import Enum
from typing import Any

from pydantic import BaseModel, Field, ConfigDict


class FaultCategory(str, Enum):
    """Fault classification categories."""
    SKILL_BUG = "skill_bug"
    SKILL_GAP = "skill_gap"
    MISSING_SKILL = "missing_skill"
    RUNTIME_BUG = "runtime_bug"
    UNKNOWN = "unknown"


class SessionConfidence(str, Enum):
    """Session correlation confidence levels."""
    HIGH = "high"
    MEDIUM = "medium"
    LOW = "low"


# =============================================================================
# Trajectory Entry Models
# =============================================================================


class ToolInvocation(BaseModel):
    """A single tool invocation within a trajectory entry."""
    model_config = ConfigDict(extra="ignore")

    tool_name: str
    args: dict[str, Any] = Field(default_factory=dict)
    result: str | None = None
    error: str | None = None
    duration_ms: int | None = None


class SkillInvocation(BaseModel):
    """A skill invocation entry from the trajectory."""
    model_config = ConfigDict(extra="ignore")

    skill_name: str
    args: str | None = None
    start_time: datetime | None = None
    end_time: datetime | None = None
    success: bool | None = None
    error_message: str | None = None
    tools_used: list[ToolInvocation] = Field(default_factory=list)


class TrajectoryEntry(BaseModel):
    """A single entry in the trajectory JSONL file."""
    model_config = ConfigDict(extra="ignore")

    # Core fields
    timestamp: datetime | None = None
    session_id: str | None = None
    entry_type: str | None = None  # "skill", "tool", "error", "user_message"

    # Skill context
    skill: SkillInvocation | None = None

    # Tool context (for tool-only entries)
    tool: ToolInvocation | None = None

    # Error context
    error_type: str | None = None
    error_message: str | None = None
    stack_trace: str | None = None

    # User message context
    user_message: str | None = None

    # Schema version for forward compatibility
    schema_version: str | None = None


# =============================================================================
# Parse Result Models
# =============================================================================


class SessionInfo(BaseModel):
    """Session detection result."""
    model_config = ConfigDict(extra="ignore")

    confidence: SessionConfidence | str = SessionConfidence.LOW
    reason: str = ""
    session_ids: list[str] = Field(default_factory=list)


class ParseResult(BaseModel):
    """Result of trajectory parsing."""
    model_config = ConfigDict(extra="ignore")

    entries: list[TrajectoryEntry] = Field(default_factory=list)
    session_info: SessionInfo = Field(default_factory=SessionInfo)
    corrupt_lines: int = 0
    total_lines: int = 0
    parser_used: str = "jsonl"  # "jsonl" or "ijson"
    partial_parse: bool = False


# =============================================================================
# Matcher Output Models
# =============================================================================


class KeywordMatch(BaseModel):
    """A keyword match result."""
    model_config = ConfigDict(extra="ignore")

    keyword: str
    domain: str
    skill: str | None = None
    match_type: str = "exact"  # "exact", "fuzzy", "embedding"
    score: float = 1.0


class MatcherOutput(BaseModel):
    """Output from the hybrid matcher."""
    model_config = ConfigDict(extra="ignore")

    keyword_matches: list[KeywordMatch] = Field(default_factory=list)
    fuzzy_matches: list[KeywordMatch] = Field(default_factory=list)
    embedding_matches: list[KeywordMatch] = Field(default_factory=list)
    matched_skills: list[str] = Field(default_factory=list)
    matched_domains: list[str] = Field(default_factory=list)
    dependency_missing: list[str] = Field(default_factory=list)


# =============================================================================
# Classifier Output Models
# =============================================================================


class ClassifierOutput(BaseModel):
    """Output from the fault classifier."""
    model_config = ConfigDict(extra="ignore")

    category: FaultCategory = FaultCategory.UNKNOWN
    confidence: int = Field(default=0, ge=0, le=100)
    raw_scores: dict[str, float] = Field(default_factory=dict)
    signals_detected: list[str] = Field(default_factory=list)
    tie_broken: bool = False
    tie_break_reason: str | None = None
    tie_break_scores: dict[str, float] | None = None
    rationale: str = ""


# =============================================================================
# Final Analysis Result
# =============================================================================


class TraceAnalysisResult(BaseModel):
    """Complete trace analysis result."""
    model_config = ConfigDict(extra="ignore")

    # Classification
    category: FaultCategory = FaultCategory.UNKNOWN
    confidence: int = Field(default=0, ge=0, le=100)

    # Context
    matched_skills: list[str] = Field(default_factory=list)
    matched_domains: list[str] = Field(default_factory=list)
    recent_skills: list[str] = Field(default_factory=list)
    recent_errors: list[str] = Field(default_factory=list)

    # Metadata
    session_confidence: SessionConfidence | str = SessionConfidence.LOW
    entries_analyzed: int = 0
    processing_time_ms: int = 0

    # Error handling
    error: str | None = None
    timeout: bool = False
    timeout_at_stage: str | None = None
    partial_results: dict[str, Any] = Field(default_factory=dict)

    # Dependencies
    dependency_missing: list[str] = Field(default_factory=list)

    # Redaction tracking
    redaction_applied: bool = False
    redaction_fields: list[str] = Field(default_factory=list)

    # Version
    version: str = "1.0.0"


# =============================================================================
# Safe Field Allowlist
# =============================================================================

# Fields that are safe to include in output (not PII)
SAFE_OUTPUT_FIELDS = {
    "category",
    "confidence",
    "matched_skills",
    "matched_domains",
    "recent_skills",
    "session_confidence",
    "entries_analyzed",
    "processing_time_ms",
    "error",
    "timeout",
    "timeout_at_stage",
    "partial_results",
    "dependency_missing",
    "redaction_applied",
    "redaction_fields",
    "version",
}

# Fields that may contain PII and need redaction
PII_RISK_FIELDS = {
    "error_message",
    "stack_trace",
    "user_message",
    "args",
    "result",
    "recent_errors",
}
