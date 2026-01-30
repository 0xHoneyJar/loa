"""Configuration models for Simstim.

Type-safe configuration using Pydantic with TOML loading and
environment variable expansion.

Security Note: Bot tokens are wrapped in SecretStr and SafeConfig
to prevent accidental exposure in logs, exceptions, and repr output.
"""

from __future__ import annotations

import os
import re
import tomllib
from pathlib import Path
from typing import Literal

from pydantic import BaseModel, Field, SecretStr


# Token redaction pattern for exception filtering
# Matches bot tokens: 123456789:XXXXXXX... (9-10 digit ID, colon, 30-50 char alphanumeric suffix)
# Real tokens have ~35 char suffix, but we allow 30-50 for tolerance
_TOKEN_PATTERN = re.compile(r'\d{9,10}:[A-Za-z0-9_-]{30,50}')
_REDACTED = "[REDACTED]"


class SafeSecretStr(SecretStr):
    """Enhanced SecretStr that never reveals its value in any representation.

    This class overrides all methods that could potentially expose the secret
    value to ensure bot tokens never appear in logs, exceptions, or debugging.
    """

    def __repr__(self) -> str:
        return f"SafeSecretStr('{_REDACTED}')"

    def __str__(self) -> str:
        return _REDACTED

    def __format__(self, format_spec: str) -> str:
        return _REDACTED


def redact_token_from_string(text: str) -> str:
    """Redact any bot tokens from a string.

    Args:
        text: String that may contain bot tokens

    Returns:
        String with all bot tokens replaced with [REDACTED]
    """
    return _TOKEN_PATTERN.sub(_REDACTED, text)


class TelegramConfig(BaseModel):
    """Telegram bot configuration."""

    bot_token: SecretStr = Field(description="Bot token from @BotFather")
    chat_id: int = Field(description="Target chat ID for notifications")

    def get_token_safe(self) -> str:
        """Get token value for use in API calls only.

        WARNING: Only use this method when passing to Telegram API.
        Never log or display the returned value.
        """
        return self.bot_token.get_secret_value()

    def __repr__(self) -> str:
        return f"TelegramConfig(bot_token={_REDACTED}, chat_id={self.chat_id})"


class SecurityConfig(BaseModel):
    """Security settings.

    Security Note (SIMSTIM-003): By default, authorization is fail-closed.
    An empty authorized_users list will deny ALL users. To allow all users
    (development only), set allow_anonymous=True explicitly.
    """

    authorized_users: list[int] = Field(
        default_factory=list,
        description="Telegram user IDs allowed to interact",
    )
    allow_anonymous: bool = Field(
        default=False,
        description="DANGER: Allow unauthenticated users (dev only)",
    )
    callback_secret: SecretStr | None = Field(
        default=None,
        description="HMAC secret for callback signing (auto-generated if not set)",
    )
    redact_patterns: list[str] = Field(
        default=["password", "secret", "token", "api_key", "private_key"],
        description="Patterns to redact from notifications",
    )
    log_unauthorized_attempts: bool = Field(
        default=True,
        description="Log unauthorized access attempts",
    )

    def is_authorized(self, user_id: int) -> bool:
        """Check if a user is authorized.

        Security: This is fail-closed by default. An empty authorized_users
        list denies all users unless allow_anonymous is explicitly True.

        Args:
            user_id: Telegram user ID to check

        Returns:
            True if user is authorized, False otherwise
        """
        # SECURITY (SIMSTIM-003): Fail-closed authorization
        if self.allow_anonymous:
            return True
        if not self.authorized_users:
            return False
        return user_id in self.authorized_users


class TimeoutConfig(BaseModel):
    """Timeout settings."""

    permission_timeout_seconds: int = Field(
        default=300,
        ge=30,
        le=3600,
        description="Timeout for permission requests (30s-1h)",
    )
    default_action: Literal["approve", "deny"] = Field(
        default="deny",
        description="Action when timeout expires",
    )
    callback_max_age_seconds: int = Field(
        default=300,
        ge=60,
        le=3600,
        description="Maximum age for callback signatures (1-60 min)",
    )


