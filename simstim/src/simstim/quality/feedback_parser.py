"""Parser for Loa quality gate feedback files.

Parses engineer-feedback.md and auditor-sprint-feedback.md
to extract status and findings.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from pathlib import Path
from typing import Any


class FeedbackStatus(Enum):
    """Status of quality gate feedback."""

    APPROVED = "approved"
    CHANGES_REQUIRED = "changes_required"
    PENDING = "pending"
    ALL_GOOD = "all_good"
    UNKNOWN = "unknown"


class FindingSeverity(Enum):
    """Severity of a finding."""

    CRITICAL = "critical"
    HIGH = "high"
    MEDIUM = "medium"
    LOW = "low"
    INFO = "info"


@dataclass
class Finding:
    """A single finding from feedback."""

    severity: FindingSeverity
    description: str
    location: str | None = None
    line_number: int | None = None


@dataclass
class ParsedFeedback:
    """Parsed feedback from quality gate."""

    source: str  # "engineer" or "auditor"
    status: FeedbackStatus
    sprint: str | None = None
    date: datetime | None = None
    findings: list[Finding] = field(default_factory=list)
    summary: str | None = None
    raw_content: str = ""

    @property
    def has_findings(self) -> bool:
        """Check if there are any findings."""
        return len(self.findings) > 0

    @property
    def critical_count(self) -> int:
        """Count critical findings."""
        return sum(1 for f in self.findings if f.severity == FindingSeverity.CRITICAL)

    @property
    def high_count(self) -> int:
        """Count high severity findings."""
        return sum(1 for f in self.findings if f.severity == FindingSeverity.HIGH)


class FeedbackParser:
    """Parser for quality gate feedback files."""

    # Patterns for status detection
    STATUS_PATTERNS = {
        FeedbackStatus.APPROVED: [
            r"APPROVED\s*-\s*LET'?S?\s*F[UCKNG]+ING?\s*GO",
            r"Status:\s*APPROVED",
            r"✅\s*APPROVED",
        ],
        FeedbackStatus.CHANGES_REQUIRED: [
            r"CHANGES_REQUIRED",
            r"Status:\s*CHANGES\s*REQUIRED",
            r"❌\s*CHANGES\s*REQUIRED",
            r"requires?\s+changes?",
        ],
        FeedbackStatus.ALL_GOOD: [
            r"All\s+good",
            r"✅\s*All\s+good",
            r"LGTM",
            r"looks?\s+good\s+to\s+me",
        ],
    }

    # Patterns for finding detection
    FINDING_PATTERNS = [
        # Severity prefix: [CRITICAL] description
        r"\[(?P<severity>CRITICAL|HIGH|MEDIUM|LOW|INFO)\]\s*(?P<desc>.+)",
        # Numbered list with severity: 1. **Critical**: description
        r"\d+\.\s*\*\*(?P<severity2>Critical|High|Medium|Low|Info)\*\*:?\s*(?P<desc2>.+)",
        # Bullet with severity: - CRITICAL: description
        r"[-*]\s*(?P<severity3>CRITICAL|HIGH|MEDIUM|LOW|INFO):?\s*(?P<desc3>.+)",
    ]

    def parse_file(self, path: Path) -> ParsedFeedback:
        """Parse a feedback file.

        Args:
            path: Path to feedback file

        Returns:
            Parsed feedback data
        """
        if not path.exists():
            return ParsedFeedback(
                source=self._detect_source(path.name),
                status=FeedbackStatus.PENDING,
            )

        content = path.read_text()
        return self.parse_content(content, path.name)

    def parse_content(self, content: str, filename: str = "") -> ParsedFeedback:
        """Parse feedback content.

        Args:
            content: Markdown content
            filename: Optional filename for source detection

        Returns:
            Parsed feedback data
        """
        source = self._detect_source(filename)
        status = self._detect_status(content)
        sprint = self._extract_sprint(content)
        date = self._extract_date(content)
        findings = self._extract_findings(content)
        summary = self._extract_summary(content)

        return ParsedFeedback(
            source=source,
            status=status,
            sprint=sprint,
            date=date,
            findings=findings,
            summary=summary,
            raw_content=content,
        )

    def _detect_source(self, filename: str) -> str:
        """Detect feedback source from filename."""
        filename_lower = filename.lower()
        if "engineer" in filename_lower:
            return "engineer"
        elif "auditor" in filename_lower:
            return "auditor"
        return "unknown"

    def _detect_status(self, content: str) -> FeedbackStatus:
        """Detect status from content."""
        content_upper = content.upper()

        for status, patterns in self.STATUS_PATTERNS.items():
            for pattern in patterns:
                if re.search(pattern, content, re.IGNORECASE):
                    return status

        return FeedbackStatus.UNKNOWN

    def _extract_sprint(self, content: str) -> str | None:
        """Extract sprint identifier from content."""
        # Match: Sprint 1, sprint-1, Sprint 5, etc.
        match = re.search(r"Sprint[:\s-]*(\d+)", content, re.IGNORECASE)
        if match:
            return f"sprint-{match.group(1)}"
        return None

    def _extract_date(self, content: str) -> datetime | None:
        """Extract date from content."""
        # Match: Date: 2026-01-20 or similar
        match = re.search(r"Date:?\s*(\d{4}-\d{2}-\d{2})", content)
        if match:
            try:
                return datetime.fromisoformat(match.group(1))
            except ValueError:
                pass
        return None

    def _extract_findings(self, content: str) -> list[Finding]:
        """Extract findings from content."""
        findings = []

        for pattern in self.FINDING_PATTERNS:
            for match in re.finditer(pattern, content, re.IGNORECASE | re.MULTILINE):
                groups = match.groupdict()

                # Find severity and description from named groups
                severity_str = None
                desc_str = None

                for key, value in groups.items():
                    if value and "severity" in key:
                        severity_str = value
                    elif value and "desc" in key:
                        desc_str = value

                if severity_str and desc_str:
                    try:
                        severity = FindingSeverity(severity_str.lower())
                    except ValueError:
                        severity = FindingSeverity.INFO

                    findings.append(Finding(
                        severity=severity,
                        description=desc_str.strip(),
                    ))

        return findings

    def _extract_summary(self, content: str) -> str | None:
        """Extract summary section from content."""
        # Look for ## Summary or similar
        match = re.search(
            r"##\s*Summary\s*\n+(.+?)(?=\n##|\Z)",
            content,
            re.IGNORECASE | re.DOTALL,
        )
        if match:
            return match.group(1).strip()[:500]  # Limit length
        return None


def format_feedback_notification(feedback: ParsedFeedback) -> str:
    """Format feedback for Telegram notification.

    Args:
        feedback: Parsed feedback data

    Returns:
        Formatted message string
    """
    # Status emoji mapping
    status_emoji = {
        FeedbackStatus.APPROVED: "✅",
        FeedbackStatus.CHANGES_REQUIRED: "❌",
        FeedbackStatus.ALL_GOOD: "✅",
        FeedbackStatus.PENDING: "⏳",
        FeedbackStatus.UNKNOWN: "❓",
    }

    emoji = status_emoji.get(feedback.status, "❓")
    source_display = feedback.source.title()
    status_display = feedback.status.value.replace("_", " ").title()

    lines = [
        f"{emoji} <b>Quality Gate: {source_display} Review</b>",
        "",
        f"<b>Status:</b> {status_display}",
    ]

    if feedback.sprint:
        lines.append(f"<b>Sprint:</b> {feedback.sprint}")

    if feedback.has_findings:
        lines.extend([
            "",
            f"<b>Findings:</b> {len(feedback.findings)} total",
        ])

        if feedback.critical_count > 0:
            lines.append(f"  🔴 Critical: {feedback.critical_count}")
        if feedback.high_count > 0:
            lines.append(f"  🟠 High: {feedback.high_count}")

    if feedback.summary:
        # Truncate summary for notification
        summary = feedback.summary[:200]
        if len(feedback.summary) > 200:
            summary += "..."
        lines.extend([
            "",
            f"<i>{summary}</i>",
        ])

    return "\n".join(lines)
