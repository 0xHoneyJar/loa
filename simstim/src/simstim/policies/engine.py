"""Policy engine for Simstim (ICE).

Evaluates permission requests against configured policies
for auto-approve/deny decisions.
"""

from __future__ import annotations

import logging
from fnmatch import fnmatch
from typing import TYPE_CHECKING

from simstim.policies.models import PolicyMatch, PolicyEvaluationResult

if TYPE_CHECKING:
    from simstim.bridge.stdout_parser import ActionType, RiskLevel
    from simstim.config import Policy


logger = logging.getLogger(__name__)

# Risk level ordering (lower index = lower risk)
RISK_ORDER = ["low", "medium", "high", "critical"]


class PolicyEngine:
    """Auto-approve policy engine (ICE).

    Evaluates permission requests against a list of configured
    policies to determine if they can be auto-approved.
    """

    def __init__(self, policies: list[Policy]) -> None:
        """Initialize policy engine.

        Args:
            policies: List of policies to evaluate against
        """
        # Only keep enabled policies
        self._policies = [p for p in policies if p.enabled]
        self._evaluation_count = 0

        logger.info(
            "Policy engine initialized",
            extra={"active_policies": len(self._policies)},
        )

    def evaluate(
        self,
        action: ActionType,
        target: str,
        risk: RiskLevel,
    ) -> PolicyEvaluationResult:
        """Evaluate request against policies.

        Args:
            action: Type of action being requested
            target: Target file path or command
            risk: Risk level of the action

        Returns:
            Evaluation result with match details
        """
        self._evaluation_count += 1
        action_str = action.value
        risk_str = risk.value

        # Find matching policy
        for policy in self._policies:
            # Check action type matches
            if policy.action != action_str:
                continue

            # Check pattern matches target
            if not self._pattern_matches(policy.pattern, target):
                continue

            # Check risk level
            if not self._risk_acceptable(policy.max_risk, risk_str):
                match = PolicyMatch.risk_exceeded(
                    policy=policy,
                    reason=f"Risk {risk_str} exceeds policy max {policy.max_risk}",
                )
                return PolicyEvaluationResult(
                    match=match,
                    policies_checked=self._evaluation_count,
                    action=action_str,
                    target=target,
                    risk_level=risk_str,
                )

            # All checks passed - auto-approve
            match = PolicyMatch.auto_approved(
                policy=policy,
                reason=f"Matched policy: {policy.name}",
            )

            logger.info(
                "Policy matched - auto-approve",
                extra={
                    "policy": policy.name,
                    "action": action_str,
                    "target": target,
                    "risk": risk_str,
                },
            )

            return PolicyEvaluationResult(
                match=match,
                policies_checked=self._evaluation_count,
                action=action_str,
                target=target,
                risk_level=risk_str,
            )

        # No matching policy
        return PolicyEvaluationResult(
            match=PolicyMatch.no_match(),
            policies_checked=self._evaluation_count,
            action=action_str,
            target=target,
            risk_level=risk_str,
        )

    def _pattern_matches(self, pattern: str, target: str) -> bool:
        """Check if pattern matches target.

        Args:
            pattern: Glob pattern (supports * and **)
            target: Target string to match

        Returns:
            True if pattern matches target
        """
        # Handle brace expansion like *.{ts,tsx,js,jsx}
        if "{" in pattern and "}" in pattern:
            # Extract brace content
            start = pattern.index("{")
            end = pattern.index("}")
            prefix = pattern[:start]
            suffix = pattern[end + 1:]
            alternatives = pattern[start + 1:end].split(",")

            # Check each alternative
            return any(
                fnmatch(target, f"{prefix}{alt.strip()}{suffix}")
                for alt in alternatives
            )

        return fnmatch(target, pattern)

    def _risk_acceptable(self, max_risk: str, actual_risk: str) -> bool:
        """Check if actual risk is within acceptable range.

        Args:
            max_risk: Maximum allowed risk level
            actual_risk: Actual risk level of request

        Returns:
            True if actual risk <= max risk
        """
        try:
            max_idx = RISK_ORDER.index(max_risk.lower())
            actual_idx = RISK_ORDER.index(actual_risk.lower())
            return actual_idx <= max_idx
        except ValueError:
            # Unknown risk level - don't auto-approve
            return False

    def add_policy(self, policy: Policy) -> None:
        """Add a policy at runtime.

        Args:
            policy: Policy to add
        """
        if policy.enabled:
            self._policies.append(policy)
            logger.info("Policy added", extra={"policy": policy.name})

    def remove_policy(self, name: str) -> bool:
        """Remove a policy by name.

        Args:
            name: Name of policy to remove

        Returns:
            True if policy was removed
        """
        for i, p in enumerate(self._policies):
            if p.name == name:
                self._policies.pop(i)
                logger.info("Policy removed", extra={"policy": name})
                return True
        return False

    def get_policy(self, name: str) -> Policy | None:
        """Get a policy by name.

        Args:
            name: Policy name

        Returns:
            Policy if found, None otherwise
        """
        for p in self._policies:
            if p.name == name:
                return p
        return None

    def list_policies(self) -> list[Policy]:
        """Get all active policies.

        Returns:
            List of active policies
        """
        return list(self._policies)

    @property
    def policy_count(self) -> int:
        """Number of active policies."""
        return len(self._policies)

    @property
    def evaluation_count(self) -> int:
        """Total number of evaluations performed."""
        return self._evaluation_count
