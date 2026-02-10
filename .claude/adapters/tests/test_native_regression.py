"""Native path regression suite (Sprint Task 1.11).

Verifies zero breaking changes on the native_runtime path.
These tests define what "native path" means concretely and ensure
model-invoke cannot silently route native-bound agents to remote models.
"""

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from loa_cheval.routing.resolver import (
    NATIVE_PROVIDER,
    NATIVE_MODEL,
    resolve_execution,
)
from loa_cheval.types import NativeRuntimeRequired

# Config matching the default model-config.yaml
NATIVE_CONFIG = {
    "providers": {
        "openai": {
            "type": "openai",
            "endpoint": "https://api.openai.com/v1",
            "auth": "{env:OPENAI_API_KEY}",
            "models": {"gpt-5.2": {"capabilities": ["chat", "tools"], "context_window": 128000}},
        },
    },
    "aliases": {
        "native": "claude-code:session",
        "reviewer": "openai:gpt-5.2",
    },
    "agents": {
        "implementing-tasks": {"model": "native", "requires": {"native_runtime": True}},
        "riding-codebase": {"model": "native", "requires": {"native_runtime": True}},
        "designing-architecture": {"model": "native"},
        "planning-sprints": {"model": "native"},
        "discovering-requirements": {"model": "native"},
        "reviewing-code": {"model": "reviewer", "temperature": 0.3},
        "auditing-security": {"model": "native"},
        "translating-for-executives": {"model": "reviewer"},
    },
}


class TestNativeRuntimeGuard:
    """SDD §2.3: native_runtime guard prevents model-invoke routing."""

    def test_implementing_tasks_rejects_remote(self):
        """model-invoke --agent implementing-tasks with remote model must fail (exit code 2)."""
        with pytest.raises(NativeRuntimeRequired) as exc_info:
            resolve_execution("implementing-tasks", NATIVE_CONFIG, model_override="openai:gpt-5.2")
        assert exc_info.value.code == "NATIVE_RUNTIME_REQUIRED"

    def test_riding_codebase_rejects_remote(self):
        """model-invoke --agent riding-codebase with remote model must fail (exit code 2)."""
        with pytest.raises(NativeRuntimeRequired) as exc_info:
            resolve_execution("riding-codebase", NATIVE_CONFIG, model_override="openai:gpt-5.2")
        assert exc_info.value.code == "NATIVE_RUNTIME_REQUIRED"

    def test_implementing_tasks_resolves_native(self):
        """Native-bound agents resolve to native provider without error."""
        binding, resolved = resolve_execution("implementing-tasks", NATIVE_CONFIG)
        assert resolved.provider == NATIVE_PROVIDER
        assert resolved.model_id == NATIVE_MODEL

    def test_riding_codebase_resolves_native(self):
        binding, resolved = resolve_execution("riding-codebase", NATIVE_CONFIG)
        assert resolved.provider == NATIVE_PROVIDER


class TestNativePathUnchanged:
    """Verify native-bound agents are NOT routed through model-invoke."""

    def test_native_agents_resolve_to_claude_code(self):
        """All agents with model=native resolve to claude-code:session."""
        native_agents = [
            "implementing-tasks",
            "riding-codebase",
            "designing-architecture",
            "planning-sprints",
            "discovering-requirements",
            "auditing-security",
        ]
        for agent_name in native_agents:
            binding, resolved = resolve_execution(agent_name, NATIVE_CONFIG)
            assert resolved.provider == NATIVE_PROVIDER, (
                f"Agent '{agent_name}' should resolve to native, got {resolved.provider}"
            )

    def test_remote_agents_resolve_to_provider(self):
        """Agents with non-native model resolve to the configured provider."""
        binding, resolved = resolve_execution("reviewing-code", NATIVE_CONFIG)
        assert resolved.provider == "openai"
        assert resolved.model_id == "gpt-5.2"


class TestNativeAlias:
    """SDD §2.3: 'native' is a reserved alias that cannot be reassigned."""

    def test_native_always_resolves_to_claude_code(self):
        from loa_cheval.routing.resolver import resolve_alias

        # Even with custom aliases, 'native' always resolves to claude-code:session
        aliases = {"native": "openai:gpt-5.2"}  # Attempt to override
        result = resolve_alias("native", aliases)
        # resolve_alias has a hard check for NATIVE_ALIAS
        assert result.provider == NATIVE_PROVIDER
        assert result.model_id == NATIVE_MODEL


class TestCompatibilityMatrix:
    """SDD §2.3 compatibility matrix tests."""

    def test_implement_pre_and_post_migration(self):
        """Pre: SKILL.md (Claude Code), Post: SKILL.md (Claude Code) — unchanged."""
        binding, resolved = resolve_execution("implementing-tasks", NATIVE_CONFIG)
        assert resolved.provider == NATIVE_PROVIDER

    def test_ride_pre_and_post_migration(self):
        """Pre: SKILL.md (Claude Code), Post: SKILL.md (Claude Code) — unchanged."""
        binding, resolved = resolve_execution("riding-codebase", NATIVE_CONFIG)
        assert resolved.provider == NATIVE_PROVIDER

    def test_flatline_review_routes_through_model_invoke(self):
        """Pre: model-adapter.sh → curl, Post: model-invoke → cheval.py."""
        config = {
            **NATIVE_CONFIG,
            "agents": {
                **NATIVE_CONFIG["agents"],
                "flatline-reviewer": {"model": "reviewer"},
            },
        }
        binding, resolved = resolve_execution("flatline-reviewer", config)
        assert resolved.provider == "openai"
        assert resolved.model_id == "gpt-5.2"
