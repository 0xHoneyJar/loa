"""PR #896 BB iter-1 FIND-002 — voice-slug collision fix tests.

The pre-fix `_vq_derive_voice_slug` returned `role` verbatim when set,
causing voice-ID collisions in multi-model cohorts that shared a role.
The fix makes role a METADATA tag and derives the slug from the
canonical model_id (with role prefixed for operator readability when
both are present).
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))


def _import_cheval():
    """Load cheval.py for direct helper access (handles dataclass refs)."""
    name = "cheval_voice_slug_test"
    if name in sys.modules:
        return sys.modules[name]
    spec = importlib.util.spec_from_file_location(name, ROOT / "cheval.py")
    if spec is None or spec.loader is None:
        pytest.skip("cannot load cheval module spec")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    try:
        spec.loader.exec_module(module)
    except Exception:
        sys.modules.pop(name, None)
        raise
    return module


# ---------------------------------------------------------------------------
# Closure tests — no collision across a cohort that shares a role
# ---------------------------------------------------------------------------


def test_two_model_cohort_with_shared_role_does_not_collide():
    """The FIND-002 reproduction: two reviewers in one cohort sharing
    --role=review must NOT produce duplicate voice-slugs."""
    cheval = _import_cheval()
    slug_a = cheval._vq_derive_voice_slug("review", "anthropic:claude-opus-4-7")
    slug_b = cheval._vq_derive_voice_slug("review", "openai:gpt-5.5-pro")
    assert slug_a != slug_b
    # Both should be non-empty + non-"unknown"
    assert slug_a and slug_a != "unknown"
    assert slug_b and slug_b != "unknown"


def test_role_appears_in_slug_when_provided():
    """Operator readability: when role is present, it prefixes the slug
    so the cohort table is readable at a glance."""
    cheval = _import_cheval()
    slug = cheval._vq_derive_voice_slug("review", "anthropic:claude-opus-4-7")
    assert "review" in slug
    assert "claude-opus-4-7" in slug


def test_model_id_alone_when_no_role():
    """When --role is absent, slug derives from the model_id portion of
    the canonical (provider:model_id → model_id)."""
    cheval = _import_cheval()
    slug = cheval._vq_derive_voice_slug(None, "openai:gpt-5.5-pro")
    assert slug == "gpt-5.5-pro"


def test_role_only_fallback_when_no_primary():
    """Degraded pre-resolution path: when primary_canonical is None
    (no chain resolved yet), fall back to role-only slug."""
    cheval = _import_cheval()
    slug = cheval._vq_derive_voice_slug("audit", None)
    assert slug == "audit"


def test_unknown_when_both_missing():
    """Edge case: neither role nor primary → 'unknown'."""
    cheval = _import_cheval()
    slug = cheval._vq_derive_voice_slug(None, None)
    assert slug == "unknown"


def test_handles_canonical_without_colon():
    """When primary is bare model_id (no provider: prefix), use it directly."""
    cheval = _import_cheval()
    slug = cheval._vq_derive_voice_slug(None, "gpt-5.5-pro")
    assert slug == "gpt-5.5-pro"


def test_three_model_cohort_produces_three_distinct_slugs():
    """The full multi-model cohort case — all 3 BB models with shared role."""
    cheval = _import_cheval()
    slugs = {
        cheval._vq_derive_voice_slug("review", "anthropic:claude-opus-4-7"),
        cheval._vq_derive_voice_slug("review", "openai:gpt-5.5-pro"),
        cheval._vq_derive_voice_slug("review", "google:gemini-3.1-pro-preview"),
    }
    assert len(slugs) == 3  # no collisions
