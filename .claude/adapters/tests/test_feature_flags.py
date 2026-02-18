"""Multi-flag feature flag combination tests (Sprint 7, Task 7.2).

Tests config-driven feature toggles in combination. Individual flags are
tested by component tests; these verify the interaction matrix:

- metering.enabled toggles budget enforcement
- Provider presence/absence in config toggles adapter availability
- thinking config (budget/level) toggles thinking traces
- Routing config toggles fallback behavior

Bridgebuilder Review Part I: "Real-world configurations involve multiple
flags simultaneously, and the interaction between flags is untested."
"""

from __future__ import annotations

import copy
import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from loa_cheval.metering.budget import ALLOW, BLOCK, DOWNGRADE, WARN, BudgetEnforcer
from loa_cheval.routing.chains import walk_fallback_chain
from loa_cheval.routing.resolver import resolve_alias, resolve_execution
from loa_cheval.types import (
    AgentBinding,
    CompletionRequest,
    ConfigError,
    NativeRuntimeRequired,
    ProviderUnavailableError,
    ResolvedModel,
)

# ── Base Config Fixture ──────────────────────────────────────────────────────

FULL_CONFIG = {
    "providers": {
        "openai": {
            "type": "openai",
            "endpoint": "https://api.openai.com/v1",
            "auth": "sk-test",
            "models": {
                "gpt-5.2": {
                    "capabilities": ["chat", "tools"],
                    "context_window": 128000,
                    "pricing": {
                        "input_per_mtok": 10_000_000,
                        "output_per_mtok": 30_000_000,
                    },
                },
            },
        },
        "google": {
            "type": "google",
            "endpoint": "https://generativelanguage.googleapis.com/v1beta",
            "auth": "test-key",
            "models": {
                "gemini-3-pro": {
                    "capabilities": ["chat", "thinking_traces"],
                    "context_window": 2097152,
                    "pricing": {
                        "input_per_mtok": 2_500_000,
                        "output_per_mtok": 15_000_000,
                    },
                    "extra": {"thinking_level": "high"},
                },
                "deep-research-pro": {
                    "capabilities": ["chat", "deep_research"],
                    "api_mode": "interactions",
                    "pricing": {
                        "per_task_micro_usd": 50_000_000,
                        "pricing_mode": "task",
                    },
                },
            },
        },
        "anthropic": {
            "type": "anthropic",
            "endpoint": "https://api.anthropic.com/v1",
            "auth": "sk-ant-test",
            "models": {
                "claude-sonnet-4-6": {
                    "capabilities": ["chat", "tools"],
                    "context_window": 200000,
                    "pricing": {
                        "input_per_mtok": 3_000_000,
                        "output_per_mtok": 15_000_000,
                    },
                },
            },
        },
    },
    "aliases": {
        "native": "claude-code:session",
        "reviewer": "openai:gpt-5.2",
        "deep-thinker": "google:gemini-3-pro",
        "researcher": "google:deep-research-pro",
        "cheap": "anthropic:claude-sonnet-4-6",
    },
    "agents": {
        "implementing-tasks": {
            "model": "native",
            "requires": {"native_runtime": True},
        },
        "reviewing-code": {
            "model": "reviewer",
            "temperature": 0.3,
        },
        "deep-thinker": {
            "model": "deep-thinker",
            "requires": {"thinking_traces": True},
        },
        "deep-researcher": {
            "model": "researcher",
            "requires": {"deep_research": True},
        },
    },
    "routing": {
        "fallback": {
            "openai": ["cheap"],
            "google": ["reviewer"],
        },
        "downgrade": {
            "reviewer": ["cheap"],
        },
    },
    "metering": {
        "enabled": True,
        "budget": {
            "daily_micro_usd": 500_000_000,
            "warn_at_percent": 80,
            "on_exceeded": "downgrade",
        },
    },
}


def _config(**overrides):
    """Deep-copy base config with overrides applied at top level."""
    cfg = copy.deepcopy(FULL_CONFIG)
    for key, value in overrides.items():
        if isinstance(value, dict) and isinstance(cfg.get(key), dict):
            cfg[key].update(value)
        else:
            cfg[key] = value
    return cfg


# ── Test Classes ─────────────────────────────────────────────────────────────


