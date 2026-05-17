"""cycle-113 Sprint 1 T1.4 review-feedback regression tests.

Pins the ``check_idempotency`` failure modes flagged in Phase 2.5
cross-model review (gpt-5.5-pro BLOCKING finding): missing on-disk
fixtures, divergent re-emit, and orphan files MUST fail the check.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[3]
GENERATE_PY = (
    REPO_ROOT / "tests" / "fixtures" / "cycle-113" / "streaming-parity"
    / "generate.py"
)


def _import_generator():
    spec = importlib.util.spec_from_file_location("generate_module", GENERATE_PY)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


@pytest.fixture
def generator():
    return _import_generator()


@pytest.fixture
def empty_dir(tmp_path):
    d = tmp_path / "fixtures"
    d.mkdir()
    return d


# ---------------------------------------------------------------------------
# Full happy path — generated corpus matches itself
# ---------------------------------------------------------------------------


def test_check_passes_on_freshly_emitted_corpus(generator, empty_dir):
    """Sanity: emit + immediately check returns True."""
    generator.emit_all(empty_dir, generator.PROVIDERS)
    assert generator.check_idempotency(empty_dir, generator.PROVIDERS) is True


# ---------------------------------------------------------------------------
# BLOCKING fix from Phase 2.5: missing fixtures MUST fail
# ---------------------------------------------------------------------------


def test_check_fails_when_on_disk_fixture_missing(generator, empty_dir):
    """Phase 2.5 review-feedback BLOCKING fix: a partial fixture corpus
    must NOT pass check_idempotency. Prior to the fix, missing on-disk
    files only printed [NEW] and exited 0 — defeating the CI gate.
    """
    # Emit the full corpus
    generator.emit_all(empty_dir, generator.PROVIDERS)
    # Delete one fixture file to simulate a partial commit
    target = empty_dir / "healthy-short.anthropic.sse"
    target.unlink()

    # check_idempotency MUST fail
    assert generator.check_idempotency(empty_dir, generator.PROVIDERS) is False


def test_check_fails_when_multiple_fixtures_missing(generator, empty_dir):
    """Mirror of the above; pins behavior when most of the corpus is
    absent (the failure mode the Phase 2.5 review caught: a fixture
    directory wiped except for one scenario would have passed before)."""
    generator.emit_all(empty_dir, generator.PROVIDERS)
    # Keep only healthy-short.* files; delete everything else.
    for f in empty_dir.iterdir():
        if not f.name.startswith("healthy-short."):
            f.unlink()
    assert generator.check_idempotency(empty_dir, generator.PROVIDERS) is False


# ---------------------------------------------------------------------------
# Drift detection (was already working pre-fix; pin against regression)
# ---------------------------------------------------------------------------


def test_check_fails_when_on_disk_fixture_diverged(generator, empty_dir):
    """An on-disk file with mutated content MUST fail the check.
    Distinguishes [DIVERGED] (hash mismatch) from [MISSING] (no file).
    """
    generator.emit_all(empty_dir, generator.PROVIDERS)
    target = empty_dir / "healthy-short.anthropic.sse"
    target.write_bytes(b"corrupted content")
    assert generator.check_idempotency(empty_dir, generator.PROVIDERS) is False


# ---------------------------------------------------------------------------
# Orphan detection (additional NEW safeguard from the fix)
# ---------------------------------------------------------------------------


def test_check_fails_on_orphan_when_full_provider_run(generator, empty_dir):
    """An on-disk file that the generator did NOT emit (e.g., a stale
    fixture from a deleted scenario) MUST fail when the check runs
    over all providers. Catches the "deleted SCENARIOS entry but forgot
    to clean up disk" case.
    """
    generator.emit_all(empty_dir, generator.PROVIDERS)
    orphan = empty_dir / "ghost-scenario.anthropic.sse"
    orphan.write_bytes(b"data")
    # Re-hash the on-disk corpus by re-emitting; orphan must surface
    # as a failure on a FULL provider-set check.
    assert generator.check_idempotency(empty_dir, generator.PROVIDERS) is False


def test_check_tolerates_orphan_when_provider_subset(generator, empty_dir):
    """A subset run (``--provider anthropic`` only) MUST tolerate
    on-disk files for OTHER providers. This is the legitimate use
    case: the generator is asked to validate only one provider, the
    other providers' fixtures are unrelated noise."""
    generator.emit_all(empty_dir, generator.PROVIDERS)
    # Sanity: full check passes
    assert generator.check_idempotency(empty_dir, generator.PROVIDERS) is True
    # Subset check passes when on-disk has more than the subset
    assert generator.check_idempotency(empty_dir, ("anthropic",)) is True
