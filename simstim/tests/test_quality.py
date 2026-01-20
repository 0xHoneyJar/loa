"""Tests for quality gate integration module."""

from __future__ import annotations

import tempfile
from datetime import datetime
from pathlib import Path

import pytest

from simstim.quality import (
    FeedbackParser,
    FeedbackStatus,
    ParsedFeedback,
    NotesParser,
    ParsedNotes,
    CurrentFocus,
    Blocker,
    Decision,
    generate_file_link,
    generate_sprint_link,
    generate_notes_link,
    generate_feedback_link,
    generate_quick_links,
    format_telegram_link,
    format_quick_links_message,
)
from simstim.quality.feedback_parser import (
    Finding,
    FindingSeverity,
    format_feedback_notification,
)
from simstim.quality.notes_parser import (
    BlockerStatus,
    DecisionType,
    SessionLogEntry,
    format_notes_notification,
)


class TestFeedbackParser:
    """Tests for FeedbackParser."""

    def test_parse_approved_feedback(self) -> None:
        """Test parsing approved feedback."""
        content = """# Sprint 5 Review

## Status
APPROVED - LET'S FUCKING GO

## Summary
All tests passing, code quality excellent.
"""
        parser = FeedbackParser()
        result = parser.parse_content(content, "auditor-sprint-feedback.md")

        assert result.status == FeedbackStatus.APPROVED
        assert result.source == "auditor"
        assert result.sprint == "sprint-5"
        assert result.summary is not None
        assert "All tests passing" in result.summary

    def test_parse_changes_required_feedback(self) -> None:
        """Test parsing feedback requiring changes."""
        content = """# Engineer Feedback

Status: CHANGES_REQUIRED

## Findings

[CRITICAL] Missing input validation in user handler
[HIGH] SQL injection risk in query builder
"""
        parser = FeedbackParser()
        result = parser.parse_content(content, "engineer-feedback.md")

        assert result.status == FeedbackStatus.CHANGES_REQUIRED
        assert result.source == "engineer"
        assert len(result.findings) == 2
        assert result.critical_count == 1
        assert result.high_count == 1

    def test_parse_all_good_feedback(self) -> None:
        """Test parsing 'all good' feedback."""
        content = """# Review

All good, nice work!

LGTM
"""
        parser = FeedbackParser()
        result = parser.parse_content(content, "engineer-feedback.md")

        assert result.status == FeedbackStatus.ALL_GOOD

    def test_parse_findings_with_severity(self) -> None:
        """Test extracting findings with different severities."""
        content = """# Audit

1. **Critical**: Buffer overflow in parser
2. **High**: Missing authentication check
3. **Medium**: Inefficient algorithm
4. **Low**: Code style inconsistency
5. **Info**: Consider adding documentation
"""
        parser = FeedbackParser()
        result = parser.parse_content(content, "auditor-feedback.md")

        assert len(result.findings) == 5
        severities = [f.severity for f in result.findings]
        assert FindingSeverity.CRITICAL in severities
        assert FindingSeverity.HIGH in severities
        assert FindingSeverity.MEDIUM in severities
        assert FindingSeverity.LOW in severities
        assert FindingSeverity.INFO in severities

    def test_parse_bullet_findings(self) -> None:
        """Test parsing bullet-style findings."""
        content = """# Findings

- CRITICAL: XSS vulnerability
- HIGH: Missing rate limiting
"""
        parser = FeedbackParser()
        result = parser.parse_content(content, "feedback.md")

        assert len(result.findings) == 2
        assert result.findings[0].severity == FindingSeverity.CRITICAL
        assert "XSS vulnerability" in result.findings[0].description

    def test_parse_date_extraction(self) -> None:
        """Test date extraction from content."""
        content = """# Review
Date: 2026-01-20

All good.
"""
        parser = FeedbackParser()
        result = parser.parse_content(content)

        assert result.date is not None
        assert result.date.year == 2026
        assert result.date.month == 1
        assert result.date.day == 20

    def test_parse_nonexistent_file(self) -> None:
        """Test parsing a nonexistent file returns pending status."""
        parser = FeedbackParser()
        result = parser.parse_file(Path("/nonexistent/path/feedback.md"))

        assert result.status == FeedbackStatus.PENDING
        assert result.source == "unknown"

    def test_format_feedback_notification_approved(self) -> None:
        """Test formatting approved feedback for Telegram."""
        feedback = ParsedFeedback(
            source="auditor",
            status=FeedbackStatus.APPROVED,
            sprint="sprint-5",
        )

        message = format_feedback_notification(feedback)

        assert "✅" in message
        assert "Auditor" in message
        assert "Approved" in message
        assert "sprint-5" in message

    def test_format_feedback_notification_with_findings(self) -> None:
        """Test formatting feedback with findings."""
        feedback = ParsedFeedback(
            source="engineer",
            status=FeedbackStatus.CHANGES_REQUIRED,
            findings=[
                Finding(severity=FindingSeverity.CRITICAL, description="Bug 1"),
                Finding(severity=FindingSeverity.HIGH, description="Bug 2"),
            ],
            summary="Multiple issues found.",
        )

        message = format_feedback_notification(feedback)

        assert "❌" in message
        assert "Changes Required" in message
        assert "2 total" in message
        assert "Critical: 1" in message
        assert "High: 1" in message


