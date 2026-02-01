"""Tests for stdout parser module."""

import pytest

from simstim.bridge.stdout_parser import (
    ActionType,
    PhaseType,
    RiskLevel,
    StdoutParser,
)


class TestPermissionParsing:
    """Test permission prompt detection."""

    def test_parse_file_create(self, parser: StdoutParser) -> None:
        """Test detecting file creation prompts."""
        line = "Create file 'src/components/Button.tsx'?"
        result = parser.parse_permission(line)

        assert result is not None
        assert result.action == ActionType.FILE_CREATE
        assert result.target == "src/components/Button.tsx"

    def test_parse_file_create_with_new(self, parser: StdoutParser) -> None:
        """Test detecting 'Create new file' variant."""
        line = "Create new file 'src/utils/helpers.ts'?"
        result = parser.parse_permission(line)

        assert result is not None
        assert result.action == ActionType.FILE_CREATE
        assert result.target == "src/utils/helpers.ts"

    def test_parse_file_create_with_in(self, parser: StdoutParser) -> None:
        """Test detecting 'Create file in' variant."""
        line = "Create file in `tests/unit/test_foo.py`?"
        result = parser.parse_permission(line)

        assert result is not None
        assert result.action == ActionType.FILE_CREATE
        assert result.target == "tests/unit/test_foo.py"

    def test_parse_file_edit(self, parser: StdoutParser) -> None:
        """Test detecting file edit prompts."""
        line = "Edit file 'src/main.ts'?"
        result = parser.parse_permission(line)

        assert result is not None
        assert result.action == ActionType.FILE_EDIT
        assert result.target == "src/main.ts"

    def test_parse_file_edit_without_file(self, parser: StdoutParser) -> None:
        """Test detecting 'Edit' without 'file' keyword."""
        line = "Edit 'README.md'?"
        result = parser.parse_permission(line)

        assert result is not None
        assert result.action == ActionType.FILE_EDIT
        assert result.target == "README.md"

    def test_parse_file_delete(self, parser: StdoutParser) -> None:
        """Test detecting file deletion prompts."""
        line = "Delete file 'tmp/old_file.txt'?"
        result = parser.parse_permission(line)

        assert result is not None
        assert result.action == ActionType.FILE_DELETE
        assert result.target == "tmp/old_file.txt"

    def test_parse_bash_execute(self, parser: StdoutParser) -> None:
        """Test detecting bash execution prompts."""
        line = "Run 'npm test'?"
        result = parser.parse_permission(line)

        assert result is not None
        assert result.action == ActionType.BASH_EXECUTE
        assert result.target == "npm test"

    def test_parse_bash_execute_with_backticks(self, parser: StdoutParser) -> None:
        """Test detecting bash with backticks."""
        line = "Run `git status`?"
        result = parser.parse_permission(line)

        assert result is not None
        assert result.action == ActionType.BASH_EXECUTE
        assert result.target == "git status"

    def test_parse_mcp_tool(self, parser: StdoutParser) -> None:
        """Test detecting MCP tool prompts."""
        line = "Use MCP tool 'github.create_issue'?"
        result = parser.parse_permission(line)

        assert result is not None
        assert result.action == ActionType.MCP_TOOL
        assert result.target == "github.create_issue"

    def test_parse_mcp_tool_without_mcp(self, parser: StdoutParser) -> None:
        """Test detecting 'Use tool' without MCP keyword."""
        line = "Use tool 'linear.create_task'?"
        result = parser.parse_permission(line)

        assert result is not None
        assert result.action == ActionType.MCP_TOOL
        assert result.target == "linear.create_task"

    def test_parse_no_match(self, parser: StdoutParser) -> None:
        """Test that non-permission lines return None."""
        line = "Processing files in src/"
        result = parser.parse_permission(line)

        assert result is None

    def test_parse_with_context(self, parser_with_context: StdoutParser) -> None:
        """Test that context is captured with permission."""
        line = "Create file 'src/new.ts'?"
        result = parser_with_context.parse_permission(line)

        assert result is not None
        assert len(result.context_lines) == 3
        assert "sprint-1" in result.context_lines[1]


