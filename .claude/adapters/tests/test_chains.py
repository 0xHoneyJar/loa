"""Tests for routing chains — fallback, downgrade, cycle detection (Sprint 3)."""

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from loa_cheval.routing.chains import (
    validate_chains,
    walk_downgrade_chain,
    walk_fallback_chain,
)
from loa_cheval.types import AgentBinding, ProviderUnavailableError, ResolvedModel


# ── Test Config ───────────────────────────────────────────────────────────────

ROUTING_CONFIG = {
    "providers": {
        "openai": {
            "type": "openai",
            "models": {
                "gpt-5.2": {
                    "capabilities": ["chat", "tools", "function_calling"],
                },
                "gpt-5.2-codex": {
                    "capabilities": ["chat", "tools", "function_calling", "code"],
                },
            },
        },
        "anthropic": {
            "type": "anthropic",
            "models": {
                "claude-opus-4-6": {
                    "capabilities": ["chat", "tools", "function_calling", "thinking_traces"],
                },
                "claude-sonnet-4-6": {
                    "capabilities": ["chat", "tools", "function_calling"],
                },
            },
        },
    },
    "aliases": {
        "native": "claude-code:session",
        "reviewer": "openai:gpt-5.2",
        "reasoning": "openai:gpt-5.2",
        "cheap": "anthropic:claude-sonnet-4-6",
        "opus": "anthropic:claude-opus-4-6",
    },
    "routing": {
        "fallback": {
            "openai": ["opus"],
            "anthropic": ["reviewer"],
        },
        "downgrade": {
            "reviewer": ["cheap"],
        },
    },
}


def _agent(name="test-agent", model="reviewer", requires=None):
    return AgentBinding(
        agent=name,
        model=model,
        requires=requires or {},
    )


# ── Fallback Chain Tests ─────────────────────────────────────────────────────


class TestWalkFallbackChain:
    """Fallback chain walker tests."""

    def test_basic_fallback(self):
        """OpenAI fails → falls back to Anthropic (opus)."""
        original = ResolvedModel(provider="openai", model_id="gpt-5.2")
        result = walk_fallback_chain(
            original, _agent(), ROUTING_CONFIG
        )
        assert result.provider == "anthropic"
        assert result.model_id == "claude-opus-4-6"

    def test_reverse_fallback(self):
        """Anthropic fails → falls back to OpenAI (reviewer)."""
        original = ResolvedModel(provider="anthropic", model_id="claude-opus-4-6")
        result = walk_fallback_chain(
            original, _agent(), ROUTING_CONFIG
        )
        assert result.provider == "openai"
        assert result.model_id == "gpt-5.2"

    def test_fallback_with_health_check(self):
        """Fallback skips unhealthy providers."""
        original = ResolvedModel(provider="openai", model_id="gpt-5.2")

        def is_healthy(provider):
            return provider != "anthropic"

        with pytest.raises(ProviderUnavailableError):
            walk_fallback_chain(
                original, _agent(), ROUTING_CONFIG,
                is_provider_healthy=is_healthy,
            )

    def test_fallback_healthy_provider_resolves(self):
        """Fallback finds healthy provider."""
        original = ResolvedModel(provider="openai", model_id="gpt-5.2")

        result = walk_fallback_chain(
            original, _agent(), ROUTING_CONFIG,
            is_provider_healthy=lambda p: True,
        )
        assert result.provider == "anthropic"

    def test_no_fallback_chain(self):
        """Missing fallback chain raises error."""
        config = {**ROUTING_CONFIG, "routing": {"fallback": {}, "downgrade": {}}}
        original = ResolvedModel(provider="openai", model_id="gpt-5.2")

        with pytest.raises(ProviderUnavailableError, match="No fallback chain"):
            walk_fallback_chain(original, _agent(), config)

    def test_cycle_prevention(self):
        """Visited models are skipped."""
        original = ResolvedModel(provider="openai", model_id="gpt-5.2")
        visited = {"anthropic:claude-opus-4-6"}

        with pytest.raises(ProviderUnavailableError):
            walk_fallback_chain(
                original, _agent(), ROUTING_CONFIG,
                visited=visited,
            )

    def test_capability_filtering(self):
        """Fallback skips candidates missing required capabilities."""
        original = ResolvedModel(provider="openai", model_id="gpt-5.2")

        # Require thinking_traces — cheap doesn't have it
        config = {
            **ROUTING_CONFIG,
            "routing": {
                "fallback": {"openai": ["cheap"]},
                "downgrade": {},
            },
        }
        agent = _agent(requires={"thinking_traces": True})

        with pytest.raises(ProviderUnavailableError):
            walk_fallback_chain(original, agent, config)

    def test_native_runtime_blocks_fallback(self):
        """Agents requiring native_runtime can't fall back to remote."""
        original = ResolvedModel(provider="openai", model_id="gpt-5.2")
        agent = _agent(requires={"native_runtime": True})

        with pytest.raises(ProviderUnavailableError):
            walk_fallback_chain(original, agent, ROUTING_CONFIG)


