#!/usr/bin/env python3
"""model-resolver.py — cycle-099 Sprint 2D (T2.6).

The CANONICAL implementation of the FR-3.9 6-stage model resolution algorithm.
Per SDD §1.5.1, this is the sole source-of-truth resolver; bash and TypeScript
runtimes are projections (build-time generated overlays + Bridgebuilder dist).

Public API
----------

    resolve(merged_config: dict, skill: str, role: str) -> dict

A pure function. Given a merged config (framework_defaults + operator_config),
a skill name, and a role within that skill, returns a single ResolutionResult
dict matching `model-resolver-output.schema.json`. No I/O, no env access, no
state.

Invariants enforced
-------------------

Per SDD §1.5.1:
  * Input is JCS-canonicalized BEFORE entering the 6-stage pipeline. This
    eliminates ordering-dependent edge cases where two equivalent configs
    produce different stage traces.
  * Output `resolution_path` is ordered by stage number ascending.
  * Output is canonical JSON (sort_keys=True, ensure_ascii=False) when
    emitted via `dump_canonical_json()`.
  * Stage labels are pinned per the schema enum.

Per FR-3.9 (PRD):
  * Six stages exactly:
      S1 explicit `provider:model_id` pin in `skill_models.<skill>.<role>`
      S2 tier-tag in `skill_models` → operator `tier_groups.mappings`
      S3 tier-tag in `skill_models` → framework `tier_groups.mappings`
      S4 legacy shape (`<skill>.models.<role>`) with deprecation warning
      S5 framework default `agents.<skill>.{model,default_tier}`
      S6 `prefer_pro_models` overlay (POST-resolution; gated per FR-3.4)
  * Pre-resolution validation (stage 0):
      - IMP-004: same id in both `model_aliases_extra` AND `model_aliases_override`
        → `[MODEL-EXTRA-OVERRIDE-CONFLICT]`
      - `model_aliases_override` targets unknown framework id
        → `[OVERRIDE-UNKNOWN-MODEL]`
  * IMP-007: tier-tag interpretation wins when an alias name in
    `model_aliases_extra` collides with a tier name. Resolver emits
    `details.alias_collides_with_tier: true` on the stage 3 hit.

Module entry points
-------------------

  resolve(...)        — public pure function (above).
  resolve_fixture(...) — convenience wrapper for golden test runners; reads a
                        fixture YAML and emits one ResolutionResult per
                        `expected.resolutions[]` entry, decorated with the
                        `fixture` context tag.
  dump_canonical_json(obj) — `json.dumps(obj, sort_keys=True, ensure_ascii=False,
                            separators=(",", ":"))` — the cross-runtime byte-equal
                            emission contract.
  CLI: `model-resolver resolve|resolve-fixture` — see `--help`.

cycle-099 Sprint 2D — T2.6.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

# We import yaml at function scope only when needed (resolve() itself is YAML-
# unaware; only the CLI / fixture wrapper touches YAML). This keeps the public
# resolve() surface stdlib-only at import time.

# ----------------------------------------------------------------------------
# Constants
# ----------------------------------------------------------------------------

EXIT_OK = 0
EXIT_ERROR = 1
EXIT_USAGE = 64

# Stage labels — pinned by `model-resolver-output.schema.json::StageOutcome.label`.
STAGE1_LABEL = "stage1_pin_check"
STAGE2_LABEL = "stage2_skill_models"
STAGE3_LABEL = "stage3_tier_groups"
STAGE4_LABEL = "stage4_legacy_shape"
STAGE5_LABEL = "stage5_framework_default"
STAGE6_LABEL = "stage6_prefer_pro_overlay"

# Error codes — pinned by schema enum.
ERR_TIER_NO_MAPPING = "[TIER-NO-MAPPING]"
ERR_OVERRIDE_UNKNOWN = "[OVERRIDE-UNKNOWN-MODEL]"
ERR_EXTRA_OVERRIDE_CONFLICT = "[MODEL-EXTRA-OVERRIDE-CONFLICT]"
ERR_NO_RESOLUTION = "[NO-RESOLUTION]"
ERR_CONFLICT_PIN_AND_TIER = "[CONFLICT-PIN-AND-TIER]"

# Tier names recognized as tier-tags (vs explicit aliases). Per IMP-007, when
# a `skill_models.<skill>.<role>` value matches one of these AND also exists
# as an entry in `model_aliases_extra`, the tier-tag interpretation wins.
TIER_NAMES = frozenset({"max", "cheap", "mid", "tiny"})


# ----------------------------------------------------------------------------
# Canonicalization helpers
# ----------------------------------------------------------------------------

def dump_canonical_json(obj: Any) -> str:
    """Serialize to canonical JSON: sorted keys, no whitespace, UTF-8 literals.

    Matches the bash runner's `jq -S -c` and the TS runner's
    `canonicalizeRecursive` patterns from cycle-099 Sprint 1D. Cross-runtime
    byte-equal emission contract.

    NOTE on `ensure_ascii=False`: per `feedback_cross_runtime_parity_traps.md`,
    Python's default `ensure_ascii=True` emits `\\uXXXX` escapes for non-ASCII;
    bash `jq -c` and TS `JSON.stringify` emit literal UTF-8. This MUST stay
    False for cross-runtime parity.
    """
    return json.dumps(obj, sort_keys=True, ensure_ascii=False, separators=(",", ":"))


def _canonicalize_dict_keys(value: Any) -> Any:
    """Recursively sort dict keys (depth-first, all levels).

    Per SDD §1.5.1 input normalization invariant. The resolver iterates over
    dicts in insertion order; canonicalizing first ensures stage outcomes do
    not depend on YAML key declaration order. (Python's yaml.safe_load
    preserves order in 3.7+, but we don't want behavior-dependence on order
    that other YAML parsers might not preserve.)
    """
    if isinstance(value, dict):
        return {k: _canonicalize_dict_keys(value[k]) for k in sorted(value.keys())}
    if isinstance(value, list):
        return [_canonicalize_dict_keys(item) for item in value]
    return value


def _normalize_alias_entry(entry: Any) -> dict | None:
    """Normalize a framework_aliases entry to the canonical {provider, model_id} dict.

    Two shapes are accepted:
      * Dict form (cycle-099 fixture corpus): `{provider: ..., model_id: ...}`
      * String form (cycle-095 production back-compat): `"provider:model_id"`

    The string form is what `.claude/defaults/model-config.yaml` currently uses
    for the `aliases:` block (e.g., `opus: "anthropic:claude-opus-4-7"`). The
    dict form is what Sprint 2A's `model_aliases_extra.schema.json` mandates
    for operator-added entries. The resolver supports both transparently to
    handle the cross-shape merge during Sprint 2's deprecation window.

    Returns the normalized dict, or None if the entry is malformed (not a
    dict, not a string, missing fields, etc.) — caller treats None as "alias
    not present" and falls through.
    """
    if isinstance(entry, dict):
        provider = entry.get("provider")
        model_id = entry.get("model_id")
        if isinstance(provider, str) and provider and isinstance(model_id, str) and model_id:
            return {"provider": provider, "model_id": model_id}
        return None
    if isinstance(entry, str) and ":" in entry:
        provider, _, model_id = entry.partition(":")
        if provider and model_id:
            return {"provider": provider, "model_id": model_id}
    return None


def _lookup_alias(aliases: dict, alias_name: str) -> dict | None:
    """Look up `aliases[alias_name]` and return the normalized {provider, model_id}.

    Returns None if alias is absent or malformed.
    """
    if not isinstance(aliases, dict):
        return None
    raw = aliases.get(alias_name)
    if raw is None:
        return None
    return _normalize_alias_entry(raw)


# ----------------------------------------------------------------------------
# Pre-resolution validation (stage 0 — IMP-004)
# ----------------------------------------------------------------------------

def _pre_validate(merged_config: dict) -> dict | None:
    """Run pre-resolution validation. Returns an error dict (without skill/role)
    if a config-level violation is detected; None if validation passes.

    Stage 0 covers IMP-004 conflict detection — entries that are wrong at the
    config level rather than the resolution level. These would fail every
    (skill, role) resolution against the same config; we surface them as a
    consistent error rather than silently per-resolution.
    """
    operator = merged_config.get("operator_config") or {}
    framework = merged_config.get("framework_defaults") or {}

    extra = operator.get("model_aliases_extra") or {}
    override = operator.get("model_aliases_override") or {}

    # IMP-004: same id in both extra AND override is mutually exclusive.
    collisions = sorted(set(extra.keys()) & set(override.keys()))
    if collisions:
        return {
            "code": ERR_EXTRA_OVERRIDE_CONFLICT,
            "stage_failed": 0,
            "detail": (
                f"id `{collisions[0]}` appears in BOTH model_aliases_extra and "
                f"model_aliases_override; mutually exclusive at entry level (IMP-004)"
            ),
        }

    # IMP-004: model_aliases_override must target a known framework id.
    framework_models = set()
    providers = framework.get("providers") or {}
    for prov_data in providers.values():
        models = (prov_data or {}).get("models") or {}
        framework_models.update(models.keys())

    for override_id in sorted(override.keys()):
        if override_id not in framework_models:
            return {
                "code": ERR_OVERRIDE_UNKNOWN,
                "stage_failed": 0,
                "detail": (
                    f"model_aliases_override targets `{override_id}` which is not a "
                    f"framework-default ID"
                ),
            }

    return None


# ----------------------------------------------------------------------------
# Stage helpers
# ----------------------------------------------------------------------------

def _stage1_explicit_pin(skill_models_value: Any) -> dict | None:
    """S1: explicit `provider:model_id` pin in `skill_models.<skill>.<role>`.

    Returns a partial result dict (no resolution_path yet, just provider+model_id+
    stage entry) on hit, None on miss.
    """
    if not isinstance(skill_models_value, str):
        return None
    if ":" not in skill_models_value:
        return None
    provider, _, model_id = skill_models_value.partition(":")
    if not provider or not model_id:
        return None
    return {
        "resolved_provider": provider,
        "resolved_model_id": model_id,
        "stage_entry": {
            "stage": 1,
            "outcome": "hit",
            "label": STAGE1_LABEL,
            "details": {"pin": skill_models_value},
        },
    }


def _stage2_skill_models(
    skill_models_value: Any,
    operator_tier_mappings: dict,
    framework_tier_mappings: dict,
    framework_aliases: dict,
    operator_extra: dict,
) -> dict | None:
    """S2: tag at `skill_models.<skill>.<role>` — alias direct or tier cascade.

    Per the cycle-099 fixture corpus convention, S2 emits `details.alias: X`
    (uniform regardless of cascade decision; X is the operator-input value).
    The cascade-or-resolve decision is:

      * If X is a tier-tag (member of TIER_NAMES OR present in
        operator/framework `tier_groups.mappings`) → cascade to S3 (per
        IMP-007: tier-tag interpretation wins over a colliding alias entry).
      * Else if X is a known alias (in framework_aliases ∪ operator_extra) →
        resolve directly at S2 (no cascade).
      * Else → cascade to S3 (S3 will likely emit `[TIER-NO-MAPPING]`).

    Returns:
      * `{resolved_provider, resolved_model_id, stage_entry}` on direct alias hit
      * `{stage_entry, tier_for_cascade}` when cascade is needed
      * None when no string value (S1 explicit pin path)
    """
    if not isinstance(skill_models_value, str):
        return None
    if ":" in skill_models_value:
        return None  # explicit pin — handled by S1

    val = skill_models_value
    is_tier = (
        val in TIER_NAMES
        or val in operator_tier_mappings
        or val in framework_tier_mappings
    )
    is_alias_in_aliases = val in framework_aliases
    is_alias_in_extra = val in operator_extra

    stage_entry = {
        "stage": 2,
        "outcome": "hit",
        "label": STAGE2_LABEL,
        "details": {"alias": val},
    }

    # Tier-tag path (IMP-007 also lands here when tier collides with alias)
    if is_tier:
        return {"stage_entry": stage_entry, "tier_for_cascade": val}

    # Direct alias path — resolve at S2, no cascade
    if is_alias_in_aliases:
        alias_entry = _lookup_alias(framework_aliases, val)
        if alias_entry is not None:
            return {
                "resolved_provider": alias_entry["provider"],
                "resolved_model_id": alias_entry["model_id"],
                "stage_entry": stage_entry,
            }
    if is_alias_in_extra:
        extra_entry = _normalize_alias_entry(operator_extra[val])
        if extra_entry is not None:
            return {
                "resolved_provider": extra_entry["provider"],
                "resolved_model_id": extra_entry["model_id"],
                "stage_entry": stage_entry,
            }

    # Unknown tag — cascade (S3 will emit [TIER-NO-MAPPING])
    return {"stage_entry": stage_entry, "tier_for_cascade": val}


def _stage3_tier_groups(
    tier: str,
    operator_tier_mappings: dict,
    framework_tier_mappings: dict,
    framework_aliases: dict,
    operator_extra: dict,
) -> dict | None:
    """S3: tier-tag → tier_groups.mappings (operator first, then framework).

    Returns final resolution dict on hit. Returns error dict on TIER-NO-MAPPING.

    Per IMP-007: when an alias name in `model_aliases_extra` collides with the
    resolved alias from tier_groups, we add `alias_collides_with_tier: true` to
    the stage 3 details. Tier-tag wins (this resolution is taking that path).
    """
    # Operator mappings checked first (precedence). The mapping value is
    # provider→alias; we pick the first provider deterministically (sorted).
    mapping = operator_tier_mappings.get(tier) or framework_tier_mappings.get(tier)
    if not mapping:
        return {
            "error": {
                "code": ERR_TIER_NO_MAPPING,
                "stage_failed": 3,
                "detail": (
                    f"tier `{tier}` has no mapping for any provider; configure "
                    f"tier_groups.mappings or use explicit alias"
                ),
            }
        }

    # Pick a provider deterministically. For now, take the first sorted entry.
    provider = sorted(mapping.keys())[0]
    alias = mapping[provider]

    alias_entry = _lookup_alias(framework_aliases, alias)
    if alias_entry is None:
        return {
            "error": {
                "code": ERR_TIER_NO_MAPPING,
                "stage_failed": 3,
                "detail": (
                    f"tier `{tier}` mapped to alias `{alias}` for provider `{provider}` "
                    f"but alias not found in framework_defaults.aliases"
                ),
            }
        }

    details = {"resolved_alias": alias}
    if tier in operator_extra:
        # IMP-007: the tier-tag name (the operator input value, e.g. `max`)
        # collides with a model_aliases_extra entry of the same name. Tier-tag
        # interpretation wins; the resolver took the tier path (cascaded to
        # S3). Report the collision so operators see why their extra-entry
        # was shadowed. (Surfaces the IMP-007 silent-shadow case as a visible
        # field in the resolution_path.)
        details["alias_collides_with_tier"] = True

    return {
        "resolved_provider": alias_entry["provider"],
        "resolved_model_id": alias_entry["model_id"],
        "stage_entry": {
            "stage": 3,
            "outcome": "hit",
            "label": STAGE3_LABEL,
            "details": details,
        },
    }


def _stage4_legacy_shape(
    operator_config: dict, skill: str, role: str, framework_aliases: dict
) -> dict | None:
    """S4: legacy shape `<skill>.models.<role>: <alias>` with deprecation warning.

    Returns resolution dict on hit. None if legacy shape not present for
    (skill, role) tuple.
    """
    skill_block = operator_config.get(skill)
    if not isinstance(skill_block, dict):
        return None
    legacy_models = skill_block.get("models")
    if not isinstance(legacy_models, dict):
        return None
    alias = legacy_models.get(role)
    if not isinstance(alias, str):
        return None
    alias_entry = _lookup_alias(framework_aliases, alias)
    if alias_entry is None:
        # Legacy shape referenced an unknown alias — fall through to S5
        # per FR-3.7 deprecation_warn_fallback semantics.
        return None
    return {
        "resolved_provider": alias_entry["provider"],
        "resolved_model_id": alias_entry["model_id"],
        "is_legacy": True,
        "stage_entry": {
            "stage": 4,
            "outcome": "hit",
            "label": STAGE4_LABEL,
            "details": {"warning": "[LEGACY-SHAPE-DEPRECATED]"},
        },
    }


def _stage5_framework_default(
    framework_defaults: dict,
    skill: str,
    framework_aliases: dict,
    framework_tier_mappings: dict,
    runtime_state: dict,
) -> dict | None:
    """S5: framework default for skill via `agents.<skill>.{model,default_tier}`.

    Per FR-3.9 stage 5, look up the agents.<skill> entry. If `model:` is set,
    use that directly. Else use `default_tier:` and resolve via tier_groups.

    Per fixture #12, when `runtime_state.overlay_state == "degraded"`, append
    `details.source: "degraded_cache"` to the stage-5 entry.

    NOTE: The fixture's `framework_defaults.agents.<skill>` lookup uses the same
    skill name as `skill_models.<skill>` — both underscore-form. SDD §7.6.1's
    example uses hyphen-form (`flatline-reviewer`); this is a doc bug. We follow
    the fixture corpus's actual usage.
    """
    agents = framework_defaults.get("agents") or {}
    agent = agents.get(skill)
    if not isinstance(agent, dict):
        return None

    details: dict = {}
    is_degraded = (runtime_state.get("overlay_state") == "degraded")
    if is_degraded:
        details["source"] = "degraded_cache"

    # Try direct model first
    model_alias = agent.get("model")
    if isinstance(model_alias, str):
        alias_entry = _lookup_alias(framework_aliases, model_alias)
        if alias_entry:
            details["alias"] = model_alias
            return {
                "resolved_provider": alias_entry["provider"],
                "resolved_model_id": alias_entry["model_id"],
                "stage_entry": {
                    "stage": 5,
                    "outcome": "hit",
                    "label": STAGE5_LABEL,
                    "details": details,
                },
            }

    # Fall back to default_tier
    default_tier = agent.get("default_tier")
    if isinstance(default_tier, str):
        mapping = framework_tier_mappings.get(default_tier)
        if mapping:
            provider = sorted(mapping.keys())[0]
            alias = mapping[provider]
            alias_entry = _lookup_alias(framework_aliases, alias)
            if alias_entry:
                details["alias"] = alias
                return {
                    "resolved_provider": alias_entry["provider"],
                    "resolved_model_id": alias_entry["model_id"],
                    "stage_entry": {
                        "stage": 5,
                        "outcome": "hit",
                        "label": STAGE5_LABEL,
                        "details": details,
                    },
                }
        # No mapping — try direct alias by tier name (some frameworks
        # define `tiny:` as both a tier and an alias; the alias lookup
        # is a permissive fallback).
        alias_entry = _lookup_alias(framework_aliases, default_tier)
        if alias_entry:
            details["alias"] = default_tier
            return {
                "resolved_provider": alias_entry["provider"],
                "resolved_model_id": alias_entry["model_id"],
                "stage_entry": {
                    "stage": 5,
                    "outcome": "hit",
                    "label": STAGE5_LABEL,
                    "details": details,
                },
            }

    return None


def _stage6_prefer_pro(
    resolved_alias: str | None,
    operator_config: dict,
    framework_aliases: dict,
    is_legacy_path: bool,
) -> dict | None:
    """S6: `prefer_pro_models` overlay.

    Per FR-3.9 stage 6 + FR-3.4 gating:
      - If `prefer_pro_models` is False (or absent) → no entry emitted.
      - If True and skill came via legacy shape AND `respect_prefer_pro` is
        not True → emit entry with outcome=skipped.
      - If True and either modern shape OR (legacy AND respect_prefer_pro) →
        check if `<resolved_alias>-pro` exists in framework_aliases; if so,
        emit `applied` and return retargeted resolution.

    Returns dict with `stage_entry` and optionally retargeted
    `resolved_provider` / `resolved_model_id`. None if no entry should be
    emitted (prefer_pro disabled).
    """
    prefer_pro = operator_config.get("prefer_pro_models") is True
    if not prefer_pro:
        return None

    if is_legacy_path:
        respect = operator_config.get("respect_prefer_pro") is True
        if not respect:
            return {
                "stage_entry": {
                    "stage": 6,
                    "outcome": "skipped",
                    "label": STAGE6_LABEL,
                    "details": {"reason": "legacy_shape_without_respect_prefer_pro"},
                },
            }

    if resolved_alias is None:
        # We don't know the alias name (e.g., resolution didn't go through
        # an aliased path). Skip the overlay.
        return {
            "stage_entry": {
                "stage": 6,
                "outcome": "skipped",
                "label": STAGE6_LABEL,
                "details": {"reason": "no_alias_to_overlay"},
            },
        }

    pro_alias = f"{resolved_alias}-pro"
    pro_entry = _lookup_alias(framework_aliases, pro_alias)
    if pro_entry is None:
        return {
            "stage_entry": {
                "stage": 6,
                "outcome": "skipped",
                "label": STAGE6_LABEL,
                "details": {"reason": "no_pro_variant_for_alias", "alias": resolved_alias},
            },
        }

    return {
        "resolved_provider": pro_entry["provider"],
        "resolved_model_id": pro_entry["model_id"],
        "stage_entry": {
            "stage": 6,
            "outcome": "applied",
            "label": STAGE6_LABEL,
            "details": {"from": resolved_alias, "to": pro_alias},
        },
    }


# ----------------------------------------------------------------------------
# Public API
# ----------------------------------------------------------------------------

def resolve(merged_config: dict, skill: str, role: str) -> dict:
    """Resolve (skill, role) against merged_config per FR-3.9 6 stages.

    Args:
        merged_config: the full merged config dict — the fixture's `input`
            block (with framework_defaults + operator_config + optional
            runtime_state).
        skill: skill name (e.g., 'flatline_protocol').
        role: role within skill (e.g., 'primary').

    Returns:
        ResolutionResult dict per `model-resolver-output.schema.json`. On
        success: {skill, role, resolved_provider, resolved_model_id,
        resolution_path}. On failure: {skill, role, error: {code,
        stage_failed, detail}}.
    """
    # JCS-canonicalize input. Idempotent for already-canonical inputs.
    cfg = _canonicalize_dict_keys(merged_config)

    # ----- Stage 0: pre-validation -----
    err = _pre_validate(cfg)
    if err is not None:
        return {"skill": skill, "role": role, "error": err}

    operator_config = cfg.get("operator_config") or {}
    framework_defaults = cfg.get("framework_defaults") or {}
    runtime_state = cfg.get("runtime_state") or {}
    framework_aliases = framework_defaults.get("aliases") or {}
    framework_tier_groups = framework_defaults.get("tier_groups") or {}
    framework_tier_mappings = framework_tier_groups.get("mappings") or {}
    operator_tier_groups = operator_config.get("tier_groups") or {}
    operator_tier_mappings = operator_tier_groups.get("mappings") or {}
    operator_extra = operator_config.get("model_aliases_extra") or {}

    # `skill_models.<skill>.<role>` value (or None)
    skill_models = operator_config.get("skill_models") or {}
    skill_block = skill_models.get(skill) or {}
    skill_value = skill_block.get(role) if isinstance(skill_block, dict) else None

    resolution_path: list[dict] = []
    final_provider: str | None = None
    final_model_id: str | None = None
    is_legacy_path = False
    resolved_alias_for_overlay: str | None = None

    # ----- Stage 1: explicit pin -----
    s1 = _stage1_explicit_pin(skill_value)
    if s1:
        resolution_path.append(s1["stage_entry"])
        final_provider = s1["resolved_provider"]
        final_model_id = s1["resolved_model_id"]
        # Pin path: stage 6 has no alias to overlay; we still emit per FR-3.9
        # (operators expect to see prefer_pro decisions even when no-op).
        s6 = _stage6_prefer_pro(None, operator_config, framework_aliases, False)
        if s6 is not None:
            resolution_path.append(s6["stage_entry"])
            if "resolved_provider" in s6:
                final_provider = s6["resolved_provider"]
                final_model_id = s6["resolved_model_id"]
        return {
            "skill": skill,
            "role": role,
            "resolved_provider": final_provider,
            "resolved_model_id": final_model_id,
            "resolution_path": resolution_path,
        }

    # ----- Stage 2 (+ optional Stage 3 cascade): tag in skill_models -----
    s2 = _stage2_skill_models(
        skill_value,
        operator_tier_mappings,
        framework_tier_mappings,
        framework_aliases,
        operator_extra,
    )
    if s2:
        resolution_path.append(s2["stage_entry"])
        # Direct alias hit at S2 — no cascade
        if "resolved_provider" in s2:
            final_provider = s2["resolved_provider"]
            final_model_id = s2["resolved_model_id"]
            resolved_alias_for_overlay = s2["stage_entry"]["details"].get("alias")
            s6 = _stage6_prefer_pro(
                resolved_alias_for_overlay, operator_config, framework_aliases, False
            )
            if s6 is not None:
                resolution_path.append(s6["stage_entry"])
                if "resolved_provider" in s6:
                    final_provider = s6["resolved_provider"]
                    final_model_id = s6["resolved_model_id"]
            return {
                "skill": skill,
                "role": role,
                "resolved_provider": final_provider,
                "resolved_model_id": final_model_id,
                "resolution_path": resolution_path,
            }

        # Cascade to S3
        tier = s2["tier_for_cascade"]
        s3 = _stage3_tier_groups(
            tier,
            operator_tier_mappings,
            framework_tier_mappings,
            framework_aliases,
            operator_extra,
        )
        if "error" in s3:
            return {
                "skill": skill,
                "role": role,
                "error": s3["error"],
            }
        resolution_path.append(s3["stage_entry"])
        final_provider = s3["resolved_provider"]
        final_model_id = s3["resolved_model_id"]
        resolved_alias_for_overlay = s3["stage_entry"]["details"].get("resolved_alias")
        s6 = _stage6_prefer_pro(
            resolved_alias_for_overlay, operator_config, framework_aliases, False
        )
        if s6 is not None:
            resolution_path.append(s6["stage_entry"])
            if "resolved_provider" in s6:
                final_provider = s6["resolved_provider"]
                final_model_id = s6["resolved_model_id"]
        return {
            "skill": skill,
            "role": role,
            "resolved_provider": final_provider,
            "resolved_model_id": final_model_id,
            "resolution_path": resolution_path,
        }

    # ----- Stage 4: legacy shape -----
    s4 = _stage4_legacy_shape(operator_config, skill, role, framework_aliases)
    if s4:
        resolution_path.append(s4["stage_entry"])
        final_provider = s4["resolved_provider"]
        final_model_id = s4["resolved_model_id"]
        is_legacy_path = True
        # Recover alias name from legacy shape for stage 6 overlay
        legacy_alias = (operator_config.get(skill) or {}).get("models", {}).get(role)
        s6 = _stage6_prefer_pro(
            legacy_alias, operator_config, framework_aliases, is_legacy_path
        )
        if s6 is not None:
            resolution_path.append(s6["stage_entry"])
            if "resolved_provider" in s6:
                final_provider = s6["resolved_provider"]
                final_model_id = s6["resolved_model_id"]
        return {
            "skill": skill,
            "role": role,
            "resolved_provider": final_provider,
            "resolved_model_id": final_model_id,
            "resolution_path": resolution_path,
        }

    # ----- Stage 5: framework default -----
    s5 = _stage5_framework_default(
        framework_defaults, skill, framework_aliases, framework_tier_mappings, runtime_state
    )
    if s5:
        resolution_path.append(s5["stage_entry"])
        final_provider = s5["resolved_provider"]
        final_model_id = s5["resolved_model_id"]
        s5_alias = s5["stage_entry"]["details"].get("alias")
        s6 = _stage6_prefer_pro(s5_alias, operator_config, framework_aliases, False)
        if s6 is not None:
            resolution_path.append(s6["stage_entry"])
            if "resolved_provider" in s6:
                final_provider = s6["resolved_provider"]
                final_model_id = s6["resolved_model_id"]
        return {
            "skill": skill,
            "role": role,
            "resolved_provider": final_provider,
            "resolved_model_id": final_model_id,
            "resolution_path": resolution_path,
        }

    # ----- All stages exhausted — fail-closed -----
    return {
        "skill": skill,
        "role": role,
        "error": {
            "code": ERR_NO_RESOLUTION,
            "stage_failed": 5,
            "detail": (
                f"no resolution for skill `{skill}` role `{role}`; check "
                f"skill_models, legacy shape, and agents.{skill} default"
            ),
        },
    }


# ----------------------------------------------------------------------------
# Fixture wrapper (golden test runner support)
# ----------------------------------------------------------------------------

def resolve_fixture(fixture_path: Path) -> list[dict]:
    """Read a model-resolution fixture YAML and produce one ResolutionResult
    per `expected.resolutions[]` entry. Each result is decorated with the
    `fixture` context tag (filename without extension).

    Used by `tests/python/golden_resolution.py` and the CLI subcommand
    `resolve-fixture`. Does NOT compare actual-vs-expected; that's the
    runner's job. The resolver simply runs the algorithm against
    `input.{framework_defaults, operator_config, runtime_state}` for each
    declared (skill, role) pair.
    """
    import yaml  # local import; keeps stdlib-only at module load

    with open(fixture_path, "r", encoding="utf-8") as fh:
        fixture = yaml.safe_load(fh)
    if not isinstance(fixture, dict):
        return []

    fixture_name = fixture_path.stem
    merged_config = fixture.get("input") or {}
    expected = fixture.get("expected") or {}
    expected_resolutions = expected.get("resolutions") or []

    results: list[dict] = []
    for entry in expected_resolutions:
        if not isinstance(entry, dict):
            continue
        skill = entry.get("skill")
        role = entry.get("role")
        if not isinstance(skill, str) or not isinstance(role, str):
            continue
        result = resolve(merged_config, skill, role)
        result["fixture"] = fixture_name
        results.append(result)
    return results


# ----------------------------------------------------------------------------
# CLI entry point
# ----------------------------------------------------------------------------

def _cli_resolve(args: argparse.Namespace) -> int:
    import yaml
    with open(args.config, "r", encoding="utf-8") as fh:
        config = yaml.safe_load(fh)
    if not isinstance(config, dict):
        print(f"[MODEL-RESOLVER] config at {args.config} is not a dict", file=sys.stderr)
        return EXIT_USAGE
    result = resolve(config, args.skill, args.role)
    print(dump_canonical_json(result))
    return EXIT_OK if "error" not in result else EXIT_ERROR


def _cli_resolve_fixture(args: argparse.Namespace) -> int:
    fixture_path = Path(args.fixture)
    if not fixture_path.is_file():
        print(f"[MODEL-RESOLVER] fixture not found: {fixture_path}", file=sys.stderr)
        return EXIT_USAGE
    results = resolve_fixture(fixture_path)
    for r in results:
        print(dump_canonical_json(r))
    return EXIT_OK


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="model-resolver",
        description="cycle-099 FR-3.9 6-stage model resolver (Python canonical).",
    )
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_resolve = sub.add_parser("resolve", help="Resolve a single (skill, role)")
    p_resolve.add_argument("--config", required=True, help="Path to merged config YAML")
    p_resolve.add_argument("--skill", required=True)
    p_resolve.add_argument("--role", required=True)
    p_resolve.set_defaults(func=_cli_resolve)

    p_fixture = sub.add_parser(
        "resolve-fixture",
        help="Resolve all expected (skill, role) pairs in a fixture YAML, emit JSON Lines",
    )
    p_fixture.add_argument("fixture", help="Path to fixture YAML")
    p_fixture.set_defaults(func=_cli_resolve_fixture)

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
