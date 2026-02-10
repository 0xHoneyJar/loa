"""Tests for alias resolution and agent binding (SDD §4.1.2, §2.3)."""

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from loa_cheval.routing.resolver import (
    NATIVE_ALIAS,
    NATIVE_PROVIDER,
    NATIVE_MODEL,
    resolve_alias,
    resolve_agent_binding,
    resolve_execution,
    validate_bindings,
    _detect_alias_cycles,
)
from loa_cheval.types import (
    ConfigError,
    InvalidInputError,
    NativeRuntimeRequired,
    ResolvedModel,
)

SAMPLE_CONFIG = {
    "providers": {
        "openai": {
            "type": "openai",
            "endpoint": "https://api.openai.com/v1",
            "auth": "{env:OPENAI_API_KEY}",
            "models": {
                "gpt-5.2": {
                    "capabilities": ["chat", "tools"],
                    "context_window": 128000,
                },
            },
        },
        "anthropic": {
            "type": "anthropic",
            "endpoint": "https://api.anthropic.com/v1",
            "auth": "{env:ANTHROPIC_API_KEY}",
            "models": {
                "claude-opus-4-6": {
                    "capabilities": ["chat", "tools", "thinking_traces"],
                    "context_window": 200000,
                },
            },
        },
    },
    "aliases": {
        "native": "claude-code:session",
        "reviewer": "openai:gpt-5.2",
        "reasoning": "openai:gpt-5.2",
        "cheap": "anthropic:claude-opus-4-6",
        "opus": "anthropic:claude-opus-4-6",
    },
    "agents": {
        "implementing-tasks": {
            "model": "native",
            "requires": {"native_runtime": True},
        },
        "riding-codebase": {
            "model": "native",
            "requires": {"native_runtime": True},
        },
        "reviewing-code": {
            "model": "reviewer",
            "temperature": 0.3,
        },
        "translating-for-executives": {
            "model": "cheap",
            "temperature": 0.5,
        },
        "flatline-skeptic": {
            "model": "reasoning",
            "requires": {"thinking_traces": "preferred"},
        },
    },
}


class TestResolveAlias:
    def test_native_alias(self):
        result = resolve_alias("native", {})
        assert result.provider == NATIVE_PROVIDER
        assert result.model_id == NATIVE_MODEL

    def test_direct_provider_model(self):
        result = resolve_alias("openai:gpt-5.2", {})
        assert result.provider == "openai"
        assert result.model_id == "gpt-5.2"

    def test_alias_resolution(self):
        aliases = {"reviewer": "openai:gpt-5.2"}
        result = resolve_alias("reviewer", aliases)
        assert result.provider == "openai"
        assert result.model_id == "gpt-5.2"

    def test_chained_alias(self):
        aliases = {"fast": "reviewer", "reviewer": "openai:gpt-5.2"}
        result = resolve_alias("fast", aliases)
        assert result.provider == "openai"
        assert result.model_id == "gpt-5.2"

    def test_unknown_alias(self):
        with pytest.raises(ConfigError, match="Unknown alias"):
            resolve_alias("nonexistent", {})

    def test_circular_alias(self):
        aliases = {"a": "b", "b": "a"}
        with pytest.raises(ConfigError, match="Circular"):
            resolve_alias("a", aliases)


class TestResolveAgentBinding:
    def test_known_agent(self):
        binding = resolve_agent_binding("reviewing-code", SAMPLE_CONFIG)
        assert binding.agent == "reviewing-code"
        assert binding.model == "reviewer"
        assert binding.temperature == 0.3

    def test_unknown_agent(self):
        with pytest.raises(InvalidInputError, match="Unknown agent"):
            resolve_agent_binding("nonexistent-agent", SAMPLE_CONFIG)

    def test_native_agent(self):
        binding = resolve_agent_binding("implementing-tasks", SAMPLE_CONFIG)
        assert binding.model == "native"
        assert binding.requires.get("native_runtime") is True


class TestResolveExecution:
    def test_remote_agent(self):
        binding, resolved = resolve_execution("reviewing-code", SAMPLE_CONFIG)
        assert resolved.provider == "openai"
        assert resolved.model_id == "gpt-5.2"
        assert binding.temperature == 0.3

    def test_native_agent_resolves(self):
        binding, resolved = resolve_execution("implementing-tasks", SAMPLE_CONFIG)
        assert resolved.provider == NATIVE_PROVIDER
        assert resolved.model_id == NATIVE_MODEL

    def test_native_agent_rejects_remote_override(self):
        """SDD §2.3: native_runtime guard blocks remote execution."""
        with pytest.raises(NativeRuntimeRequired):
            resolve_execution("implementing-tasks", SAMPLE_CONFIG, model_override="openai:gpt-5.2")

    def test_model_override(self):
        binding, resolved = resolve_execution(
            "reviewing-code", SAMPLE_CONFIG, model_override="anthropic:claude-opus-4-6"
        )
        assert resolved.provider == "anthropic"
        assert resolved.model_id == "claude-opus-4-6"


class TestValidateBindings:
    def test_valid_config(self):
        errors = validate_bindings(SAMPLE_CONFIG)
        # thinking_traces is "preferred" not True, so no error expected
        assert errors == []

    def test_missing_provider(self):
        config = {
            **SAMPLE_CONFIG,
            "aliases": {"reviewer": "missing_provider:model"},
        }
        errors = validate_bindings(config)
        assert any("missing_provider" in e for e in errors)

    def test_missing_model(self):
        config = {
            **SAMPLE_CONFIG,
            "aliases": {
                **SAMPLE_CONFIG["aliases"],
                "reviewer": "openai:nonexistent-model",
            },
        }
        errors = validate_bindings(config)
        assert any("nonexistent-model" in e for e in errors)


class TestAliasCircularDetection:
    def test_no_cycles(self):
        _detect_alias_cycles({"a": "openai:gpt-5.2", "b": "anthropic:claude"})

    def test_direct_cycle(self):
        with pytest.raises(ConfigError, match="Circular"):
            _detect_alias_cycles({"a": "b", "b": "a"})

    def test_indirect_cycle(self):
        with pytest.raises(ConfigError, match="Circular"):
            _detect_alias_cycles({"a": "b", "b": "c", "c": "a"})

    def test_native_alias_skipped(self):
        _detect_alias_cycles({"native": "claude-code:session"})
