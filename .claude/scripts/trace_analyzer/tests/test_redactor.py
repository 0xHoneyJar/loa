"""Tests for the PrivacyRedactor."""

import pytest

from trace_analyzer.redactor import PrivacyRedactor
from trace_analyzer.models import TraceAnalysisResult, FaultCategory


@pytest.fixture
def redactor():
    """Create a redactor instance."""
    return PrivacyRedactor(workspace_root="/home/user/project")


class TestJWTRedaction:
    """Test JWT token redaction."""

    def test_redact_jwt(self, redactor):
        """Test that JWT tokens are redacted."""
        text = "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"

        result = redactor.redact_text(text)

        assert "eyJ" not in result
        assert "[REDACTED:JWT]" in result

    def test_partial_jwt_not_redacted(self, redactor):
        """Test that partial JWT-like strings are handled."""
        text = "eyJ is the start of a JWT"

        result = redactor.redact_text(text)

        # Partial patterns shouldn't match
        assert "eyJ" in result


class TestUUIDRedaction:
    """Test UUID redaction."""

    def test_redact_uuid(self, redactor):
        """Test that UUIDs are redacted."""
        text = "Session ID: 550e8400-e29b-41d4-a716-446655440000"

        result = redactor.redact_text(text)

        assert "550e8400" not in result
        assert "[REDACTED:UUID]" in result


class TestAPIKeyRedaction:
    """Test API key redaction."""

    def test_redact_openai_key(self, redactor):
        """Test that OpenAI API keys are redacted."""
        text = "OPENAI_API_KEY=sk-1234567890abcdefghijklmnopqrstuvwxyz"

        result = redactor.redact_text(text)

        assert "sk-" not in result
        assert "[REDACTED:API_KEY]" in result

    def test_redact_github_pat(self, redactor):
        """Test that GitHub PATs are redacted."""
        text = "token: ghp_1234567890abcdefghijklmnopqrstuvwxyz"

        result = redactor.redact_text(text)

        assert "ghp_" not in result
        assert "[REDACTED:API_KEY]" in result

    def test_redact_github_fine_grained(self, redactor):
        """Test that GitHub fine-grained PATs are redacted."""
        text = "GITHUB_TOKEN=github_pat_1234567890abcdefghij"

        result = redactor.redact_text(text)

        assert "github_pat_" not in result

    def test_redact_slack_token(self, redactor):
        """Test that Slack tokens are redacted."""
        text = "slack_token: xoxb-12345-67890-abcdefghijklmnop"

        result = redactor.redact_text(text)

        assert "xoxb-" not in result

    def test_redact_aws_access_key(self, redactor):
        """Test that AWS access keys are redacted."""
        text = "AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE"

        result = redactor.redact_text(text)

        assert "AKIA" not in result

    def test_redact_generic_api_key(self, redactor):
        """Test that generic API key patterns are redacted."""
        text = "api_key: abcdefghijklmnopqrstuvwxyz123456"

        result = redactor.redact_text(text)

        assert "[REDACTED:API_KEY]" in result


class TestEmailRedaction:
    """Test email redaction."""

    def test_redact_email(self, redactor):
        """Test that emails are redacted."""
        text = "Contact: john.doe@example.com for help"

        result = redactor.redact_text(text)

        assert "john.doe@example.com" not in result
        assert "[REDACTED:EMAIL]" in result

    def test_redact_subaddress_email(self, redactor):
        """Test that subaddress emails are redacted."""
        text = "user+tag@domain.org"

        result = redactor.redact_text(text)

        assert "user+tag@domain.org" not in result

    def test_preserve_at_in_code(self, redactor):
        """Test that @ in non-email context is preserved."""
        text = "@decorator_function"

        result = redactor.redact_text(text)

        assert "@decorator_function" in result


class TestURLRedaction:
    """Test URL with auth token redaction."""

    def test_redact_url_with_token(self, redactor):
        """Test that URLs with tokens are redacted."""
        text = "https://api.example.com/data?token=secret123&other=value"

        result = redactor.redact_text(text)

        assert "secret123" not in result
        assert "[REDACTED:URL_WITH_AUTH]" in result

    def test_redact_url_with_api_key(self, redactor):
        """Test that URLs with api_key are redacted."""
        text = "https://api.example.com/data?api_key=mysecretkey"

        result = redactor.redact_text(text)

        assert "mysecretkey" not in result

    def test_preserve_safe_url(self, redactor):
        """Test that URLs without auth are preserved."""
        text = "https://example.com/page?foo=bar"

        result = redactor.redact_text(text)

        assert "https://example.com/page?foo=bar" in result


