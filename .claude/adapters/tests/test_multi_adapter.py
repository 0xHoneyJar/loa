"""Cross-adapter routing integration tests (Sprint 7, Task 7.6).

Tests that routing works correctly when multiple adapters are registered
simultaneously. Verifies agent binding resolution across providers,
fallback chains between adapters, and alias resolution through to the
correct adapter type.

Bridgebuilder Review Part I: "The adapter registry is a provider
ecosystem — its health depends on correct routing under all conditions."
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from loa_cheval.routing.chains import (
    validate_chains,
    walk_downgrade_chain,
    walk_fallback_chain,
)
from loa_cheval.routing.resolver import (
    NATIVE_ALIAS,
    NATIVE_MODEL,
    NATIVE_PROVIDER,
    resolve_alias,
    resolve_agent_binding,
    resolve_execution,
    validate_bindings,
)
from loa_cheval.types import (
    AgentBinding,
    ConfigError,
    InvalidInputError,
    NativeRuntimeRequired,
    ProviderUnavailableError,
    ResolvedModel,
)

# ── Multi-Adapter Config ─────────────────────────────────────────────────────

MULTI_CONFIG = {
    "providers": {
        "openai": {
            "type": "openai",
            "endpoint": "https://api.openai.com/v1",
            "auth": "sk-test",
            "models": {
                "gpt-5.2": {
                    "capabilities": ["chat", "tools", "function_calling"],
                    "context_window": 128000,
                },
            },
        },
        "google": {
            "type": "google",
            "endpoint": "https://generativelanguage.googleapis.com/v1beta",
            "auth": "test-google-key",
            "models": {
                "gemini-3-pro": {
                    "capabilities": ["chat", "thinking_traces"],
                    "context_window": 2097152,
                },
                "deep-research-pro": {
                    "capabilities": ["chat", "deep_research"],
                    "context_window": 1048576,
                    "api_mode": "interactions",
                },
            },
        },
        "anthropic": {
            "type": "anthropic",
            "endpoint": "https://api.anthropic.com/v1",
            "auth": "sk-ant-test",
            "models": {
                "claude-opus-4-6": {
                    "capabilities": ["chat", "tools", "thinking_traces"],
                    "context_window": 200000,
                },
                "claude-sonnet-4-6": {
                    "capabilities": ["chat", "tools"],
                    "context_window": 200000,
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
        "deep-thinker": "google:gemini-3-pro",
        "fast-thinker": "google:gemini-3-pro",
        "researcher": "google:deep-research-pro",
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
        "deep-researcher": {
            "model": "researcher",
            "requires": {"deep_research": True},
        },
        "deep-thinker": {
            "model": "deep-thinker",
            "temperature": 0.4,
            "requires": {"thinking_traces": True},
        },
        "translating-for-executives": {
            "model": "cheap",
            "temperature": 0.5,
        },
    },
    "routing": {
        "fallback": {
            "openai": ["opus"],
            "google": ["reviewer"],
            "anthropic": ["reviewer"],
        },
        "downgrade": {
            "reviewer": ["cheap"],
        },
    },
}


# ── Agent Binding Resolution ─────────────────────────────────────────────────


class TestCrossAdapterAgentResolution:
    """Agent binding resolves to correct provider across all 3 adapters + native."""

    def test_deep_researcher_resolves_to_google(self):
        binding, resolved = resolve_execution("deep-researcher", MULTI_CONFIG)
        assert resolved.provider == "google"
        assert resolved.model_id == "deep-research-pro"
        assert binding.requires.get("deep_research") is True

    def test_reviewer_resolves_to_openai(self):
        binding, resolved = resolve_execution("reviewing-code", MULTI_CONFIG)
        assert resolved.provider == "openai"
        assert resolved.model_id == "gpt-5.2"
        assert binding.temperature == 0.3

    def test_native_resolves_to_claude_code(self):
        binding, resolved = resolve_execution("implementing-tasks", MULTI_CONFIG)
        assert resolved.provider == NATIVE_PROVIDER
        assert resolved.model_id == NATIVE_MODEL

    def test_cheap_resolves_to_anthropic(self):
        binding, resolved = resolve_execution("translating-for-executives", MULTI_CONFIG)
        assert resolved.provider == "anthropic"
        assert resolved.model_id == "claude-sonnet-4-6"

    def test_deep_thinker_resolves_to_google(self):
        binding, resolved = resolve_execution("deep-thinker", MULTI_CONFIG)
        assert resolved.provider == "google"
        assert resolved.model_id == "gemini-3-pro"


# ── Fallback Chain: Google → OpenAI ──────────────────────────────────────────


class TestGoogleToOpenAIFallback:
    """Circuit breaker trip on Google → fallback to OpenAI."""

    def test_google_fallback_to_openai(self):
        """Standard agent (no special requirements) falls back via reviewer alias."""
        original = ResolvedModel(provider="google", model_id="gemini-3-pro")
        agent = AgentBinding(agent="generic-agent", model="deep-thinker", requires={})
        resolved = walk_fallback_chain(original, agent, MULTI_CONFIG)
        assert resolved.provider == "openai"
        assert resolved.model_id == "gpt-5.2"

    def test_google_fallback_blocked_for_deep_research(self):
        """Agent requiring deep_research can't fall back (OpenAI doesn't have it)."""
        original = ResolvedModel(provider="google", model_id="deep-research-pro")
        agent = AgentBinding(
            agent="deep-researcher", model="researcher",
            requires={"deep_research": True},
        )
        with pytest.raises(ProviderUnavailableError, match="exhausted"):
            walk_fallback_chain(original, agent, MULTI_CONFIG)

    def test_openai_fallback_to_anthropic(self):
        """OpenAI fails → falls back to Anthropic via opus alias."""
        original = ResolvedModel(provider="openai", model_id="gpt-5.2")
        agent = AgentBinding(agent="reviewing-code", model="reviewer", requires={})
        resolved = walk_fallback_chain(original, agent, MULTI_CONFIG)
        assert resolved.provider == "anthropic"
        assert resolved.model_id == "claude-opus-4-6"

    def test_anthropic_fallback_to_openai(self):
        """Anthropic fails → falls back to OpenAI via reviewer alias."""
        original = ResolvedModel(provider="anthropic", model_id="claude-sonnet-4-6")
        agent = AgentBinding(agent="translator", model="cheap", requires={})
        resolved = walk_fallback_chain(original, agent, MULTI_CONFIG)
        assert resolved.provider == "openai"
        assert resolved.model_id == "gpt-5.2"


# ── Validate Bindings ────────────────────────────────────────────────────────


class TestValidateBindingsMultiAdapter:
    """validate_bindings catches configuration errors across providers."""

    def test_valid_multi_config(self):
        errors = validate_bindings(MULTI_CONFIG)
        assert errors == []

    def test_missing_google_provider(self):
        """Removing google provider makes deep-researcher fail validation."""
        cfg = {**MULTI_CONFIG, "providers": {
            k: v for k, v in MULTI_CONFIG["providers"].items() if k != "google"
        }}
        errors = validate_bindings(cfg)
        assert any("google" in e for e in errors)

    def test_missing_openai_provider(self):
        cfg = {**MULTI_CONFIG, "providers": {
            k: v for k, v in MULTI_CONFIG["providers"].items() if k != "openai"
        }}
        errors = validate_bindings(cfg)
        assert any("openai" in e for e in errors)

    def test_missing_model_in_provider(self):
        """Provider exists but model doesn't."""
        cfg = dict(MULTI_CONFIG)
        cfg = {
            **MULTI_CONFIG,
            "providers": {
                **MULTI_CONFIG["providers"],
                "openai": {
                    **MULTI_CONFIG["providers"]["openai"],
                    "models": {},  # Empty models
                },
            },
        }
        errors = validate_bindings(cfg)
        assert any("gpt-5.2" in e for e in errors)

    def test_capability_mismatch_detected(self):
        """Agent requires thinking_traces but model doesn't have it."""
        cfg = {
            **MULTI_CONFIG,
            "providers": {
                **MULTI_CONFIG["providers"],
                "google": {
                    **MULTI_CONFIG["providers"]["google"],
                    "models": {
                        "gemini-3-pro": {
                            "capabilities": ["chat"],  # No thinking_traces
                            "context_window": 2097152,
                        },
                        "deep-research-pro": MULTI_CONFIG["providers"]["google"]["models"]["deep-research-pro"],
                    },
                },
            },
        }
        errors = validate_bindings(cfg)
        assert any("thinking_traces" in e for e in errors)


