"""Config merge pipeline — 4-layer config loading (SDD §4.1.1).

Precedence (lowest → highest):
1. System Zone defaults (.claude/defaults/model-config.yaml)
2. Project config (.loa.config.yaml → hounfour: section)
3. Environment variables (LOA_MODEL only)
4. CLI arguments (--model, --agent, etc.)
"""

from __future__ import annotations

import copy
import json
import os
import re
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

from loa_cheval.config.interpolation import interpolate_config, redact_config
from loa_cheval.types import ConfigError

# Try yaml import — pyyaml optional, yq fallback
try:
    import yaml

    def _load_yaml(path: str) -> Dict[str, Any]:
        with open(path) as f:
            return yaml.safe_load(f) or {}
except ImportError:
    import subprocess

    def _load_yaml(path: str) -> Dict[str, Any]:
        """Fallback: use yq to convert YAML to JSON, then parse.

        SAFETY: path comes from _find_project_root() or hardcoded defaults,
        never from user input. If config paths become user-configurable,
        this subprocess call will need input sanitization.
        """
        try:
            result = subprocess.run(
                ["yq", "-o", "json", ".", path],
                capture_output=True,
                text=True,
                timeout=5,
            )
            if result.returncode != 0:
                raise ConfigError(f"yq failed on {path}: {result.stderr}")
            return json.loads(result.stdout) if result.stdout.strip() else {}
        except FileNotFoundError:
            raise ConfigError("Neither pyyaml nor yq (mikefarah/yq) is available. Install one to load config.")


def _deep_merge(base: Dict[str, Any], overlay: Dict[str, Any]) -> Dict[str, Any]:
    """Deep merge overlay into base. Overlay values win."""
    result = copy.deepcopy(base)
    for key, value in overlay.items():
        if key in result and isinstance(result[key], dict) and isinstance(value, dict):
            result[key] = _deep_merge(result[key], value)
        else:
            result[key] = copy.deepcopy(value)
    return result


def _find_project_root() -> str:
    """Walk up from cwd to find project root (contains .loa.config.yaml or .claude/)."""
    cwd = Path.cwd()
    for parent in [cwd] + list(cwd.parents):
        if (parent / ".loa.config.yaml").exists() or (parent / ".claude").is_dir():
            return str(parent)
    return str(cwd)


def load_system_defaults(project_root: str) -> Dict[str, Any]:
    """Layer 1: System Zone defaults from .claude/defaults/model-config.yaml."""
    defaults_path = Path(project_root) / ".claude" / "defaults" / "model-config.yaml"
    if defaults_path.exists():
        return _load_yaml(str(defaults_path))
    return {}


def load_project_config(project_root: str) -> Dict[str, Any]:
    """Layer 2: Project config from .loa.config.yaml (hounfour: section)."""
    config_path = Path(project_root) / ".loa.config.yaml"
    if config_path.exists():
        full = _load_yaml(str(config_path))
        return full.get("hounfour", {})
    return {}


def load_env_overrides() -> Dict[str, Any]:
    """Layer 3: Environment variable overrides (limited scope).

    Only LOA_MODEL (alias override) is supported.
    Env vars cannot override routing, pricing, or agent bindings.
    """
    overrides = {}
    model = os.environ.get("LOA_MODEL")
    if model:
        overrides["env_model_override"] = model
    return overrides


def apply_cli_overrides(config: Dict[str, Any], cli_args: Dict[str, Any]) -> Dict[str, Any]:
    """Layer 4: CLI argument overrides (highest precedence)."""
    result = copy.deepcopy(config)

    if "model" in cli_args and cli_args["model"]:
        result["cli_model_override"] = cli_args["model"]
    if "timeout" in cli_args and cli_args["timeout"]:
        result.setdefault("defaults", {})["timeout"] = cli_args["timeout"]

    return result


