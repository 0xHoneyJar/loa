"""Cycle-108 sprint-1 T1.C — Advisor-Strategy config loader.

Implements the single-chokepoint loader for the role→tier routing config.
Closes:
  - PRD §5 FR-1 (configuration schema)
  - SDD §3.3 (loader-layer enforcement)
  - SDD §21.1 (canonical AdvisorStrategyConfig dataclass)
  - SDD §20.1 (Red Team ATK-A1: audited_review_skills loader enforcement)
  - NFR-Sec1 (review/audit tier hard-pin)

The dataclasses are FROZEN — runtime mutation MUST raise. The loader is the
ONLY place tier-resolution decisions originate; downstream consumers (cheval,
modelinv, validate-skill-capabilities.sh) call into `resolve()` rather than
re-implementing routing logic.

NFR-P1 budget: ≤5ms per load (covered by jsonschema validator's O(n) walk).
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, FrozenSet, List, Literal, Optional


# Exit codes (BSD sysexits.h)
EX_CONFIG = 78


# --- Data types --------------------------------------------------------------

@dataclass(frozen=True)
class ResolvedTier:
    """Result of role→tier→model resolution for a single cheval invocation.

    Returned by ``AdvisorStrategyConfig.resolve()``. Every field is required;
    callers do not need to handle ``None`` field branches.
    """
    model_id: str                          # e.g. "claude-sonnet-4-6"
    tier: str                              # "advisor" | "executor"
    tier_source: str                       # "default" | "per_skill_override" | "kill_switch"
    tier_resolution: str                   # "static:<sha>" | "dynamic"
    provider: str                          # "anthropic" | "openai" | "google"


@dataclass(frozen=True)
class AdvisorStrategyConfig:
    """Canonical config loaded from .loa.config.yaml::advisor_strategy.

    Loaded ONLY by ``load_advisor_strategy()``. Frozen dataclass — no
    runtime mutation. Callers must invoke ``.resolve(role, skill, provider)``
    to perform tier-routing lookups.

    Cycle-110 sprint-2a (T2.2) extends with dispatch_preference + per-role
    overrides + auto_mode + headless_concurrency_* fields. Pre-cycle-110
    configs (schema_version=1) load with cycle-110 defaults applied per
    SDD §3.6.
    """
    schema_version: int
    enabled: bool
    tier_resolution: str                                       # "static" | "dynamic"
    defaults: Dict[str, str]                                   # role -> tier
    tier_aliases: Dict[str, Dict[str, str]]                    # tier -> {provider -> model_id}
    per_skill_overrides: Dict[str, str]                        # skill_name -> tier
    audited_review_skills: FrozenSet[str]                      # SDD §3.7 ATK-A1
    benchmark_max_cost_usd: float                              # NFR-P3
    config_sha: str                                            # static-mode pin

    # Cycle-110 sprint-2a additions (FR-1)
    dispatch_preference: str                                   # "headless" | "http_api" | "auto"
    allow_cross_auth_fallback: Optional[bool]                  # None = derive per FR-1.4 ladder
    per_role_dispatch_preference: Dict[str, str]               # role -> dispatch_preference enum
    auto_mode_headless_margin_bps: int                         # C15 carry-in (default 200)
    headless_concurrency_scope: str                            # C7 (cross_process | process_only)
    headless_concurrency_limit: int                            # C7 (default 50)

    # Cycle-110 default ladder per FR-1.4 (C16 closure)
    # When allow_cross_auth_fallback is None, derive from dispatch_preference:
    #   headless → False  (operator chose headless explicitly; do NOT fallback
    #                      to paid HTTP silently)
    #   http_api → True   (legacy behavior — falls back to headless when
    #                      available)
    #   auto     → True   (auto-mode already evaluates all buckets)
    _CROSS_AUTH_FALLBACK_LADDER: Dict[str, bool] = field(
        default_factory=lambda: {
            "headless": False,
            "http_api": True,
            "auto": True,
        },
        repr=False,
        compare=False,
    )

    def effective_cross_auth_fallback(self, role: Optional[str] = None) -> bool:
        """Resolve allow_cross_auth_fallback per FR-1.4 (C16 closure).

        Explicit operator setting always wins. Otherwise derives from the
        effective dispatch_preference (per-role override applied if present).
        """
        if self.allow_cross_auth_fallback is not None:
            return self.allow_cross_auth_fallback
        pref = self.effective_dispatch_preference(role)
        # Defensive fallback — schema enforces the enum so this should never
        # trip in practice, but the dataclass MUST not crash if a future
        # schema version adds a new value before this map is updated.
        return self._CROSS_AUTH_FALLBACK_LADDER.get(pref, True)

    def effective_dispatch_preference(self, role: Optional[str] = None) -> str:
        """Resolve per-role dispatch_preference override (FR-1.3) or fall back
        to the cycle-wide setting."""
        if role and role in self.per_role_dispatch_preference:
            return self.per_role_dispatch_preference[role]
        return self.dispatch_preference

    @classmethod
    def disabled_legacy(cls) -> "AdvisorStrategyConfig":
        """Returned when advisor_strategy is absent, disabled, or kill-switched.

        Identical behavior to pre-cycle-108 cheval: tier-routing is a no-op,
        all roles resolve to advisor (legacy default).
        """
        return cls(
            schema_version=1,
            enabled=False,
            tier_resolution="static",
            defaults={},
            tier_aliases={},
            per_skill_overrides={},
            audited_review_skills=frozenset(),
            benchmark_max_cost_usd=0.0,
            config_sha="DISABLED",
            # cycle-110 defaults — match schema defaults for the absent-field
            # case (legacy / disabled configs behave as auto + None ladder).
            dispatch_preference="auto",
            allow_cross_auth_fallback=None,
            per_role_dispatch_preference={},
            auto_mode_headless_margin_bps=200,
            headless_concurrency_scope="cross_process",
            headless_concurrency_limit=50,
        )

    def resolve(
        self,
        role: str,
        skill: str,
        provider: str,
    ) -> ResolvedTier:
        """Resolve (role, skill, provider) → ResolvedTier.

        Raises ConfigError if invariants are violated (NFR-Sec1 etc).
        """
        if not self.enabled:
            # Should not be called when disabled; legacy callers omit role.
            raise ConfigError(
                "AdvisorStrategyConfig.resolve() called on disabled config; "
                "this is a programming error — caller should check .enabled first"
            )

        # 1. per-skill override wins
        tier_source = "default"
        if skill in self.per_skill_overrides:
            tier = self.per_skill_overrides[skill]
            tier_source = "per_skill_override"
        else:
            if role not in self.defaults:
                raise ConfigError(
                    f"Role '{role}' not in defaults (have: {list(self.defaults.keys())})"
                )
            tier = self.defaults[role]

        # 2. NFR-Sec1: review/audit roles MUST resolve to advisor
        if role in ("review", "audit") and tier != "advisor":
            raise ConfigError(
                f"NFR-Sec1 violation: role={role} resolved to tier={tier}; "
                f"review/audit MUST resolve to advisor"
            )

        # 3. Resolve provider+tier → model_id
        if tier not in self.tier_aliases:
            raise ConfigError(
                f"Tier '{tier}' not in tier_aliases (have: {list(self.tier_aliases.keys())})"
            )
        if provider not in self.tier_aliases[tier]:
            raise ConfigError(
                f"Provider '{provider}' not in tier_aliases.{tier} "
                f"(have: {list(self.tier_aliases[tier].keys())})"
            )
        model_id = self.tier_aliases[tier][provider]

        # 4. tier_resolution semantics
        if self.tier_resolution == "static":
            tr = f"static:{self.config_sha}"
        else:
            tr = "dynamic"

        return ResolvedTier(
            model_id=model_id,
            tier=tier,
            tier_source=tier_source,
            tier_resolution=tr,
            provider=provider,
        )


class ConfigError(Exception):
    """Raised on advisor-strategy config violations. Maps to exit code 78."""
    pass


# --- Schema location ---------------------------------------------------------

SCHEMA_PATH_REL = ".claude/data/schemas/advisor-strategy.schema.json"


# --- Helpers -----------------------------------------------------------------

def _load_yaml_section(repo_root: Path, key: str) -> Optional[Dict[str, Any]]:
    """Read a top-level key from .loa.config.yaml. Returns None if absent."""
    config_path = repo_root / ".loa.config.yaml"
    if not config_path.exists():
        return None
    try:
        import yaml
        with config_path.open() as f:
            data = yaml.safe_load(f)
    except ImportError:
        # Fallback to yq subprocess
        result = subprocess.run(
            ["yq", "eval", f".{key}", str(config_path)],
            capture_output=True, text=True,
        )
        if result.returncode != 0 or not result.stdout.strip() or result.stdout.strip() == "null":
            return None
        try:
            import yaml as yaml_local
            return yaml_local.safe_load(result.stdout)
        except ImportError:
            # Last resort: JSON parse via yq
            result = subprocess.run(
                ["yq", "eval", "-o=json", f".{key}", str(config_path)],
                capture_output=True, text=True,
            )
            if result.returncode == 0 and result.stdout.strip() and result.stdout.strip() != "null":
                return json.loads(result.stdout)
            return None

    if not isinstance(data, dict):
        return None
    return data.get(key)


def _validate_schema(raw: Dict[str, Any], schema_path: Path) -> None:
    """Validate raw config dict against JSON Schema. Raises ConfigError on failure."""
    try:
        import jsonschema
    except ImportError:
        # Schema validation is REQUIRED — without jsonschema, fail-closed.
        raise ConfigError(
            "jsonschema package not installed; cannot validate advisor-strategy config. "
            "Install via: pip install jsonschema>=4.21"
        )

    with schema_path.open() as f:
        schema = json.load(f)

    validator = jsonschema.Draft202012Validator(schema)
    errors = sorted(validator.iter_errors(raw), key=lambda e: e.path)
    if errors:
        msgs = []
        for err in errors:
            path = ".".join(str(p) for p in err.absolute_path) or "<root>"
            msgs.append(f"  at {path}: {err.message}")
        raise ConfigError(
            f"advisor-strategy schema invalid:\n" + "\n".join(msgs)
        )


def _enumerate_skills(repo_root: Path) -> Dict[str, Dict[str, Any]]:
    """Walk .claude/skills/*/SKILL.md and extract role + primary_role.

    Returns: skill_name -> {"role": str, "primary_role": Optional[str]}
    """
    skills_dir = repo_root / ".claude" / "skills"
    registry: Dict[str, Dict[str, Any]] = {}

    if not skills_dir.is_dir():
        return registry

    for skill_dir in sorted(skills_dir.iterdir()):
        if not skill_dir.is_dir():
            continue
        skill_md = skill_dir / "SKILL.md"
        if not skill_md.exists():
            continue
        skill_name = skill_dir.name
        registry[skill_name] = _extract_role_from_skill_md(skill_md)

    return registry


def _extract_role_from_skill_md(skill_md: Path) -> Dict[str, Any]:
    """Extract role + primary_role from SKILL.md frontmatter. Missing fields → None."""
    text = skill_md.read_text()
    # Frontmatter is between the first --- and the second ---
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return {"role": None, "primary_role": None}
    fm_end = None
    for i, line in enumerate(lines[1:], start=1):
        if line.strip() == "---":
            fm_end = i
            break
    if fm_end is None:
        return {"role": None, "primary_role": None}

    role = None
    primary_role = None
    for line in lines[1:fm_end]:
        stripped = line.strip()
        if stripped.startswith("role:"):
            role = stripped.split(":", 1)[1].strip().strip("\"'")
        elif stripped.startswith("primary_role:"):
            primary_role = stripped.split(":", 1)[1].strip().strip("\"'")

    return {
        "role": role,
        "primary_role": primary_role,
    }


def _config_file_git_sha(repo_root: Path, rel_path: str) -> str:
    """Capture the git commit SHA of the config file for static-mode pinning."""
    try:
        result = subprocess.run(
            ["git", "-C", str(repo_root), "log", "-1", "--format=%H", "--", rel_path],
            capture_output=True, text=True,
        )
        if result.returncode == 0 and result.stdout.strip():
            return result.stdout.strip()
    except (FileNotFoundError, subprocess.CalledProcessError):
        pass
    return "UNKNOWN"


# --- Main entrypoint ---------------------------------------------------------

def load_advisor_strategy(repo_root: Path | str) -> AdvisorStrategyConfig:
    """Load and validate the advisor-strategy config section.

    Order of operations (mirrors SDD §3.3):
      1. Kill-switch wins (NFR-Sec3): LOA_ADVISOR_STRATEGY_DISABLE=1 → disabled
      2. Read .loa.config.yaml::advisor_strategy
      3. Validate against JSON schema (Draft 2020-12)
      4. Runtime checks: per_skill_overrides keys exist in skill registry;
         NFR-Sec1 (review/audit skill overrides MUST be advisor); ATK-A1
         (audited_review_skills enforcement)
      5. Static-mode pinning (FR-9): capture .loa.config.yaml commit SHA

    Raises:
      ConfigError: any validation failure. Caller should map to exit 78.
    """
    if isinstance(repo_root, str):
        repo_root = Path(repo_root)

    # 1. Kill-switch (NFR-Sec3 / IMP-007 in-flight)
    if os.environ.get("LOA_ADVISOR_STRATEGY_DISABLE") == "1":
        return AdvisorStrategyConfig.disabled_legacy()

    # 2. Read config section
    raw = _load_yaml_section(repo_root, "advisor_strategy")
    if raw is None or not raw:
        return AdvisorStrategyConfig.disabled_legacy()

    # 3. Schema validate
    schema_path = repo_root / SCHEMA_PATH_REL
    if not schema_path.exists():
        raise ConfigError(
            f"advisor-strategy schema not found at {schema_path}; cycle-108 T1.A may be incomplete"
        )
    _validate_schema(raw, schema_path)

    # 4. Runtime checks
    skill_registry = _enumerate_skills(repo_root)
    per_skill_overrides = raw.get("per_skill_overrides", {})

    for skill_name, tier in per_skill_overrides.items():
        # 4a. Skill exists in registry
        if skill_name not in skill_registry:
            raise ConfigError(
                f"per_skill_overrides references unknown skill '{skill_name}' "
                f"(known: {sorted(skill_registry.keys())[:5]}...)"
            )
        # 4b. NFR-Sec1: review/audit role overrides MUST be advisor
        skill_role = skill_registry[skill_name].get("primary_role") or skill_registry[skill_name].get("role")
        # BB iter-4 F001 closure: if a per_skill_override targets a skill with
        # BOTH role fields absent (unmigrated / partial-merge state), refuse
        # the override entirely when its tier is non-advisor. The previous
        # `if skill_role in ("review", "audit")` predicate let unannotated
        # skills slip through as a silent skip — defense-in-depth gap.
        if skill_role is None and tier != "advisor":
            raise ConfigError(
                f"NFR-Sec1 violation: per_skill_overrides['{skill_name}']='{tier}' "
                f"but skill has no 'role' or 'primary_role' annotation. "
                f"Operator must (a) annotate the skill via tools/migrate-skill-roles.sh, "
                f"or (b) pin the override to 'advisor' (fail-safe)."
            )
        # Cross-check against audited_review_skills enum: any skill in the
        # explicitly-audited allowlist MUST resolve to advisor regardless of
        # its role annotation (covers the case where the enum is operator-
        # curated but the SKILL.md role field is stale).
        audited_enum = frozenset(raw.get("audited_review_skills", []))
        if skill_name in audited_enum and tier != "advisor":
            raise ConfigError(
                f"NFR-Sec1 violation: per_skill_overrides['{skill_name}']='{tier}' "
                f"but skill is in audited_review_skills enum (must be advisor regardless of role field)."
            )
        if skill_role in ("review", "audit") and tier != "advisor":
            raise ConfigError(
                f"NFR-Sec1 violation: per_skill_overrides['{skill_name}']='{tier}' "
                f"but skill role is '{skill_role}' (must be advisor)"
            )

    # 4c. ATK-A1 (SDD §3.7): audited_review_skills enforcement
    audited = frozenset(raw.get("audited_review_skills", []))
    if not audited:
        # Default: derive from skill registry
        audited = frozenset(
            name for name, meta in skill_registry.items()
            if (meta.get("primary_role") or meta.get("role")) == "review"
        )

    enabled = raw.get("enabled", False)
    if enabled:
        # Only enforce audited_review_skills when feature is enabled
        for name, meta in skill_registry.items():
            skill_role = meta.get("primary_role") or meta.get("role")
            # Only check single-role review skills (multi-role need different scrutiny per SDD §3.7)
            if skill_role == "review" and not meta.get("primary_role"):
                # Single-role review skill (primary_role absent or equal to role)
                if name not in audited:
                    # Only warn — adding new review skills should be operator-reviewed
                    # via schema PR (CODEOWNERS), but loader should not fail-closed on
                    # legitimate operator-added review skills that haven't been added
                    # to the enum yet. The CI gate (T1.B) catches this at PR time.
                    print(
                        f"[advisor-strategy] WARN: review skill '{name}' is not in "
                        f"audited_review_skills enum (SDD §3.7); operator should "
                        f"update .claude/data/schemas/advisor-strategy.schema.json",
                        file=sys.stderr,
                    )

    # 5. Static-mode pinning
    config_sha = _config_file_git_sha(repo_root, ".loa.config.yaml")

    # Cycle-110 sprint-2a additions (FR-1). Defaults match the schema's
    # default ladder so pre-cycle-110 (schema_version=1) configs that omit
    # these fields load with sensible behavior.
    auto_mode_raw = raw.get("auto_mode", {}) or {}
    per_role_pref = raw.get("per_role_dispatch_preference", {}) or {}
    if not isinstance(per_role_pref, dict):
        raise ConfigError(
            f"advisor_strategy.per_role_dispatch_preference must be a mapping; "
            f"got {type(per_role_pref).__name__}"
        )

    return AdvisorStrategyConfig(
        schema_version=raw["schema_version"],
        enabled=raw.get("enabled", False),
        tier_resolution=raw.get("tier_resolution", "static"),
        defaults=raw.get("defaults", {}),
        tier_aliases=raw.get("tier_aliases", {}),
        per_skill_overrides=raw.get("per_skill_overrides", {}),
        audited_review_skills=audited,
        benchmark_max_cost_usd=float(raw.get("benchmark", {}).get("max_cost_usd", 50.0)),
        config_sha=config_sha,
        dispatch_preference=raw.get("dispatch_preference", "auto"),
        allow_cross_auth_fallback=raw.get("allow_cross_auth_fallback"),  # None = derive
        per_role_dispatch_preference=dict(per_role_pref),
        auto_mode_headless_margin_bps=int(auto_mode_raw.get("headless_margin_bps", 200)),
        headless_concurrency_scope=raw.get("headless_concurrency_scope", "cross_process"),
        headless_concurrency_limit=int(raw.get("headless_concurrency_limit", 50)),
    )