# ── Alias Chain Resolution ───────────────────────────────────────────────────


class TestAliasChainResolution:
    """Alias chains resolve through to the correct provider:model."""

    def test_direct_alias_to_google(self):
        resolved = resolve_alias("deep-thinker", MULTI_CONFIG["aliases"])
        assert resolved.provider == "google"
        assert resolved.model_id == "gemini-3-pro"

    def test_chained_alias(self):
        """Two-level alias chain resolves correctly."""
        aliases = {
            **MULTI_CONFIG["aliases"],
            "my-reviewer": "reviewer",  # my-reviewer → reviewer → openai:gpt-5.2
        }
        resolved = resolve_alias("my-reviewer", aliases)
        assert resolved.provider == "openai"
        assert resolved.model_id == "gpt-5.2"

    def test_direct_provider_model_bypasses_aliases(self):
        """provider:model format bypasses alias lookup entirely."""
        resolved = resolve_alias("anthropic:claude-opus-4-6", {})
        assert resolved.provider == "anthropic"
        assert resolved.model_id == "claude-opus-4-6"

    def test_native_alias_always_native(self):
        resolved = resolve_alias("native", MULTI_CONFIG["aliases"])
        assert resolved.provider == "claude-code"
        assert resolved.model_id == "session"


# ── Adapter Registry ─────────────────────────────────────────────────────────


