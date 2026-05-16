"""cycle-109 Sprint 2 T2.3 — blocker-risk classifier (SDD §3.2.2 blocker-risk
computation table, operator-overridden into Sprint 2 AC per C109.OP-10 /
v6 SKP-002).

The classifier is the SOLE canonical Python writer of ``blocker_risk`` for
every ``voices_dropped[]`` entry in a verdict-quality envelope. It is
invoked at envelope-emission time by the producer (cheval.cmd_invoke for
T2.3 PRODUCER #1 per SDD §3.2.3 IMP-004); consumers MUST NOT re-derive
the value (consumer-lint enforcement lands in T2.8 / FR-2.7).

Per SDD §3.2.2 the inputs are three weighted axes summed into a composite
score with documented cutoffs:

  +---------------------------+--------+------------------------------------+
  | Axis                      | Weight | Source                             |
  +---------------------------+--------+------------------------------------+
  | Role of dropped voice     |  0.5   | Cohort metadata (FL voice plan)    |
  | Sprint-kind risk band     |  0.3   | --sprint-kind flag                 |
  | KF priors (voice,kind)    |  0.2   | known-failures.md parser           |
  +---------------------------+--------+------------------------------------+

For v1 of the classifier the KF-priors axis is approximated by the
``reason`` enum — KF-002 / KF-class drop reasons (EmptyContent /
ContextTooLarge) carry the same risk weight that a 1+ recurrence in the
KF parser would produce. Sprint 3+ adds a full known-failures.md parser
that populates kf_priors with per-(voice, sprint_kind) recurrence counts;
the public signature reserves the kwarg today so callers don't break
across the upgrade.

Cutoffs (SDD §3.2.2):
  composite ≥ 0.7          → high
  0.4 ≤ composite < 0.7    → med
  0.1 ≤ composite < 0.4    → low
  composite < 0.1          → unknown (insufficient context)
  no role AND no sprint    → unknown (insufficient priors)

Hard rules (override the composite):
  reason == "ChainExhausted"  →  high   (NFR-Rel-1: a fully-walked chain
                                         that produced no usable result
                                         is by-definition a high-blocker-
                                         risk drop, regardless of context)

The output enum mirrors the verdict-quality.schema.json
``voices_dropped[].blocker_risk`` property:
``{"unknown", "low", "med", "high"}``.

The classifier is pure (no I/O, no global state) and deterministic —
identical inputs MUST produce identical outputs. This contract is
critical for the conformance-test corpus (T2.8) which pins blocker_risk
values per fixture.
"""

from __future__ import annotations

from typing import Any, Dict, Optional


# ---------------------------------------------------------------------------
# Risk levels (mirrors verdict-quality.schema.json voices_dropped[].blocker_risk)
# ---------------------------------------------------------------------------


_LEVEL_UNKNOWN = "unknown"
_LEVEL_LOW = "low"
_LEVEL_MED = "med"
_LEVEL_HIGH = "high"

_VALID_LEVELS = frozenset({_LEVEL_UNKNOWN, _LEVEL_LOW, _LEVEL_MED, _LEVEL_HIGH})


# ---------------------------------------------------------------------------
# Weight tables (SDD §3.2.2 computation table)
# ---------------------------------------------------------------------------


# Axis 1: role of the dropped voice in the adversarial cohort.
# Max weight 0.5; safety roles (review/audit/dissent/arbiter) carry the full
# weight because losing them silently is the canonical NFR-Rel-1 violation
# pattern documented in vision-019 M1 silent-degradation.
_ROLE_WEIGHTS: Dict[str, float] = {
    "review": 0.30,
    "audit": 0.30,
    "dissent": 0.30,
    "arbiter": 0.30,
    "implementation": 0.20,
    # Tier-tagged role variants — same weight as the canonical role.
    "primary": 0.30,
    "secondary": 0.20,
    "tertiary": 0.10,
}
_ROLE_WEIGHT_DEFAULT = 0.10  # caller passed an unrecognized role
_ROLE_WEIGHT_NONE = 0.00     # caller passed no role at all


# Axis 2: sprint-kind risk band per PRD §FR-2.3 / SDD §3.2.2.
# Max weight 0.3; security-touching kinds (implementation / security /
# audit / review / design) carry the higher band, infrastructure and
# operational kinds the middle band, documentation / test kinds the lower.
_SPRINT_WEIGHTS: Dict[str, float] = {
    "implementation": 0.20,
    "security": 0.20,
    "audit": 0.15,
    "review": 0.15,
    "design": 0.15,
    "infra": 0.10,
    "ops": 0.10,
    "test": 0.05,
    "docs": 0.05,
    "glue": 0.05,
}
_SPRINT_WEIGHT_NONE = 0.00   # caller passed no sprint_kind


