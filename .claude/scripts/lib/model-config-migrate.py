"""model-config-migrate — pure v1→v2 migration logic per cycle-099 SDD §3.1.1.1.

This module is the contract surface; the CLI driver
.claude/scripts/loa-migrate-model-config.py wraps it with file I/O + report
formatting + exit-code handling.

The single public function `migrate_v1_to_v2` is pure: takes a parsed v1 dict
(plus optional cycle-026 model-permissions dict), returns a parsed v2 dict
and a structured change report. No I/O. Idempotent on v2 input.

Schema version detection:
  - missing `schema_version` key  → treated as v1 (cycle-095 vintage)
  - `schema_version: 1`           → v1
  - `schema_version: 2`           → v2 (idempotent no-op + WARN)
  - `schema_version: ≥3`          → unsupported (caller raises exit 78)

Field-level migration table (SDD §3.1.1.1):
  Pass-through (silent):
    providers.<p>.models.<id>.{capabilities, context_window, …}
    aliases.<name>
  Populated with §3.1.2 defaults (INFO each):
    tier_groups.mappings.<tier>.<provider>     (cycle-095 empty maps)
  Auto-rename when value is a tier-tag (INFO):
    agents.<skill>.model: <tier>  →  agents.<skill>.default_tier: <tier>
  Merged from cycle-026 standalone file (INFO each):
    model-permissions.yaml entries → providers.<p>.models.<id>.permissions
  Renamed at model level (INFO each):
    endpoint_class                 →  endpoint_family
  Archived (WARN each):
    fields removed in v2 → top-level _archived_v1_fields:
  Preserved with namespace (WARN each):
    operator-added top-level keys → top-level _unknown_v1_fields:
"""

from __future__ import annotations

import copy
from typing import Any

# Tier-tags whose presence in `agents.<skill>.model:` triggers rename to
# `agents.<skill>.default_tier:`. Custom aliases (e.g., 'opus', 'reviewer')
# stay under `model:` — they are not formal tiers per SDD §3.1.2.
TIER_TAGS = frozenset({"max", "cheap", "mid", "tiny"})

# Top-level keys recognized as v1 schema. Any other top-level key in a v1
# input is treated as operator-added "unknown" and namespaced into
# _unknown_v1_fields:.
KNOWN_V1_TOP_KEYS = frozenset(
    {
        "schema_version",
        "providers",
        "aliases",
        "backward_compat_aliases",
        "agents",
        "tier_groups",
        "routing",
        "retry",
        "metering",
        "defaults",
    }
)

# Within a model entry, v1→v2 renames. Add new entries here as the v2 schema
# evolves; the migrator emits one INFO per renamed instance.
MODEL_FIELD_RENAMES: dict[str, str] = {
    "endpoint_class": "endpoint_family",
}

# Top-level fields that v1 had but v2 explicitly removes. Currently empty;
# any future deletion would land in _archived_v1_fields:.
REMOVED_V1_TOP_KEYS: frozenset[str] = frozenset()

# §3.1.2 default tier_groups.mappings populated when v1's mappings are empty.
# These are the cycle-099 v2 defaults; operators can override in their own
# .loa.config.yaml::tier_groups.mappings during Sprint 2 rollout.
TIER_GROUPS_DEFAULTS: dict[str, dict[str, str]] = {
    "max": {
        "anthropic": "opus",
        "openai": "gpt-5.5-pro",
        "google": "gemini-3.1-pro",
    },
    "cheap": {
        "anthropic": "cheap",
        "openai": "gpt-5.3-codex",
        "google": "gemini-3-flash",
    },
    "mid": {
        "anthropic": "cheap",
        "openai": "gpt-5.5",
        "google": "gemini-2.5-pro",
    },
    "tiny": {
        "anthropic": "tiny",
        "openai": "gpt-5.3-codex",
        "google": "gemini-3-flash",
    },
}


class MigrationError(Exception):
    """Raised when migration cannot proceed (schema version unsupported, etc.)."""

    def __init__(self, code: str, detail: str):
        super().__init__(f"[{code}] {detail}")
        self.code = code
        self.detail = detail