class TestAllFlagsEnabled:
    """Default config: all providers + metering + thinking enabled."""

    def test_reviewer_resolves_to_openai(self):
        binding, resolved = resolve_execution("reviewing-code", FULL_CONFIG)
        assert resolved.provider == "openai"
        assert resolved.model_id == "gpt-5.2"

    def test_deep_thinker_resolves_to_google(self):
        binding, resolved = resolve_execution("deep-thinker", FULL_CONFIG)
        assert resolved.provider == "google"
        assert resolved.model_id == "gemini-3-pro"

    def test_native_resolves_to_claude_code(self):
        binding, resolved = resolve_execution("implementing-tasks", FULL_CONFIG)
        assert resolved.provider == "claude-code"
        assert resolved.model_id == "session"

    def test_budget_enforcer_enabled(self, tmp_path):
        enforcer = BudgetEnforcer(FULL_CONFIG, str(tmp_path / "ledger.jsonl"))
        request = CompletionRequest(
            messages=[{"role": "user", "content": "test"}],
            model="gpt-5.2",
        )
        assert enforcer.pre_call(request) == ALLOW


class TestGoogleDisabledDeepResearchEnabled:
    """google_adapter disabled but deep_research config still present.

    When google provider is removed from config, deep-research agents
    can't resolve their alias and should fail with ConfigError.
    """

    def test_deep_researcher_alias_fails(self):
        cfg = _config()
        del cfg["providers"]["google"]
        # researcher alias still points to google:deep-research-pro
        # but validate_bindings should flag the missing provider
        resolved = resolve_alias("researcher", cfg["aliases"])
        assert resolved.provider == "google"
        # The provider is gone — validate_bindings would catch this
        from loa_cheval.routing.resolver import validate_bindings
        errors = validate_bindings(cfg)
        assert any("google" in e for e in errors)

    def test_deep_thinker_alias_still_resolves(self):
        """Alias resolution doesn't check provider existence — only validation does."""
        cfg = _config()
        del cfg["providers"]["google"]
        resolved = resolve_alias("deep-thinker", cfg["aliases"])
        assert resolved.provider == "google"

    def test_fallback_google_to_openai(self):
        """When Google is down, fallback chain routes to OpenAI."""
        cfg = _config()
        original = ResolvedModel(provider="google", model_id="gemini-3-pro")
        agent = AgentBinding(agent="deep-thinker", model="deep-thinker", requires={})
        resolved = walk_fallback_chain(original, agent, cfg)
        assert resolved.provider == "openai"
        assert resolved.model_id == "gpt-5.2"


class TestMeteringDisabledAdaptersEnabled:
    """Metering disabled, all adapters available."""

    def test_budget_always_allows(self, tmp_path):
        cfg = _config(metering={"enabled": False})
        enforcer = BudgetEnforcer(cfg, str(tmp_path / "ledger.jsonl"))
        request = CompletionRequest(
            messages=[{"role": "user", "content": "test"}],
            model="gpt-5.2",
        )
        assert enforcer.pre_call(request) == ALLOW

    def test_budget_atomic_always_allows(self, tmp_path):
        cfg = _config(metering={"enabled": False})
        enforcer = BudgetEnforcer(cfg, str(tmp_path / "ledger.jsonl"))
        request = CompletionRequest(
            messages=[{"role": "user", "content": "test"}],
            model="gpt-5.2",
        )
        assert enforcer.pre_call_atomic(request, reservation_micro=100_000) == ALLOW

    def test_post_call_is_noop(self, tmp_path):
        """Disabled metering skips post_call recording."""
        cfg = _config(metering={"enabled": False})
        enforcer = BudgetEnforcer(cfg, str(tmp_path / "ledger.jsonl"))
        result = MagicMock()
        result.usage = MagicMock()
        result.usage.input_tokens = 100
        result.usage.output_tokens = 50
        result.usage.reasoning_tokens = 0
        result.usage.source = "actual"
        result.latency_ms = 100
        result.provider = "openai"
        result.model = "gpt-5.2"
        result.interaction_id = None
        # Should not raise even with no ledger file
        enforcer.post_call(result)

    def test_routing_still_works(self):
        """Routing operates independently of metering."""
        cfg = _config(metering={"enabled": False})
        binding, resolved = resolve_execution("reviewing-code", cfg)
        assert resolved.provider == "openai"


