"""Secret interpolation for {env:VAR} and {file:path} patterns (SDD §4.1.3, §6.2).

Supports lazy interpolation (v1.35.0): auth fields under providers.* are deferred
until the specific provider is invoked, so missing env vars for unused providers
don't cause errors at config load time.

Supports credential provider chain (v1.37.0): env var resolution falls through to
encrypted store and .env.local when the variable is not in os.environ.
"""

from __future__ import annotations

import fnmatch
import functools
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

# Default paths where interpolation is deferred (lazy)
_DEFAULT_LAZY_PATHS = {"providers.*.auth"}


class LazyValue:
    """Deferred interpolation token. Resolved on first str() access.

    Used for provider auth fields so that missing env vars for unused
    providers don't cause errors at config load time.
    """

    def __init__(
        self,
        raw: str,
        project_root: str,
        extra_env_patterns: List[re.Pattern] = (),
        allowed_file_dirs: List[str] = (),
        commands_enabled: bool = False,
        context: Optional[Dict[str, str]] = None,
    ):
        self._raw = raw
        self._project_root = project_root
        self._extra_env_patterns = list(extra_env_patterns)
        self._allowed_file_dirs = list(allowed_file_dirs)
        self._commands_enabled = commands_enabled
        self._context = context or {}
        self._resolved: Optional[str] = None

    def resolve(self) -> str:
        """Resolve the interpolation token. Caches result on first call."""
        if self._resolved is None:
            try:
                self._resolved = interpolate_value(
                    self._raw,
                    self._project_root,
                    self._extra_env_patterns,
                    self._allowed_file_dirs,
                    self._commands_enabled,
                )
            except ConfigError as e:
                # Enhance error message with provider context
                provider = self._context.get("provider", "unknown")
                agent = self._context.get("agent", "")
                hint = ""
                # Extract env var name from the raw token for hint
                m = _INTERP_RE.search(self._raw)
                if m and m.group(1) == "env":
                    var_name = m.group(2)
                    hint = f"\n  Hint: Run '/loa-credentials set {var_name}' to configure."
                agent_note = f"\n  Agent: {agent}" if agent else ""
                raise ConfigError(
                    f"Environment variable required by provider '{provider}' (auth field).{agent_note}{hint}\n  Original error: {e}"
                ) from e
        return self._resolved

    @property
    def raw(self) -> str:
        """The unresolved interpolation template string."""
        return self._raw

    def __str__(self) -> str:
        return self.resolve()

    def __repr__(self) -> str:
        return f"LazyValue({self._raw!r})"

    def __bool__(self) -> bool:
        return bool(self._raw)

    def __eq__(self, other: object) -> bool:
        """Compare LazyValue with another value.

        - vs str: resolves this LazyValue and compares resolved value.
        - vs LazyValue: compares raw templates (avoids triggering resolution).
        """
        if isinstance(other, str):
            return self.resolve() == other
        if isinstance(other, LazyValue):
            return self._raw == other._raw
        return NotImplemented

    def __hash__(self) -> int:
        return hash(self._raw)


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


@functools.lru_cache(maxsize=1)
def _get_credential_provider(project_root: str):
    """Get the credential provider chain (lazily initialized, thread-safe).

    Uses lru_cache(maxsize=1) for thread-safe singleton initialization
    without explicit global mutable state.
    """
    try:
        from loa_cheval.credentials.providers import get_credential_provider
        return get_credential_provider(project_root)
    except Exception:
        return None


def _reset_credential_provider():
    """Reset credential provider cache. Used for testing."""
    _get_credential_provider.cache_clear()


def _resolve_env(var_name: str, project_root: str) -> Optional[str]:
    """Resolve an environment variable through the credential provider chain.

    Priority: os.environ → encrypted store → .env.local
    Falls back to os.environ alone if credential module unavailable.
    """
    # Direct env var check first (fastest path)
    val = os.environ.get(var_name)
    if val is not None:
        return val

    # Try credential provider chain (encrypted store, dotenv)
    provider = _get_credential_provider(project_root)
    if provider is not None:
        val = provider.get(var_name)
        if val is not None:
            return val

    return None


def interpolate_value(
    value: str,
    project_root: str,
    extra_env_patterns: List[re.Pattern] = (),
    allowed_file_dirs: List[str] = (),
    commands_enabled: bool = False,
) -> str:
    """Resolve interpolation tokens in a string value.

    Supports:
      {env:VAR_NAME} — read from credential chain: env → encrypted → .env.local
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
            val = _resolve_env(source_ref, project_root)
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


def _matches_lazy_path(dotted_path: str, lazy_paths: Set[str]) -> bool:
    """Check if a dotted config key path matches any lazy path pattern.

    Supports '*' as a single-segment wildcard.
    Example: 'providers.openai.auth' matches 'providers.*.auth'
    """
    for pattern in lazy_paths:
        if fnmatch.fnmatch(dotted_path, pattern):
            return True
    return False


def interpolate_config(
    config: Dict[str, Any],
    project_root: str,
    extra_env_patterns: List[re.Pattern] = (),
    allowed_file_dirs: List[str] = (),
    commands_enabled: bool = False,
    _secret_keys: Optional[Set[str]] = None,
    lazy_paths: Optional[Set[str]] = None,
    _current_path: str = "",
) -> Dict[str, Any]:
    """Recursively interpolate all string values in a config dict.

    Returns a new dict with resolved values.
    Tracks which keys contained secrets for redaction.

    Args:
        lazy_paths: Set of dotted key patterns where interpolation is deferred.
            Defaults to _DEFAULT_LAZY_PATHS (providers.*.auth).
            Pass empty set() to disable lazy behavior entirely.
    """
    if _secret_keys is None:
        _secret_keys = set()
    if lazy_paths is None:
        lazy_paths = _DEFAULT_LAZY_PATHS

    result = {}
    for key, value in config.items():
        full_path = f"{_current_path}.{key}" if _current_path else key

        if isinstance(value, str) and _INTERP_RE.search(value):
            _secret_keys.add(key)
            if lazy_paths and _matches_lazy_path(full_path, lazy_paths):
                # Defer resolution — wrap in LazyValue
                # Extract provider name from path for error context
                parts = full_path.split(".")
                provider_name = parts[1] if len(parts) >= 2 else "unknown"
                result[key] = LazyValue(
                    raw=value,
                    project_root=project_root,
                    extra_env_patterns=extra_env_patterns,
                    allowed_file_dirs=allowed_file_dirs,
                    commands_enabled=commands_enabled,
                    context={"provider": provider_name},
                )
            else:
                result[key] = interpolate_value(value, project_root, extra_env_patterns, allowed_file_dirs, commands_enabled)
        elif isinstance(value, dict):
            result[key] = interpolate_config(
                value, project_root, extra_env_patterns, allowed_file_dirs,
                commands_enabled, _secret_keys, lazy_paths, full_path,
            )
        elif isinstance(value, list):
            result[key] = [
                interpolate_config(
                    item, project_root, extra_env_patterns, allowed_file_dirs,
                    commands_enabled, _secret_keys, lazy_paths, full_path,
                )
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
    LazyValue instances are redacted without triggering resolution.
    """
    result = {}
    for key, value in config.items():
        if isinstance(value, dict):
            result[key] = redact_config(value, secret_keys)
        elif isinstance(value, LazyValue):
            # Redact without resolving — show raw template
            sources = _INTERP_RE.findall(value.raw)
            annotations = ", ".join(f"{t}:{r}" for t, r in sources)
            result[key] = f"{REDACTED} (lazy: {annotations})"
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
