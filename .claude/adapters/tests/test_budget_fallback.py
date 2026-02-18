"""Budget + fallback chain integration tests (Sprint 7, Task 7.3).

Tests the interaction between budget enforcement and routing chains.
Individual components are tested separately; these verify the critical
integration path: "What happens when budget-exceeded triggers fallback?"

Bridgebuilder Review Part II: "The conservation invariant is the most
important architectural property — budget+fallback is where it gets
stress-tested in production."
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from loa_cheval.metering.budget import (
    ALLOW,
    BLOCK,
    DOWNGRADE,
    WARN,
    BudgetEnforcer,
    check_budget,
)
from loa_cheval.metering.ledger import record_cost, update_daily_spend
from loa_cheval.routing.chains import walk_downgrade_chain, walk_fallback_chain
from loa_cheval.types import (
    AgentBinding,
    CompletionRequest,
    CompletionResult,
    ProviderUnavailableError,
    ResolvedModel,
    Usage,
)

# ── Shared Config ────────────────────────────────────────────────────────────

CONFIG = {
    "providers": {
        "openai": {
            "type": "openai",
            "models": {
                "gpt-5.2": {
                    "capabilities": ["chat", "tools"],
                    "pricing": {
                        "input_per_mtok": 10_000_000,
                        "output_per_mtok": 30_000_000,
                    },
                },
            },
        },
        "google": {
            "type": "google",
            "models": {
                "gemini-3-pro": {
                    "capabilities": ["chat", "thinking_traces"],
                    "pricing": {
                        "input_per_mtok": 2_500_000,
                        "output_per_mtok": 15_000_000,
                    },
                },
            },
        },
        "anthropic": {
            "type": "anthropic",
            "models": {
                "claude-sonnet-4-6": {
                    "capabilities": ["chat", "tools"],
                    "pricing": {
                        "input_per_mtok": 3_000_000,
                        "output_per_mtok": 15_000_000,
                    },
                },
            },
        },
    },
    "aliases": {
        "reviewer": "openai:gpt-5.2",
        "cheap": "anthropic:claude-sonnet-4-6",
        "deep-thinker": "google:gemini-3-pro",
    },
    "routing": {
        "fallback": {
            "openai": ["cheap"],
            "google": ["reviewer"],
            "anthropic": ["reviewer"],
        },
        "downgrade": {
            "reviewer": ["cheap"],
        },
    },
    "metering": {
        "enabled": True,
        "budget": {
            "daily_micro_usd": 100_000_000,  # $100
            "warn_at_percent": 80,
            "on_exceeded": "downgrade",
        },
    },
}


def _make_request(model="gpt-5.2"):
    return CompletionRequest(
        messages=[{"role": "user", "content": "test"}],
        model=model,
    )


# ── Test Classes ─────────────────────────────────────────────────────────────


class TestDowngradeTriggersFallback:
    """DOWNGRADE status triggers downgrade chain walk."""

    def test_downgrade_walks_chain(self):
        """DOWNGRADE → walk_downgrade_chain → cheaper model."""
        original = ResolvedModel(provider="openai", model_id="gpt-5.2")
        agent = AgentBinding(agent="reviewing-code", model="reviewer", requires={})
        resolved = walk_downgrade_chain(original, agent, CONFIG)
        assert resolved.provider == "anthropic"
        assert resolved.model_id == "claude-sonnet-4-6"

    def test_downgrade_budget_enforcer_returns_downgrade(self, tmp_path):
        """When over budget, pre_call returns DOWNGRADE."""
        ledger_path = str(tmp_path / "ledger.jsonl")
        # Seed daily spend over limit
        update_daily_spend(100_000_001, ledger_path)

        enforcer = BudgetEnforcer(CONFIG, ledger_path)
        result = enforcer.pre_call(_make_request())
        assert result == DOWNGRADE


class TestDowngradeRespectsNativeRuntime:
    """native_runtime agents cannot be downgraded to remote models."""

    def test_native_agent_no_downgrade(self):
        original = ResolvedModel(provider="openai", model_id="gpt-5.2")
        agent = AgentBinding(
            agent="implementing-tasks",
            model="native",
            requires={"native_runtime": True},
        )
        with pytest.raises(ProviderUnavailableError, match="native_runtime"):
            walk_downgrade_chain(original, agent, CONFIG)

    def test_native_agent_no_fallback(self):
        original = ResolvedModel(provider="google", model_id="gemini-3-pro")
        agent = AgentBinding(
            agent="implementing-tasks",
            model="native",
            requires={"native_runtime": True},
        )
        with pytest.raises(ProviderUnavailableError, match="native_runtime"):
            walk_fallback_chain(original, agent, CONFIG)


class TestDowngradeChainWalk:
    """Downgrade from expensive → cheap via configured chain."""

    def test_reviewer_downgrades_to_cheap(self):
        original = ResolvedModel(provider="openai", model_id="gpt-5.2")
        agent = AgentBinding(agent="reviewing-code", model="reviewer", requires={})
        resolved = walk_downgrade_chain(original, agent, CONFIG)
        assert resolved.provider == "anthropic"
        assert resolved.model_id == "claude-sonnet-4-6"

    def test_no_downgrade_chain_for_google(self):
        """Google models have no downgrade chain configured."""
        original = ResolvedModel(provider="google", model_id="gemini-3-pro")
        agent = AgentBinding(agent="deep-thinker", model="deep-thinker", requires={})
        with pytest.raises(ProviderUnavailableError, match="No downgrade chain"):
            walk_downgrade_chain(original, agent, CONFIG)


class TestBlockAction:
    """BLOCK action halts invocation entirely."""

    def test_block_when_on_exceeded_is_block(self, tmp_path):
        ledger_path = str(tmp_path / "ledger.jsonl")
        update_daily_spend(200_000_000, ledger_path)

        cfg = dict(CONFIG)
        cfg = {**CONFIG, "metering": {
            **CONFIG["metering"],
            "budget": {
                "daily_micro_usd": 100_000_000,
                "on_exceeded": "block",
            },
        }}
        enforcer = BudgetEnforcer(cfg, ledger_path)
        result = enforcer.pre_call(_make_request())
        assert result == BLOCK

    def test_atomic_block(self, tmp_path):
        """pre_call_atomic also returns BLOCK when configured."""
        ledger_path = str(tmp_path / "ledger.jsonl")
        update_daily_spend(200_000_000, ledger_path)

        cfg = {**CONFIG, "metering": {
            **CONFIG["metering"],
            "budget": {
                "daily_micro_usd": 100_000_000,
                "on_exceeded": "block",
            },
        }}
        enforcer = BudgetEnforcer(cfg, ledger_path)
        result = enforcer.pre_call_atomic(_make_request())
        assert result == BLOCK


class TestWarnAction:
    """WARN allows invocation but logs."""

    def test_warn_at_threshold(self, tmp_path):
        """Spend at warn_at_percent → WARN."""
        ledger_path = str(tmp_path / "ledger.jsonl")
        # 80% of 100M = 80M
        update_daily_spend(80_000_000, ledger_path)

        enforcer = BudgetEnforcer(CONFIG, ledger_path)
        result = enforcer.pre_call(_make_request())
        assert result == WARN

    def test_warn_on_exceeded_warn(self, tmp_path):
        """on_exceeded: warn → WARN even when over limit."""
        ledger_path = str(tmp_path / "ledger.jsonl")
        update_daily_spend(200_000_000, ledger_path)

        cfg = {**CONFIG, "metering": {
            **CONFIG["metering"],
            "budget": {
                "daily_micro_usd": 100_000_000,
                "on_exceeded": "warn",
            },
        }}
        enforcer = BudgetEnforcer(cfg, ledger_path)
        result = enforcer.pre_call(_make_request())
        assert result == WARN


class TestBudgetUsesConfigValues:
    """Budget check uses daily_micro_usd from config, not hardcoded."""

    def test_custom_limit_respected(self, tmp_path):
        ledger_path = str(tmp_path / "ledger.jsonl")
        update_daily_spend(50_000, ledger_path)  # $0.05

        # Low budget: $0.01
        cfg = {**CONFIG, "metering": {
            "enabled": True,
            "budget": {
                "daily_micro_usd": 10_000,
                "on_exceeded": "block",
            },
        }}
        enforcer = BudgetEnforcer(cfg, ledger_path)
        result = enforcer.pre_call(_make_request())
        assert result == BLOCK

    def test_high_limit_allows(self, tmp_path):
        ledger_path = str(tmp_path / "ledger.jsonl")
        update_daily_spend(50_000, ledger_path)

        # Very high budget: $1000
        cfg = {**CONFIG, "metering": {
            "enabled": True,
            "budget": {
                "daily_micro_usd": 1_000_000_000,
                "on_exceeded": "block",
            },
        }}
        enforcer = BudgetEnforcer(cfg, ledger_path)
        result = enforcer.pre_call(_make_request())
        assert result == ALLOW

    def test_standalone_check_budget(self, tmp_path):
        """check_budget() uses config values."""
        ledger_path = str(tmp_path / "ledger.jsonl")
        update_daily_spend(200_000_000, ledger_path)
        result = check_budget(CONFIG, ledger_path)
        assert result == DOWNGRADE


class TestAtomicPreCallPostCallZeroCost:
    """Sprint 5 fix: atomic pre_call + provider failure → zero cost recorded."""

    def test_post_call_deduplicates_interaction_id(self, tmp_path):
        """Same interaction_id → second post_call is no-op."""
        ledger_path = str(tmp_path / "ledger.jsonl")
        enforcer = BudgetEnforcer(CONFIG, ledger_path)

        result1 = CompletionResult(
            content="ok",
            tool_calls=None,
            thinking=None,
            usage=Usage(input_tokens=100, output_tokens=50),
            model="gpt-5.2",
            latency_ms=100,
            provider="openai",
            interaction_id="dr-123",
        )
        result2 = CompletionResult(
            content="ok again",
            tool_calls=None,
            thinking=None,
            usage=Usage(input_tokens=200, output_tokens=100),
            model="gpt-5.2",
            latency_ms=150,
            provider="openai",
            interaction_id="dr-123",  # Same interaction
        )

        enforcer.post_call(result1)
        enforcer.post_call(result2)

        # Only one entry should be in the ledger
        from loa_cheval.metering.ledger import read_ledger
        entries = read_ledger(ledger_path)
        assert len(entries) == 1

    def test_disabled_metering_post_call_noop(self, tmp_path):
        """post_call is a no-op when metering disabled."""
        ledger_path = str(tmp_path / "ledger.jsonl")
        cfg = {**CONFIG, "metering": {"enabled": False}}
        enforcer = BudgetEnforcer(cfg, ledger_path)

        result = CompletionResult(
            content="ok",
            tool_calls=None,
            thinking=None,
            usage=Usage(input_tokens=100, output_tokens=50),
            model="gpt-5.2",
            latency_ms=100,
            provider="openai",
        )
        enforcer.post_call(result)
        # No ledger file created
        assert not os.path.exists(ledger_path)


class TestFallbackChainCapabilityCheck:
    """Fallback candidates must satisfy agent capabilities."""

    def test_thinking_traces_required_skips_non_capable(self):
        """Agent requires thinking_traces → skip providers without it."""
        original = ResolvedModel(provider="google", model_id="gemini-3-pro")
        agent = AgentBinding(
            agent="deep-thinker",
            model="deep-thinker",
            requires={"thinking_traces": True},
        )
        # openai:gpt-5.2 has capabilities=["chat", "tools"] — no thinking_traces
        with pytest.raises(ProviderUnavailableError, match="exhausted"):
            walk_fallback_chain(original, agent, CONFIG)

    def test_deep_research_required_no_fallback(self):
        """Agent requires deep_research → no fallback candidate has it."""
        original = ResolvedModel(provider="google", model_id="deep-research-pro")
        agent = AgentBinding(
            agent="deep-researcher",
            model="researcher",
            requires={"deep_research": True},
        )
        # deep_research is Google-only capability
        with pytest.raises(ProviderUnavailableError, match="exhausted"):
            walk_fallback_chain(
                original, agent,
                {**CONFIG, "routing": {"fallback": {"google": ["openai", "anthropic"]}}},
            )
