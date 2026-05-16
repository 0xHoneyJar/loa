"""Cycle-108 sprint-1 T1.C — advisor_strategy loader tests.

Validates the load_advisor_strategy() function against:
  - Schema-level NFR-Sec1 enforcement (defaults.review + defaults.audit
    pinned to advisor)
  - Runtime NFR-Sec1 enforcement (per_skill_overrides cannot downgrade
    review/audit skills)
  - Unknown skill rejection (per_skill_overrides keys must exist in registry)
  - Schema-version const-pin
  - Kill-switch env var precedence
  - Disabled-by-absence fallback to disabled_legacy()
  - Positive case: valid config parses + resolve() works correctly
"""

from __future__ import annotations

import os
import shutil
import sys
from pathlib import Path

import pytest

# Make .claude/adapters importable
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / ".claude" / "adapters"))

from loa_cheval.config.advisor_strategy import (  # noqa: E402
    AdvisorStrategyConfig,
    ConfigError,
    ResolvedTier,
    load_advisor_strategy,
)


@pytest.fixture
def repo_with_fixture(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    """Materialize a minimal repo at tmp_path with a chosen fixture as .loa.config.yaml.

    Returns a factory: call with `fixture_name` (e.g. "valid-default")
    to copy that fixture in. Also copies the schema and minimal skill
    registry so the loader can perform schema + skill-registry checks.
    """
    fixture_dir = ROOT / "tests" / "fixtures" / "advisor-strategy" / "configs"
    schema_src = ROOT / ".claude" / "data" / "schemas" / "advisor-strategy.schema.json"
    skills_src = ROOT / ".claude" / "skills"

    # Set up minimal scaffold under tmp_path
    schema_dst = tmp_path / ".claude" / "data" / "schemas"
    schema_dst.mkdir(parents=True)
    shutil.copy(schema_src, schema_dst / "advisor-strategy.schema.json")

    # Copy skills registry (used for per_skill_overrides validation)
    skills_dst = tmp_path / ".claude" / "skills"
    shutil.copytree(skills_src, skills_dst)

    # Ensure kill-switch is unset for this test
    monkeypatch.delenv("LOA_ADVISOR_STRATEGY_DISABLE", raising=False)

    def _setup(fixture_name: str) -> Path:
        src = fixture_dir / f"{fixture_name}.yaml"
        dst = tmp_path / ".loa.config.yaml"
        shutil.copy(src, dst)
        return tmp_path

    return _setup


# --- Positive case -----------------------------------------------------------

def test_valid_default_loads_successfully(repo_with_fixture):
    repo = repo_with_fixture("valid-default")
    cfg = load_advisor_strategy(repo)
    assert isinstance(cfg, AdvisorStrategyConfig)
    assert cfg.enabled is True
    assert cfg.schema_version == 1
    assert cfg.defaults["review"] == "advisor"
    assert cfg.defaults["audit"] == "advisor"
    assert cfg.defaults["implementation"] == "executor"


def test_valid_default_resolves_implementation_role(repo_with_fixture):
    repo = repo_with_fixture("valid-default")
    cfg = load_advisor_strategy(repo)
    resolved = cfg.resolve(role="implementation", skill="implementing-tasks", provider="anthropic")
    assert isinstance(resolved, ResolvedTier)
    assert resolved.tier == "executor"
    assert resolved.model_id == "claude-sonnet-4-6"
    # implementing-tasks is in per_skill_overrides → tier_source
    assert resolved.tier_source == "per_skill_override"


def test_valid_default_resolves_review_role_to_advisor(repo_with_fixture):
    repo = repo_with_fixture("valid-default")
    cfg = load_advisor_strategy(repo)
    resolved = cfg.resolve(role="review", skill="reviewing-code", provider="anthropic")
    assert resolved.tier == "advisor"
    assert resolved.model_id == "claude-opus-4-7"
    # reviewing-code not in per_skill_overrides → tier_source defaults
    assert resolved.tier_source == "default"


# --- Negative cases — schema-layer rejection ---------------------------------

def test_poisoned_review_executor_schema_rejection(repo_with_fixture):
    repo = repo_with_fixture("poisoned-review-executor")
    with pytest.raises(ConfigError) as exc:
        load_advisor_strategy(repo)
    assert "schema invalid" in str(exc.value).lower() or "review" in str(exc.value).lower()


def test_poisoned_audit_executor_schema_rejection(repo_with_fixture):
    repo = repo_with_fixture("poisoned-audit-executor")
    with pytest.raises(ConfigError) as exc:
        load_advisor_strategy(repo)
    assert "schema invalid" in str(exc.value).lower() or "audit" in str(exc.value).lower()


def test_poisoned_bad_schema_version_rejection(repo_with_fixture):
    repo = repo_with_fixture("poisoned-bad-schema-version")
    with pytest.raises(ConfigError) as exc:
        load_advisor_strategy(repo)
    assert "schema invalid" in str(exc.value).lower() or "999" in str(exc.value) or "const" in str(exc.value).lower()


# --- Negative cases — runtime rejection --------------------------------------

def test_poisoned_skill_override_review_runtime_rejection(repo_with_fixture):
    """per_skill_overrides downgrading a review-class skill to executor must fail."""
    repo = repo_with_fixture("poisoned-skill-override-review")
    with pytest.raises(ConfigError) as exc:
        load_advisor_strategy(repo)
    msg = str(exc.value).lower()
    assert "nfr-sec1" in msg or "bridgebuilder-review" in msg


def test_poisoned_unknown_skill_rejection(repo_with_fixture):
    """per_skill_overrides referencing a non-existent skill must fail."""
    repo = repo_with_fixture("poisoned-unknown-skill")
    with pytest.raises(ConfigError) as exc:
        load_advisor_strategy(repo)
    assert "unknown skill" in str(exc.value).lower() or "nonexistent-skill-zzz" in str(exc.value)


# --- Kill-switch + disabled-by-absence semantics -----------------------------

def test_kill_switch_returns_disabled_legacy(repo_with_fixture, monkeypatch):
    repo = repo_with_fixture("valid-default")
    monkeypatch.setenv("LOA_ADVISOR_STRATEGY_DISABLE", "1")
    cfg = load_advisor_strategy(repo)
    assert cfg.enabled is False
    assert cfg.config_sha == "DISABLED"


def test_disabled_legacy_factory():
    """Direct factory call works without any repo state."""
    cfg = AdvisorStrategyConfig.disabled_legacy()
    assert cfg.enabled is False
    assert cfg.schema_version == 1
    assert cfg.tier_aliases == {}


def test_disabled_legacy_resolve_raises():
    """Calling resolve() on disabled config is a programming error."""
    cfg = AdvisorStrategyConfig.disabled_legacy()
    with pytest.raises(ConfigError) as exc:
        cfg.resolve(role="implementation", skill="implement", provider="anthropic")
    assert "disabled" in str(exc.value).lower()


def test_missing_config_section_returns_disabled_legacy(tmp_path, monkeypatch):
    """When .loa.config.yaml is absent OR lacks advisor_strategy section → legacy."""
    monkeypatch.delenv("LOA_ADVISOR_STRATEGY_DISABLE", raising=False)
    # Empty repo — no .loa.config.yaml at all
    cfg = load_advisor_strategy(tmp_path)
    assert cfg.enabled is False


# --- Frozen dataclass enforcement --------------------------------------------

def test_advisor_strategy_config_is_frozen():
    cfg = AdvisorStrategyConfig.disabled_legacy()
    with pytest.raises((AttributeError, Exception)):
        cfg.enabled = True  # type: ignore[misc]


def test_resolved_tier_is_frozen():
    rt = ResolvedTier(
        model_id="x", tier="advisor", tier_source="default",
        tier_resolution="static:abc", provider="anthropic"
    )
    with pytest.raises((AttributeError, Exception)):
        rt.model_id = "y"  # type: ignore[misc]
