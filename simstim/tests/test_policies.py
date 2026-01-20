"""Unit tests for policy engine (ICE)."""

from __future__ import annotations

import pytest
from unittest.mock import MagicMock

from simstim.policies.engine import PolicyEngine, RISK_ORDER
from simstim.policies.models import PolicyMatch, PolicyDecision, PolicyEvaluationResult
from simstim.bridge.stdout_parser import ActionType, RiskLevel


class MockPolicy:
    """Mock policy for testing."""

    def __init__(
        self,
        name: str = "test-policy",
        action: str = "bash_execute",
        pattern: str = "*.sh",
        max_risk: str = "medium",
        enabled: bool = True,
    ):
        self.name = name
        self.action = action
        self.pattern = pattern
        self.max_risk = max_risk
        self.enabled = enabled


class TestPolicyEngine:
    """Tests for PolicyEngine class."""

    def test_init_filters_disabled_policies(self):
        """Should only include enabled policies."""
        policies = [
            MockPolicy(name="enabled", enabled=True),
            MockPolicy(name="disabled", enabled=False),
            MockPolicy(name="also-enabled", enabled=True),
        ]
        engine = PolicyEngine(policies)
        assert engine.policy_count == 2

    def test_init_empty_policies(self):
        """Should handle empty policy list."""
        engine = PolicyEngine([])
        assert engine.policy_count == 0

    def test_evaluate_auto_approve_simple_match(self):
        """Should auto-approve when action, pattern, and risk all match."""
        policy = MockPolicy(
            name="allow-shell-scripts",
            action="bash_execute",
            pattern="*.sh",
            max_risk="high",
        )
        engine = PolicyEngine([policy])

        result = engine.evaluate(
            action=ActionType.BASH_EXECUTE,
            target="deploy.sh",
            risk=RiskLevel.LOW,
        )

        assert result.match.matched is True
        assert result.match.decision == PolicyDecision.AUTO_APPROVE
        assert result.match.policy.name == "allow-shell-scripts"

    def test_evaluate_no_match_wrong_action(self):
        """Should not match when action type differs."""
        policy = MockPolicy(
            action="file_create",
            pattern="*",
        )
        engine = PolicyEngine([policy])

        result = engine.evaluate(
            action=ActionType.BASH_EXECUTE,
            target="deploy.sh",
            risk=RiskLevel.LOW,
        )

        assert result.match.matched is False
        assert result.match.decision == PolicyDecision.REQUIRE_MANUAL

    def test_evaluate_no_match_wrong_pattern(self):
        """Should not match when target doesn't match pattern."""
        policy = MockPolicy(
            action="bash_execute",
            pattern="*.py",
        )
        engine = PolicyEngine([policy])

        result = engine.evaluate(
            action=ActionType.BASH_EXECUTE,
            target="deploy.sh",
            risk=RiskLevel.LOW,
        )

        assert result.match.matched is False
        assert result.match.decision == PolicyDecision.REQUIRE_MANUAL

    def test_evaluate_risk_exceeded(self):
        """Should not match when risk exceeds policy maximum."""
        policy = MockPolicy(
            action="bash_execute",
            pattern="*.sh",
            max_risk="low",
        )
        engine = PolicyEngine([policy])

        result = engine.evaluate(
            action=ActionType.BASH_EXECUTE,
            target="deploy.sh",
            risk=RiskLevel.HIGH,
        )

        assert result.match.matched is False
        assert result.match.decision == PolicyDecision.REQUIRE_MANUAL
        assert "exceeds" in result.match.reason.lower()

    def test_evaluate_glob_star_pattern(self):
        """Should match single-star glob patterns."""
        policy = MockPolicy(
            action="file_edit",
            pattern="src/*.ts",
            max_risk="medium",
        )
        engine = PolicyEngine([policy])

        # Should match
        result = engine.evaluate(
            action=ActionType.FILE_EDIT,
            target="src/index.ts",
            risk=RiskLevel.LOW,
        )
        assert result.match.matched is True

        # Should not match nested
        result = engine.evaluate(
            action=ActionType.FILE_EDIT,
            target="src/components/Button.ts",
            risk=RiskLevel.LOW,
        )
        assert result.match.matched is False

    def test_evaluate_glob_double_star_pattern(self):
        """Should match double-star glob patterns."""
        policy = MockPolicy(
            action="file_edit",
            pattern="src/**/*.ts",
            max_risk="medium",
        )
        engine = PolicyEngine([policy])

        # Should match nested
        result = engine.evaluate(
            action=ActionType.FILE_EDIT,
            target="src/components/Button.ts",
            risk=RiskLevel.LOW,
        )
        assert result.match.matched is True

    def test_evaluate_brace_expansion(self):
        """Should handle brace expansion patterns."""
        policy = MockPolicy(
            action="file_edit",
            pattern="*.{ts,tsx,js,jsx}",
            max_risk="medium",
        )
        engine = PolicyEngine([policy])

        # Should match .ts
        result = engine.evaluate(
            action=ActionType.FILE_EDIT,
            target="index.ts",
            risk=RiskLevel.LOW,
        )
        assert result.match.matched is True

        # Should match .tsx
        result = engine.evaluate(
            action=ActionType.FILE_EDIT,
            target="Component.tsx",
            risk=RiskLevel.LOW,
        )
        assert result.match.matched is True

        # Should not match .py
        result = engine.evaluate(
            action=ActionType.FILE_EDIT,
            target="script.py",
            risk=RiskLevel.LOW,
        )
        assert result.match.matched is False

    def test_evaluate_first_match_wins(self):
        """Should return first matching policy."""
        policies = [
            MockPolicy(name="first", action="bash_execute", pattern="*.sh"),
            MockPolicy(name="second", action="bash_execute", pattern="*"),
        ]
        engine = PolicyEngine(policies)

        result = engine.evaluate(
            action=ActionType.BASH_EXECUTE,
            target="test.sh",
            risk=RiskLevel.LOW,
        )

        assert result.match.policy.name == "first"

    def test_evaluation_count_increments(self):
        """Should track total evaluations."""
        engine = PolicyEngine([MockPolicy()])

        assert engine.evaluation_count == 0

        engine.evaluate(ActionType.BASH_EXECUTE, "test.sh", RiskLevel.LOW)
        assert engine.evaluation_count == 1

        engine.evaluate(ActionType.BASH_EXECUTE, "test.sh", RiskLevel.LOW)
        assert engine.evaluation_count == 2


