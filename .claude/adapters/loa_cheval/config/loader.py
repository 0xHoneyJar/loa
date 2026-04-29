"""Config merge pipeline — 4-layer config loading (SDD §4.1.1).

Precedence (lowest → highest):
1. System Zone defaults (.claude/defaults/model-config.yaml)
2. Project config (.loa.config.yaml → hounfour: section)
3. Environment variables (LOA_MODEL only)
4. CLI arguments (--model, --agent, etc.)

Post-merge steps (cycle-095 Sprint 1):
A. Force-legacy-aliases kill-switch (SDD §1.4.5): if env or experimental
   config flag is set, replace `aliases:` with the pre-cycle-095 snapshot.
B. Endpoint-family strict validation (SDD §3.4): every providers.openai.models.*
   entry MUST declare `endpoint_family: chat | responses`.
"""

from __future__ import annotations

import copy
import json
import logging
import os
import re
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

from loa_cheval.config.interpolation import interpolate_config, redact_config
from loa_cheval.types import ConfigError

logger = logging.getLogger("loa_cheval.config.loader")

# Module-level guard so the force-legacy-aliases WARN fires at most once per
# process even when load_config() is invoked multiple times (cache-clear,
# tests, --print-effective-config).
_force_legacy_warned = False
_endpoint_family_default_warned: set[str] = set()


def _reset_warning_state_for_tests() -> None:
    """Reset module-level warning trackers. Used only by test fixtures."""
    global _force_legacy_warned
    _force_legacy_warned = False
    _endpoint_family_default_warned.clear()

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

    # cycle-095 Sprint 1 post-merge step A — force-legacy-aliases kill-switch
    # (SDD §1.4.5). Replaces `aliases:` block with the pre-cycle-095 snapshot
    # AND short-circuits tier_groups apply (Sprint 3 will add that step).
    merged = _maybe_apply_force_legacy_aliases(merged, project_root, sources)

    # cycle-095 Sprint 1 post-merge step B — endpoint_family strict validation
    # (SDD §3.4). Walks providers.openai.models and raises ConfigError on
    # missing/unknown values. Honors LOA_LEGACY_ENDPOINT_FAMILY_DEFAULT=chat
    # env-var backstop with WARN per affected entry.
    _validate_endpoint_family(merged)

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


# --- cycle-095 Sprint 1 post-merge helpers (SDD §1.4.5, §3.4) ---


_LEGACY_ALIASES_FILENAME = "aliases-legacy.yaml"


def _force_legacy_aliases_active(merged: Dict[str, Any]) -> bool:
    """Return True if either the env var or experimental config flag is set.

    Precedence: env var wins on conflict. If LOA_FORCE_LEGACY_ALIASES is set
    to a truthy value, the kill-switch fires regardless of the config flag —
    matching the documented "operator-side incident escape hatch" semantics.
    """
    env = os.environ.get("LOA_FORCE_LEGACY_ALIASES", "").strip().lower()
    if env in ("1", "true", "yes", "on"):
        return True
    flag = merged.get("experimental", {}).get("force_legacy_aliases", False)
    if isinstance(flag, str):
        flag = flag.strip().lower() in ("true", "yes", "on", "1")
    return bool(flag)


def _alias_target_resolves(target: Any, merged: Dict[str, Any]) -> bool:
    """Check whether an alias target resolves to an existing model entry.

    Accepts the canonical 'provider:model_id' form. Special-cases the reserved
    'claude-code:session' (Claude Code native runtime — no provider entry).
    Anything else is rejected.
    """
    if not isinstance(target, str) or ":" not in target:
        return False
    provider, model_id = target.split(":", 1)
    if not provider or not model_id:
        return False
    if provider == "claude-code":
        # Reserved native-runtime tag — no providers.<...> entry expected.
        return model_id == "session"
    providers = (merged.get("providers") or {}).get(provider) or {}
    models = providers.get("models") or {}
    return isinstance(models, dict) and model_id in models


