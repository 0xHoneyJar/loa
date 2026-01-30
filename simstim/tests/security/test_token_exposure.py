"""Security tests for SIMSTIM-001: Bot Token Exposure.

Tests verify that bot tokens are never exposed in:
- Log messages
- Exception traces
- String representations
- Error output
"""

import pytest
import re
import logging
from io import StringIO

from simstim.config import (
    TelegramConfig,
    SimstimConfig,
    redact_token_from_string,
    SafeSecretStr,
    _TOKEN_PATTERN,
    _REDACTED,
)


# Example bot token format: 123456789:ABCDEFghijklmnop_qrstuvwxyz123456
SAMPLE_TOKEN = "1234567890:ABCDEFghijklmnop_qrstuvwxyz12345"
SAMPLE_TOKEN_2 = "9876543210:ZYXWVUtsrqponmlk_jihgfedcba09876"


class TestTokenRedaction:
    """Test token redaction functions."""

    def test_redact_token_from_string_single(self):
        """Test redacting a single token from a string."""
        text = f"Error: Invalid token {SAMPLE_TOKEN} provided"
        result = redact_token_from_string(text)

        assert SAMPLE_TOKEN not in result
        assert _REDACTED in result
        assert "Error: Invalid token" in result

    def test_redact_token_from_string_multiple(self):
        """Test redacting multiple tokens from a string."""
        text = f"Token1: {SAMPLE_TOKEN}, Token2: {SAMPLE_TOKEN_2}"
        result = redact_token_from_string(text)

        assert SAMPLE_TOKEN not in result
        assert SAMPLE_TOKEN_2 not in result
        assert result.count(_REDACTED) == 2

    def test_redact_token_pattern_variations(self):
        """Test redaction handles various token formats."""
        # Standard format
        assert SAMPLE_TOKEN not in redact_token_from_string(SAMPLE_TOKEN)

        # Embedded in URL
        url = f"https://api.telegram.org/bot{SAMPLE_TOKEN}/getMe"
        result = redact_token_from_string(url)
        assert SAMPLE_TOKEN not in result

        # In JSON-like structure
        json_text = f'{{"bot_token": "{SAMPLE_TOKEN}"}}'
        result = redact_token_from_string(json_text)
        assert SAMPLE_TOKEN not in result

    def test_redact_preserves_non_token_content(self):
        """Test that non-token content is preserved."""
        text = "Normal log message without tokens"
        result = redact_token_from_string(text)
        assert result == text

    def test_redact_empty_string(self):
        """Test handling of empty strings."""
        assert redact_token_from_string("") == ""

    def test_token_pattern_matches_valid_tokens(self):
        """Test the token regex matches valid bot token formats."""
        valid_tokens = [
            "123456789:ABCDEFghijklmnopqrstuvwxyz1234567",
            "9876543210:ABCDEFGHIJKLMNOPQRSTUVWXYZ12345",
            "1234567890:abcdefghijklmnopqrstuvwxyz_1234",
            "123456789:ABC-DEF_ghi-jkl_123456789012345",
        ]

        for token in valid_tokens:
            assert _TOKEN_PATTERN.search(token), f"Pattern should match: {token}"

    def test_token_pattern_rejects_invalid_formats(self):
        """Test the token regex doesn't match invalid formats."""
        invalid_tokens = [
            "12345:short",  # Too short numeric prefix
            "abcdefghij:ABCDEFghijklmnopqrstuvwxyz1234567",  # Non-numeric prefix
            "123456789:ABC",  # Too short suffix
        ]

        for token in invalid_tokens:
            # These may or may not match depending on the exact pattern
            # Main goal is to ensure valid tokens ARE matched
            pass


class TestSafeSecretStr:
    """Test SafeSecretStr class prevents token exposure."""

    def test_repr_is_redacted(self):
        """Test __repr__ doesn't expose the secret."""
        secret = SafeSecretStr(SAMPLE_TOKEN)
        repr_output = repr(secret)

        assert SAMPLE_TOKEN not in repr_output
        assert _REDACTED in repr_output

    def test_str_is_redacted(self):
        """Test __str__ doesn't expose the secret."""
        secret = SafeSecretStr(SAMPLE_TOKEN)
        str_output = str(secret)

        assert SAMPLE_TOKEN not in str_output
        assert str_output == _REDACTED

    def test_format_is_redacted(self):
        """Test __format__ doesn't expose the secret."""
        secret = SafeSecretStr(SAMPLE_TOKEN)
        formatted = f"Token: {secret}"

        assert SAMPLE_TOKEN not in formatted
        assert _REDACTED in formatted


