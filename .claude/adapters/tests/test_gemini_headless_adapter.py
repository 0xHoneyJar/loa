"""Tests for gemini-headless provider adapter (sibling to codex-headless).

Covers:
  - registry dispatch on type='gemini-headless'
  - command construction (model, plan-mode, skip-trust, policy + extra flags)
  - JSON output parsing (response, stats.models.<id>.tokens, session_id, warnings)
  - error classification (auth, rate limit, generic non-zero exit, timeout)
  - validate_config + health_check
  - prompt flattening (system / user / assistant / tool / list-content)

Live test (real gemini CLI invocation) is gated behind LOA_GEMINI_HEADLESS_LIVE=1.
Run locally with:
    LOA_GEMINI_HEADLESS_LIVE=1 pytest tests/test_gemini_headless_adapter.py -k live
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from loa_cheval.providers import get_adapter
from loa_cheval.providers.gemini_headless_adapter import GeminiHeadlessAdapter
from loa_cheval.types import (
    CompletionRequest,
    ConfigError,
    ModelConfig,
    ProviderConfig,
    ProviderUnavailableError,
    RateLimitError,
)


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


def _make_config(
    name: str = "gemini-headless",
    ptype: str = "gemini-headless",
    extra=None,
    read_timeout: float = 600.0,
    model_id: str = "gemini-3-pro",
) -> ProviderConfig:
    return ProviderConfig(
        name=name,
        type=ptype,
        endpoint="",
        auth="",
        connect_timeout=10.0,
        read_timeout=read_timeout,
        models={
            model_id: ModelConfig(
                context_window=1048576,
                extra=extra,
            ),
        },
    )


def _make_request(
    model: str = "gemini-3-pro",
    messages=None,
    metadata=None,
    max_tokens: int = 256,
) -> CompletionRequest:
    return CompletionRequest(
        messages=messages or [{"role": "user", "content": "hi"}],
        model=model,
        max_tokens=max_tokens,
        metadata=metadata,
    )


def _ok_proc(stdout: str, stderr: str = "") -> MagicMock:
    proc = MagicMock(spec=subprocess.CompletedProcess)
    proc.returncode = 0
    proc.stdout = stdout
    proc.stderr = stderr
    return proc


def _fail_proc(returncode: int, stderr: str = "", stdout: str = "") -> MagicMock:
    proc = MagicMock(spec=subprocess.CompletedProcess)
    proc.returncode = returncode
    proc.stdout = stdout
    proc.stderr = stderr
    return proc


SAMPLE_OK_JSON = json.dumps(
    {
        "session_id": "9cac101a-0d08-46ea-b69d-7d6f6a7a878d",
        "response": "pong",
        "stats": {
            "models": {
                "gemini-3-pro": {
                    "tokens": {
                        "prompt": 1024,
                        "candidates": 8,
                        "total": 1032,
                        "cached": 0,
                        "thoughts": 4,
                    },
                    "api": {"totalRequests": 1, "totalErrors": 0, "totalLatencyMs": 1234},
                }
            },
            "tools": {
                "totalCalls": 0,
                "totalSuccess": 0,
                "totalFail": 0,
                "totalDurationMs": 0,
            },
            "files": {"totalLinesAdded": 0, "totalLinesRemoved": 0},
        },
    }
)

AUTH_ERROR_JSON = json.dumps(
    {
        "session_id": "abc-123",
        "error": {
            "type": "Error",
            "message": (
                "Please set an Auth method in your /home/user/.gemini/settings.json or "
                "specify one of the following environment variables before running: "
                "GEMINI_API_KEY, GOOGLE_GENAI_USE_VERTEXAI, GOOGLE_GENAI_USE_GCA"
            ),
            "code": 41,
        },
    }
)

QUOTA_ERROR_JSON = json.dumps(
    {
        "session_id": "abc-456",
        "error": {
            "type": "Error",
            "message": "RESOURCE_EXHAUSTED: Quota exceeded for free tier (60 RPM).",
            "code": 8,
        },
    }
)


# ---------------------------------------------------------------------------
# Registry dispatch
# ---------------------------------------------------------------------------


class TestRegistryDispatch:
    def test_get_adapter_returns_gemini_headless_adapter(self):
        adapter = get_adapter(_make_config())
        assert isinstance(adapter, GeminiHeadlessAdapter)


# ---------------------------------------------------------------------------
# Command construction
# ---------------------------------------------------------------------------


class TestCommandConstruction:
    def test_minimal_command(self):
        adapter = GeminiHeadlessAdapter(_make_config())
        cmd = adapter._build_command(_make_request(), ModelConfig(), "hello prompt")
        # Required flags for safe non-interactive invocation
        assert cmd[0] == "gemini"
        # -p must be present and followed by the prompt
        idx = cmd.index("-p")
        assert cmd[idx + 1] == "hello prompt"
        assert "--output-format" in cmd
        assert cmd[cmd.index("--output-format") + 1] == "json"
        assert "--approval-mode" in cmd
        assert cmd[cmd.index("--approval-mode") + 1] == "plan"
        assert "--skip-trust" in cmd
        # Model flag
        midx = cmd.index("-m")
        assert cmd[midx + 1] == "gemini-3-pro"

    def test_policy_paths_forwarded(self):
        adapter = GeminiHeadlessAdapter(
            _make_config(extra={"gemini_policies": ["./.gemini/policy-a.json", "./.gemini/policy-b.json"]})
        )
        cmd = adapter._build_command(_make_request(), adapter.config.models["gemini-3-pro"], "x")
        # Two --policy flags in order
        policy_indices = [i for i, v in enumerate(cmd) if v == "--policy"]
        assert len(policy_indices) == 2
        assert cmd[policy_indices[0] + 1] == "./.gemini/policy-a.json"
        assert cmd[policy_indices[1] + 1] == "./.gemini/policy-b.json"

    def test_extra_flags_pass_through(self):
        adapter = GeminiHeadlessAdapter(
            _make_config(extra={"gemini_extra_flags": [["--allowed-tools", "read,grep"], "--list-extensions"]})
        )
        cmd = adapter._build_command(_make_request(), adapter.config.models["gemini-3-pro"], "x")
        assert "--allowed-tools" in cmd
        assert cmd[cmd.index("--allowed-tools") + 1] == "read,grep"
        assert "--list-extensions" in cmd

    def test_gemini_bin_env_override(self):
        adapter = GeminiHeadlessAdapter(_make_config())
        with patch.dict(os.environ, {"GEMINI_HEADLESS_BIN": "/custom/path/gemini"}):
            cmd = adapter._build_command(_make_request(), ModelConfig(), "x")
            assert cmd[0] == "/custom/path/gemini"


# ---------------------------------------------------------------------------
# Prompt flattening
# ---------------------------------------------------------------------------


class TestPromptFlattening:
    def test_system_user_assistant_sequence(self):
        adapter = GeminiHeadlessAdapter(_make_config())
        prompt = adapter._build_prompt(
            [
                {"role": "system", "content": "be terse"},
                {"role": "user", "content": "hi"},
                {"role": "assistant", "content": "hello"},
                {"role": "user", "content": "again"},
            ]
        )
        assert "## System" in prompt
        assert "## User" in prompt
        assert "## Assistant" in prompt
        assert prompt.index("be terse") < prompt.index("hello")
        assert prompt.index("hello") < prompt.rindex("again")

    def test_anthropic_style_list_content(self):
        adapter = GeminiHeadlessAdapter(_make_config())
        prompt = adapter._build_prompt(
            [
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": "block A"},
                        {"type": "text", "text": "block B"},
                    ],
                }
            ]
        )
        assert "block A" in prompt
        assert "block B" in prompt


# ---------------------------------------------------------------------------
# JSON output parsing
# ---------------------------------------------------------------------------


class TestJsonParsing:
    def test_parses_response_and_stats(self):
        adapter = GeminiHeadlessAdapter(_make_config())
        with patch("loa_cheval.providers.gemini_headless_adapter.subprocess.run") as mock_run:
            mock_run.return_value = _ok_proc(SAMPLE_OK_JSON)
            result = adapter.complete(_make_request())
        assert result.content == "pong"
        assert result.usage.input_tokens == 1024
        assert result.usage.output_tokens == 8
        assert result.usage.reasoning_tokens == 4
        assert result.usage.source == "actual"
        assert result.model == "gemini-3-pro"
        assert result.provider == "gemini-headless"
        assert result.interaction_id == "9cac101a-0d08-46ea-b69d-7d6f6a7a878d"
        assert result.tool_calls is None

    def test_falls_back_to_only_model_in_stats(self):
        # Request gemini-3-pro but stats key on gemini-3-pro-preview (single entry).
        # Adapter should still find the tokens.
        stats_under_alt = json.dumps(
            {
                "session_id": "x",
                "response": "ok",
                "stats": {
                    "models": {
                        "gemini-3-pro-preview": {
                            "tokens": {"prompt": 100, "candidates": 5},
                        }
                    }
                },
            }
        )
        adapter = GeminiHeadlessAdapter(_make_config())
        with patch("loa_cheval.providers.gemini_headless_adapter.subprocess.run") as mock_run:
            mock_run.return_value = _ok_proc(stats_under_alt)
            result = adapter.complete(_make_request())
        assert result.usage.input_tokens == 100
        assert result.usage.output_tokens == 5

    def test_missing_stats_yields_estimated_source(self):
        no_stats = json.dumps({"session_id": "x", "response": "ok"})
        adapter = GeminiHeadlessAdapter(_make_config())
        with patch("loa_cheval.providers.gemini_headless_adapter.subprocess.run") as mock_run:
            mock_run.return_value = _ok_proc(no_stats)
            result = adapter.complete(_make_request())
        assert result.content == "ok"
        assert result.usage.source == "estimated"
        assert result.usage.input_tokens == 0
        assert result.usage.output_tokens == 0

    def test_warnings_propagate_to_metadata(self):
        with_warnings = json.dumps(
            {
                "session_id": "x",
                "response": "ok",
                "warnings": ["some non-fatal warning", "another"],
            }
        )
        adapter = GeminiHeadlessAdapter(_make_config())
        with patch("loa_cheval.providers.gemini_headless_adapter.subprocess.run") as mock_run:
            mock_run.return_value = _ok_proc(with_warnings)
            result = adapter.complete(_make_request())
        assert result.metadata.get("warnings") == ["some non-fatal warning", "another"]

    def test_cached_tokens_propagate_to_metadata(self):
        with_cached = json.dumps(
            {
                "session_id": "x",
                "response": "ok",
                "stats": {
                    "models": {
                        "gemini-3-pro": {
                            "tokens": {"prompt": 100, "candidates": 5, "cached": 80}
                        }
                    }
                },
            }
        )
        adapter = GeminiHeadlessAdapter(_make_config())
        with patch("loa_cheval.providers.gemini_headless_adapter.subprocess.run") as mock_run:
            mock_run.return_value = _ok_proc(with_cached)
            result = adapter.complete(_make_request())
        assert result.metadata.get("cached_tokens") == 80


# ---------------------------------------------------------------------------
# Error classification
# ---------------------------------------------------------------------------


class TestErrorClassification:
    def test_structured_auth_error_raises_config_error(self):
        adapter = GeminiHeadlessAdapter(_make_config())
        # gemini may exit non-zero AND emit JSON error — verify we surface the
        # structured diagnostic.
        with patch("loa_cheval.providers.gemini_headless_adapter.subprocess.run") as mock_run:
            mock_run.return_value = _fail_proc(41, stdout=AUTH_ERROR_JSON)
            with pytest.raises(ConfigError) as exc_info:
                adapter.complete(_make_request())
            assert "settings.json" in str(exc_info.value) or "Auth method" in str(exc_info.value)

    def test_quota_error_raises_rate_limit(self):
        adapter = GeminiHeadlessAdapter(_make_config())
        with patch("loa_cheval.providers.gemini_headless_adapter.subprocess.run") as mock_run:
            mock_run.return_value = _fail_proc(8, stdout=QUOTA_ERROR_JSON)
            with pytest.raises(RateLimitError):
                adapter.complete(_make_request())

    def test_stderr_429_raises_rate_limit(self):
        adapter = GeminiHeadlessAdapter(_make_config())
        with patch("loa_cheval.providers.gemini_headless_adapter.subprocess.run") as mock_run:
            mock_run.return_value = _fail_proc(1, stderr="HTTP 429 Too Many Requests")
            with pytest.raises(RateLimitError):
                adapter.complete(_make_request())

    def test_generic_failure_raises_provider_unavailable(self):
        adapter = GeminiHeadlessAdapter(_make_config())
        with patch("loa_cheval.providers.gemini_headless_adapter.subprocess.run") as mock_run:
            mock_run.return_value = _fail_proc(2, stderr="some unexpected internal error")
            with pytest.raises(ProviderUnavailableError) as exc_info:
                adapter.complete(_make_request())
            assert "exit 2" in str(exc_info.value)

    def test_timeout_raises_provider_unavailable(self):
        adapter = GeminiHeadlessAdapter(_make_config(read_timeout=5.0))
        with patch("loa_cheval.providers.gemini_headless_adapter.subprocess.run") as mock_run:
            mock_run.side_effect = subprocess.TimeoutExpired(cmd=["gemini"], timeout=5)
            with pytest.raises(ProviderUnavailableError) as exc_info:
                adapter.complete(_make_request())
            assert "timed out" in str(exc_info.value)

    def test_gemini_not_on_path_raises_config_error(self):
        adapter = GeminiHeadlessAdapter(_make_config())
        with patch("loa_cheval.providers.gemini_headless_adapter.subprocess.run") as mock_run:
            mock_run.side_effect = FileNotFoundError("gemini: command not found")
            with pytest.raises(ConfigError) as exc_info:
                adapter.complete(_make_request())
            assert "not found on PATH" in str(exc_info.value)

    def test_unparseable_stdout_raises_provider_unavailable(self):
        adapter = GeminiHeadlessAdapter(_make_config())
        with patch("loa_cheval.providers.gemini_headless_adapter.subprocess.run") as mock_run:
            mock_run.return_value = _ok_proc("this is not json at all")
            with pytest.raises(ProviderUnavailableError) as exc_info:
                adapter.complete(_make_request())
            assert "no parseable JSON" in str(exc_info.value)


# ---------------------------------------------------------------------------
# validate_config + health_check
# ---------------------------------------------------------------------------


class TestValidateAndHealth:
    def test_validate_config_clean_when_gemini_present(self):
        adapter = GeminiHeadlessAdapter(_make_config())
        with patch("loa_cheval.providers.gemini_headless_adapter.shutil.which") as mock_which:
            mock_which.return_value = "/usr/local/bin/gemini"
            assert adapter.validate_config() == []

    def test_validate_config_complains_when_gemini_missing(self):
        adapter = GeminiHeadlessAdapter(_make_config())
        with patch("loa_cheval.providers.gemini_headless_adapter.shutil.which") as mock_which:
            mock_which.return_value = None
            errors = adapter.validate_config()
            assert any("not found on PATH" in e for e in errors)

    def test_validate_config_complains_on_wrong_type(self):
        adapter = GeminiHeadlessAdapter(_make_config(ptype="google"))
        with patch("loa_cheval.providers.gemini_headless_adapter.shutil.which") as mock_which:
            mock_which.return_value = "/usr/local/bin/gemini"
            errors = adapter.validate_config()
            assert any("type must be 'gemini-headless'" in e for e in errors)

    def test_health_check_returns_true_on_zero_exit(self):
        adapter = GeminiHeadlessAdapter(_make_config())
        with (
            patch("loa_cheval.providers.gemini_headless_adapter.shutil.which") as mock_which,
            patch("loa_cheval.providers.gemini_headless_adapter.subprocess.run") as mock_run,
        ):
            mock_which.return_value = "/usr/local/bin/gemini"
            mock_run.return_value = _ok_proc("0.40.1\n")
            assert adapter.health_check() is True

    def test_health_check_false_when_binary_missing(self):
        adapter = GeminiHeadlessAdapter(_make_config())
        with patch("loa_cheval.providers.gemini_headless_adapter.shutil.which") as mock_which:
            mock_which.return_value = None
            assert adapter.health_check() is False


# ---------------------------------------------------------------------------
# End-to-end happy path (mocked subprocess)
# ---------------------------------------------------------------------------


class TestEndToEnd:
    def test_complete_round_trip(self):
        adapter = GeminiHeadlessAdapter(_make_config())
        with patch("loa_cheval.providers.gemini_headless_adapter.subprocess.run") as mock_run:
            mock_run.return_value = _ok_proc(SAMPLE_OK_JSON)
            result = adapter.complete(
                _make_request(
                    messages=[
                        {"role": "system", "content": "be terse"},
                        {"role": "user", "content": "ping"},
                    ]
                )
            )
        called_cmd = mock_run.call_args.args[0]
        assert called_cmd[0] == "gemini"
        # Confirm prompt was assembled with role prefixes and passed via -p
        p_idx = called_cmd.index("-p")
        prompt_passed = called_cmd[p_idx + 1]
        assert "## System" in prompt_passed
        assert "be terse" in prompt_passed
        assert "ping" in prompt_passed
        # Confirm we set plan-mode + skip-trust
        assert "--approval-mode" in called_cmd
        assert called_cmd[called_cmd.index("--approval-mode") + 1] == "plan"
        assert "--skip-trust" in called_cmd
        # Confirm result shape
        assert result.content == "pong"
        assert result.provider == "gemini-headless"
        assert result.usage.input_tokens == 1024


# ---------------------------------------------------------------------------
# Subprocess env filtering (closes issues #879 / #880 — gemini symmetric)
#
# gemini CLI uses GCA OAuth (Google Cloud Auth) by default. When GOOGLE_API_KEY
# or GEMINI_API_KEY is exported, the CLI prefers API mode over OAuth.
# Adapter must strip both from subprocess env.
# ---------------------------------------------------------------------------


class TestSubprocessEnvFilter:
    def test_google_api_keys_stripped_by_default(self, monkeypatch):
        monkeypatch.setenv("GOOGLE_API_KEY", "test-google-key")
        monkeypatch.setenv("GEMINI_API_KEY", "test-gemini-key")
        monkeypatch.delenv("LOA_HEADLESS_KEEP_API_KEY", raising=False)
        adapter = GeminiHeadlessAdapter(_make_config())
        with patch("loa_cheval.providers.gemini_headless_adapter.subprocess.run") as mock_run:
            mock_run.return_value = _ok_proc(SAMPLE_OK_JSON)
            adapter.complete(_make_request())
        kwargs = mock_run.call_args.kwargs
        assert "env" in kwargs, "subprocess.run must pass explicit env="
        assert "GOOGLE_API_KEY" not in kwargs["env"]
        assert "GEMINI_API_KEY" not in kwargs["env"]

    def test_path_and_home_preserved(self, monkeypatch):
        monkeypatch.setenv("GOOGLE_API_KEY", "test-key")
        monkeypatch.setenv("PATH", "/test/bin:/usr/bin")
        monkeypatch.setenv("HOME", "/test/home")
        adapter = GeminiHeadlessAdapter(_make_config())
        with patch("loa_cheval.providers.gemini_headless_adapter.subprocess.run") as mock_run:
            mock_run.return_value = _ok_proc(SAMPLE_OK_JSON)
            adapter.complete(_make_request())
        env = mock_run.call_args.kwargs.get("env", {})
        assert env.get("PATH") == "/test/bin:/usr/bin"
        assert env.get("HOME") == "/test/home"

    def test_opt_out_keeps_api_keys(self, monkeypatch):
        monkeypatch.setenv("GOOGLE_API_KEY", "test-google")
        monkeypatch.setenv("GEMINI_API_KEY", "test-gemini")
        monkeypatch.setenv("LOA_HEADLESS_KEEP_API_KEY", "1")
        adapter = GeminiHeadlessAdapter(_make_config())
        with patch("loa_cheval.providers.gemini_headless_adapter.subprocess.run") as mock_run:
            mock_run.return_value = _ok_proc(SAMPLE_OK_JSON)
            adapter.complete(_make_request())
        env = mock_run.call_args.kwargs.get("env", {})
        assert env.get("GOOGLE_API_KEY") == "test-google"
        assert env.get("GEMINI_API_KEY") == "test-gemini"


# ---------------------------------------------------------------------------
# Live test (gated)
# ---------------------------------------------------------------------------


@pytest.mark.skipif(
    os.environ.get("LOA_GEMINI_HEADLESS_LIVE") != "1",
    reason="Set LOA_GEMINI_HEADLESS_LIVE=1 to run real gemini -p invocation",
)
class TestLive:
    def test_live_completion(self):
        """Real gemini CLI invocation. Requires `gemini` interactive first-run + auth."""
        adapter = GeminiHeadlessAdapter(_make_config())
        result = adapter.complete(
            _make_request(
                messages=[
                    {
                        "role": "user",
                        "content": "Reply with exactly the word: PONG (uppercase, no punctuation).",
                    }
                ],
                max_tokens=32,
            )
        )
        assert "PONG" in result.content.upper()
        assert result.provider == "gemini-headless"