class TestAdapterRegistry:
    """All 3 provider adapters registered in the adapter registry."""

    def test_openai_registered(self):
        from loa_cheval.providers import _ADAPTER_REGISTRY
        assert "openai" in _ADAPTER_REGISTRY

    def test_google_registered(self):
        from loa_cheval.providers import _ADAPTER_REGISTRY
        assert "google" in _ADAPTER_REGISTRY

    def test_anthropic_registered(self):
        from loa_cheval.providers import _ADAPTER_REGISTRY
        # anthropic uses openai_compat type which is registered as "anthropic"
        # or shares the openai adapter. Check for the type.
        # The config type for anthropic is "anthropic"
        assert "anthropic" in _ADAPTER_REGISTRY or "openai_compat" in _ADAPTER_REGISTRY

    def test_get_adapter_google(self):
        from loa_cheval.providers import get_adapter, GoogleAdapter
        from loa_cheval.types import ProviderConfig, ModelConfig
        config = ProviderConfig(
            name="google", type="google",
            endpoint="https://generativelanguage.googleapis.com/v1beta",
            auth="test-key",
            models={"gemini-3-pro": ModelConfig()},
        )
        adapter = get_adapter(config)
        assert isinstance(adapter, GoogleAdapter)


# ── Chain Validation ─────────────────────────────────────────────────────────


class TestChainValidation:
    """validate_chains detects issues in routing configuration."""

    def test_valid_chains(self):
        errors = validate_chains(MULTI_CONFIG)
        assert errors == []

    def test_unresolvable_fallback(self):
        cfg = {
            **MULTI_CONFIG,
            "routing": {
                "fallback": {"openai": ["nonexistent-alias"]},
            },
        }
        errors = validate_chains(cfg)
        assert len(errors) > 0
        assert any("nonexistent" in e for e in errors)

    def test_duplicate_target_in_chain(self):
        """Same alias appearing twice is detected as cycle."""
        cfg = {
            **MULTI_CONFIG,
            "routing": {
                "fallback": {"openai": ["opus", "opus"]},
                "downgrade": {},
            },
        }
        errors = validate_chains(cfg)
        assert any("cycle" in e.lower() for e in errors)


# ── Model Override ───────────────────────────────────────────────────────────


class TestModelOverride:
    """Model override routes agent to different provider at runtime."""

    def test_override_reviewer_to_anthropic(self):
        binding, resolved = resolve_execution(
            "reviewing-code", MULTI_CONFIG,
            model_override="anthropic:claude-opus-4-6",
        )
        assert resolved.provider == "anthropic"
        assert resolved.model_id == "claude-opus-4-6"

    def test_override_reviewer_to_google(self):
        binding, resolved = resolve_execution(
            "reviewing-code", MULTI_CONFIG,
            model_override="google:gemini-3-pro",
        )
        assert resolved.provider == "google"
        assert resolved.model_id == "gemini-3-pro"

    def test_override_blocked_for_native_agent(self):
        """native_runtime agents reject remote model override."""
        with pytest.raises(NativeRuntimeRequired):
            resolve_execution(
                "implementing-tasks", MULTI_CONFIG,
                model_override="openai:gpt-5.2",
            )