class NotificationConfig(BaseModel):
    """Notification preferences."""

    phase_transitions: bool = Field(
        default=True,
        description="Notify on Loa phase changes",
    )
    quality_gates: bool = Field(
        default=True,
        description="Notify on review/audit feedback",
    )
    notes_updates: bool = Field(
        default=False,
        description="Notify on NOTES.md changes",
    )


class Policy(BaseModel):
    """Auto-approve policy definition."""

    name: str = Field(description="Policy identifier")
    enabled: bool = Field(default=True)
    action: Literal[
        "file_create", "file_edit", "file_delete", "bash_execute", "mcp_tool"
    ]
    pattern: str = Field(description="Glob pattern to match")
    max_risk: Literal["low", "medium", "high", "critical"] = Field(
        default="medium",
        description="Maximum risk level for auto-approve",
    )


class LoaConfig(BaseModel):
    """Loa process settings."""

    command: str = Field(
        default="claude",
        description="Command to launch Loa",
    )
    working_directory: Path = Field(
        default=Path("."),
        description="Working directory for Loa process",
    )
    environment: dict[str, str] = Field(
        default_factory=dict,
        description="Additional environment variables",
    )


class AuditConfig(BaseModel):
    """Audit logging settings."""

    enabled: bool = Field(
        default=True,
        description="Enable audit logging",
    )
    log_path: Path = Field(
        default=Path("simstim-audit.jsonl"),
        description="Path to audit log file",
    )
    max_file_size_mb: int = Field(
        default=100,
        ge=1,
        le=1000,
        description="Maximum log file size before rotation",
    )
    rotate_count: int = Field(
        default=5,
        ge=1,
        le=20,
        description="Number of rotated files to keep",
    )


class ReconnectionConfig(BaseModel):
    """Reconnection settings."""

    initial_delay: float = Field(
        default=1.0,
        ge=0.1,
        description="Initial delay between reconnection attempts (seconds)",
    )
    max_delay: float = Field(
        default=300.0,
        ge=1.0,
        description="Maximum delay between reconnection attempts (seconds)",
    )
    backoff_factor: float = Field(
        default=2.0,
        ge=1.0,
        description="Exponential backoff factor",
    )


class RateLimitConfig(BaseModel):
    """Rate limiting settings."""

    requests_per_minute: int = Field(
        default=30,
        ge=1,
        le=100,
        description="Maximum requests per minute per user",
    )
    denial_backoff_base: float = Field(
        default=5.0,
        ge=1.0,
        description="Base backoff seconds after denials",
    )
    denial_threshold: int = Field(
        default=3,
        ge=1,
        description="Number of denials to trigger backoff",
    )


class SimstimConfig(BaseModel):
    """Root configuration model."""

    telegram: TelegramConfig
    security: SecurityConfig = Field(default_factory=SecurityConfig)
    timeouts: TimeoutConfig = Field(default_factory=TimeoutConfig)
    notifications: NotificationConfig = Field(default_factory=NotificationConfig)
    policies: list[Policy] = Field(default_factory=list)
    loa: LoaConfig = Field(default_factory=LoaConfig)
    audit: AuditConfig = Field(default_factory=AuditConfig)
    reconnection: ReconnectionConfig = Field(default_factory=ReconnectionConfig)
    rate_limit: RateLimitConfig = Field(default_factory=RateLimitConfig)

    @classmethod
    def from_toml(cls, path: Path) -> SimstimConfig:
        """Load configuration from TOML file with environment variable expansion."""
        with open(path, "rb") as f:
            raw_content = f.read().decode("utf-8")

        # Expand environment variables: ${VAR_NAME}
        expanded = _expand_env_vars(raw_content)

        # Parse TOML
        data = tomllib.loads(expanded)
        return cls.model_validate(data)