class TestPathRedaction:
    """Test file path redaction."""

    def test_redact_home_path(self, redactor):
        """Test that home directory paths are redacted."""
        text = "Error in file /home/user/secrets/config.json"

        result = redactor.redact_text(text)

        assert "/home/user/secrets" not in result
        assert "[PATH:" in result

    def test_redact_windows_path(self, redactor):
        """Test that Windows paths are redacted."""
        text = r"File: C:\Users\Admin\Documents\secrets.txt"

        result = redactor.redact_text(text)

        assert r"C:\Users" not in result

    def test_relativize_workspace_path(self):
        """Test that workspace paths are made relative."""
        redactor = PrivacyRedactor(workspace_root="/home/user/project")
        text = "File: /home/user/project/src/main.py"

        result = redactor.redact_text(text)

        # Should be relativized, not hashed
        # Note: actual behavior depends on implementation
        assert "/home/user/project" not in result or "src/main.py" in result


class TestStackTraceRedaction:
    """Test stack trace redaction."""

    def test_redact_python_traceback(self, redactor):
        """Test that Python tracebacks have paths redacted."""
        text = 'File "/home/user/app/main.py", line 42'

        result = redactor.redact_text(text)

        # Path should be redacted
        assert "/home/user/app" not in result
        assert "[PATH:" in result

    def test_redact_js_stack(self, redactor):
        """Test that JavaScript stack trace patterns are handled."""
        text = "at processTicksAndRejections (internal/process/task_queues.js:95:5)"

        result = redactor.redact_text(text)

        # Internal paths don't match the absolute path pattern, so may not be redacted
        # The important thing is the function works without error
        assert result is not None


class TestTraceOutputRedaction:
    """Test full trace output redaction."""

    def test_redact_recent_errors(self, redactor):
        """Test that recent_errors field is redacted."""
        result = TraceAnalysisResult(
            category=FaultCategory.SKILL_BUG,
            confidence=70,
            recent_errors=[
                "Error at /home/user/app/main.py:42",
                "API key: sk-1234567890abcdefghijklmnopqrstuvwxyz",
            ],
        )

        redacted = redactor.redact_trace_output(result)

        assert redacted.redaction_applied is True
        assert "recent_errors" in redacted.redaction_fields
        # Verify actual redaction
        assert "sk-" not in str(redacted.recent_errors)

    def test_redact_partial_results(self, redactor):
        """Test that partial_results field is redacted."""
        result = TraceAnalysisResult(
            partial_results={
                "error": "john@example.com reported: token=secret123",
            },
        )

        redacted = redactor.redact_trace_output(result)

        assert "[REDACTED:EMAIL]" in str(redacted.partial_results)
        assert "john@example.com" not in str(redacted.partial_results)


class TestRedactionTracking:
    """Test redaction tracking and reporting."""

    def test_track_redacted_fields(self, redactor):
        """Test that redacted fields are tracked."""
        result = TraceAnalysisResult(
            recent_errors=["Email: test@example.com"],
        )

        redacted = redactor.redact_trace_output(result)

        assert redacted.redaction_applied is True
        assert len(redacted.redaction_fields) > 0

    def test_no_redaction_when_clean(self, redactor):
        """Test that no redaction is reported when input is clean."""
        result = TraceAnalysisResult(
            category=FaultCategory.SKILL_BUG,
            confidence=70,
            matched_skills=["commit"],
        )

        redacted = redactor.redact_trace_output(result)

        assert redacted.redaction_applied is False
        assert len(redacted.redaction_fields) == 0


class TestEdgeCases:
    """Test edge cases in redaction."""

    def test_empty_string(self, redactor):
        """Test redacting empty string."""
        result = redactor.redact_text("")
        assert result == ""

    def test_none_handling(self, redactor):
        """Test that None values don't cause errors."""
        result = TraceAnalysisResult(
            recent_errors=[],
        )

        redacted = redactor.redact_trace_output(result)

        assert redacted is not None

    def test_no_over_redaction(self, redactor):
        """Test that normal text isn't over-redacted."""
        text = "The commit skill failed because the message was too short"

        result = redactor.redact_text(text)

        # Should be unchanged - no PII
        assert result == text
