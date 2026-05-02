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
import sys
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

    # cycle-095 Sprint 2 post-merge step C — fold backward_compat_aliases
    # into the resolved aliases: dict so the Python resolver can chain
    # through legacy keys (matches the bash adapter's gen-adapter-maps.sh
    # behavior). Existing aliases win on key collision — SSOT precedence
    # (SDD §6.3 + Task 2.2). The resolver gets the legacy-key set so it
    # can emit one-time INFO logs on first resolution.
    _fold_backward_compat_aliases(merged)

    # cycle-096 Sprint 1 post-merge step D — Bedrock compliance_profile
    # defaulting (SDD §5.6, Task 1.5). 4-step deterministic rule replaces
    # null with bedrock_only / prefer_bedrock / unset based on env-var state.
    # Also enforces the SKP-003 gate: prefer_bedrock requires explicit
    # fallback_to on every model (no heuristic name matching).
    _resolve_bedrock_compliance_profile(merged)
    _reject_unsupported_bedrock_auth_modes(merged)
    _reject_unsupported_bedrock_auth_lifetime(merged)

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


def _fold_backward_compat_aliases(merged: Dict[str, Any]) -> None:
    """Merge backward_compat_aliases into aliases (existing aliases win).

    Mirrors the bash mirror's behavior in gen-adapter-maps.sh: the union of
    aliases + backward_compat_aliases is what alias resolution consults.
    Hands the legacy-key set to the resolver for once-per-process INFO
    logging.
    """
    bcompat_raw = merged.get("backward_compat_aliases") or {}
    if not isinstance(bcompat_raw, dict) or not bcompat_raw:
        # Either no entries or malformed — clear any prior state (matters for
        # tests that re-load with different configs).
        from loa_cheval.routing.resolver import set_legacy_alias_keys

        set_legacy_alias_keys(set())
        return

    aliases = merged.setdefault("aliases", {})
    if not isinstance(aliases, dict):
        # Malformed; let resolver fail loud later. Don't try to merge.
        return

    folded_keys: set[str] = set()
    for key, target in bcompat_raw.items():
        if not isinstance(key, str) or not isinstance(target, str):
            continue
        # Existing aliases entry wins on collision (SSOT precedence).
        if key not in aliases:
            aliases[key] = target
        folded_keys.add(key)

    from loa_cheval.routing.resolver import set_legacy_alias_keys

    set_legacy_alias_keys(folded_keys)


# ---------------------------------------------------------------------------
# cycle-096 Sprint 1 Task 1.5 — Bedrock compliance_profile defaulting (SDD §5.6)
# ---------------------------------------------------------------------------

# Module-level latch: emit the migration notice exactly once per process.
_bedrock_migration_notice_emitted: bool = False


def _resolve_bedrock_compliance_profile(merged: Dict[str, Any]) -> None:
    """Apply the 4-step deterministic rule for ``providers.bedrock.compliance_profile``.

    The rule (SDD §5.6, PRD §G-S0-3):

    1. If user ``.loa.config.yaml`` explicitly sets the field → keep it.
    2. Else if ``AWS_BEARER_TOKEN_BEDROCK`` is set AND ``ANTHROPIC_API_KEY``
       is NOT set → default to ``bedrock_only`` (single-provider posture;
       fail-closed protects compliance).
    3. Else if both env vars are set → default to ``prefer_bedrock``
       (warned-fallback never silent).
    4. Else if ``AWS_BEARER_TOKEN_BEDROCK`` is unset → leave None
       (Bedrock provider unused).

    Mutates ``merged`` in place: writes the resolved value back to the
    bedrock provider entry. The first time defaulting fires (rule 2 or 3),
    we emit a one-shot stderr notice gated by a sentinel file at
    ``${LOA_CACHE_DIR:-.run}/bedrock-migration-acked.sentinel``.
    """
    providers = (merged.get("providers") or {})
    bedrock = providers.get("bedrock")
    if not isinstance(bedrock, dict):
        return  # No bedrock provider configured.

    explicit = bedrock.get("compliance_profile")
    if isinstance(explicit, str) and explicit:
        # Rule 1 — explicit override wins; validate and keep.
        if explicit not in ("bedrock_only", "prefer_bedrock", "none"):
            raise ConfigError(
                f"providers.bedrock.compliance_profile must be one of "
                f"'bedrock_only' | 'prefer_bedrock' | 'none' (got {explicit!r})"
            )
        # Validate prefer_bedrock invariant before returning.
        if explicit == "prefer_bedrock":
            _enforce_prefer_bedrock_fallback_to(bedrock)
        return

    has_bedrock_token = bool(os.environ.get("AWS_BEARER_TOKEN_BEDROCK"))
    has_anthropic_key = bool(os.environ.get("ANTHROPIC_API_KEY"))

    if not has_bedrock_token:
        # Rule 4 — Bedrock provider not in use; field stays None.
        bedrock["compliance_profile"] = None
        return

    if has_bedrock_token and not has_anthropic_key:
        resolved = "bedrock_only"  # Rule 2.
    else:
        resolved = "prefer_bedrock"  # Rule 3.

    bedrock["compliance_profile"] = resolved

    if resolved == "prefer_bedrock":
        # Validate fallback_to is declared on every Bedrock model
        # (Flatline BLOCKER SKP-003 — no heuristic name matching).
        _enforce_prefer_bedrock_fallback_to(bedrock)

    _maybe_emit_bedrock_migration_notice(merged, resolved)


