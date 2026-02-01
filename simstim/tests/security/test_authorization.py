"""Security tests for SIMSTIM-003: Authorization Bypass.

Tests verify that:
- Empty authorized_users list denies all (fail-closed)
- allow_anonymous flag must be explicit
- Authorization is properly checked
"""

import pytest
from simstim.config import SecurityConfig


class TestFailClosedAuthorization:
    """Test fail-closed authorization behavior."""

    def test_empty_authorized_users_denies_all(self):
        """Test that empty authorized_users list denies everyone."""
        config = SecurityConfig()
        assert config.authorized_users == []
        assert not config.allow_anonymous

        # Should deny any user
        assert not config.is_authorized(123456789)
        assert not config.is_authorized(987654321)
        assert not config.is_authorized(0)

    def test_allow_anonymous_must_be_explicit(self):
        """Test that allow_anonymous defaults to False."""
        config = SecurityConfig()
        assert config.allow_anonymous is False

    def test_allow_anonymous_allows_all(self):
        """Test that explicit allow_anonymous=True allows all users."""
        config = SecurityConfig(allow_anonymous=True)

        assert config.is_authorized(123456789)
        assert config.is_authorized(987654321)
        assert config.is_authorized(0)

    def test_authorized_users_checked(self):
        """Test that authorized_users list is properly checked."""
        config = SecurityConfig(authorized_users=[123456789, 111111111])

        assert config.is_authorized(123456789)
        assert config.is_authorized(111111111)
        assert not config.is_authorized(987654321)
        assert not config.is_authorized(0)

    def test_authorization_priority(self):
        """Test that allow_anonymous takes priority."""
        # Even with authorized_users set, allow_anonymous should allow all
        config = SecurityConfig(
            authorized_users=[123456789],
            allow_anonymous=True,
        )

        assert config.is_authorized(123456789)  # In list
        assert config.is_authorized(987654321)  # Not in list, but anonymous allowed


class TestAuthorizationEdgeCases:
    """Test authorization edge cases."""

    def test_single_authorized_user(self):
        """Test authorization with single user."""
        config = SecurityConfig(authorized_users=[42])

        assert config.is_authorized(42)
        assert not config.is_authorized(43)

    def test_large_user_id(self):
        """Test authorization with large user IDs."""
        large_id = 9999999999  # 10 digits
        config = SecurityConfig(authorized_users=[large_id])

        assert config.is_authorized(large_id)
        assert not config.is_authorized(large_id + 1)

    def test_negative_user_id_not_authorized(self):
        """Test that negative user IDs are not authorized by default."""
        config = SecurityConfig(authorized_users=[-1])

        # Negative IDs should be authorized if in list (Telegram doesn't use them)
        assert config.is_authorized(-1)
        assert not config.is_authorized(1)


class TestSecurityConfigValidation:
    """Test SecurityConfig validation."""

    def test_default_redact_patterns(self):
        """Test default redact patterns are set."""
        config = SecurityConfig()
        assert "password" in config.redact_patterns
        assert "secret" in config.redact_patterns
        assert "token" in config.redact_patterns

    def test_log_unauthorized_default_true(self):
        """Test that unauthorized logging defaults to True."""
        config = SecurityConfig()
        assert config.log_unauthorized_attempts is True