class TestPolicyEngineRiskLevels:
    """Tests for risk level comparison."""

    def test_risk_order(self):
        """Should have correct risk ordering."""
        assert RISK_ORDER.index("low") < RISK_ORDER.index("medium")
        assert RISK_ORDER.index("medium") < RISK_ORDER.index("high")
        assert RISK_ORDER.index("high") < RISK_ORDER.index("critical")

    def test_risk_acceptable_same_level(self):
        """Same risk level should be acceptable."""
        policy = MockPolicy(max_risk="medium")
        engine = PolicyEngine([policy])

        # Access private method for direct testing
        assert engine._risk_acceptable("medium", "medium") is True

    def test_risk_acceptable_lower_actual(self):
        """Lower actual risk should be acceptable."""
        engine = PolicyEngine([])
        assert engine._risk_acceptable("high", "low") is True
        assert engine._risk_acceptable("high", "medium") is True

    def test_risk_not_acceptable_higher_actual(self):
        """Higher actual risk should not be acceptable."""
        engine = PolicyEngine([])
        assert engine._risk_acceptable("low", "medium") is False
        assert engine._risk_acceptable("low", "high") is False

    def test_risk_unknown_level_rejected(self):
        """Unknown risk levels should be rejected."""
        engine = PolicyEngine([])
        assert engine._risk_acceptable("low", "unknown") is False
        assert engine._risk_acceptable("unknown", "low") is False