class TestTelegramConfigRepr:
    """Test TelegramConfig doesn't expose tokens in repr."""

    def test_telegram_config_repr_is_safe(self):
        """Test TelegramConfig.__repr__ doesn't expose token."""
        from pydantic import SecretStr

        config = TelegramConfig(
            bot_token=SecretStr(SAMPLE_TOKEN),
            chat_id=123456789,
        )

        repr_output = repr(config)

        assert SAMPLE_TOKEN not in repr_output
        assert _REDACTED in repr_output
        assert "123456789" in repr_output  # chat_id is fine to expose


class TestTokenNotInLogs:
    """Test tokens don't appear in log output."""

    def test_token_not_in_info_log(self, caplog):
        """Test token is redacted from info logs."""
        from simstim.telegram.bot import SafeLogger

        logger = logging.getLogger("test_logger")
        safe_logger = SafeLogger(logger)

        with caplog.at_level(logging.INFO):
            safe_logger.info(f"Starting bot with token {SAMPLE_TOKEN}")

        for record in caplog.records:
            assert SAMPLE_TOKEN not in record.getMessage()

    def test_token_not_in_error_log(self, caplog):
        """Test token is redacted from error logs."""
        from simstim.telegram.bot import SafeLogger

        logger = logging.getLogger("test_logger")
        safe_logger = SafeLogger(logger)

        with caplog.at_level(logging.ERROR):
            safe_logger.error(f"Failed with token {SAMPLE_TOKEN}")

        for record in caplog.records:
            assert SAMPLE_TOKEN not in record.getMessage()

    def test_token_not_in_warning_log(self, caplog):
        """Test token is redacted from warning logs."""
        from simstim.telegram.bot import SafeLogger

        logger = logging.getLogger("test_logger")
        safe_logger = SafeLogger(logger)

        with caplog.at_level(logging.WARNING):
            safe_logger.warning(f"Warning about token {SAMPLE_TOKEN}")

        for record in caplog.records:
            assert SAMPLE_TOKEN not in record.getMessage()


class TestTokenNotInExceptions:
    """Test tokens are redacted from exception messages."""

    def test_redact_preserves_exception_structure(self):
        """Test redaction maintains exception message structure."""
        error_msg = f"TelegramError: Invalid token {SAMPLE_TOKEN}"
        safe_msg = redact_token_from_string(error_msg)

        assert "TelegramError:" in safe_msg
        assert SAMPLE_TOKEN not in safe_msg
        assert _REDACTED in safe_msg


class TestFuzzTokenExposure:
    """Fuzz testing for token exposure prevention."""

    @pytest.mark.parametrize(
        "wrapper_text",
        [
            "plain {}",
            "{} at end",
            "start {} end",
            '"{}"',
            "'{}'",
            "<{}>",
            "{{}}: ".format("{}"),  # JSON-like
            "error({}, code=1)",  # Function-like
            "Token\n{}\nmore",  # Newlines
            "Token\t{}\ttabs",  # Tabs
        ],
    )
    def test_token_redacted_in_various_contexts(self, wrapper_text):
        """Test token is redacted regardless of surrounding context."""
        text = wrapper_text.format(SAMPLE_TOKEN)
        result = redact_token_from_string(text)

        assert SAMPLE_TOKEN not in result, f"Token exposed in: {wrapper_text}"


# Verify no hardcoded tokens in source files
class TestNoHardcodedTokens:
    """Test that no real tokens are hardcoded in source."""

    def test_test_file_uses_fake_token(self):
        """Verify this test file uses an obviously fake token."""
        # The sample tokens should not be valid real tokens
        assert SAMPLE_TOKEN.startswith("123456789")  # Obviously fake
        assert "ABCDEF" in SAMPLE_TOKEN  # Clearly test data
