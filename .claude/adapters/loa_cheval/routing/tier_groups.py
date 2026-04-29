"""Tier-groups module — `prefer_pro_models` retargeting (SDD §1.4.3, §5.9, §5.10).

cycle-095 Sprint 2 (Task 2.8 / FR-5a) ships:
  - validate_tier_groups: shape validation for `tier_groups:` config block
  - dryrun_preview: returns the alias remaps that `apply_tier_groups()` WOULD
    produce given the current config — without applying them. Used by
    LOA_PREFER_PRO_DRYRUN env var / `model-invoke --validate-bindings --dryrun`.

Sprint 3 will ship:
  - apply_tier_groups: the actual mutation function (with override_user_aliases
    precedence + denylist + WARN log)

This module is import-safe and stateless (no module-level globals beyond
the imports). All functions are pure transformations of merged-config dicts.
"""

from __future__ import annotations

import logging
import os
from typing import Any, Dict, List, Tuple

from loa_cheval.types import ConfigError

logger = logging.getLogger("loa_cheval.routing.tier_groups")


def validate_tier_groups(config: Dict[str, Any]) -> List[str]:
    """Validate the shape of `tier_groups:` in the merged config.

    Returns a list of validation error / warning strings. Empty list = clean.
    Hard errors raise ConfigError; soft errors return as strings (caller
    decides whether to log WARN).
    """
    tg = config.get("tier_groups")
    if tg is None:
        return []
    if not isinstance(tg, dict):
        raise ConfigError(
            f"tier_groups must be a mapping, got {type(tg).__name__}."
        )

    warnings: List[str] = []
    aliases = config.get("aliases", {}) or {}

    # mappings: dict[alias -> alias-or-pair]
    mappings = tg.get("mappings", {})
    if mappings is None:
        mappings = {}
    if not isinstance(mappings, dict):
        raise ConfigError(
            f"tier_groups.mappings must be a mapping, got {type(mappings).__name__}."
        )
    for base, target in mappings.items():
        if not isinstance(base, str) or not isinstance(target, str):
            raise ConfigError(
                f"tier_groups.mappings entries must be string→string; "
                f"got {base!r}→{target!r}."
            )

    # denylist: list of alias names
    denylist = tg.get("denylist", [])
    if denylist is None:
        denylist = []
    if not isinstance(denylist, list):
        raise ConfigError(
            f"tier_groups.denylist must be a list, got {type(denylist).__name__}."
        )
    for entry in denylist:
        if not isinstance(entry, str):
            raise ConfigError(
                f"tier_groups.denylist entries must be strings, got {type(entry).__name__}."
            )
        if entry not in aliases and entry not in mappings:
            warnings.append(
                f"tier_groups.denylist references {entry!r} which is not "
                f"a known alias and not in tier_groups.mappings — entry is a no-op."
            )

    # max_cost_per_session_micro_usd: int >= 0 OR None
    cap = tg.get("max_cost_per_session_micro_usd", None)
    if cap is not None and not (isinstance(cap, int) and cap >= 0):
        raise ConfigError(
            f"tier_groups.max_cost_per_session_micro_usd must be a non-negative "
            f"integer or null, got {cap!r}."
        )

    return warnings


def dryrun_preview(config: Dict[str, Any]) -> List[str]:
    """Return human-readable preview of what apply_tier_groups would do.

    Sprint 2 ships this as the dry-run primitive; Sprint 3 wires it into
    `model-invoke --validate-bindings --dryrun` for full activation.

    Output is a list of strings, one per alias decision:
      - "{base}: SKIPPED (denylist)"
      - "{base}: SKIPPED (mappings empty — no Sprint 2 retargets)"
      - "{base}: {old_target} -> {pro_target}"
      - "{base}: SKIPPED (user explicit override; would resolve to {target})"

    Pure function — does NOT mutate config or fire any logs.
    """
    flag_on = config.get("hounfour", {}).get("prefer_pro_models", False)
    tg = config.get("tier_groups", {}) or {}
    mappings = tg.get("mappings", {}) or {}
    denylist = set(tg.get("denylist", []) or [])
    aliases = config.get("aliases", {}) or {}

    lines: List[str] = []
    if not flag_on:
        lines.append("prefer_pro_models is off — no remaps would apply.")
        return lines

    if not mappings:
        lines.append("tier_groups.mappings is empty — no remaps configured.")
        return lines

    for base, pro_target in mappings.items():
        if base in denylist:
            lines.append(f"  {base}: SKIPPED (denylist)")
            continue
        old = aliases.get(base, "(unknown)")
        new = pro_target if ":" in pro_target else aliases.get(pro_target, pro_target)
        lines.append(f"  {base}: {old} -> {new}")

    return lines


def is_dryrun_active() -> bool:
    """Return True when LOA_PREFER_PRO_DRYRUN is set to a truthy env value.

    Operators set this for one-shot preview without enabling the flag.
    Used by callers (model-invoke --validate-bindings) to switch to
    preview-only mode.
    """
    val = os.environ.get("LOA_PREFER_PRO_DRYRUN", "").strip().lower()
    return val in ("1", "true", "yes", "on")