class TestNotesParser:
    """Tests for NotesParser."""

    def test_parse_current_focus(self) -> None:
        """Test parsing Current Focus section."""
        content = """# NOTES.md

## Current Focus

Task: Implement user authentication
Status: In Progress
Blocked by: API credentials
Next action: Request credentials from admin
"""
        parser = NotesParser()
        result = parser.parse_content(content)

        assert result.current_focus is not None
        assert "authentication" in result.current_focus.task
        assert result.current_focus.status == "In Progress"
        assert "credentials" in result.current_focus.blocked_by
        assert "Request credentials" in result.current_focus.next_action

    def test_parse_blockers(self) -> None:
        """Test parsing Blockers section."""
        content = """## Blockers

- [ ] BLOCK-001: Waiting for API access
- [x] BLOCK-002: Database connection issue
- [RESOLVED] BLOCK-003: Dependency conflict
"""
        parser = NotesParser()
        result = parser.parse_content(content)

        assert len(result.blockers) == 3

        # First blocker - active
        assert result.blockers[0].status == BlockerStatus.ACTIVE
        assert result.blockers[0].id == "BLOCK-001"
        assert "API access" in result.blockers[0].description

        # Second blocker - resolved (x)
        assert result.blockers[1].status == BlockerStatus.RESOLVED
        assert result.blockers[1].id == "BLOCK-002"

        # Third blocker - resolved
        assert result.blockers[2].status == BlockerStatus.RESOLVED
        assert result.blockers[2].id == "BLOCK-003"

    def test_active_blockers_property(self) -> None:
        """Test active_blockers property filtering."""
        content = """## Blockers

- [ ] Active blocker 1
- [x] Resolved blocker
- [ ] Active blocker 2
"""
        parser = NotesParser()
        result = parser.parse_content(content)

        assert len(result.blockers) == 3
        assert len(result.active_blockers) == 2
        assert result.has_active_blockers is True

    def test_parse_decisions_table(self) -> None:
        """Test parsing Decisions table."""
        content = """## Decisions

| Date | Area | Decision | Rationale |
|------|------|----------|-----------|
| 2026-01-20 | Architecture | Use microservices | Better scalability |
| 2026-01-19 | Implementation | Use Python | Team expertise |
"""
        parser = NotesParser()
        result = parser.parse_content(content)

        assert len(result.decisions) == 2

        assert result.decisions[0].date == "2026-01-20"
        assert result.decisions[0].type == DecisionType.ARCHITECTURE
        assert "microservices" in result.decisions[0].decision

        assert result.decisions[1].type == DecisionType.IMPLEMENTATION
        assert "Python" in result.decisions[1].decision

    def test_parse_session_log(self) -> None:
        """Test parsing Session Log table."""
        content = """## Session Log

| Timestamp | Event | Details |
|-----------|-------|---------|
| 10:00 | Session started | Sprint 5 implementation |
| 11:30 | Code review | Addressing feedback |
"""
        parser = NotesParser()
        result = parser.parse_content(content)

        assert len(result.session_log) == 2
        assert result.session_log[0].timestamp == "10:00"
        assert "started" in result.session_log[0].event
        assert result.session_log[1].details == "Addressing feedback"

    def test_parse_technical_debt(self) -> None:
        """Test parsing Technical Debt section."""
        content = """## Technical Debt

- TODO: Refactor database layer
- FIXME: Memory leak in parser
- Consider: Add caching
"""
        parser = NotesParser()
        result = parser.parse_content(content)

        assert len(result.technical_debt) == 3
        assert any("Refactor" in item for item in result.technical_debt)
        assert any("Memory leak" in item for item in result.technical_debt)

    def test_parse_learnings(self) -> None:
        """Test parsing Learnings section."""
        content = """## Learnings

- Always validate user input at boundaries
- Use async/await for IO operations
- Document architecture decisions early
"""
        parser = NotesParser()
        result = parser.parse_content(content)

        assert len(result.learnings) == 3
        assert any("validate" in item for item in result.learnings)
        assert any("async" in item for item in result.learnings)

    def test_parse_file(self) -> None:
        """Test parsing from file."""
        with tempfile.NamedTemporaryFile(mode="w", suffix=".md", delete=False) as f:
            f.write("""## Current Focus
Task: Test file parsing
""")
            f.flush()
            path = Path(f.name)

        try:
            parser = NotesParser()
            result = parser.parse_file(path)

            assert result.current_focus is not None
            assert "Test file parsing" in result.current_focus.task
        finally:
            path.unlink()

    def test_parse_nonexistent_file(self) -> None:
        """Test parsing nonexistent file returns empty result."""
        parser = NotesParser()
        result = parser.parse_file(Path("/nonexistent/NOTES.md"))

        assert result.current_focus is None
        assert result.blockers == []
        assert result.has_active_blockers is False

    def test_format_notes_notification(self) -> None:
        """Test formatting notes for Telegram."""
        notes = ParsedNotes(
            current_focus=CurrentFocus(
                task="Implement feature X",
                status="In Progress",
                blocked_by="API access",
            ),
            blockers=[
                Blocker(description="Waiting for API", status=BlockerStatus.ACTIVE),
                Blocker(description="Fixed issue", status=BlockerStatus.RESOLVED),
            ],
            technical_debt=["Item 1", "Item 2"],
        )

        message = format_notes_notification(notes)

        assert "📋" in message
        assert "Implement feature X" in message
        assert "In Progress" in message
        assert "⚠️" in message  # Blocked by indicator
        assert "Active Blockers" in message
        assert "1" in message  # 1 active blocker
        assert "Tech Debt Items" in message
        assert "2" in message  # 2 tech debt items


