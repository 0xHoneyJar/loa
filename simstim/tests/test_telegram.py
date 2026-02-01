"""Unit tests for Telegram module components."""

from __future__ import annotations

import pytest

from simstim.bridge.stdout_parser import ActionType, PhaseType, RiskLevel


class TestFormatters:
    """Test message formatters."""

    def test_escape_markdown(self) -> None:
        """Test Markdown escaping."""
        from simstim.telegram.formatters import escape_markdown

        # Test special characters
        assert escape_markdown("*bold*") == "\\*bold\\*"
        assert escape_markdown("_italic_") == "\\_italic\\_"
        assert escape_markdown("[link](url)") == "\\[link\\]\\(url\\)"

    def test_redact_sensitive_default_patterns(self) -> None:
        """Test redaction with default patterns."""
        from simstim.telegram.formatters import redact_sensitive

        # Test password redaction
        assert "***REDACTED***" in redact_sensitive("password=secret123")
        assert "secret123" not in redact_sensitive("password=secret123")

        # Test token redaction
        assert "***REDACTED***" in redact_sensitive("api_key: abc123")
        assert "abc123" not in redact_sensitive("api_key: abc123")

        # Test case insensitivity
        assert "***REDACTED***" in redact_sensitive("PASSWORD=SECRET")

    def test_redact_sensitive_custom_patterns(self) -> None:
        """Test redaction with custom patterns."""
        from simstim.telegram.formatters import redact_sensitive

        result = redact_sensitive(
            "database_url=postgres://user:pass@host",
            patterns=["database_url"],
        )
        assert "***REDACTED***" in result
        assert "postgres://" not in result

    def test_format_permission_request(self) -> None:
        """Test permission request formatting."""
        from simstim.bridge.permission_queue import PermissionRequest
        from simstim.telegram.formatters import format_permission_request

        request = PermissionRequest(
            action=ActionType.FILE_CREATE,
            target="src/app.ts",
            context="Creating app\nSecond line",
            risk_level=RiskLevel.LOW,
        )

        result = format_permission_request(request, timeout_seconds=300)

        # Check structure
        assert "<b>Permission Request</b>" in result
        assert "File Create" in result
        assert "src/app.ts" in result
        assert "🟢" in result  # Low risk
        assert "5:00" in result  # Timeout

    def test_format_permission_request_all_risk_levels(self) -> None:
        """Test all risk level emoji mappings."""
        from simstim.bridge.permission_queue import PermissionRequest
        from simstim.telegram.formatters import format_permission_request

        risk_emoji_map = {
            RiskLevel.LOW: "🟢",
            RiskLevel.MEDIUM: "🟡",
            RiskLevel.HIGH: "🟠",
            RiskLevel.CRITICAL: "🔴",
        }

        for risk_level, expected_emoji in risk_emoji_map.items():
            request = PermissionRequest(
                action=ActionType.FILE_CREATE,
                target="test.ts",
                context="",
                risk_level=risk_level,
            )
            result = format_permission_request(request, timeout_seconds=60)
            assert expected_emoji in result, f"Expected {expected_emoji} for {risk_level}"

    def test_format_phase_notification(self) -> None:
        """Test phase notification formatting."""
        from simstim.bridge.stdout_parser import ParsedPhase
        from simstim.telegram.formatters import format_phase_notification

        phase = ParsedPhase(
            phase=PhaseType.IMPLEMENTATION,
            metadata={"sprint": "sprint-1"},
            raw_text="Starting /implement sprint-1",
        )

        result = format_phase_notification(phase)

        assert "⚙️" in result  # Implementation emoji
        assert "Implementation" in result
        assert "sprint-1" in result

    def test_format_phase_notification_all_phases(self) -> None:
        """Test all phase emoji mappings."""
        from simstim.bridge.stdout_parser import ParsedPhase
        from simstim.telegram.formatters import PHASE_EMOJI, format_phase_notification

        for phase_type in PhaseType:
            phase = ParsedPhase(
                phase=phase_type,
                metadata={},
                raw_text="",
            )
            result = format_phase_notification(phase)
            expected_emoji = PHASE_EMOJI.get(phase_type.value, "📌")
            assert expected_emoji in result

    def test_format_status(self) -> None:
        """Test status formatting."""
        from simstim.telegram.formatters import format_status

        result = format_status(
            pending_count=5,
            current_phase=PhaseType.IMPLEMENTATION,
            loa_running=True,
            bot_connected=True,
        )

        assert "Simstim Status" in result
        assert "5" in result  # Pending count
        assert "✅ Running" in result
        assert "✅ Online" in result
        assert "Implementation" in result

    def test_format_status_stopped(self) -> None:
        """Test status formatting when stopped."""
        from simstim.telegram.formatters import format_status

        result = format_status(
            pending_count=0,
            loa_running=False,
            bot_connected=True,
        )

        assert "⏹️ Stopped" in result

    def test_format_error(self) -> None:
        """Test error formatting."""
        from simstim.telegram.formatters import format_error

        result = format_error("Connection failed", "Network timeout")

        assert "Error" in result
        assert "Connection failed" in result
        assert "Network timeout" in result

    def test_format_response_confirmation(self) -> None:
        """Test response confirmation formatting."""
        from simstim.telegram.formatters import format_response_confirmation

        # User response
        result = format_response_confirmation(
            request_id="abc123",
            approved=True,
            user_id=123456789,
        )
        assert "✅ Approved" in result
        assert "123456789" in result

        # Timeout response
        result = format_response_confirmation(
            request_id="abc123",
            approved=False,
            user_id=0,
            auto=True,
            policy_name="timeout",
        )
        assert "❌ Denied" in result
        assert "timeout" in result

        # Policy response
        result = format_response_confirmation(
            request_id="abc123",
            approved=True,
            user_id=0,
            auto=True,
            policy_name="auto-approve-tests",
        )
        assert "✅ Approved" in result
        assert "auto-approve-tests" in result