def detect_schema_version(data: dict[str, Any]) -> int:
    """Return the integer schema_version. Missing key → 1 (cycle-095 vintage).

    Raises MigrationError if the value is present but not a positive integer.
    """
    raw = data.get("schema_version")
    if raw is None:
        return 1
    if isinstance(raw, bool) or not isinstance(raw, int) or raw < 1:
        raise MigrationError(
            "CONFIG-SCHEMA-VERSION-INVALID",
            f"schema_version must be a positive integer; got {raw!r}",
        )
    return raw


def migrate_v1_to_v2(
    v1: dict[str, Any],
    model_permissions: dict[str, Any] | None = None,
) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    """Pure migration. Returns (v2_dict, report).

    `report` is a list of `{kind: str, path: str, detail: str, severity: str}`.
    `kind` ∈ {pass_through, rename, populate, merge_permissions, archive,
              preserve_unknown, agent_default_tier, idempotent_noop}.
    `severity` ∈ {INFO, WARN, ERROR}.

    No file I/O. The caller (CLI) handles reading, writing, validation, and
    structured error emission.

    `model_permissions` is the optional cycle-026 standalone permissions
    dict (parsed from model-permissions.yaml, top-level shape:
    `model_permissions: { "<provider>:<model_id>": {...trust_scopes...} }`).
    When provided, each entry is merged into the corresponding model's
    `permissions` block per DD-1 Option B.

    Defensive copy: the function deep-copies the inputs before mutating so the
    caller's v1 dict (and its nested children — providers, models, agents)
    survive untouched. This matches the SDD's "pure function" claim.
    """
    version = detect_schema_version(v1)
    if version >= 3:
        raise MigrationError(
            "CONFIG-SCHEMA-VERSION-UNSUPPORTED",
            f"schema_version {version} is newer than the migrator's target (v2). "
            "Use a cycle-{N+1}+ migrator.",
        )
    if version == 2:
        # Idempotent: return a defensive copy so caller-side post-migration
        # mutations cannot retroactively change the input doc.
        return copy.deepcopy(v1), [
            {
                "kind": "idempotent_noop",
                "path": "schema_version",
                "detail": "input is already v2; no migration applied",
                "severity": "WARN",
                "code": "MIGRATION-NOOP-V2-INPUT",
            }
        ]

    # version == 1 (or absent — same path)
    v1 = copy.deepcopy(v1)
    if model_permissions is not None:
        model_permissions = copy.deepcopy(model_permissions)
    report: list[dict[str, Any]] = []
    v2: dict[str, Any] = {"schema_version": 2}
    # G-M2 (review remediation): emit an explicit version_bump entry so the
    # CLI's text report doesn't print "(no changes)" on a v1→v2 migration that
    # happened to have no field-level rewrites. The structural change (adding
    # schema_version) is itself worth surfacing.
    report.append(
        {
            "kind": "version_bump",
            "path": "schema_version",
            "detail": "added schema_version: 2 (v1 → v2)",
            "severity": "INFO",
        }
    )

    # Carry forward known top-level v1 keys; collect unknowns + removed.
    unknown: dict[str, Any] = {}
    archived: dict[str, Any] = {}

    for key, value in v1.items():
        if key == "schema_version":
            continue
        if key in REMOVED_V1_TOP_KEYS:
            archived[key] = value
            report.append(
                {
                    "kind": "archive",
                    "path": key,
                    "detail": f"archived field {key} (deprecated in v2)",
                    "severity": "WARN",
                }
            )
            continue
        if key not in KNOWN_V1_TOP_KEYS:
            unknown[key] = value
            report.append(
                {
                    "kind": "preserve_unknown",
                    "path": key,
                    "detail": (
                        f"preserved unknown v1 field {key} under "
                        f"_unknown_v1_fields/{key}; review and re-place in v2 schema if needed"
                    ),
                    "severity": "WARN",
                }
            )
            continue
        v2[key] = value

    # Per-model field renames (e.g., endpoint_class → endpoint_family).
    if "providers" in v2:
        v2["providers"] = _migrate_providers(v2["providers"], report)

    # Agent-binding rename when value is a tier-tag.
    if "agents" in v2:
        v2["agents"] = _migrate_agents(v2["agents"], report)

    # Populate tier_groups.mappings per SDD §3.1.1.1 row 3. Three cases per
    # review remediation (G-H2 + G-H3):
    #   1. v1 had no `tier_groups:` at all      → create the section + populate
    #   2. v1 had empty `mappings: {}`          → populate all 4 tiers
    #   3. v1 had partial mappings (cycle-095   → fill in missing (tier, provider)
    #      operator started populating)            pairs without overwriting
    v2["tier_groups"] = _migrate_tier_groups(v2.get("tier_groups", {}), report)

    # Merge cycle-026 model-permissions.yaml entries.
    if model_permissions is not None:
        _merge_model_permissions(v2.get("providers", {}), model_permissions, report)

    if archived:
        v2["_archived_v1_fields"] = archived
    if unknown:
        v2["_unknown_v1_fields"] = unknown

    return v2, report