# ── Downgrade Chain Tests ────────────────────────────────────────────────────


class TestWalkDowngradeChain:
    """Downgrade chain walker tests."""

    def test_basic_downgrade(self):
        """Reviewer downgrades to cheap."""
        original = ResolvedModel(provider="openai", model_id="gpt-5.2")
        result = walk_downgrade_chain(
            original, _agent(), ROUTING_CONFIG
        )
        assert result.provider == "anthropic"
        assert result.model_id == "claude-sonnet-4-6"

    def test_no_downgrade_chain(self):
        """No downgrade chain for this model."""
        original = ResolvedModel(provider="anthropic", model_id="claude-opus-4-6")
        with pytest.raises(ProviderUnavailableError, match="No downgrade chain"):
            walk_downgrade_chain(original, _agent(), ROUTING_CONFIG)

    def test_downgrade_cycle_prevention(self):
        """Pre-visited candidates are skipped."""
        original = ResolvedModel(provider="openai", model_id="gpt-5.2")
        visited = {"anthropic:claude-sonnet-4-6"}

        with pytest.raises(ProviderUnavailableError):
            walk_downgrade_chain(
                original, _agent(), ROUTING_CONFIG,
                visited=visited,
            )


# ── Chain Validation Tests ───────────────────────────────────────────────────


class TestValidateChains:
    """Config validation for routing chains."""

    def test_valid_config(self):
        errors = validate_chains(ROUTING_CONFIG)
        assert errors == []

    def test_unresolvable_alias(self):
        config = {
            **ROUTING_CONFIG,
            "routing": {
                "fallback": {"openai": ["nonexistent_alias"]},
                "downgrade": {},
            },
        }
        errors = validate_chains(config)
        assert len(errors) == 1
        assert "cannot resolve" in errors[0]

    def test_cycle_detection(self):
        """Duplicate targets in chain detected."""
        config = {
            **ROUTING_CONFIG,
            "routing": {
                "fallback": {"openai": ["opus", "opus"]},
                "downgrade": {},
            },
        }
        errors = validate_chains(config)
        assert len(errors) == 1
        assert "cycle" in errors[0]

    def test_empty_chains_valid(self):
        config = {
            **ROUTING_CONFIG,
            "routing": {"fallback": {}, "downgrade": {}},
        }
        errors = validate_chains(config)
        assert errors == []


# ── Combined Scenario Tests ──────────────────────────────────────────────────


class TestCombinedScenarios:
    """Multi-step routing scenarios."""

    def test_budget_then_fallback(self):
        """Budget downgrade, then provider falls back."""
        # Step 1: Downgrade from reviewer to cheap
        original = ResolvedModel(provider="openai", model_id="gpt-5.2")
        downgraded = walk_downgrade_chain(
            original, _agent(), ROUTING_CONFIG
        )
        assert downgraded.provider == "anthropic"
        assert downgraded.model_id == "claude-sonnet-4-6"

        # Step 2: Anthropic is also down → fallback to a different provider
        # Only mark the downgraded model as visited (not the original, since
        # going back to original provider is valid for fallback)
        visited = {
            f"{downgraded.provider}:{downgraded.model_id}",
        }
        config_with_fallback = {
            **ROUTING_CONFIG,
            "routing": {
                "fallback": {
                    "anthropic": ["reviewer"],
                },
                "downgrade": {"reviewer": ["cheap"]},
            },
        }
        fallback = walk_fallback_chain(
            downgraded, _agent(), config_with_fallback,
            visited=visited,
        )
        assert fallback.provider == "openai"
        assert fallback.model_id == "gpt-5.2"