# Axis 3 (KF-priors proxy): reason enum from
# verdict-quality.schema.json voices_dropped[].reason.
# Max weight 0.2 per SDD; KF-002 class reasons (EmptyContent /
# ContextTooLarge) carry the highest weight because each has a documented
# recurrence ≥ 3 in known-failures.md. ChainExhausted is NOT in this
# table — it short-circuits to "high" before composite calculation.
_REASON_WEIGHTS: Dict[str, float] = {
    "EmptyContent": 0.15,
    "ContextTooLarge": 0.15,
    "ProviderUnavailable": 0.10,
    "RetriesExhausted": 0.10,
    "NoEligibleAdapter": 0.10,
    "RateLimited": 0.05,
    "InteractionPending": 0.00,
    "Other": 0.05,
}
_REASON_WEIGHT_DEFAULT = 0.00  # reason not in the canonical taxonomy


# ---------------------------------------------------------------------------
# Cutoffs (SDD §3.2.2)
# ---------------------------------------------------------------------------

_CUTOFF_HIGH = 0.70
_CUTOFF_MED = 0.40
_CUTOFF_LOW = 0.10


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


def compute_blocker_risk(
    *,
    reason: str,
    voice_role: Optional[str] = None,
    sprint_kind: Optional[str] = None,
    kf_priors: Optional[Dict[str, Any]] = None,
) -> str:
    """Classify a dropped voice's blocker-risk per SDD §3.2.2.

    Args:
      reason: canonical drop-reason enum from verdict-quality.schema.json
        voices_dropped[].reason (e.g., "EmptyContent", "ChainExhausted").
        Required; the only positional axis.
      voice_role: role of the dropped voice in the adversarial cohort
        (e.g., "review", "audit", "implementation"). Optional; when omitted
        the role-weight axis contributes nothing.
      sprint_kind: declared sprint-kind risk band (e.g., "implementation",
        "docs"). Optional; when omitted the sprint-weight axis contributes
        nothing.
      kf_priors: forward-compat hook for the Sprint 3+ known-failures.md
        parser. v1 ignores the value but the signature is stable so
        callers don't break across the upgrade. MUST NOT be mutated.

    Returns:
      One of ``"unknown" | "low" | "med" | "high"``.

    Determinism: identical inputs MUST produce identical outputs. The
    function is pure (no I/O, no global state, no time-dependence).
    """
    # Hard rule: chain-exhausted is always high. NFR-Rel-1 — a fully-walked
    # chain that produced no usable result is by-definition high-blocker
    # regardless of role / sprint / KF priors.
    if reason == "ChainExhausted":
        return _LEVEL_HIGH

    # Insufficient-priors short-circuit: with neither role nor sprint_kind
    # the classifier has no contextual anchor and must return "unknown"
    # per SDD §3.2.2 ("insufficient priors → unknown"). This is the
    # primary defense against silently classifying as "low" when the
    # caller simply hasn't populated context yet.
    if not voice_role and not sprint_kind:
        return _LEVEL_UNKNOWN

    # Compose the score from the three axes.
    role_weight = _resolve_role_weight(voice_role)
    sprint_weight = _SPRINT_WEIGHTS.get(sprint_kind or "", _SPRINT_WEIGHT_NONE)
    reason_weight = _REASON_WEIGHTS.get(reason, _REASON_WEIGHT_DEFAULT)

    composite = role_weight + sprint_weight + reason_weight

    if composite >= _CUTOFF_HIGH:
        return _LEVEL_HIGH
    if composite >= _CUTOFF_MED:
        return _LEVEL_MED
    if composite >= _CUTOFF_LOW:
        return _LEVEL_LOW
    return _LEVEL_UNKNOWN


def _resolve_role_weight(voice_role: Optional[str]) -> float:
    if not voice_role:
        return _ROLE_WEIGHT_NONE
    return _ROLE_WEIGHTS.get(voice_role, _ROLE_WEIGHT_DEFAULT)


# ---------------------------------------------------------------------------
# Public introspection (test-friendly, forward-compat)
# ---------------------------------------------------------------------------


def valid_levels() -> frozenset:
    """Return the canonical set of output values. Mirrors the
    verdict-quality.schema.json ``voices_dropped[].blocker_risk`` enum.
    """
    return _VALID_LEVELS