# =============================================================================
# cycle-109 Sprint 1 T1.2 — v2 → v3 migration with conservative defaults
# (SDD §3.1.2 IMP-008). All v3 model-entry additions per SDD §3.1.1.
# =============================================================================

# Reasoning-class opt-in list (SDD §3.1.2). The migrator flips `reasoning_class:
# true` when the model_id matches one of these patterns; everything else
# defaults to false. Operators can override post-migration.
_REASONING_CLASS_MATCHERS: tuple[str, ...] = (
    "claude-opus-4-",   # claude-opus-4-7, claude-opus-4-6, etc.
    "claude-opus-4.",   # alias-style with dot separator
    "gpt-5.5-pro",
    "gpt-5.5-pro-",
    "gemini-3.1-pro",
)

# Allow-all role list per SDD §3.1.4 (SKP-004 v5 closure).
_RECOMMENDED_FOR_ALLOW_ALL: tuple[str, ...] = (
    "review",
    "audit",
    "implementation",
    "dissent",
    "arbiter",
)

# Conservative-defaults floor for effective_input_ceiling when context_window
# is absent. Matches SDD §3.1.2: min(50% × api_context_window, 30000) collapses
# to 30000 when api is undefined.
_EFFECTIVE_CEILING_FLOOR = 30000


def _is_reasoning_class(model_id: str) -> bool:
    """Return True iff model_id matches the reasoning-class opt-in list."""
    return any(model_id.startswith(p) for p in _REASONING_CLASS_MATCHERS)


