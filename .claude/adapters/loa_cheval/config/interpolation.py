"""Secret interpolation for {env:VAR} and {file:path} patterns (SDD §4.1.3, §6.2)."""

from __future__ import annotations

import os
import re
import stat
from pathlib import Path
from typing import Any, Dict, List, Optional, Set

from loa_cheval.types import ConfigError

# Core allowlist — always applied
_CORE_ENV_PATTERNS = [
    re.compile(r"^LOA_"),
    re.compile(r"^OPENAI_API_KEY$"),
    re.compile(r"^ANTHROPIC_API_KEY$"),
    re.compile(r"^MOONSHOT_API_KEY$"),
]

# Regex for interpolation tokens
_INTERP_RE = re.compile(r"\{(env|file|cmd):([^}]+)\}")

# Sentinel for redacted values
REDACTED = "***REDACTED***"


def _check_env_allowed(var_name: str, extra_patterns: List[re.Pattern] = ()) -> bool:
    """Check if env var name is in the allowlist."""
    for pattern in _CORE_ENV_PATTERNS:
        if pattern.search(var_name):
            return True
    for pattern in extra_patterns:
        if pattern.search(var_name):
            return True
    return False


def _check_file_allowed(
    file_path: str,
    project_root: str,
    allowed_dirs: List[str] = (),
) -> str:
    """Validate and resolve a file path for secret reading.

    Returns the resolved absolute path.
    Raises ConfigError on validation failure.
    """
    path = Path(file_path)

    # Resolve relative to project root
    if not path.is_absolute():
        path = Path(project_root) / path

    resolved = path.resolve()

    # Check symlink
    if path.is_symlink():
        raise ConfigError(f"Secret file must not be a symlink: {file_path}")

    # Check allowed directories
    config_d = Path(project_root) / ".loa.config.d"
    allowed = [config_d] + [Path(d) for d in allowed_dirs]

    in_allowed = False
    for allowed_dir in allowed:
        try:
            resolved.relative_to(allowed_dir.resolve())
            in_allowed = True
            break
        except ValueError:
            continue

    if not in_allowed:
        raise ConfigError(
            f"Secret file '{file_path}' not in allowed directories. "
            f"Allowed: .loa.config.d/ or paths in hounfour.secret_paths"
        )

    # Check file exists
    if not resolved.is_file():
        raise ConfigError(f"Secret file not found: {resolved}")

    # Check ownership (must be current user)
    file_stat = resolved.stat()
    if file_stat.st_uid != os.getuid():
        raise ConfigError(f"Secret file not owned by current user: {resolved}")

    # Check mode (<= 0640)
    mode = stat.S_IMODE(file_stat.st_mode)
    if mode & 0o137:  # Any of: group write, other read/write/exec
        raise ConfigError(f"Secret file has unsafe permissions ({oct(mode)}): {resolved}. Must be <= 0640")

    return str(resolved)


def interpolate_value(
    value: str,
    project_root: str,
    extra_env_patterns: List[re.Pattern] = (),
    allowed_file_dirs: List[str] = (),
    commands_enabled: bool = False,
) -> str:
    """Resolve interpolation tokens in a string value.

    Supports:
      {env:VAR_NAME} — read from environment (allowlisted)
      {file:/path}   — read from file (restricted directories)
      {cmd:command}   — execute command (disabled by default)
    """

    def _replace(match: re.Match) -> str:
        source_type = match.group(1)
        source_ref = match.group(2)

        if source_type == "env":
            if not _check_env_allowed(source_ref, extra_env_patterns):
                raise ConfigError(
                    f"Environment variable '{source_ref}' is not in the allowlist. "
                    f"Allowed: ^LOA_.*, ^OPENAI_API_KEY$, ^ANTHROPIC_API_KEY$, ^MOONSHOT_API_KEY$"
                )
            val = os.environ.get(source_ref)
            if val is None:
                raise ConfigError(f"Environment variable '{source_ref}' is not set")
            return val

        elif source_type == "file":
            resolved_path = _check_file_allowed(source_ref, project_root, allowed_file_dirs)
            return Path(resolved_path).read_text().strip()

        elif source_type == "cmd":
            if not commands_enabled:
                raise ConfigError("Command interpolation ({cmd:...}) is disabled. Set hounfour.secret_commands_enabled: true")
            raise ConfigError("Command interpolation not yet implemented")

        raise ConfigError(f"Unknown interpolation type: {source_type}")

    return _INTERP_RE.sub(_replace, value)


def interpolate_config(
    config: Dict[str, Any],
    project_root: str,
    extra_env_patterns: List[re.Pattern] = (),
    allowed_file_dirs: List[str] = (),
    commands_enabled: bool = False,
    _secret_keys: Optional[Set[str]] = None,
) -> Dict[str, Any]:
    """Recursively interpolate all string values in a config dict.

    Returns a new dict with resolved values.
    Tracks which keys contained secrets for redaction.
    """
    if _secret_keys is None:
        _secret_keys = set()

    result = {}
    for key, value in config.items():
        if isinstance(value, str) and _INTERP_RE.search(value):
            _secret_keys.add(key)
            result[key] = interpolate_value(value, project_root, extra_env_patterns, allowed_file_dirs, commands_enabled)
        elif isinstance(value, dict):
            result[key] = interpolate_config(value, project_root, extra_env_patterns, allowed_file_dirs, commands_enabled, _secret_keys)
        elif isinstance(value, list):
            result[key] = [
                interpolate_config(item, project_root, extra_env_patterns, allowed_file_dirs, commands_enabled, _secret_keys)
                if isinstance(item, dict)
                else interpolate_value(item, project_root, extra_env_patterns, allowed_file_dirs, commands_enabled)
                if isinstance(item, str) and _INTERP_RE.search(item)
                else item
                for item in value
            ]
        else:
            result[key] = value
    return result


def redact_config(config: Dict[str, Any], secret_keys: Optional[Set[str]] = None) -> Dict[str, Any]:
    """Create a redacted copy of config for display/logging.

    Values sourced from {env:} or {file:} show '***REDACTED*** (from ...)' instead of actual values.
    """
    result = {}
    for key, value in config.items():
        if isinstance(value, dict):
            result[key] = redact_config(value, secret_keys)
        elif isinstance(value, str) and _INTERP_RE.search(value):
            # Show source annotation without actual value
            sources = _INTERP_RE.findall(value)
            annotations = ", ".join(f"{t}:{r}" for t, r in sources)
            result[key] = f"{REDACTED} (from {annotations})"
        elif key == "auth" or key.endswith("_key") or key.endswith("_secret"):
            result[key] = REDACTED
        else:
            result[key] = value
    return result
