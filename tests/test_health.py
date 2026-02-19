"""Tests for credential health checks (cycle-028 FR-2).

Validates format-only mode (default), live mode, log redaction,
and Moonshot weak validation handling.
"""

import logging
import sys
import unittest
from unittest.mock import patch, MagicMock
from io import StringIO

# Add the adapter path so we can import health module
sys.path.insert(0, ".claude/adapters")

from loa_cheval.credentials.health import (
    HealthResult,
    FORMAT_RULES,
    check_credential,
    check_all,
    _redact_credential_from_error,
    _check_format,
)
from loa_cheval.credentials.providers import CredentialProvider


class MockProvider(CredentialProvider):
    """Test credential provider backed by a dict."""

    def __init__(self, creds: dict):
        self._creds = creds

    def get(self, credential_id: str):
        return self._creds.get(credential_id)

    def name(self) -> str:
        return "mock"


class TestFormatRules(unittest.TestCase):
    """Test FORMAT_RULES coverage."""

    def test_openai_rule_exists(self):
        self.assertIn("OPENAI_API_KEY", FORMAT_RULES)
        self.assertEqual(FORMAT_RULES["OPENAI_API_KEY"]["prefix"], "sk-")

    def test_anthropic_rule_exists(self):
        self.assertIn("ANTHROPIC_API_KEY", FORMAT_RULES)
        self.assertEqual(FORMAT_RULES["ANTHROPIC_API_KEY"]["prefix"], "sk-ant-")

    def test_moonshot_rule_weak(self):
        self.assertIn("MOONSHOT_API_KEY", FORMAT_RULES)
        self.assertEqual(FORMAT_RULES["MOONSHOT_API_KEY"]["validation_confidence"], "weak")


class TestCheckFormat(unittest.TestCase):
    """Test format-only validation (dry-run mode)."""

    def test_openai_valid_key(self):
        key = "sk-" + "a" * 48
        result = _check_format("OPENAI_API_KEY", key)
        self.assertEqual(result.status, "ok")
        self.assertIn("format valid", result.message)

    def test_openai_bad_prefix(self):
        result = _check_format("OPENAI_API_KEY", "bad-prefix-key-value-12345678901234567890")
        self.assertEqual(result.status, "format_invalid")
        self.assertIn("prefix", result.message)

    def test_openai_too_short(self):
        result = _check_format("OPENAI_API_KEY", "sk-short")
        self.assertEqual(result.status, "format_invalid")
        self.assertIn("minimum", result.message)

    def test_openai_bad_charset(self):
        key = "sk-" + "a" * 44 + "!!!!"
        result = _check_format("OPENAI_API_KEY", key)
        self.assertEqual(result.status, "format_invalid")
        self.assertIn("invalid character", result.message)

    def test_anthropic_valid_key(self):
        key = "sk-ant-" + "a" * 90
        result = _check_format("ANTHROPIC_API_KEY", key)
        self.assertEqual(result.status, "ok")

    def test_anthropic_bad_prefix(self):
        result = _check_format("ANTHROPIC_API_KEY", "sk-" + "a" * 90)
        self.assertEqual(result.status, "format_invalid")

    def test_anthropic_too_short(self):
        result = _check_format("ANTHROPIC_API_KEY", "sk-ant-short")
        self.assertEqual(result.status, "format_invalid")

    def test_moonshot_returns_weak_validation(self):
        result = _check_format("MOONSHOT_API_KEY", "any-value-here")
        self.assertEqual(result.status, "unknown/weak_validation")
        self.assertIn("weak", result.message)

    def test_unknown_credential_skipped(self):
        result = _check_format("UNKNOWN_KEY", "value")
        self.assertEqual(result.status, "skipped")


class TestCheckCredentialDefault(unittest.TestCase):
    """Test that default check_credential (no live arg) does NOT make HTTP requests."""

    @patch("loa_cheval.credentials.health.urllib.request.urlopen")
    def test_default_no_http(self, mock_urlopen):
        key = "sk-" + "a" * 48
        result = check_credential("OPENAI_API_KEY", key)
        mock_urlopen.assert_not_called()
        self.assertEqual(result.status, "ok")

    @patch("loa_cheval.credentials.health.urllib.request.urlopen")
    def test_live_false_no_http(self, mock_urlopen):
        key = "sk-" + "a" * 48
        result = check_credential("OPENAI_API_KEY", key, live=False)
        mock_urlopen.assert_not_called()


class TestCheckCredentialLive(unittest.TestCase):
    """Test that live=True makes HTTP requests."""

    @patch("loa_cheval.credentials.health.urllib.request.build_opener")
    def test_live_true_makes_http(self, mock_build_opener):
        mock_opener = MagicMock()
        mock_response = MagicMock()
        mock_response.status = 200
        mock_opener.open.return_value = mock_response
        mock_build_opener.return_value = mock_opener

        result = check_credential("OPENAI_API_KEY", "sk-test-key-value", live=True)
        mock_opener.open.assert_called_once()
        self.assertEqual(result.status, "ok")

    @patch("loa_cheval.credentials.health.urllib.request.build_opener")
    def test_live_error_redacts_credential(self, mock_build_opener):
        sentinel = "sk-SENTINEL-SECRET-VALUE-1234567890"
        mock_opener = MagicMock()
        mock_opener.open.side_effect = Exception(f"Connection failed with key {sentinel}")
        mock_build_opener.return_value = mock_opener

        result = check_credential("OPENAI_API_KEY", sentinel, live=True)
        self.assertEqual(result.status, "error")
        self.assertNotIn(sentinel, result.message)
        self.assertIn("[REDACTED]", result.message)


