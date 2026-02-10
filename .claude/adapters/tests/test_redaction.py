"""Tests for redaction/sanitization layer — forced-failure secret leak tests (SDD §6.2)."""

import os
import sys
from pathlib import Path
from unittest.mock import patch

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from loa_cheval.config.redaction import (
    REDACTED,
    redact_string,
    redact_exception,
    redact_headers,
    redact_config_value,
    wrap_provider_error,
    configure_http_logging,
)


class TestRedactString:
    """Forced-failure tests: verify secrets are stripped from error messages."""

    def test_env_var_value_redacted(self):
        with patch.dict(os.environ, {"OPENAI_API_KEY": "sk-real-secret-key-12345"}):
            result = redact_string("Error: sk-real-secret-key-12345 is invalid")
            assert "sk-real-secret-key-12345" not in result
            assert REDACTED in result

    def test_anthropic_key_redacted(self):
        with patch.dict(os.environ, {"ANTHROPIC_API_KEY": "sk-ant-secret-value"}):
            result = redact_string("Auth failed: sk-ant-secret-value")
            assert "sk-ant-secret-value" not in result
            assert REDACTED in result

    def test_authorization_header_redacted(self):
        result = redact_string("Authorization: Bearer sk-test-12345")
        assert "sk-test-12345" not in result
        assert REDACTED in result

    def test_x_api_key_header_redacted(self):
        result = redact_string("x-api-key: sk-ant-12345")
        assert "sk-ant-12345" not in result
        assert REDACTED in result

    def test_url_query_params_redacted(self):
        result = redact_string("https://api.example.com/v1?api_key=secret123&other=value")
        assert "secret123" not in result
        assert REDACTED in result
        assert "other=value" in result  # Non-secret params preserved

    def test_multiple_secrets_redacted(self):
        with patch.dict(os.environ, {
            "OPENAI_API_KEY": "sk-open-123",
            "ANTHROPIC_API_KEY": "sk-ant-456",
        }):
            result = redact_string("Tried sk-open-123, then sk-ant-456")
            assert "sk-open-123" not in result
            assert "sk-ant-456" not in result

    def test_loa_prefixed_env_var_redacted(self):
        with patch.dict(os.environ, {"LOA_CUSTOM_SECRET": "my-long-secret-value"}):
            result = redact_string("Error with my-long-secret-value")
            assert "my-long-secret-value" not in result

    def test_short_env_values_not_redacted(self):
        """Short env values (<=8 chars) are excluded to avoid false positives."""
        with patch.dict(os.environ, {"LOA_SHORT": "abc"}):
            result = redact_string("Value: abc is fine")
            # Short values should NOT be redacted (false positive risk)
            assert "abc" in result


class TestRedactException:
    def test_exception_message_redacted(self):
        with patch.dict(os.environ, {"OPENAI_API_KEY": "sk-exception-leak"}):
            exc = Exception("Connection refused for key sk-exception-leak")
            result = redact_exception(exc)
            assert "sk-exception-leak" not in result

    def test_provider_error_wrapped(self):
        with patch.dict(os.environ, {"OPENAI_API_KEY": "sk-wrap-test"}):
            exc = Exception("Auth failed with Bearer sk-wrap-test")
            wrapped = wrap_provider_error(exc, "openai")
            assert "sk-wrap-test" not in str(wrapped)
            assert wrapped.code == "API_ERROR"
            assert wrapped.retryable is True


class TestRedactHeaders:
    def test_auth_header_redacted(self):
        headers = {
            "Authorization": "Bearer sk-123",
            "Content-Type": "application/json",
        }
        result = redact_headers(headers)
        assert result["Authorization"] == REDACTED
        assert result["Content-Type"] == "application/json"

    def test_api_key_header_redacted(self):
        headers = {
            "x-api-key": "sk-ant-123",
            "anthropic-version": "2023-06-01",
        }
        result = redact_headers(headers)
        assert result["x-api-key"] == REDACTED
        assert result["anthropic-version"] == "2023-06-01"

    def test_custom_secret_header(self):
        headers = {"x-custom-token": "secret-value"}
        result = redact_headers(headers)
        assert result["x-custom-token"] == REDACTED


class TestRedactConfigValue:
    def test_auth_key_redacted(self):
        result = redact_config_value("auth", "sk-real-key")
        assert result == REDACTED

    def test_interpolation_token_annotated(self):
        result = redact_config_value("value", "{env:OPENAI_API_KEY}")
        assert REDACTED in result
        assert "env:OPENAI_API_KEY" in result

    def test_nested_dict_redacted(self):
        value = {"auth": "sk-key", "name": "test"}
        result = redact_config_value("config", value)
        assert result["auth"] == REDACTED
        assert result["name"] == "test"

    def test_list_values_redacted(self):
        value = [{"auth": "sk-key"}, "normal"]
        result = redact_config_value("items", value)
        assert result[0]["auth"] == REDACTED
        assert result[1] == "normal"

    def test_non_sensitive_key_preserved(self):
        result = redact_config_value("endpoint", "https://api.openai.com/v1")
        assert result == "https://api.openai.com/v1"


class TestConfigureHttpLogging:
    def test_sets_warning_level(self):
        import logging

        configure_http_logging()
        for logger_name in ["httpx", "httpcore", "urllib3", "http.client"]:
            assert logging.getLogger(logger_name).level >= logging.WARNING