class TestPolicyEngineManagement:
    """Tests for runtime policy management."""

    def test_add_policy(self):
        """Should add enabled policy."""
        engine = PolicyEngine([])
        assert engine.policy_count == 0

        policy = MockPolicy(enabled=True)
        engine.add_policy(policy)
        assert engine.policy_count == 1

    def test_add_disabled_policy_ignored(self):
        """Should not add disabled policy."""
        engine = PolicyEngine([])
        policy = MockPolicy(enabled=False)
        engine.add_policy(policy)
        assert engine.policy_count == 0

    def test_remove_policy(self):
        """Should remove policy by name."""
        policy = MockPolicy(name="to-remove")
        engine = PolicyEngine([policy])

        assert engine.remove_policy("to-remove") is True
        assert engine.policy_count == 0

    def test_remove_nonexistent_policy(self):
        """Should return False for nonexistent policy."""
        engine = PolicyEngine([])
        assert engine.remove_policy("nonexistent") is False

    def test_get_policy(self):
        """Should return policy by name."""
        policy = MockPolicy(name="target-policy")
        engine = PolicyEngine([policy])

        found = engine.get_policy("target-policy")
        assert found is not None
        assert found.name == "target-policy"

    def test_get_policy_not_found(self):
        """Should return None for missing policy."""
        engine = PolicyEngine([])
        assert engine.get_policy("nonexistent") is None

    def test_list_policies(self):
        """Should return all active policies."""
        policies = [
            MockPolicy(name="p1"),
            MockPolicy(name="p2"),
        ]
        engine = PolicyEngine(policies)

        listed = engine.list_policies()
        assert len(listed) == 2
        assert listed[0].name == "p1"
        assert listed[1].name == "p2"


class TestPolicyMatch:
    """Tests for PolicyMatch dataclass."""

    def test_no_match_factory(self):
        """Should create no-match result."""
        match = PolicyMatch.no_match()
        assert match.matched is False
        assert match.policy is None
        assert match.decision == PolicyDecision.REQUIRE_MANUAL

    def test_no_match_custom_reason(self):
        """Should accept custom reason."""
        match = PolicyMatch.no_match("Custom reason")
        assert match.reason == "Custom reason"

    def test_auto_approved_factory(self):
        """Should create auto-approved result."""
        policy = MockPolicy(name="test")
        match = PolicyMatch.auto_approved(policy, "Matched pattern")

        assert match.matched is True
        assert match.policy == policy
        assert match.decision == PolicyDecision.AUTO_APPROVE
        assert "Matched" in match.reason

    def test_risk_exceeded_factory(self):
        """Should create risk-exceeded result."""
        policy = MockPolicy(name="test")
        match = PolicyMatch.risk_exceeded(policy, "Risk too high")

        assert match.matched is False
        assert match.policy == policy
        assert match.decision == PolicyDecision.REQUIRE_MANUAL
        assert "Risk" in match.reason


class TestPolicyEvaluationResult:
    """Tests for PolicyEvaluationResult dataclass."""

    def test_to_audit_dict(self):
        """Should convert to audit-friendly dict."""
        policy = MockPolicy(name="audit-policy")
        match = PolicyMatch.auto_approved(policy, "Matched")
        result = PolicyEvaluationResult(
            match=match,
            policies_checked=5,
            action="bash_execute",
            target="test.sh",
            risk_level="low",
        )

        audit = result.to_audit_dict()

        assert audit["event"] == "policy_evaluation"
        assert audit["action"] == "bash_execute"
        assert audit["target"] == "test.sh"
        assert audit["risk"] == "low"
        assert audit["matched"] is True
        assert audit["decision"] == "auto_approve"
        assert audit["policy"] == "audit-policy"
        assert audit["policies_checked"] == 5
        assert "timestamp" in audit

    def test_to_audit_dict_no_policy(self):
        """Should handle None policy in audit dict."""
        match = PolicyMatch.no_match()
        result = PolicyEvaluationResult(
            match=match,
            action="bash_execute",
            target="test.sh",
            risk_level="low",
        )

        audit = result.to_audit_dict()
        assert audit["policy"] is None