class TestRedactHelper(unittest.TestCase):
    """Test _redact_credential_from_error."""

    def test_redacts_credential_value(self):
        msg = "Error: key sk-secret-123 is invalid"
        result = _redact_credential_from_error(msg, "sk-secret-123")
        self.assertNotIn("sk-secret-123", result)
        self.assertIn("[REDACTED]", result)

    def test_no_credential_in_message(self):
        msg = "Connection timeout"
        result = _redact_credential_from_error(msg, "sk-secret-123")
        self.assertEqual(msg, result)

    def test_empty_credential(self):
        msg = "Some error"
        result = _redact_credential_from_error(msg, "")
        self.assertEqual(msg, result)


class TestCheckAll(unittest.TestCase):
    """Test check_all integration."""

    def test_check_all_default_no_http(self):
        provider = MockProvider({
            "OPENAI_API_KEY": "sk-" + "a" * 48,
            "ANTHROPIC_API_KEY": "sk-ant-" + "b" * 90,
        })
        with patch("loa_cheval.credentials.health.urllib.request.urlopen") as mock:
            results = check_all(provider)
            mock.assert_not_called()

        statuses = {r.credential_id: r.status for r in results}
        self.assertEqual(statuses["OPENAI_API_KEY"], "ok")
        self.assertEqual(statuses["ANTHROPIC_API_KEY"], "ok")
        self.assertEqual(statuses["MOONSHOT_API_KEY"], "missing")

    def test_check_all_passes_live(self):
        provider = MockProvider({"OPENAI_API_KEY": "sk-" + "a" * 48})
        with patch("loa_cheval.credentials.health.urllib.request.build_opener") as mock_build:
            mock_opener = MagicMock()
            mock_response = MagicMock()
            mock_response.status = 200
            mock_opener.open.return_value = mock_response
            mock_build.return_value = mock_opener

            results = check_all(provider, credential_ids=["OPENAI_API_KEY"], live=True)
            mock_opener.open.assert_called_once()

    def test_missing_credential(self):
        provider = MockProvider({})
        results = check_all(provider, credential_ids=["OPENAI_API_KEY"])
        self.assertEqual(results[0].status, "missing")


class TestLogLeakage(unittest.TestCase):
    """Centralized log capture test — Flatline SKP-007.

    Run health checks with sentinel secret values and verify zero leakage
    in test output, log output, and result messages.
    """

    def test_sentinel_never_appears_in_output(self):
        sentinel_openai = "sk-SENTINEL-OPENAI-LEAK-CHECK-9876543210ab"
        sentinel_anthropic = "sk-ant-SENTINEL-ANTHROPIC-LEAK-CHECK-" + "x" * 60
        sentinel_moonshot = "SENTINEL-MOONSHOT-LEAK-CHECK-VALUE"

        provider = MockProvider({
            "OPENAI_API_KEY": sentinel_openai,
            "ANTHROPIC_API_KEY": sentinel_anthropic,
            "MOONSHOT_API_KEY": sentinel_moonshot,
        })

        # Capture all log output
        log_capture = StringIO()
        handler = logging.StreamHandler(log_capture)
        handler.setLevel(logging.DEBUG)
        test_logger = logging.getLogger("loa_cheval.credentials.health")
        test_logger.addHandler(handler)
        test_logger.setLevel(logging.DEBUG)

        try:
            # Default (format-only) check
            results = check_all(provider)

            # Check results don't contain sentinel values
            for result in results:
                self.assertNotIn(sentinel_openai, result.message,
                                 f"OpenAI sentinel leaked in result: {result}")
                self.assertNotIn(sentinel_anthropic, result.message,
                                 f"Anthropic sentinel leaked in result: {result}")
                self.assertNotIn(sentinel_moonshot, result.message,
                                 f"Moonshot sentinel leaked in result: {result}")

            # Check log output doesn't contain sentinel values
            log_output = log_capture.getvalue()
            self.assertNotIn(sentinel_openai, log_output,
                             "OpenAI sentinel leaked in log output")
            self.assertNotIn(sentinel_anthropic, log_output,
                             "Anthropic sentinel leaked in log output")
            self.assertNotIn(sentinel_moonshot, log_output,
                             "Moonshot sentinel leaked in log output")
        finally:
            test_logger.removeHandler(handler)

    def test_sentinel_never_appears_in_live_error(self):
        sentinel = "sk-SENTINEL-LIVE-ERROR-LEAK-CHECK-123456789"

        with patch("loa_cheval.credentials.health.urllib.request.build_opener") as mock_build:
            mock_opener = MagicMock()
            mock_opener.open.side_effect = Exception(
                f"Failed to connect: key={sentinel} was rejected"
            )
            mock_build.return_value = mock_opener

            result = check_credential("OPENAI_API_KEY", sentinel, live=True)
            self.assertNotIn(sentinel, result.message)


if __name__ == "__main__":
    unittest.main()