def _enforce_prefer_bedrock_fallback_to(bedrock: Dict[str, Any]) -> None:
    """Reject prefer_bedrock when any Bedrock model lacks fallback_to.

    Per Flatline v1.1 BLOCKER SKP-003 (SDD §6.2): no heuristic name matching;
    the operator must declare an explicit ``provider:model_id`` fallback per
    model entry. Loader fails loud at load time so the operator sees the
    problem before any request fires.
    """
    models = bedrock.get("models") or {}
    if not isinstance(models, dict):
        return
    missing = [
        model_id
        for model_id, mc in models.items()
        if isinstance(mc, dict) and not mc.get("fallback_to")
    ]
    if missing:
        raise ConfigError(
            "providers.bedrock.compliance_profile=prefer_bedrock requires "
            "every Bedrock model entry to declare `fallback_to: <provider>:<model_id>`. "
            f"Missing on: {missing}. "
            "(Flatline BLOCKER SKP-003 — no heuristic name matching; operator "
            "must declare equivalence explicitly.)"
        )


def _maybe_emit_bedrock_migration_notice(merged: Dict[str, Any], resolved: str) -> None:
    """One-shot stderr notice on first defaulting, gated by sentinel file.

    Sentinel path honors ``LOA_CACHE_DIR`` (default ``.run``). Submodule
    consumers can pre-create the sentinel to silence the notice in CI.
    """
    global _bedrock_migration_notice_emitted
    if _bedrock_migration_notice_emitted:
        return

    cache_dir = os.environ.get("LOA_CACHE_DIR") or ".run"
    sentinel_path = Path(cache_dir) / "bedrock-migration-acked.sentinel"
    if sentinel_path.exists():
        _bedrock_migration_notice_emitted = True
        return

    sys.stderr.write(
        f"[loa-cheval] Bedrock provider defaulting compliance_profile to "
        f"{resolved!r} (SDD §5.6 / PRD G-S0-3). Override in .loa.config.yaml: "
        f"hounfour.bedrock.compliance_profile: bedrock_only | prefer_bedrock | none. "
        f"Suppress this notice by touching {sentinel_path}.\n"
    )

    # Try to create the sentinel so subsequent processes silently skip.
    try:
        sentinel_path.parent.mkdir(parents=True, exist_ok=True)
        sentinel_path.touch()
    except OSError:
        # Best-effort; if we can't create the sentinel (read-only FS, etc.),
        # the notice will print again next process. Acceptable v1.
        pass

    _bedrock_migration_notice_emitted = True


def _reject_unsupported_bedrock_auth_modes(merged: Dict[str, Any]) -> None:
    """Reject `auth_modes` lists that v1 cannot actually honor.

    Schema allows `[api_key, sigv4]` for forward compat with FR-4 v2, but
    v1 only honors `api_key`. If the operator sets `auth_modes: [sigv4]`
    (no api_key), we surface a loud error rather than silently defaulting
    to api_key behavior.
    """
    providers = (merged.get("providers") or {})
    bedrock = providers.get("bedrock")
    if not isinstance(bedrock, dict):
        return
    modes = bedrock.get("auth_modes")
    if modes is None:
        return
    if not isinstance(modes, list):
        raise ConfigError(
            f"providers.bedrock.auth_modes must be a list, got {type(modes).__name__}"
        )
    if "api_key" not in modes:
        raise ConfigError(
            "providers.bedrock.auth_modes must include 'api_key' in v1. "
            "SigV4/IAM auth is designed not built — track v2 status in "
            "grimoires/loa/proposals/bedrock-sigv4-v2.md (Sprint 2 stub) "
            "and the next-cycle planning."
        )


def _reject_unsupported_bedrock_auth_lifetime(merged: Dict[str, Any]) -> None:
    """Reject `auth_lifetime: short` per SDD §9 NFR-Sec11.

    The `auth_lifetime` schema field is documented for forward compat with
    short-lived (≤12h) token rotation flows, but v1 does not implement the
    rotation-window enforcement code path. Silently accepting `short` would
    let operators believe they have rotation enforcement when they do not.

    Honored values v1: `long` (default), absent (treated as `long`).
    Rejected values v1: `short` (with pointer to the next-cycle proposal).
    """
    providers = (merged.get("providers") or {})
    bedrock = providers.get("bedrock")
    if not isinstance(bedrock, dict):
        return
    lifetime = bedrock.get("auth_lifetime")
    if lifetime is None:
        return
    if not isinstance(lifetime, str):
        raise ConfigError(
            f"providers.bedrock.auth_lifetime must be a string, got "
            f"{type(lifetime).__name__}"
        )
    if lifetime == "long":
        return
    if lifetime == "short":
        raise ConfigError(
            "providers.bedrock.auth_lifetime: short is documented in "
            "SDD §9 NFR-Sec11 but not implemented in v1 — the rotation-"
            "window enforcement path is designed not built. Use 'long' "
            "(or omit the field) until short-mode lands. Track v2 in "
            "grimoires/loa/proposals/bedrock-sigv4-v2.md."
        )
    raise ConfigError(
        f"providers.bedrock.auth_lifetime must be 'long' or 'short', got "
        f"{lifetime!r}. v1 honors only 'long'; 'short' is reserved for v2."
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