class TestThinkingDisabled:
    """Thinking traces disabled via config (budget=0)."""

    def test_thinking_budget_zero_returns_none(self):
        """When thinking_budget=0, _build_thinking_config returns None."""
        from loa_cheval.providers.google_adapter import _build_thinking_config
        from loa_cheval.types import ModelConfig

        config = ModelConfig(
            capabilities=["chat", "thinking_traces"],
            extra={"thinking_budget": 0},
        )
        result = _build_thinking_config("gemini-2.5-pro", config)
        assert result is None

    def test_no_extra_disables_for_non_gemini(self):
        from loa_cheval.providers.google_adapter import _build_thinking_config
        from loa_cheval.types import ModelConfig

        config = ModelConfig(capabilities=["chat"], extra=None)
        result = _build_thinking_config("gpt-5.2", config)
        assert result is None


class TestFlatlineRoutingWithoutGoogle:
    """Flatline routing enabled but Google adapter removed."""

    def test_fallback_chain_exhausted_for_native_agent(self):
        """native_runtime agent can't fall back to any remote model."""
        cfg = _config()
        original = ResolvedModel(provider="google", model_id="gemini-3-pro")
        agent = AgentBinding(
            agent="implementing-tasks",
            model="native",
            requires={"native_runtime": True},
        )
        with pytest.raises(ProviderUnavailableError, match="native_runtime"):
            walk_fallback_chain(original, agent, cfg)

    def test_fallback_chain_skips_unhealthy(self):
        """Health check callback prevents routing to unhealthy provider."""
        cfg = _config()
        original = ResolvedModel(provider="google", model_id="gemini-3-pro")
        agent = AgentBinding(agent="reviewing-code", model="reviewer", requires={})
        with pytest.raises(ProviderUnavailableError, match="exhausted"):
            walk_fallback_chain(
                original, agent, cfg,
                is_provider_healthy=lambda p: False,  # All unhealthy
            )


class TestAllFlagsDisabled:
    """All external providers removed, metering disabled."""

    def test_only_native_agents_resolve(self):
        cfg = _config(metering={"enabled": False})
        cfg["providers"] = {}  # No external providers
        binding, resolved = resolve_execution("implementing-tasks", cfg)
        assert resolved.provider == "claude-code"

    def test_non_native_agent_validation_fails(self):
        cfg = _config()
        cfg["providers"] = {}
        from loa_cheval.routing.resolver import validate_bindings
        errors = validate_bindings(cfg)
        # reviewing-code points to reviewer alias → openai:gpt-5.2 → missing provider
        assert any("openai" in e for e in errors)


class TestFlagPrecedence:
    """Config values can be overridden at multiple layers."""

    def test_budget_config_overrides_default(self, tmp_path):
        """Custom budget limit from config is respected."""
        cfg = _config(metering={
            "enabled": True,
            "budget": {
                "daily_micro_usd": 1_000,  # Very low: $0.001
                "warn_at_percent": 80,
                "on_exceeded": "block",
            },
        })
        enforcer = BudgetEnforcer(cfg, str(tmp_path / "ledger.jsonl"))
        request = CompletionRequest(
            messages=[{"role": "user", "content": "test"}],
            model="gpt-5.2",
        )
        # Fresh start, under budget
        assert enforcer.pre_call(request) == ALLOW

    def test_on_exceeded_block_vs_downgrade(self, tmp_path):
        """on_exceeded config controls response type."""
        for action, expected in [("block", BLOCK), ("downgrade", DOWNGRADE), ("warn", WARN)]:
            cfg = _config(metering={
                "enabled": True,
                "budget": {
                    "daily_micro_usd": 0,  # Already exceeded
                    "on_exceeded": action,
                },
            })
            enforcer = BudgetEnforcer(cfg, str(tmp_path / f"ledger-{action}.jsonl"))
            request = CompletionRequest(
                messages=[{"role": "user", "content": "test"}],
                model="gpt-5.2",
            )
            assert enforcer.pre_call(request) == expected, f"Expected {expected} for on_exceeded={action}"