# Fields that are allowed to use environment variable expansion
# All other fields will reject ${...} syntax for security
_ENV_VAR_ALLOWED_FIELDS = frozenset({
    "bot_token",  # Telegram config
    "environment",  # Loa config extra env vars
})


# SECURITY (SIMSTIM-009): Whitelist of allowed environment variable names
# Only these variables can be referenced via ${VAR_NAME} syntax in config
_ALLOWED_ENV_VARS = frozenset({
    # Simstim-specific
    "SIMSTIM_BOT_TOKEN",
    "SIMSTIM_CHAT_ID",
    "SIMSTIM_AUDIT_KEY",
    "SIMSTIM_CALLBACK_SECRET",
    # Standard variables
    "HOME",
    "USER",
    "PWD",
    # Optional: Allow prefixed custom vars
})


def _is_allowed_env_var(var_name: str) -> bool:
    """Check if environment variable is in the whitelist.

    Security Note (SIMSTIM-009): Allow explicit whitelist or SIMSTIM_ prefix.

    Args:
        var_name: Environment variable name to check

    Returns:
        True if variable is allowed
    """
    # Explicit whitelist
    if var_name in _ALLOWED_ENV_VARS:
        return True
    # Allow any SIMSTIM_ prefixed variable (user-controlled)
    if var_name.startswith("SIMSTIM_"):
        return True
    return False


def _expand_env_vars(content: str) -> str:
    """Expand ${VAR_NAME} patterns with environment variable values.

    Security Note (SIMSTIM-009): Only whitelisted environment variables
    can be referenced. This prevents config-based exfiltration of
    sensitive environment variables.
    """
    pattern = re.compile(r"\$\{([^}]+)\}")

    def replacer(match: re.Match[str]) -> str:
        var_name = match.group(1).strip()

        # SECURITY (SIMSTIM-009): Validate against whitelist
        if not _is_allowed_env_var(var_name):
            raise ValueError(
                f"Environment variable '{var_name}' not in whitelist. "
                f"Only SIMSTIM_* prefixed variables and standard variables are allowed."
            )

        value = os.environ.get(var_name, "")
        if not value:
            raise ValueError(f"Environment variable {var_name} is not set")
        return value

    return pattern.sub(replacer, content)


def get_default_config_path() -> Path:
    """Get the default configuration file path."""
    # Check current directory first, then home directory
    cwd_config = Path("simstim.toml")
    if cwd_config.exists():
        return cwd_config

    home_config = Path.home() / ".config" / "simstim" / "simstim.toml"
    if home_config.exists():
        return home_config

    # Default to current directory
    return cwd_config


def create_default_config(path: Path) -> None:
    """Create a default configuration file template."""
    template = '''# Simstim Configuration
# See: https://github.com/0xHoneyJar/simstim

[telegram]
bot_token = "${SIMSTIM_BOT_TOKEN}"
chat_id = 0  # Your Telegram chat ID

[security]
# IMPORTANT: Add your Telegram user ID(s) - empty list denies ALL users!
# Get your user ID by messaging @userinfobot on Telegram
authorized_users = []  # Example: [123456789, 987654321]

# DANGER: Set to true only for local development (allows unauthenticated access)
# allow_anonymous = false

redact_patterns = ["password", "secret", "token", "api_key", "private_key"]
log_unauthorized_attempts = true

[timeouts]
permission_timeout_seconds = 300
default_action = "deny"

[notifications]
phase_transitions = true
quality_gates = true
notes_updates = false

[loa]
command = "claude"
working_directory = "."

# Example policies (uncomment to enable)
# [[policies]]
# name = "auto-approve-src-files"
# enabled = true
# action = "file_create"
# pattern = "src/**/*.{ts,tsx,js,jsx}"
# max_risk = "medium"
'''
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(template)