class TestDeepLinks:
    """Tests for deep link generation."""

    def test_generate_file_link_default(self) -> None:
        """Test default file:// link generation."""
        link = generate_file_link("/path/to/file.md")

        assert link.startswith("file://")
        assert "file.md" in link

    def test_generate_file_link_with_line_number(self) -> None:
        """Test file link with line number."""
        link = generate_file_link("/path/to/file.md", line_number=42)

        assert "#L42" in link

    def test_generate_file_link_vscode(self) -> None:
        """Test VS Code scheme link."""
        link = generate_file_link("/path/to/file.md", line_number=10, scheme="vscode")

        assert link.startswith("vscode://file/")
        assert ":10" in link

    def test_generate_file_link_cursor(self) -> None:
        """Test Cursor scheme link."""
        link = generate_file_link("/path/to/file.md", scheme="cursor")

        assert link.startswith("cursor://file/")

    def test_generate_file_link_github(self) -> None:
        """Test GitHub web link."""
        link = generate_file_link(
            "src/main.py",
            line_number=50,
            scheme="github",
            base_url="https://github.com/owner/repo",
        )

        assert "github.com" in link
        assert "blob/main" in link
        assert "#L50" in link

    def test_generate_file_link_github_requires_base_url(self) -> None:
        """Test GitHub link requires base_url."""
        with pytest.raises(ValueError, match="base_url required"):
            generate_file_link("file.py", scheme="github")

    def test_generate_sprint_link(self) -> None:
        """Test sprint file link generation."""
        link = generate_sprint_link("sprint-5", "reviewer")

        assert "sprint-5" in link
        assert "reviewer.md" in link

    def test_generate_sprint_link_feedback(self) -> None:
        """Test sprint feedback link."""
        link = generate_sprint_link("sprint-3", "engineer-feedback")

        assert "sprint-3" in link
        assert "engineer-feedback.md" in link

    def test_generate_notes_link(self) -> None:
        """Test NOTES.md link generation."""
        link = generate_notes_link()

        assert "NOTES.md" in link

    def test_generate_feedback_link(self) -> None:
        """Test feedback link generation."""
        link = generate_feedback_link("engineer", "sprint-2")

        assert "sprint-2" in link
        assert "engineer-feedback.md" in link

    def test_generate_feedback_link_auditor(self) -> None:
        """Test auditor feedback link."""
        link = generate_feedback_link("auditor", "sprint-1")

        assert "auditor-sprint-feedback.md" in link

    def test_generate_feedback_link_requires_sprint(self) -> None:
        """Test feedback link requires sprint_id."""
        with pytest.raises(ValueError, match="sprint_id is required"):
            generate_feedback_link("engineer", None)

    def test_format_telegram_link(self) -> None:
        """Test Telegram HTML link formatting."""
        link = format_telegram_link("https://example.com", "Example")

        assert '<a href="https://example.com">Example</a>' == link

    def test_generate_quick_links(self) -> None:
        """Test quick links dictionary generation."""
        links = generate_quick_links("sprint-5")

        assert "notes" in links
        assert "reviewer" in links
        assert "engineer_feedback" in links
        assert "auditor_feedback" in links

    def test_generate_quick_links_without_sprint(self) -> None:
        """Test quick links without sprint ID."""
        links = generate_quick_links()

        assert "notes" in links
        assert "reviewer" not in links

    def test_generate_quick_links_without_notes(self) -> None:
        """Test quick links without NOTES.md."""
        links = generate_quick_links("sprint-1", include_notes=False)

        assert "notes" not in links
        assert "reviewer" in links

    def test_format_quick_links_message(self) -> None:
        """Test formatting quick links for Telegram."""
        links = {
            "notes": "file:///path/NOTES.md",
            "reviewer": "file:///path/reviewer.md",
        }

        message = format_quick_links_message(links)

        assert "📎 Quick Links" in message
        assert "📋 NOTES.md" in message
        assert "📝 Reviewer Report" in message
        assert "<a href=" in message

    def test_format_quick_links_empty(self) -> None:
        """Test formatting empty links."""
        message = format_quick_links_message({})

        assert message == ""

    def test_format_quick_links_custom_header(self) -> None:
        """Test custom header in quick links."""
        links = {"notes": "file:///NOTES.md"}
        message = format_quick_links_message(links, header="🔗 Links")

        assert "🔗 Links" in message


