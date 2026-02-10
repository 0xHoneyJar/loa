"""Tests for Flatline routing through model-invoke (Sprint 2, SDD §4.4.2-3).

Tests the new agent bindings (flatline-scorer, flatline-dissenter, gpt-reviewer),
the model-adapter.sh compatibility shim, and feature flag behavior.
"""

import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from loa_cheval.routing.resolver import (
    resolve_agent_binding,
    resolve_execution,
    validate_bindings,
)
from loa_cheval.types import ConfigError, NativeRuntimeRequired

# Project root (relative to test file)
PROJECT_ROOT = Path(__file__).resolve().parent.parent.parent.parent
SCRIPTS_DIR = PROJECT_ROOT / ".claude" / "scripts"
MODEL_INVOKE = SCRIPTS_DIR / "model-invoke"
MODEL_ADAPTER = SCRIPTS_DIR / "model-adapter.sh"


# ── Sample config matching model-config.yaml ─────────────────────────────────

FLATLINE_CONFIG = {
    "providers": {
        "openai": {
            "type": "openai",
            "endpoint": "https://api.openai.com/v1",
            "auth": "{env:OPENAI_API_KEY}",
            "models": {
                "gpt-5.2": {
                    "capabilities": ["chat", "tools", "function_calling"],
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
        "flatline-reviewer": {
            "model": "reviewer",
            "temperature": 0.3,
        },
        "flatline-skeptic": {
            "model": "reasoning",
            "temperature": 0.5,
            "requires": {"thinking_traces": "preferred"},
        },
        "flatline-scorer": {
            "model": "reviewer",
            "temperature": 0.2,
        },
        "flatline-dissenter": {
            "model": "reasoning",
            "temperature": 0.6,
            "requires": {"thinking_traces": "preferred"},
        },
        "gpt-reviewer": {
            "model": "reviewer",
            "temperature": 0.3,
        },
    },
}


# ── Agent Binding Tests ──────────────────────────────────────────────────────


class TestFlatlineAgentBindings:
    """Test that all 5 Flatline agents resolve correctly."""

    def test_flatline_reviewer_resolves(self):
        binding, resolved = resolve_execution("flatline-reviewer", FLATLINE_CONFIG)
        assert resolved.provider == "openai"
        assert resolved.model_id == "gpt-5.2"
        assert binding.temperature == 0.3

    def test_flatline_skeptic_resolves(self):
        binding, resolved = resolve_execution("flatline-skeptic", FLATLINE_CONFIG)
        assert resolved.provider == "openai"
        assert resolved.model_id == "gpt-5.2"
        assert binding.temperature == 0.5

    def test_flatline_scorer_resolves(self):
        binding, resolved = resolve_execution("flatline-scorer", FLATLINE_CONFIG)
        assert resolved.provider == "openai"
        assert resolved.model_id == "gpt-5.2"
        assert binding.temperature == 0.2

    def test_flatline_dissenter_resolves(self):
        binding, resolved = resolve_execution("flatline-dissenter", FLATLINE_CONFIG)
        assert resolved.provider == "openai"
        assert resolved.model_id == "gpt-5.2"
        assert binding.temperature == 0.6

    def test_gpt_reviewer_resolves(self):
        binding, resolved = resolve_execution("gpt-reviewer", FLATLINE_CONFIG)
        assert resolved.provider == "openai"
        assert resolved.model_id == "gpt-5.2"
        assert binding.temperature == 0.3

    def test_all_flatline_bindings_valid(self):
        errors = validate_bindings(FLATLINE_CONFIG)
        assert errors == [], f"Binding validation errors: {errors}"


class TestModelOverride:
    """Test that --model override routes Flatline agents to different providers."""

    def test_reviewer_with_opus_override(self):
        """flatline-reviewer defaults to openai, but can be overridden to anthropic."""
        binding, resolved = resolve_execution(
            "flatline-reviewer",
            FLATLINE_CONFIG,
            model_override="anthropic:claude-opus-4-6",
        )
        assert resolved.provider == "anthropic"
        assert resolved.model_id == "claude-opus-4-6"

    def test_scorer_with_opus_override(self):
        binding, resolved = resolve_execution(
            "flatline-scorer",
            FLATLINE_CONFIG,
            model_override="anthropic:claude-opus-4-6",
        )
        assert resolved.provider == "anthropic"
        assert resolved.model_id == "claude-opus-4-6"

    def test_skeptic_with_opus_override(self):
        binding, resolved = resolve_execution(
            "flatline-skeptic",
            FLATLINE_CONFIG,
            model_override="opus",
        )
        assert resolved.provider == "anthropic"
        assert resolved.model_id == "claude-opus-4-6"

    def test_dissenter_with_reviewer_override(self):
        binding, resolved = resolve_execution(
            "flatline-dissenter",
            FLATLINE_CONFIG,
            model_override="reviewer",
        )
        assert resolved.provider == "openai"
        assert resolved.model_id == "gpt-5.2"


# ── CLI Dry-Run Tests (model-invoke) ────────────────────────────────────────


class TestModelInvokeDryRun:
    """Test model-invoke --dry-run for Flatline agents.

    These tests run actual shell commands but don't call external APIs.
    """

    @pytest.fixture(autouse=True)
    def check_model_invoke_exists(self):
        if not MODEL_INVOKE.exists():
            pytest.skip("model-invoke not found")

    def _dry_run(self, agent, model_override=None):
        cmd = [str(MODEL_INVOKE), "--agent", agent, "--dry-run"]
        if model_override:
            cmd.extend(["--model", model_override])
        result = subprocess.run(
            cmd, capture_output=True, text=True, cwd=str(PROJECT_ROOT)
        )
        assert result.returncode == 0, f"dry-run failed: {result.stderr}"
        return json.loads(result.stdout)

    def test_flatline_reviewer_dry_run(self):
        data = self._dry_run("flatline-reviewer")
        assert data["agent"] == "flatline-reviewer"
        assert data["resolved_provider"] == "openai"
        assert data["resolved_model"] == "gpt-5.2"

    def test_flatline_scorer_dry_run(self):
        data = self._dry_run("flatline-scorer")
        assert data["agent"] == "flatline-scorer"
        assert data["resolved_provider"] == "openai"

    def test_flatline_dissenter_dry_run(self):
        data = self._dry_run("flatline-dissenter")
        assert data["agent"] == "flatline-dissenter"
        assert data["resolved_provider"] == "openai"

    def test_gpt_reviewer_dry_run(self):
        data = self._dry_run("gpt-reviewer")
        assert data["agent"] == "gpt-reviewer"
        assert data["resolved_provider"] == "openai"

    def test_reviewer_with_opus_override_dry_run(self):
        data = self._dry_run("flatline-reviewer", "anthropic:claude-opus-4-6")
        assert data["resolved_provider"] == "anthropic"
        assert data["resolved_model"] == "claude-opus-4-6"


# ── Compatibility Shim Tests (model-adapter.sh) ─────────────────────────────


class TestModelAdapterShim:
    """Test the model-adapter.sh compatibility shim.

    Tests both feature flag=true (model-invoke) and flag=false (legacy) paths.
    """

    @pytest.fixture(autouse=True)
    def check_scripts_exist(self):
        if not MODEL_ADAPTER.exists():
            pytest.skip("model-adapter.sh not found")

    @pytest.fixture
    def dummy_input(self, tmp_path):
        """Create a dummy input file for model-adapter.sh."""
        f = tmp_path / "test-input.md"
        f.write_text("# Test Document\n\nThis is test content for review.\n")
        return str(f)

    def _run_adapter(self, args, env_overrides=None):
        env = os.environ.copy()
        if env_overrides:
            env.update(env_overrides)
        result = subprocess.run(
            [str(MODEL_ADAPTER)] + args,
            capture_output=True, text=True, cwd=str(PROJECT_ROOT), env=env,
        )
        return result

    def test_shim_legacy_mock_mode(self, dummy_input):
        """With flag=false and mock mode, shim delegates to legacy adapter."""
        result = self._run_adapter(
            ["--model", "opus", "--mode", "review", "--input", dummy_input, "--json"],
            env_overrides={
                "HOUNFOUR_FLATLINE_ROUTING": "false",
                "FLATLINE_MOCK_MODE": "true",
            },
        )
        assert result.returncode == 0
        data = json.loads(result.stdout)
        assert data.get("mock") is True

    def test_shim_routes_to_model_invoke_dry_run(self, dummy_input):
        """With flag=true, shim routes through model-invoke."""
        result = self._run_adapter(
            ["--model", "opus", "--mode", "review", "--input", dummy_input, "--dry-run"],
            env_overrides={"HOUNFOUR_FLATLINE_ROUTING": "true"},
        )
        assert result.returncode == 0
        data = json.loads(result.stdout)
        assert data["agent"] == "flatline-reviewer"
        assert data["resolved_provider"] == "anthropic"

    def test_shim_mode_to_agent_mapping(self, dummy_input):
        """All 4 modes map to correct agents."""
        mode_agent_map = {
            "review": "flatline-reviewer",
            "skeptic": "flatline-skeptic",
            "score": "flatline-scorer",
            "dissent": "flatline-dissenter",
        }
        for mode, expected_agent in mode_agent_map.items():
            result = self._run_adapter(
                ["--model", "gpt-5.2", "--mode", mode,
                 "--input", dummy_input, "--dry-run"],
                env_overrides={"HOUNFOUR_FLATLINE_ROUTING": "true"},
            )
            assert result.returncode == 0, f"mode={mode} failed: {result.stderr}"
            data = json.loads(result.stdout)
            assert data["agent"] == expected_agent, f"mode={mode}: expected {expected_agent}, got {data['agent']}"

    def test_shim_model_translation(self, dummy_input):
        """Legacy model names correctly translate to provider:model-id."""
        tests = [
            ("gpt-5.2", "openai", "gpt-5.2"),
            ("opus", "anthropic", "claude-opus-4-6"),
        ]
        for model, expected_provider, expected_model in tests:
            result = self._run_adapter(
                ["--model", model, "--mode", "review",
                 "--input", dummy_input, "--dry-run"],
                env_overrides={"HOUNFOUR_FLATLINE_ROUTING": "true"},
            )
            assert result.returncode == 0, f"model={model} failed: {result.stderr}"
            data = json.loads(result.stdout)
            assert data["resolved_provider"] == expected_provider
            assert data["resolved_model"] == expected_model

    def test_shim_invalid_mode(self, dummy_input):
        """Invalid mode returns exit code 2."""
        result = self._run_adapter(
            ["--model", "opus", "--mode", "invalid", "--input", dummy_input],
            env_overrides={"HOUNFOUR_FLATLINE_ROUTING": "true"},
        )
        assert result.returncode == 2

    def test_shim_missing_input(self):
        """Missing input file returns exit code 2."""
        result = self._run_adapter(
            ["--model", "opus", "--mode", "review"],
            env_overrides={"HOUNFOUR_FLATLINE_ROUTING": "true"},
        )
        assert result.returncode == 2

    def test_feature_flag_toggle(self, dummy_input):
        """Switching flag doesn't require restart — just env change."""
        # Flag=false → legacy mock
        result1 = self._run_adapter(
            ["--model", "opus", "--mode", "review", "--input", dummy_input],
            env_overrides={
                "HOUNFOUR_FLATLINE_ROUTING": "false",
                "FLATLINE_MOCK_MODE": "true",
            },
        )
        assert result1.returncode == 0
        data1 = json.loads(result1.stdout)
        assert data1.get("mock") is True

        # Flag=true → model-invoke dry-run
        result2 = self._run_adapter(
            ["--model", "opus", "--mode", "review",
             "--input", dummy_input, "--dry-run"],
            env_overrides={"HOUNFOUR_FLATLINE_ROUTING": "true"},
        )
        assert result2.returncode == 0
        data2 = json.loads(result2.stdout)
        assert "agent" in data2


# ── Validate Bindings CLI Test ───────────────────────────────────────────────


class TestValidateBindingsCLI:
    """Test --validate-bindings includes new Flatline agents."""

    @pytest.fixture(autouse=True)
    def check_model_invoke_exists(self):
        if not MODEL_INVOKE.exists():
            pytest.skip("model-invoke not found")

    def test_validate_bindings_includes_new_agents(self):
        result = subprocess.run(
            [str(MODEL_INVOKE), "--validate-bindings"],
            capture_output=True, text=True, cwd=str(PROJECT_ROOT),
        )
        assert result.returncode == 0
        data = json.loads(result.stdout)
        assert data["valid"] is True

        expected_agents = [
            "flatline-reviewer", "flatline-skeptic",
            "flatline-scorer", "flatline-dissenter",
            "gpt-reviewer",
        ]
        for agent in expected_agents:
            assert agent in data["agents"], f"Missing agent: {agent}"
