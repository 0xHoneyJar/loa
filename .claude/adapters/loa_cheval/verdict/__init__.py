"""cycle-109 Sprint 2 — verdict-quality envelope module.

Canonical writer of the `verdict_quality.status` field per SDD §3.2.2.
Consumers across the substrate (cheval, Flatline orchestrator,
adversarial-review, BB cheval-delegate, flatline-readiness,
red-team-pipeline, post-PR-triage) read status from this module;
re-derivation in caller code is blocked by `tools/lint-verdict-consumers.py`
(Sprint 2 T2.8 deliverable).

Public API: import from the submodule directly to avoid runtime ordering
issues with the ``python -m loa_cheval.verdict.quality`` CLI entry-point:

    from loa_cheval.verdict.quality import (
        compute_verdict_status,
        validate_invariants,
        emit_envelope_with_status,
        EnvelopeInvariantViolation,
    )
"""