class TestKeyboards:
    """Test keyboard builders."""

    def test_create_permission_keyboard(self) -> None:
        """Test permission keyboard creation."""
        from simstim.telegram.keyboards import create_permission_keyboard

        keyboard = create_permission_keyboard("req123")

        # Should have one row with two buttons
        assert len(keyboard.inline_keyboard) == 1
        assert len(keyboard.inline_keyboard[0]) == 2

        # Check button labels
        buttons = keyboard.inline_keyboard[0]
        assert "Approve" in buttons[0].text
        assert "Deny" in buttons[1].text

        # Check callback data
        assert "approve:req123" in buttons[0].callback_data
        assert "deny:req123" in buttons[1].callback_data

    def test_create_confirmation_keyboard(self) -> None:
        """Test confirmation keyboard creation."""
        from simstim.telegram.keyboards import create_confirmation_keyboard

        keyboard = create_confirmation_keyboard("halt", "emergency")

        buttons = keyboard.inline_keyboard[0]
        assert "Confirm" in buttons[0].text
        assert "Cancel" in buttons[1].text
        assert "confirm:halt:emergency" in buttons[0].callback_data

    def test_parse_callback_data(self) -> None:
        """Test callback data parsing."""
        from simstim.telegram.keyboards import CallbackAction, parse_callback_data

        # Approve
        result = parse_callback_data("approve:abc123")
        assert result.action == CallbackAction.APPROVE
        assert result.request_id == "abc123"
        assert result.extra is None

        # Deny
        result = parse_callback_data("deny:xyz789")
        assert result.action == CallbackAction.DENY
        assert result.request_id == "xyz789"

        # With extra data
        result = parse_callback_data("confirm:halt:emergency")
        assert result.action == CallbackAction.CONFIRM
        assert result.request_id == "halt"
        assert result.extra == "emergency"

    def test_parse_callback_data_errors(self) -> None:
        """Test callback data parsing errors."""
        from simstim.telegram.keyboards import parse_callback_data

        with pytest.raises(ValueError, match="Empty"):
            parse_callback_data("")

        with pytest.raises(ValueError, match="Invalid callback action"):
            parse_callback_data("unknown:123")