def _maybe_apply_force_legacy_aliases(
    merged: Dict[str, Any],
    project_root: str,
    sources: Dict[str, str],
) -> Dict[str, Any]:
    """Replace `aliases:` block with the pre-cycle-095 snapshot when active.

    Per SDD §1.4.5: critical invariant — each restored alias still routes per
    its own model entry's `endpoint_family`. There is no endpoint-force layer.
    """
    global _force_legacy_warned
    if not _force_legacy_aliases_active(merged):
        return merged

    snapshot_path = Path(project_root) / ".claude" / "defaults" / _LEGACY_ALIASES_FILENAME
    if not snapshot_path.exists():
        # Loud failure: kill-switch is asked for but the snapshot file is
        # missing (deployment integrity issue). Do not silently fall back.
        raise ConfigError(
            f"LOA_FORCE_LEGACY_ALIASES is set but {snapshot_path} is missing. "
            f"Reinstall or restore the file from the cycle-095 release."
        )

    try:
        snapshot = _load_yaml(str(snapshot_path)) or {}
    except Exception as exc:
        raise ConfigError(f"Failed to parse {snapshot_path}: {exc}") from exc

    legacy_aliases = snapshot.get("aliases")
    if not isinstance(legacy_aliases, dict) or not legacy_aliases:
        raise ConfigError(
            f"{snapshot_path} does not contain a non-empty `aliases:` block. "
            f"Restore the file from the cycle-095 release."
        )

    # cycle-095 Sprint 1 review-iter-2 (DISS-002): validate that every restored
    # alias target still resolves to an existing model entry in the merged
    # config. Without this gate, an operator who removed a model from their
    # custom config would have the kill-switch restore an alias pointing
    # nowhere — the rollback designed to RESTORE service would WORSEN the
    # outage by routing traffic to unresolvable models.
    unresolved = []
    for alias_name, target in legacy_aliases.items():
        if not _alias_target_resolves(target, merged):
            unresolved.append(f"{alias_name} -> {target}")
    if unresolved:
        raise ConfigError(
            f"LOA_FORCE_LEGACY_ALIASES would restore aliases pointing to "
            f"models that no longer exist in this config: "
            f"{', '.join(unresolved)}. Either re-add the missing models OR "
            f"unset the kill-switch and use per-alias pins via aliases: "
            f"{{...}} in .loa.config.yaml."
        )

    if not _force_legacy_warned:
        logger.warning(
            "LOA_FORCE_LEGACY_ALIASES kill-switch active — replaced %d alias entries "
            "with %s. Each restored alias still routes per its own endpoint_family. "
            "Unset to restore normal cycle-095 alias resolution.",
            len(legacy_aliases),
            _LEGACY_ALIASES_FILENAME,
        )
        _force_legacy_warned = True

    out = copy.deepcopy(merged)
    out["aliases"] = copy.deepcopy(legacy_aliases)
    # Mark the override in source annotations so --print-effective-config
    # surfaces the kill-switch as the alias provenance.
    for alias_name in legacy_aliases:
        sources[f"aliases.{alias_name}"] = "force_legacy_aliases_kill_switch"
    return out


_ALLOWED_ENDPOINT_FAMILIES = ("chat", "responses")


def _validate_endpoint_family(merged: Dict[str, Any]) -> None:
    """Reject merged configs that lack `endpoint_family` on OpenAI models.

    Honors `LOA_LEGACY_ENDPOINT_FAMILY_DEFAULT=chat` env-var backstop:
    when set, missing values default to "chat" with a per-entry WARN
    rather than raising. The env var is the operator-side migration aid for
    custom OpenAI entries declared in `.loa.config.yaml`.
    """
    backstop_raw = os.environ.get("LOA_LEGACY_ENDPOINT_FAMILY_DEFAULT", "").strip().lower()
    backstop_active = backstop_raw == "chat"
    if backstop_raw and not backstop_active:
        # Only "chat" is supported as a backstop value (the only legacy default
        # that ever existed pre-cycle-095). "responses" or anything else is
        # operator confusion — fail loudly.
        raise ConfigError(
            f"LOA_LEGACY_ENDPOINT_FAMILY_DEFAULT={backstop_raw!r} is not supported. "
            f"Only 'chat' is allowed (matches the pre-cycle-095 implicit default)."
        )

    providers = merged.get("providers", {}) or {}
    openai_models = ((providers.get("openai") or {}).get("models")) or {}
    if not isinstance(openai_models, dict):
        # Defensive: malformed YAML produces a non-dict — caller will fail
        # later, but emit a precise diagnostic now.
        raise ConfigError(
            "providers.openai.models must be a mapping; "
            f"got {type(openai_models).__name__}."
        )

    for model_id, model_data in openai_models.items():
        # cycle-095 Sprint 1 review-iter-2 (DISS-001): non-dict entries are a
        # config-shape error, not a deferral target. Raising here gives the
        # operator a precise pointer to the malformed YAML; deferring to the
        # adapter produced opaque AttributeError-style failures (PRD R-13).
        if not isinstance(model_data, dict):
            raise ConfigError(
                f"providers.openai.models.{model_id} must be a mapping with "
                f"endpoint_family + capabilities + ..., got "
                f"{type(model_data).__name__} ({model_data!r}). "
                f"Check your .loa.config.yaml or System Zone defaults file."
            )
        family = model_data.get("endpoint_family")
        if family is None:
            if backstop_active:
                if model_id not in _endpoint_family_default_warned:
                    logger.warning(
                        "providers.openai.models.%s missing endpoint_family — "
                        "defaulting to 'chat' under LOA_LEGACY_ENDPOINT_FAMILY_DEFAULT. "
                        "Migrate by adding 'endpoint_family: chat' to your config; "
                        "this fallback will be removed in cycle-100+.",
                        model_id,
                    )
                    _endpoint_family_default_warned.add(model_id)
                model_data["endpoint_family"] = "chat"
                continue
            raise ConfigError(
                f"providers.openai.models.{model_id} is missing required 'endpoint_family'. "
                f"Add 'endpoint_family: chat' or 'endpoint_family: responses' to your "
                f"config (cycle-095 Sprint 1 migration). For a one-shot backward-compat "
                f"shim, set LOA_LEGACY_ENDPOINT_FAMILY_DEFAULT=chat."
            )
        if family not in _ALLOWED_ENDPOINT_FAMILIES:
            raise ConfigError(
                f"providers.openai.models.{model_id} has invalid "
                f"endpoint_family={family!r}. Allowed values: "
                f"{', '.join(_ALLOWED_ENDPOINT_FAMILIES)}."
            )


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