class TestFeedbackParserEdgeCases:
    """Edge case tests for FeedbackParser."""

    def test_parse_empty_content(self) -> None:
        """Test parsing empty content."""
        parser = FeedbackParser()
        result = parser.parse_content("")

        assert result.status == FeedbackStatus.UNKNOWN
        assert result.findings == []

    def test_parse_no_structured_sections(self) -> None:
        """Test parsing content without structured sections."""
        content = "Just some random text without any structure."
        parser = FeedbackParser()
        result = parser.parse_content(content)

        assert result.status == FeedbackStatus.UNKNOWN

    def test_parse_mixed_case_status(self) -> None:
        """Test status detection with mixed case."""
        content = "aPpRoVeD - let's fucking go"
        parser = FeedbackParser()
        result = parser.parse_content(content)

        assert result.status == FeedbackStatus.APPROVED


class TestNotesParserEdgeCases:
    """Edge case tests for NotesParser."""

    def test_parse_empty_content(self) -> None:
        """Test parsing empty content."""
        parser = NotesParser()
        result = parser.parse_content("")

        assert result.current_focus is None
        assert result.blockers == []

    def test_parse_with_asterisk_bullets(self) -> None:
        """Test parsing with * bullets instead of -."""
        content = """## Blockers

* [ ] Blocker with asterisk
* [x] Resolved with asterisk
"""
        parser = NotesParser()
        result = parser.parse_content(content)

        assert len(result.blockers) == 2
        assert result.blockers[0].status == BlockerStatus.ACTIVE
        assert result.blockers[1].status == BlockerStatus.RESOLVED

    def test_parse_section_at_end(self) -> None:
        """Test parsing section at end of document."""
        content = """## Learnings

- Last section learning
"""
        parser = NotesParser()
        result = parser.parse_content(content)

        assert len(result.learnings) == 1
        assert "Last section" in result.learnings[0]
