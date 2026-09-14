"""Budget enforcement contracts. Live routing assertions are in test_live_chain_contracts.py.

DOWNGRADE is a signal only; its actuator remains deferred under #1001.
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

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
from loa_cheval.types import (
    CompletionRequest,
    CompletionResult,
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


class TestDowngradeSignal:
    """The budget meter reports pressure; it does not change the model."""


    def test_downgrade_budget_enforcer_returns_downgrade(self, tmp_path):
        """When over budget, pre_call returns DOWNGRADE."""
        ledger_path = str(tmp_path / "ledger.jsonl")
        # Seed daily spend over limit
        update_daily_spend(100_000_001, ledger_path)

        enforcer = BudgetEnforcer(CONFIG, ledger_path)
        result = enforcer.pre_call(_make_request())
        assert result == DOWNGRADE


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