def load_config(
    project_root: Optional[str] = None,
    cli_args: Optional[Dict[str, Any]] = None,
) -> Tuple[Dict[str, Any], Dict[str, str]]:
    """Load merged config through the 4-layer pipeline.

    Returns (merged_config, source_annotations).
    source_annotations maps dotted keys to their source layer.
    """
    if project_root is None:
        project_root = _find_project_root()
    if cli_args is None:
        cli_args = {}

    sources: Dict[str, str] = {}

    # Layer 1: System defaults
    defaults = load_system_defaults(project_root)
    for key in _flatten_keys(defaults):
        sources[key] = "system_defaults"

    # Layer 2: Project config
    project = load_project_config(project_root)
    for key in _flatten_keys(project):
        sources[key] = "project_config"

    # Layer 3: Env overrides
    env = load_env_overrides()
    for key in _flatten_keys(env):
        sources[key] = "env_override"

    # Merge layers 1-3
    merged = _deep_merge(defaults, project)
    merged = _deep_merge(merged, env)

    # Layer 4: CLI overrides
    merged = apply_cli_overrides(merged, cli_args)
    for key in cli_args:
        if cli_args[key] is not None:
            sources[f"cli_{key}"] = "cli_override"

    # Resolve secret interpolation
    extra_env_patterns = []
    for pattern_str in merged.get("secret_env_allowlist", []):
        try:
            extra_env_patterns.append(re.compile(pattern_str))
        except re.error as e:
            raise ConfigError(f"Invalid regex in secret_env_allowlist: {pattern_str}: {e}")

    allowed_file_dirs = merged.get("secret_paths", [])
    commands_enabled = merged.get("secret_commands_enabled", False)

    try:
        merged = interpolate_config(
            merged,
            project_root,
            extra_env_patterns=extra_env_patterns,
            allowed_file_dirs=allowed_file_dirs,
            commands_enabled=commands_enabled,
        )
    except ConfigError:
        raise
    except Exception as e:
        raise ConfigError(f"Config interpolation failed: {e}")

    return merged, sources


def get_effective_config_display(
    config: Dict[str, Any],
    sources: Dict[str, str],
) -> str:
    """Format merged config for --print-effective-config with source annotations.

    Secret values are redacted.
    """
    redacted = redact_config(config)
    lines = ["# Effective Hounfour Configuration", "# Values show source layer in comments", ""]
    _format_dict(redacted, sources, lines, prefix="")
    return "\n".join(lines)


def _format_dict(d: Dict[str, Any], sources: Dict[str, str], lines: List[str], prefix: str, indent: int = 0) -> None:
    """Recursively format dict with source annotations."""
    pad = "  " * indent
    for key, value in d.items():
        full_key = f"{prefix}.{key}" if prefix else key
        source = sources.get(full_key, "")
        source_comment = f"  # from {source}" if source else ""

        if isinstance(value, dict):
            lines.append(f"{pad}{key}:{source_comment}")
            _format_dict(value, sources, lines, full_key, indent + 1)
        elif isinstance(value, list):
            lines.append(f"{pad}{key}:{source_comment}")
            for item in value:
                if isinstance(item, dict):
                    lines.append(f"{pad}  -")
                    _format_dict(item, sources, lines, full_key, indent + 2)
                else:
                    lines.append(f"{pad}  - {item}")
        else:
            lines.append(f"{pad}{key}: {value}{source_comment}")


def _flatten_keys(d: Dict[str, Any], prefix: str = "") -> List[str]:
    """Flatten dict keys with dot notation."""
    keys = []
    for key, value in d.items():
        full_key = f"{prefix}.{key}" if prefix else key
        keys.append(full_key)
        if isinstance(value, dict):
            keys.extend(_flatten_keys(value, full_key))
    return keys


# --- Config cache (one per process) ---
# NOTE: Not thread-safe. Current use is single-threaded CLI (model-invoke).
# If loa_cheval is imported as a library in a multi-threaded application,
# wrap get_config() with threading.Lock or replace with functools.lru_cache.

_cached_config: Optional[Tuple[Dict[str, Any], Dict[str, str]]] = None
_cache_lock: Optional[Any] = None  # Lazy-init threading.Lock if needed


def get_config(project_root: Optional[str] = None, cli_args: Optional[Dict[str, Any]] = None, force_reload: bool = False) -> Dict[str, Any]:
    """Get cached config. Loads on first call, caches thereafter.

    Thread safety: safe for single-threaded CLI use. For multi-threaded
    library use, callers should synchronize externally or call load_config()
    directly.
    """
    global _cached_config
    if _cached_config is None or force_reload:
        _cached_config = load_config(project_root, cli_args)
    return _cached_config[0]


def clear_config_cache() -> None:
    """Clear the config cache. Used for testing."""
    global _cached_config
    _cached_config = None
