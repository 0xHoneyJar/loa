"""cycle-109 Sprint 2 T2.3 — blocker-risk classifier (SDD §3.2.2 blocker-risk
computation table, operator-overridden into Sprint 2 AC per C109.OP-10 / v6
SKP-002).

The classifier is the canonical Python writer of ``blocker_risk`` for every
``voices_dropped[]`` entry. It is invoked at envelope-emission time in the
producer path (cheval.cmd_invoke for T2.3); consumers MUST NOT re-derive
(consumer-lint enforcement lands in T2.8).

Per SDD §3.2.2 the inputs are:

  - voice_role: role of the dropped voice in the cohort (e.g., "review",
    "audit", "implementation")
  - sprint_kind: declared sprint-kind risk band (e.g., "implementation",
    "security", "docs")
  - reason: the canonical drop-reason enum (proxy for KF priors until a
    full known-failures.md parser lands in Sprint 3+)

The output is one of ``"unknown" | "low" | "med" | "high"``.

Cutoffs (SDD §3.2.2):
  composite ≥ 0.7 → high
  0.4 ≤ composite < 0.7 → med
  0.1 ≤ composite < 0.4 → low
  composite < 0.1 OR insufficient priors → unknown

Hard rule (NFR-Rel-1): ``reason == "ChainExhausted"`` → ``high`` regardless
of role / sprint_kind. A fully-walked chain that produced no usable result
is by-definition a high blocker-risk drop.

Golden fixture corner cases:
  - Cycle-109 PRD-review trajectory (Opus review voice dropped under
    implementation sprint) MUST classify as ``med`` per SDD §3.2.2 fixture
    enumeration. This is the load-bearing case that justified the
    blocker_risk schema field.
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))


# ---------------------------------------------------------------------------
# Hard rules
# ---------------------------------------------------------------------------


def test_chain_exhausted_short_circuits_to_high_regardless_of_role():
    from loa_cheval.verdict.blocker_risk import compute_blocker_risk

    # No role, no sprint — chain-exhausted is still high
    assert compute_blocker_risk(reason="ChainExhausted") == "high"


def test_chain_exhausted_high_even_for_docs_sprint():
    from loa_cheval.verdict.blocker_risk import compute_blocker_risk

    # A fully-walked chain produced no result; the sprint risk band cannot
    # demote this — NFR-Rel-1 says clean is definitionally impossible here.
    assert compute_blocker_risk(
        reason="ChainExhausted", voice_role="docs", sprint_kind="docs"
    ) == "high"


# ---------------------------------------------------------------------------
# Cycle-109 PRD-review trajectory (canonical regression fixture)
# ---------------------------------------------------------------------------


def test_cycle_109_prd_review_trajectory_opus_review_implementation_empty_content_is_med():
    """Per SDD §3.2.2 line ~563:
    'Cycle-109 PRD-review trajectory replayed with the new schema → MUST
    classify as DEGRADED (1 voice effectively dropped, blocker_risk
    computed med from security-touching sprint-kind + Opus primary-
    reviewer role)'.

    This is the load-bearing fixture — if this case slips to 'high',
    the cycle-109 PRD-review trajectory becomes FAILED instead of
    DEGRADED, and the substrate-output classification regresses.
    """
    from loa_cheval.verdict.blocker_risk import compute_blocker_risk

    result = compute_blocker_risk(
        reason="EmptyContent",
        voice_role="review",
        sprint_kind="implementation",
    )
    assert result == "med", (
        f"cycle-109 PRD-review trajectory regression: "
        f"expected 'med', got {result!r}"
    )


# ---------------------------------------------------------------------------
# Insufficient-priors → unknown
# ---------------------------------------------------------------------------


def test_no_role_no_sprint_returns_unknown():
    """When neither voice_role nor sprint_kind is supplied the classifier
    has no contextual priors and returns 'unknown'. SDD §3.2.2:
    'insufficient priors → unknown'.
    """
    from loa_cheval.verdict.blocker_risk import compute_blocker_risk

    assert compute_blocker_risk(reason="EmptyContent") == "unknown"


def test_no_role_no_sprint_rate_limited_returns_unknown():
    from loa_cheval.verdict.blocker_risk import compute_blocker_risk

    assert compute_blocker_risk(reason="RateLimited") == "unknown"


# ---------------------------------------------------------------------------
# Role-weight axis
# ---------------------------------------------------------------------------


@pytest.mark.parametrize("role", ["review", "audit", "dissent", "arbiter"])
def test_primary_safety_roles_increase_risk(role):
    """Primary-safety roles (review/audit/dissent/arbiter) carry the highest
    role weight per SDD §3.2.2."""
    from loa_cheval.verdict.blocker_risk import compute_blocker_risk

    # Safety role + implementation sprint + EmptyContent → MED
    assert compute_blocker_risk(
        reason="EmptyContent", voice_role=role, sprint_kind="implementation",
    ) == "med"


def test_implementation_role_lower_weight_than_safety_roles():
    """A dropped implementation voice carries less blocker-risk weight than
    a dropped review voice for the same sprint + reason."""
    from loa_cheval.verdict.blocker_risk import compute_blocker_risk

    # Implementation role + test sprint + RateLimited → expected lower
    impl_result = compute_blocker_risk(
        reason="RateLimited", voice_role="implementation", sprint_kind="test",
    )
    review_result = compute_blocker_risk(
        reason="RateLimited", voice_role="review", sprint_kind="test",
    )
    # Both low or implementation lower; never strictly greater
    _ORDER = {"unknown": -1, "low": 0, "med": 1, "high": 2}
    assert _ORDER[impl_result] <= _ORDER[review_result], (
        f"implementation role should not produce higher risk than safety "
        f"role for same inputs; got impl={impl_result!r} review={review_result!r}"
    )


# ---------------------------------------------------------------------------
# Sprint-kind axis
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    "sprint_kind,expected_floor",
    [
        ("implementation", "med"),
        ("security", "med"),
        ("audit", "med"),
        ("review", "med"),
        ("design", "med"),
        ("infra", "low"),
        ("test", "low"),
        ("docs", "low"),
    ],
)
def test_sprint_kind_risk_band(sprint_kind, expected_floor):
    """Sprint-kind drives the second weight axis. Security-touching kinds
    (implementation/security/audit/review/design) push to med under a
    primary safety role + KF-002 reason; lower-risk kinds (infra/test/docs)
    stay at low."""
    from loa_cheval.verdict.blocker_risk import compute_blocker_risk

    result = compute_blocker_risk(
        reason="EmptyContent", voice_role="review", sprint_kind=sprint_kind,
    )
    assert result == expected_floor, (
        f"sprint_kind={sprint_kind!r} expected {expected_floor!r}, got {result!r}"
    )


# ---------------------------------------------------------------------------
# Reason-weight axis (KF-priors proxy)
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    "reason,expected_for_safety_impl",
    [
        # KF-002 class reasons carry the highest reason weight
        ("EmptyContent", "med"),
        ("ContextTooLarge", "med"),
        # Mid-tier (provider availability)
        ("ProviderUnavailable", "med"),
        ("RetriesExhausted", "med"),
        ("NoEligibleAdapter", "med"),
        # Lowest-tier (transient)
        ("RateLimited", "low"),
        # Non-failure reasons
        ("InteractionPending", "low"),
        ("Other", "low"),
    ],
)
def test_reason_weight_under_safety_impl(reason, expected_for_safety_impl):
    """Under the canonical safety-role + impl-sprint corner, the reason
    weight determines whether we land at low or med. ChainExhausted is
    a separate hard-rule case."""
    from loa_cheval.verdict.blocker_risk import compute_blocker_risk

    result = compute_blocker_risk(
        reason=reason, voice_role="review", sprint_kind="implementation",
    )
    assert result == expected_for_safety_impl, (
        f"reason={reason!r} expected {expected_for_safety_impl!r}, got {result!r}"
    )


# ---------------------------------------------------------------------------
# Output enum invariant
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    "reason",
    [
        "EmptyContent", "RateLimited", "ProviderUnavailable",
        "RetriesExhausted", "ContextTooLarge", "NoEligibleAdapter",
        "ChainExhausted", "InteractionPending", "Other",
        "UnrecognizedReason",  # graceful degradation: must still return valid enum
    ],
)
def test_output_is_always_a_valid_enum(reason):
    from loa_cheval.verdict.blocker_risk import compute_blocker_risk

    result = compute_blocker_risk(reason=reason)
    assert result in {"unknown", "low", "med", "high"}


def test_unrecognized_reason_returns_unknown_when_no_context():
    """Reasons outside the canonical taxonomy should not crash the
    classifier; without context they are treated as 'unknown'."""
    from loa_cheval.verdict.blocker_risk import compute_blocker_risk

    assert compute_blocker_risk(reason="SomeNovelFailureClass") == "unknown"


# ---------------------------------------------------------------------------
# Schema-pattern voice-slug regression (cross-set with verdict-quality schema)
# ---------------------------------------------------------------------------


def test_classifier_does_not_mutate_inputs():
    """Defensive: classifier MUST NOT mutate caller-supplied data (it is
    purely a function of its inputs). Critical for callers that build
    voices_dropped[] dicts and pass them by reference."""
    from loa_cheval.verdict.blocker_risk import compute_blocker_risk

    # Pass mutable kf_priors and verify it's untouched
    priors = {"opus": 3, "gpt-5.5-pro": 1}
    priors_copy = dict(priors)
    _ = compute_blocker_risk(
        reason="EmptyContent",
        voice_role="review",
        sprint_kind="implementation",
        kf_priors=priors,
    )
    assert priors == priors_copy, "compute_blocker_risk mutated kf_priors"


# ---------------------------------------------------------------------------
# Determinism (golden-fixture friendly)
# ---------------------------------------------------------------------------


def test_classifier_is_deterministic_under_same_inputs():
    """Same inputs MUST produce the same output across calls. v6 SKP-002
    closure: the classifier is the canonical Python writer; golden fixtures
    in conformance suite (T2.8) depend on byte-identical outputs."""
    from loa_cheval.verdict.blocker_risk import compute_blocker_risk

    args = dict(
        reason="EmptyContent",
        voice_role="review",
        sprint_kind="implementation",
    )
    first = compute_blocker_risk(**args)
    for _ in range(5):
        assert compute_blocker_risk(**args) == first


# ---------------------------------------------------------------------------
# kf_priors signature stability (forward-compat for Sprint 3 KF parser)
# ---------------------------------------------------------------------------


def test_kf_priors_kwarg_accepted_but_optional():
    """The kf_priors keyword argument is part of the v1 signature even
    though the v1 heuristic doesn't directly consume it (reason-weight
    stands in as the priors proxy). Sprint 3+ adds a known-failures.md
    parser that populates it; the signature must remain stable so callers
    don't break across the upgrade."""
    from loa_cheval.verdict.blocker_risk import compute_blocker_risk

    # With kf_priors omitted
    r1 = compute_blocker_risk(
        reason="EmptyContent", voice_role="review", sprint_kind="implementation",
    )
    # With kf_priors=None
    r2 = compute_blocker_risk(
        reason="EmptyContent",
        voice_role="review",
        sprint_kind="implementation",
        kf_priors=None,
    )
    # With kf_priors empty dict
    r3 = compute_blocker_risk(
        reason="EmptyContent",
        voice_role="review",
        sprint_kind="implementation",
        kf_priors={},
    )
    assert r1 == r2 == r3, (
        f"signature variants diverged: omitted={r1!r}, None={r2!r}, "
        f"empty-dict={r3!r}"
    )