def _compute_effective_input_ceiling(context_window: int | None) -> int:
    """SDD §3.1.2: min(50% × api_context_window, 30000). Floors at 30000 when
    context_window is unset (defensive default — operator should populate)."""
    if context_window is None or context_window <= 0:
        return _EFFECTIVE_CEILING_FLOOR
    return min(context_window // 2, _EFFECTIVE_CEILING_FLOOR)


def _default_ceiling_calibration(calibrated_at: str) -> dict[str, Any]:
    """SDD §3.1.1 + §3.1.2 conservative_default ceiling_calibration block."""
    return {
        "source": "conservative_default",
        "calibrated_at": calibrated_at,
        "sample_size": None,
        "stale_after_days": 30,
        "reprobe_trigger": (
            "first KF entry referencing model OR 30d elapsed OR operator-forced"
        ),
    }


def _default_streaming_recovery(reasoning_class: bool) -> dict[str, Any]:
    """SDD §3.1.2 streaming_recovery defaults — first-token deadline and
    cot_token_budget vary with reasoning_class flag (FR-4.4)."""
    return {
        "first_token_deadline_seconds": 60 if reasoning_class else 30,
        "empty_detection_window_tokens": 200,
        "cot_token_budget": 500 if reasoning_class else None,
    }


def _apply_v3_defaults_to_model(
    model_id: str,
    entry: dict[str, Any],
    calibrated_at: str,
    report: list[dict[str, Any]],
    path: str,
) -> None:
    """Mutate `entry` in place: add v3 fields with conservative defaults
    per SDD §3.1.2. Fields already present on the model entry are preserved
    verbatim (operator-set values win over migrator defaults)."""
    if "effective_input_ceiling" not in entry:
        entry["effective_input_ceiling"] = _compute_effective_input_ceiling(
            entry.get("context_window")
        )
        report.append({
            "kind": "populate",
            "path": f"{path}.effective_input_ceiling",
            "detail": f"defaulted to {entry['effective_input_ceiling']} (SDD §3.1.2)",
            "severity": "INFO",
        })

    if "reasoning_class" not in entry:
        entry["reasoning_class"] = _is_reasoning_class(model_id)
        report.append({
            "kind": "populate",
            "path": f"{path}.reasoning_class",
            "detail": (
                f"defaulted to {entry['reasoning_class']} "
                f"({'matched opt-in list' if entry['reasoning_class'] else 'no match'})"
            ),
            "severity": "INFO",
        })

    if "recommended_for" not in entry:
        entry["recommended_for"] = list(_RECOMMENDED_FOR_ALLOW_ALL)
        report.append({
            "kind": "populate",
            "path": f"{path}.recommended_for",
            "detail": "defaulted to allow-all 5-role list (SKP-004 v5 closure)",
            "severity": "INFO",
        })

    if "failure_modes_observed" not in entry:
        entry["failure_modes_observed"] = []

    if "ceiling_calibration" not in entry:
        entry["ceiling_calibration"] = _default_ceiling_calibration(calibrated_at)
        report.append({
            "kind": "populate",
            "path": f"{path}.ceiling_calibration",
            "detail": "defaulted to conservative_default block (SDD §3.1.1)",
            "severity": "INFO",
        })

    if "streaming_recovery" not in entry:
        entry["streaming_recovery"] = _default_streaming_recovery(
            entry["reasoning_class"]
        )
        report.append({
            "kind": "populate",
            "path": f"{path}.streaming_recovery",
            "detail": (
                f"defaulted to {'reasoning' if entry['reasoning_class'] else 'non-reasoning'} "
                f"streaming-recovery defaults (FR-4.4)"
            ),
            "severity": "INFO",
        })


def migrate_v2_to_v3(
    v2: dict[str, Any],
    calibrated_at: str = "2026-05-13T00:00:00Z",
) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    """Pure v2 → v3 migration with conservative defaults per SDD §3.1.2.

    Returns (v3_dict, report). No I/O. Defensive copy of input.

    `calibrated_at` (ISO 8601) is stamped on every ceiling_calibration block
    populated at migration time. Tests can pin a deterministic value;
    production callers default to migration-time wall clock if needed.

    Idempotent on v3 input (returns deep copy + idempotent_noop report row).
    Raises MigrationError on v1 input — caller should chain v1→v2 first.
    """
    version = detect_schema_version(v2)
    if version == 3:
        return copy.deepcopy(v2), [{
            "kind": "idempotent_noop",
            "path": "schema_version",
            "detail": "input is already v3; no migration applied",
            "severity": "WARN",
            "code": "MIGRATION-NOOP-V3-INPUT",
        }]
    if version >= 4:
        raise MigrationError(
            "CONFIG-SCHEMA-VERSION-UNSUPPORTED",
            f"schema_version {version} is newer than the migrator's target (v3). "
            "Use a cycle-{N+1}+ migrator.",
        )
    if version != 2:
        raise MigrationError(
            "CONFIG-SCHEMA-VERSION-UNSUPPORTED",
            f"migrate_v2_to_v3 requires v2 input; got version {version}. "
            "Chain v1→v2 first via migrate_v1_to_v2.",
        )

    v3 = copy.deepcopy(v2)
    report: list[dict[str, Any]] = [{
        "kind": "version_bump",
        "path": "schema_version",
        "detail": "added schema_version: 3 (v2 → v3, cycle-109 Sprint 1)",
        "severity": "INFO",
    }]
    v3["schema_version"] = 3

    providers = v3.get("providers", {})
    if isinstance(providers, dict):
        for provider_id, provider_entry in providers.items():
            if not isinstance(provider_entry, dict):
                continue
            models = provider_entry.get("models", {})
            if not isinstance(models, dict):
                continue
            for model_id, model_entry in models.items():
                if not isinstance(model_entry, dict):
                    continue
                _apply_v3_defaults_to_model(
                    model_id,
                    model_entry,
                    calibrated_at,
                    report,
                    f"providers.{provider_id}.models.{model_id}",
                )

    return v3, report


def migrate_to_latest(
    data: dict[str, Any],
    target_version: int = 3,
    model_permissions: dict[str, Any] | None = None,
    calibrated_at: str = "2026-05-13T00:00:00Z",
) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    """Chain migrations from whatever the input version is up to target_version.

    Currently supported targets: 2, 3.

    For target_version=3 the chain is:
        v1 → v2 (via migrate_v1_to_v2) → v3 (via migrate_v2_to_v3)
        v2 → v3 directly
        v3 → v3 (idempotent_noop)
    """
    if target_version not in (2, 3):
        raise MigrationError(
            "CONFIG-SCHEMA-VERSION-UNSUPPORTED",
            f"migrate_to_latest target {target_version} not supported; expected 2 or 3",
        )

    source_version = detect_schema_version(data)

    if target_version == 2:
        return migrate_v1_to_v2(data, model_permissions=model_permissions)

    # target_version == 3
    if source_version <= 1:
        v2, v1_report = migrate_v1_to_v2(data, model_permissions=model_permissions)
        v3, v2_report = migrate_v2_to_v3(v2, calibrated_at=calibrated_at)
        return v3, v1_report + v2_report
    return migrate_v2_to_v3(data, calibrated_at=calibrated_at)


def _migrate_providers(
    providers: dict[str, Any], report: list[dict[str, Any]]
) -> dict[str, Any]:
    """Walk providers.<p>.models.<id> and apply MODEL_FIELD_RENAMES."""
    if not isinstance(providers, dict):
        return providers
    for provider_id, provider in providers.items():
        if not isinstance(provider, dict):
            continue
        models = provider.get("models")
        if not isinstance(models, dict):
            continue
        for model_id, model in models.items():
            if not isinstance(model, dict):
                continue
            for old_name, new_name in MODEL_FIELD_RENAMES.items():
                if old_name in model and new_name not in model:
                    model[new_name] = model.pop(old_name)
                    report.append(
                        {
                            "kind": "rename",
                            "path": f"providers.{provider_id}.models.{model_id}.{old_name}",
                            "detail": (
                                f"renamed providers.{provider_id}.models.{model_id}."
                                f"{old_name} -> .{new_name}"
                            ),
                            "severity": "INFO",
                        }
                    )
                elif old_name in model and new_name in model:
                    # Both present — operator already migrated the field; archive
                    # the legacy key into the model entry under a per-model
                    # _archived_v1_fields namespace to surface the conflict.
                    legacy_value = model.pop(old_name)
                    archived = model.setdefault("_archived_v1_fields", {})
                    archived[old_name] = legacy_value
                    report.append(
                        {
                            "kind": "archive",
                            "path": f"providers.{provider_id}.models.{model_id}.{old_name}",
                            "detail": (
                                f"both {old_name} and {new_name} present; archived "
                                f"legacy {old_name}={legacy_value!r} in favor of "
                                f"{new_name}={model[new_name]!r}"
                            ),
                            "severity": "WARN",
                        }
                    )
    return providers


def _migrate_agents(
    agents: dict[str, Any], report: list[dict[str, Any]]
) -> dict[str, Any]:
    """Rename agents.<skill>.model: <tier> → agents.<skill>.default_tier: <tier>.

    Sprint 1E uses string-match against TIER_TAGS (literal value comparison).
    SDD §3.1.1.1 row 4 wording ("IF the resolved model maps to a known tier")
    implies alias resolution should run first; that requires the Sprint 2
    resolver, which Sprint 1E doesn't ship. The string-match yields the same
    answer for every cycle-095 vintage config in practice (operator naming
    convention is to use the literal tier-tag), but a future operator who
    aliases a tier-name to a model id (e.g., `aliases.cheap: openai:gpt-...`)
    and uses `agents.x.model: <some-model-resolving-to-cheap>` will not get
    renamed here. Sprint 2 will replace this with resolver-aware rename.
    """
    if not isinstance(agents, dict):
        return agents
    for skill_name, binding in agents.items():
        if not isinstance(binding, dict):
            continue
        model_value = binding.get("model")
        if isinstance(model_value, str) and model_value in TIER_TAGS:
            binding["default_tier"] = model_value
            del binding["model"]
            report.append(
                {
                    "kind": "agent_default_tier",
                    "path": f"agents.{skill_name}.model",
                    "detail": (
                        f"renamed agents.{skill_name}.model -> "
                        f"agents.{skill_name}.default_tier (value '{model_value}' is a tier-tag)"
                    ),
                    "severity": "INFO",
                }
            )
    return agents


def _migrate_tier_groups(
    tier_groups: dict[str, Any], report: list[dict[str, Any]]
) -> dict[str, Any]:
    """Populate tier_groups.mappings with SDD §3.1.2 defaults.

    Handles three input shapes (review remediation G-H2/G-H3):
      - tier_groups absent (we received {} as fallback)         → full populate
      - tier_groups present, mappings absent or {}              → full populate
      - tier_groups present, mappings has some (tier,provider)  → fill missing
        pairs only; never overwrite operator-supplied entries
    """
    if not isinstance(tier_groups, dict):
        return tier_groups
    mappings = tier_groups.get("mappings")
    if not isinstance(mappings, dict):
        mappings = {}
        tier_groups["mappings"] = mappings
    for tier, provider_map in TIER_GROUPS_DEFAULTS.items():
        tier_dict = mappings.setdefault(tier, {})
        if not isinstance(tier_dict, dict):
            # Operator wrote a non-dict at this tier; leave as-is and skip.
            continue
        for provider, value in provider_map.items():
            if provider in tier_dict:
                continue  # operator-supplied; preserve verbatim
            tier_dict[provider] = value
            report.append(
                {
                    "kind": "populate",
                    "path": f"tier_groups.mappings.{tier}.{provider}",
                    "detail": (
                        f"populated tier_groups.mappings.{tier}.{provider} = {value} "
                        "(SDD §3.1.2 default)"
                    ),
                    "severity": "INFO",
                }
            )
    # Sprint 2 will own the denylist + max_cost defaults; Sprint 1E only
    # ensures the section exists so the loader has a stable shape.
    tier_groups.setdefault("denylist", [])
    tier_groups.setdefault("max_cost_per_session_micro_usd", None)
    return tier_groups


def _merge_model_permissions(
    providers: dict[str, Any],
    model_permissions_doc: dict[str, Any],
    report: list[dict[str, Any]],
) -> None:
    """Merge cycle-026 model_permissions block into providers.<p>.models.<id>.permissions."""
    permissions_map = model_permissions_doc.get("model_permissions", {})
    if not isinstance(permissions_map, dict):
        return
    for combined_key, perms in permissions_map.items():
        if not isinstance(combined_key, str) or ":" not in combined_key:
            continue
        provider_id, model_id = combined_key.split(":", 1)
        provider = providers.get(provider_id)
        if not isinstance(provider, dict):
            continue
        models = provider.get("models")
        if not isinstance(models, dict):
            continue
        model = models.get(model_id)
        if not isinstance(model, dict):
            continue
        # DD-1 Option B: merge as a `permissions` block per-model.
        if "permissions" in model:
            # Operator-supplied permissions take precedence; legacy stash.
            archived = model.setdefault("_archived_v1_fields", {})
            archived.setdefault("legacy_model_permissions", perms)
            report.append(
                {
                    "kind": "archive",
                    "path": f"providers.{provider_id}.models.{model_id}.permissions",
                    "detail": (
                        f"existing permissions block on {provider_id}:{model_id}; "
                        "legacy cycle-026 entry archived under _archived_v1_fields"
                    ),
                    "severity": "WARN",
                }
            )
            continue
        model["permissions"] = perms
        report.append(
            {
                "kind": "merge_permissions",
                "path": f"providers.{provider_id}.models.{model_id}.permissions",
                "detail": (
                    f"merged model-permissions {provider_id}:{model_id} -> "
                    "permissions block (DD-1 Option B)"
                ),
                "severity": "INFO",
            }
        )
