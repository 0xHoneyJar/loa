"""Configuration models for Simstim.

Type-safe configuration using Pydantic with TOML loading and
environment variable expansion.
"""

from __future__ import annotations

import os
import re
import tomllib
from pathlib import Path
from typing import Literal

from pydantic import BaseModel, Field, SecretStr


class TelegramConfig(BaseModel):
    """Telegram bot configuration."""

    bot_token: SecretStr = Field(description="Bot token from @BotFather")
    chat_id: int = Field(description="Target chat ID for notifications")


class SecurityConfig(BaseModel):
    """Security settings."""

    authorized_users: list[int] = Field(
        default_factory=list,
        description="Telegram user IDs allowed to interact",
    )
    redact_patterns: list[str] = Field(
        default=["password", "secret", "token", "api_key", "private_key"],
        description="Patterns to redact from notifications",
    )
    log_unauthorized_attempts: bool = Field(
        default=True,
        description="Log unauthorized access attempts",
    )


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


def _expand_env_vars(content: str) -> str:
    """Expand ${VAR_NAME} patterns with environment variable values."""
    pattern = re.compile(r"\$\{([^}]+)\}")

    def replacer(match: re.Match[str]) -> str:
        var_name = match.group(1)
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
authorized_users = []  # Add your Telegram user ID(s)
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
