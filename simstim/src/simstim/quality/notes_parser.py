"""Parser for Loa NOTES.md structured memory file.

Extracts Current Focus, Blockers, Decisions, and other
sections from the structured agent memory format.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from pathlib import Path
from typing import Any


class BlockerStatus(Enum):
    """Status of a blocker."""

    ACTIVE = "active"
    RESOLVED = "resolved"


class DecisionType(Enum):
    """Type of decision."""

    ARCHITECTURE = "architecture"
    IMPLEMENTATION = "implementation"
    PROCESS = "process"
    OTHER = "other"


@dataclass
class CurrentFocus:
    """Parsed Current Focus section."""

    task: str
    status: str | None = None
    blocked_by: str | None = None
    next_action: str | None = None


@dataclass
class Blocker:
    """A blocker item from NOTES.md."""

    description: str
    status: BlockerStatus = BlockerStatus.ACTIVE
    id: str | None = None


@dataclass
class Decision:
    """A decision from the Decisions section."""

    date: str | None = None
    area: str | None = None
    decision: str = ""
    rationale: str | None = None
    type: DecisionType = DecisionType.OTHER


@dataclass
class SessionLogEntry:
    """An entry from the Session Log."""

    timestamp: str
    event: str
    details: str | None = None


@dataclass
class ParsedNotes:
    """Parsed NOTES.md content."""

    current_focus: CurrentFocus | None = None
    blockers: list[Blocker] = field(default_factory=list)
    decisions: list[Decision] = field(default_factory=list)
    session_log: list[SessionLogEntry] = field(default_factory=list)
    technical_debt: list[str] = field(default_factory=list)
    learnings: list[str] = field(default_factory=list)
    raw_content: str = ""

    @property
    def active_blockers(self) -> list[Blocker]:
        """Get only active (unresolved) blockers."""
        return [b for b in self.blockers if b.status == BlockerStatus.ACTIVE]

    @property
    def has_active_blockers(self) -> bool:
        """Check if there are active blockers."""
        return len(self.active_blockers) > 0


class NotesParser:
    """Parser for NOTES.md structured memory format."""

    def parse_file(self, path: Path) -> ParsedNotes:
        """Parse a NOTES.md file.

        Args:
            path: Path to NOTES.md

        Returns:
            Parsed notes data
        """
        if not path.exists():
            return ParsedNotes()

        content = path.read_text()
        return self.parse_content(content)

    def parse_content(self, content: str) -> ParsedNotes:
        """Parse NOTES.md content.

        Args:
            content: Markdown content

        Returns:
            Parsed notes data
        """
        current_focus = self._parse_current_focus(content)
        blockers = self._parse_blockers(content)
        decisions = self._parse_decisions(content)
        session_log = self._parse_session_log(content)
        technical_debt = self._parse_technical_debt(content)
        learnings = self._parse_learnings(content)

        return ParsedNotes(
            current_focus=current_focus,
            blockers=blockers,
            decisions=decisions,
            session_log=session_log,
            technical_debt=technical_debt,
            learnings=learnings,
            raw_content=content,
        )

    def _extract_section(self, content: str, header: str) -> str | None:
        """Extract a section by header name.

        Args:
            content: Full content
            header: Section header (without ##)

        Returns:
            Section content or None
        """
        pattern = rf"##\s*{re.escape(header)}\s*\n+(.+?)(?=\n##|\Z)"
        match = re.search(pattern, content, re.IGNORECASE | re.DOTALL)
        if match:
            return match.group(1).strip()
        return None

    def _parse_current_focus(self, content: str) -> CurrentFocus | None:
        """Parse Current Focus section."""
        section = self._extract_section(content, "Current Focus")
        if not section:
            return None

        # Extract task line (usually first line or after "Task:")
        task_match = re.search(
            r"(?:Task:?\s*)?(.+?)(?:\n|$)",
            section,
            re.IGNORECASE,
        )
        task = task_match.group(1).strip() if task_match else section.split("\n")[0]

        # Extract status
        status_match = re.search(r"Status:?\s*(.+?)(?:\n|$)", section, re.IGNORECASE)
        status = status_match.group(1).strip() if status_match else None

        # Extract blocked by
        blocked_match = re.search(r"Blocked\s*by:?\s*(.+?)(?:\n|$)", section, re.IGNORECASE)
        blocked_by = blocked_match.group(1).strip() if blocked_match else None

        # Extract next action
        next_match = re.search(r"Next\s*(?:action|step):?\s*(.+?)(?:\n|$)", section, re.IGNORECASE)
        next_action = next_match.group(1).strip() if next_match else None

        return CurrentFocus(
            task=task,
            status=status,
            blocked_by=blocked_by,
            next_action=next_action,
        )

    def _parse_blockers(self, content: str) -> list[Blocker]:
        """Parse Blockers section."""
        section = self._extract_section(content, "Blockers")
        if not section:
            return []

        blockers = []

        # Match checkbox items: - [ ] or - [x] or - [RESOLVED]
        pattern = r"[-*]\s*\[([xX\s]|RESOLVED)\]\s*(.+?)(?:\n|$)"
        for match in re.finditer(pattern, section):
            checked = match.group(1)
            description = match.group(2).strip()

            # Determine status
            is_resolved = checked.upper() in ("X", "RESOLVED")
            status = BlockerStatus.RESOLVED if is_resolved else BlockerStatus.ACTIVE

            # Try to extract ID if present (e.g., "BLOCK-001: description")
            id_match = re.match(r"(BLOCK-\d+):?\s*(.+)", description)
            if id_match:
                blocker_id = id_match.group(1)
                description = id_match.group(2)
            else:
                blocker_id = None

            blockers.append(Blocker(
                description=description,
                status=status,
                id=blocker_id,
            ))

        return blockers

    def _parse_decisions(self, content: str) -> list[Decision]:
        """Parse Decisions section."""
        section = self._extract_section(content, "Decisions")
        if not section:
            return []

        decisions = []

        # Match table rows: | date | area | decision | rationale |
        table_pattern = r"\|\s*([^|]+)\s*\|\s*([^|]+)\s*\|\s*([^|]+)\s*\|\s*([^|]+)\s*\|"
        for match in re.finditer(table_pattern, section):
            date = match.group(1).strip()
            area = match.group(2).strip()
            decision_text = match.group(3).strip()
            rationale = match.group(4).strip()

            # Skip header row
            if date.lower() in ("date", "---", "-"):
                continue

            # Determine type based on area
            area_lower = area.lower()
            if "arch" in area_lower:
                decision_type = DecisionType.ARCHITECTURE
            elif "impl" in area_lower:
                decision_type = DecisionType.IMPLEMENTATION
            elif "proc" in area_lower:
                decision_type = DecisionType.PROCESS
            else:
                decision_type = DecisionType.OTHER

            decisions.append(Decision(
                date=date if date != "-" else None,
                area=area if area != "-" else None,
                decision=decision_text,
                rationale=rationale if rationale != "-" else None,
                type=decision_type,
            ))

        return decisions

    def _parse_session_log(self, content: str) -> list[SessionLogEntry]:
        """Parse Session Log section."""
        section = self._extract_section(content, "Session Log")
        if not section:
            return []

        entries = []

        # Match table rows: | timestamp | event | details |
        table_pattern = r"\|\s*([^|]+)\s*\|\s*([^|]+)\s*\|\s*([^|]*)\s*\|"
        for match in re.finditer(table_pattern, section):
            timestamp = match.group(1).strip()
            event = match.group(2).strip()
            details = match.group(3).strip()

            # Skip header row
            if timestamp.lower() in ("timestamp", "time", "---", "-"):
                continue

            entries.append(SessionLogEntry(
                timestamp=timestamp,
                event=event,
                details=details if details else None,
            ))

        return entries

    def _parse_technical_debt(self, content: str) -> list[str]:
        """Parse Technical Debt section."""
        section = self._extract_section(content, "Technical Debt")
        if not section:
            return []

        items = []

        # Match bullet points
        pattern = r"[-*]\s+(.+?)(?:\n|$)"
        for match in re.finditer(pattern, section):
            item = match.group(1).strip()
            if item:
                items.append(item)

        return items

    def _parse_learnings(self, content: str) -> list[str]:
        """Parse Learnings section."""
        section = self._extract_section(content, "Learnings")
        if not section:
            return []

        items = []

        # Match bullet points
        pattern = r"[-*]\s+(.+?)(?:\n|$)"
        for match in re.finditer(pattern, section):
            item = match.group(1).strip()
            if item:
                items.append(item)

        return items


def format_notes_notification(notes: ParsedNotes, include_details: bool = False) -> str:
    """Format NOTES.md for Telegram notification.

    Args:
        notes: Parsed notes data
        include_details: Include additional sections

    Returns:
        Formatted message string
    """
    lines = ["📋 <b>NOTES.md Summary</b>", ""]

    # Current Focus
    if notes.current_focus:
        focus = notes.current_focus
        lines.extend([
            "<b>Current Focus:</b>",
            f"  {focus.task}",
        ])
        if focus.status:
            lines.append(f"  Status: {focus.status}")
        if focus.blocked_by:
            lines.append(f"  ⚠️ Blocked by: {focus.blocked_by}")
        if focus.next_action:
            lines.append(f"  Next: {focus.next_action}")
        lines.append("")

    # Active Blockers
    if notes.has_active_blockers:
        lines.append(f"<b>⚠️ Active Blockers:</b> {len(notes.active_blockers)}")
        for blocker in notes.active_blockers[:3]:  # Show first 3
            desc = blocker.description[:100]
            if len(blocker.description) > 100:
                desc += "..."
            lines.append(f"  - {desc}")
        if len(notes.active_blockers) > 3:
            lines.append(f"  <i>+{len(notes.active_blockers) - 3} more...</i>")
        lines.append("")

    # Recent Decisions (if include_details)
    if include_details and notes.decisions:
        lines.append(f"<b>Recent Decisions:</b> {len(notes.decisions)}")
        for decision in notes.decisions[-3:]:  # Show last 3
            lines.append(f"  - {decision.decision[:80]}...")
        lines.append("")

    # Technical Debt count
    if notes.technical_debt:
        lines.append(f"<b>Tech Debt Items:</b> {len(notes.technical_debt)}")

    return "\n".join(lines)