class TestPhaseParsing:
    """Test phase transition detection."""

    def test_parse_discovery_phase(self, parser: StdoutParser) -> None:
        """Test detecting discovery phase."""
        line = "Starting /plan-and-analyze"
        result = parser.parse_phase(line)

        assert result is not None
        assert result.phase == PhaseType.DISCOVERY
        assert result.metadata == {}

    def test_parse_architecture_phase(self, parser: StdoutParser) -> None:
        """Test detecting architecture phase."""
        line = "Starting /architect"
        result = parser.parse_phase(line)

        assert result is not None
        assert result.phase == PhaseType.ARCHITECTURE

    def test_parse_sprint_planning_phase(self, parser: StdoutParser) -> None:
        """Test detecting sprint planning phase."""
        line = "Starting /sprint-plan"
        result = parser.parse_phase(line)

        assert result is not None
        assert result.phase == PhaseType.SPRINT_PLANNING

    def test_parse_implementation_phase(self, parser: StdoutParser) -> None:
        """Test detecting implementation phase with sprint metadata."""
        line = "Starting /implement sprint-1"
        result = parser.parse_phase(line)

        assert result is not None
        assert result.phase == PhaseType.IMPLEMENTATION
        assert result.metadata == {"sprint": "sprint-1"}

    def test_parse_review_phase(self, parser: StdoutParser) -> None:
        """Test detecting review phase with sprint metadata."""
        line = "Starting /review-sprint sprint-2"
        result = parser.parse_phase(line)

        assert result is not None
        assert result.phase == PhaseType.REVIEW
        assert result.metadata == {"sprint": "sprint-2"}

    def test_parse_audit_phase(self, parser: StdoutParser) -> None:
        """Test detecting audit phase."""
        line = "Starting /audit-sprint sprint-3"
        result = parser.parse_phase(line)

        assert result is not None
        assert result.phase == PhaseType.AUDIT
        assert result.metadata == {"sprint": "sprint-3"}

    def test_parse_deployment_phase(self, parser: StdoutParser) -> None:
        """Test detecting deployment phase."""
        line = "Starting /deploy"
        result = parser.parse_phase(line)

        assert result is not None
        assert result.phase == PhaseType.DEPLOYMENT

    def test_parse_no_phase_match(self, parser: StdoutParser) -> None:
        """Test that non-phase lines return None."""
        line = "Working on implementation..."
        result = parser.parse_phase(line)

        assert result is None


class TestRiskAssessment:
    """Test risk level assessment."""

    def test_risk_critical_env_file(self) -> None:
        """Test critical risk for .env files."""
        risk = StdoutParser.assess_risk(ActionType.FILE_EDIT, ".env")
        assert risk == RiskLevel.CRITICAL

    def test_risk_critical_system_path(self) -> None:
        """Test critical risk for system paths."""
        risk = StdoutParser.assess_risk(ActionType.FILE_CREATE, "/etc/passwd")
        assert risk == RiskLevel.CRITICAL

    def test_risk_critical_credentials(self) -> None:
        """Test critical risk for credential files."""
        risk = StdoutParser.assess_risk(ActionType.FILE_EDIT, "credentials.json")
        assert risk == RiskLevel.CRITICAL

    def test_risk_critical_private_key(self) -> None:
        """Test critical risk for private key files."""
        risk = StdoutParser.assess_risk(ActionType.FILE_CREATE, "server.key")
        assert risk == RiskLevel.CRITICAL

    def test_risk_critical_pem_file(self) -> None:
        """Test critical risk for PEM files."""
        risk = StdoutParser.assess_risk(ActionType.FILE_EDIT, "cert.pem")
        assert risk == RiskLevel.CRITICAL

    def test_risk_high_delete(self) -> None:
        """Test high risk for delete operations."""
        risk = StdoutParser.assess_risk(ActionType.FILE_DELETE, "src/safe.ts")
        assert risk == RiskLevel.HIGH

    def test_risk_high_rm_command(self) -> None:
        """Test high risk for rm command."""
        risk = StdoutParser.assess_risk(ActionType.BASH_EXECUTE, "rm -rf temp/")
        assert risk == RiskLevel.HIGH

    def test_risk_high_sudo_command(self) -> None:
        """Test high risk for sudo command."""
        risk = StdoutParser.assess_risk(ActionType.BASH_EXECUTE, "sudo apt install")
        assert risk == RiskLevel.HIGH

    def test_risk_high_curl_command(self) -> None:
        """Test high risk for curl command."""
        risk = StdoutParser.assess_risk(
            ActionType.BASH_EXECUTE, "curl http://example.com"
        )
        assert risk == RiskLevel.HIGH

    def test_risk_medium_file_edit(self) -> None:
        """Test medium risk for file edits."""
        risk = StdoutParser.assess_risk(ActionType.FILE_EDIT, "src/component.ts")
        assert risk == RiskLevel.MEDIUM

    def test_risk_medium_bash_safe(self) -> None:
        """Test medium risk for safe bash commands."""
        risk = StdoutParser.assess_risk(ActionType.BASH_EXECUTE, "npm test")
        assert risk == RiskLevel.MEDIUM

    def test_risk_low_file_create(self) -> None:
        """Test low risk for file creation."""
        risk = StdoutParser.assess_risk(ActionType.FILE_CREATE, "src/new_file.ts")
        assert risk == RiskLevel.LOW


class TestContextBuffer:
    """Test context buffer management."""

    def test_buffer_size_limit(self) -> None:
        """Test that buffer doesn't exceed size limit."""
        parser = StdoutParser(context_buffer_size=3)

        for i in range(10):
            parser.add_line(f"line-{i}")

        assert len(parser.context) == 3
        assert parser.context == ["line-7", "line-8", "line-9"]

    def test_clear_buffer(self, parser: StdoutParser) -> None:
        """Test clearing the buffer."""
        parser.add_line("some line")
        parser.add_line("another line")

        parser.clear_buffer()

        assert parser.context == []
