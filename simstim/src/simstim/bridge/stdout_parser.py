"""Parser for Loa stdout stream.

Detects permission prompts and phase transitions from Claude Code output.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from enum import Enum


class ActionType(Enum):
    """Types of permission actions."""

    FILE_CREATE = "file_create"
    FILE_EDIT = "file_edit"
    FILE_DELETE = "file_delete"
    BASH_EXECUTE = "bash_execute"
    MCP_TOOL = "mcp_tool"


class PhaseType(Enum):
    """Types of Loa workflow phases."""

    DISCOVERY = "discovery"
    ARCHITECTURE = "architecture"
    SPRINT_PLANNING = "sprint_planning"
    IMPLEMENTATION = "implementation"
    REVIEW = "review"
    AUDIT = "audit"
    DEPLOYMENT = "deployment"


class RiskLevel(Enum):
    """Risk levels for permission requests."""

    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"
    CRITICAL = "critical"


# Maximum input length to prevent ReDoS (SIMSTIM-004)
MAX_PATTERN_INPUT_LENGTH = 2000

# Permission prompt patterns (order matters - more specific first)
# Security Note (SIMSTIM-004): Patterns use [^`'\"?]+ instead of .+? to avoid
# catastrophic backtracking. Each pattern captures characters that are NOT
# quote marks or question marks, ensuring O(n) matching.
PERMISSION_PATTERNS: list[tuple[re.Pattern[str], ActionType]] = [
    # File creation patterns - use character class for O(n) matching
    (
        re.compile(r"Create (?:new )?files? (?:in |at )?[`'\"]?([^`'\"?\n]+)[`'\"]?\s*\?", re.I),
        ActionType.FILE_CREATE,
    ),
    (
        re.compile(r"Write (?:new )?files? (?:to )?[`'\"]?([^`'\"?\n]+)[`'\"]?\s*\?", re.I),
        ActionType.FILE_CREATE,
    ),
    # File edit patterns
    (
        re.compile(r"Edit (?:the )?(?:files? )?[`'\"]?([^`'\"?\n]+)[`'\"]?\s*\?", re.I),
        ActionType.FILE_EDIT,
    ),
    (
        re.compile(r"Modify (?:the )?(?:files? )?[`'\"]?([^`'\"?\n]+)[`'\"]?\s*\?", re.I),
        ActionType.FILE_EDIT,
    ),
    (
        re.compile(r"Update (?:the )?(?:files? )?[`'\"]?([^`'\"?\n]+)[`'\"]?\s*\?", re.I),
        ActionType.FILE_EDIT,
    ),
    # File delete patterns - handle "files in" syntax for directories
    (
        re.compile(r"Delete (?:the )?(?:files? )?(?:in )?[`'\"]?([^`'\"?\n]+)[`'\"]?\s*\?", re.I),
        ActionType.FILE_DELETE,
    ),
    (
        re.compile(r"Remove (?:the )?(?:files? )?(?:in )?[`'\"]?([^`'\"?\n]+)[`'\"]?\s*\?", re.I),
        ActionType.FILE_DELETE,
    ),
    # Bash execute patterns
    (
        re.compile(r"Run [`'\"]?([^`'\"?\n]+)[`'\"]?\s*\?", re.I),
        ActionType.BASH_EXECUTE,
    ),
    (
        re.compile(r"Execute [`'\"]?([^`'\"?\n]+)[`'\"]?\s*\?", re.I),
        ActionType.BASH_EXECUTE,
    ),
    (
        re.compile(r"Run (?:command |bash )?[`'\"]?([^`'\"?\n]+)[`'\"]?\s*\?", re.I),
        ActionType.BASH_EXECUTE,
    ),
    # MCP tool patterns
    (
        re.compile(r"Use (?:the )?(?:MCP )?tool [`'\"]?([^`'\"?\n]+)[`'\"]?", re.I),
        ActionType.MCP_TOOL,
    ),
    (
        re.compile(r"Call (?:the )?(?:MCP )?tool [`'\"]?([^`'\"?\n]+)[`'\"]?", re.I),
        ActionType.MCP_TOOL,
    ),
]

# Phase transition patterns
PHASE_PATTERNS: list[tuple[re.Pattern[str], PhaseType, str | None]] = [
    (re.compile(r"Starting /plan-and-analyze"), PhaseType.DISCOVERY, None),
    (re.compile(r"Starting /architect"), PhaseType.ARCHITECTURE, None),
    (re.compile(r"Starting /sprint-plan"), PhaseType.SPRINT_PLANNING, None),
    (
        re.compile(r"Starting /implement (sprint-\d+)"),
        PhaseType.IMPLEMENTATION,
        "sprint",
    ),
    (re.compile(r"Starting /review-sprint (sprint-\d+)"), PhaseType.REVIEW, "sprint"),
    (re.compile(r"Starting /audit-sprint (sprint-\d+)"), PhaseType.AUDIT, "sprint"),
    (re.compile(r"Starting /deploy"), PhaseType.DEPLOYMENT, None),
]

# Patterns for critical file paths
CRITICAL_PATH_PATTERNS: list[re.Pattern[str]] = [
    re.compile(r"^/etc/", re.I),
    re.compile(r"^/usr/", re.I),
    re.compile(r"^\.", re.I),  # Dotfiles
    re.compile(r"\.env$", re.I),
    re.compile(r"credentials", re.I),
    re.compile(r"\.pem$", re.I),
    re.compile(r"\.key$", re.I),
    re.compile(r"\.secret$", re.I),
]

# Dangerous bash commands
DANGEROUS_COMMANDS: list[str] = [
    "rm ",
    "sudo ",
    "chmod ",
    "curl ",
    "wget ",
    "eval ",
    "exec ",
    "> /",
    "| bash",
    "| sh",
]


@dataclass
class ParsedPermission:
    """Parsed permission request."""

    action: ActionType
    target: str
    raw_text: str
    context_lines: list[str] = field(default_factory=list)


@dataclass
class ParsedPhase:
    """Parsed phase transition."""

    phase: PhaseType
    metadata: dict[str, str] = field(default_factory=dict)
    raw_text: str = ""


class StdoutParser:
    """Parser for Loa stdout stream."""

    def __init__(self, context_buffer_size: int = 10) -> None:
        """Initialize parser with context buffer.

        Args:
            context_buffer_size: Number of lines to keep for context
        """
        self._context_buffer: list[str] = []
        self._buffer_size = context_buffer_size

    def add_line(self, line: str) -> None:
        """Add line to context buffer.

        Args:
            line: Line from stdout to add to buffer
        """
        self._context_buffer.append(line)
        if len(self._context_buffer) > self._buffer_size:
            self._context_buffer.pop(0)

    def parse_permission(self, line: str) -> ParsedPermission | None:
        """Parse line for permission prompt.

        Security Note (SIMSTIM-004): Input length is limited to prevent
        potential ReDoS attacks.

        Args:
            line: Line from stdout to parse

        Returns:
            ParsedPermission if a permission prompt is detected, None otherwise
        """
        # SECURITY: Limit input length to prevent ReDoS
        if len(line) > MAX_PATTERN_INPUT_LENGTH:
            line = line[:MAX_PATTERN_INPUT_LENGTH]

        for pattern, action_type in PERMISSION_PATTERNS:
            match = pattern.search(line)
            if match:
                return ParsedPermission(
                    action=action_type,
                    target=match.group(1).strip(),
                    raw_text=line,
                    context_lines=self._context_buffer.copy(),
                )
        return None

    def parse_phase(self, line: str) -> ParsedPhase | None:
        """Parse line for phase transition.

        Security Note (SIMSTIM-004): Input length is limited to prevent
        potential ReDoS attacks.

        Args:
            line: Line from stdout to parse

        Returns:
            ParsedPhase if a phase transition is detected, None otherwise
        """
        # SECURITY: Limit input length to prevent ReDoS
        if len(line) > MAX_PATTERN_INPUT_LENGTH:
            line = line[:MAX_PATTERN_INPUT_LENGTH]

        for pattern, phase_type, meta_key in PHASE_PATTERNS:
            match = pattern.search(line)
            if match:
                metadata: dict[str, str] = {}
                if meta_key and match.lastindex and match.lastindex >= 1:
                    metadata[meta_key] = match.group(1)
                return ParsedPhase(
                    phase=phase_type,
                    metadata=metadata,
                    raw_text=line,
                )
        return None

    @staticmethod
    def assess_risk(action: ActionType, target: str) -> RiskLevel:
        """Assess risk level for a permission request.

        Args:
            action: Type of action being requested
            target: Target file path or command

        Returns:
            Risk level assessment
        """
        # Critical: System files, credentials, destructive operations
        for pattern in CRITICAL_PATH_PATTERNS:
            if pattern.search(target):
                return RiskLevel.CRITICAL

        # High: Delete operations, dangerous commands
        if action == ActionType.FILE_DELETE:
            return RiskLevel.HIGH

        if action == ActionType.BASH_EXECUTE:
            target_lower = target.lower()
            if any(cmd in target_lower for cmd in DANGEROUS_COMMANDS):
                return RiskLevel.HIGH

        # Medium: Edit existing files, run commands
        if action in (ActionType.FILE_EDIT, ActionType.BASH_EXECUTE):
            return RiskLevel.MEDIUM

        # Low: Create files in safe locations
        return RiskLevel.LOW

    def clear_buffer(self) -> None:
        """Clear the context buffer."""
        self._context_buffer.clear()

    @property
    def context(self) -> list[str]:
        """Get current context buffer."""
        return self._context_buffer.copy()
