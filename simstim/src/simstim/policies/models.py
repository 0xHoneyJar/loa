"""Policy models for Simstim.

Data structures for policy evaluation results and matching.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timezone
from enum import Enum
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from simstim.config import Policy


class PolicyDecision(Enum):
    """Decision from policy evaluation."""

    AUTO_APPROVE = "auto_approve"
    AUTO_DENY = "auto_deny"
    REQUIRE_MANUAL = "require_manual"


@dataclass
class PolicyMatch:
    """Result of policy matching."""

    matched: bool
    policy: Policy | None = None
    decision: PolicyDecision = PolicyDecision.REQUIRE_MANUAL
    reason: str = ""

    @classmethod
    def no_match(cls, reason: str = "No matching policy") -> PolicyMatch:
        """Create a no-match result."""
        return cls(
            matched=False,
            policy=None,
            decision=PolicyDecision.REQUIRE_MANUAL,
            reason=reason,
        )

    @classmethod
    def auto_approved(cls, policy: Policy, reason: str) -> PolicyMatch:
        """Create an auto-approve result."""
        return cls(
            matched=True,
            policy=policy,
            decision=PolicyDecision.AUTO_APPROVE,
            reason=reason,
        )

    @classmethod
    def risk_exceeded(cls, policy: Policy, reason: str) -> PolicyMatch:
        """Create a risk-exceeded result (policy matched but risk too high)."""
        return cls(
            matched=False,
            policy=policy,
            decision=PolicyDecision.REQUIRE_MANUAL,
            reason=reason,
        )


@dataclass
class PolicyEvaluationResult:
    """Complete result of policy evaluation including audit info."""

    match: PolicyMatch
    evaluated_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    policies_checked: int = 0
    action: str = ""
    target: str = ""
    risk_level: str = ""

    def to_audit_dict(self) -> dict:
        """Convert to dictionary for audit logging."""
        return {
            "timestamp": self.evaluated_at.isoformat(),
            "event": "policy_evaluation",
            "action": self.action,
            "target": self.target,
            "risk": self.risk_level,
            "matched": self.match.matched,
            "decision": self.match.decision.value,
            "policy": self.match.policy.name if self.match.policy else None,
            "reason": self.match.reason,
            "policies_checked": self.policies_checked,
        }
