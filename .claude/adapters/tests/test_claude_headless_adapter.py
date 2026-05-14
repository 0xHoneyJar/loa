"""Tests for claude-headless provider adapter (third sibling to codex/gemini).

Covers:
  - registry dispatch on type='claude-headless'
  - command construction (model, plan-mode, no-session-persistence, --tools "",
    effort, system_prompt / append_system_prompt overrides, allowed_tools override)
  - JSON output parsing (result, usage including cache tokens, session_id, modelUsage)
  - error classification (auth, rate limit / overloaded, permission, generic, timeout)
  - validate_config + health_check
  - prompt flattening (system / user / assistant / tool / list-content)

Live test (real claude CLI invocation) is gated behind LOA_CLAUDE_HEADLESS_LIVE=1.
Run locally with:
    LOA_CLAUDE_HEADLESS_LIVE=1 pytest tests/test_claude_headless_adapter.py -k live
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
from loa_cheval.providers.claude_headless_adapter import (
    ClaudeHeadlessAdapter,
    _ALLOWED_EFFORTS,
)
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
    name: str = "claude-headless",
    ptype: str = "claude-headless",
    extra=None,
    read_timeout: float = 600.0,
    model_id: str = "claude-opus-4-7",
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
                context_window=200000,
                extra=extra,
            ),
        },
    )


def _make_request(
    model: str = "claude-opus-4-7",
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
        "type": "result",
        "subtype": "success",
        "is_error": False,
        "duration_ms": 2198,
        "duration_api_ms": 1968,
        "num_turns": 1,
        "result": "pong",
        "stop_reason": "end_turn",
        "session_id": "52512b12-7650-4ccb-a014-874c22c76e1a",
        "total_cost_usd": 0.053255,
        "usage": {
            "input_tokens": 3,
            "cache_creation_input_tokens": 14179,
            "cache_read_input_tokens": 0,
            "output_tokens": 5,
            "service_tier": "standard",
        },
        "modelUsage": {
            "claude-opus-4-7": {
                "inputTokens": 3,
                "outputTokens": 5,
                "cacheReadInputTokens": 0,
                "cacheCreationInputTokens": 14179,
                "costUSD": 0.053255,
                "contextWindow": 200000,
                "maxOutputTokens": 32000,
            }
        },
        "permission_denials": [],
        "terminal_reason": "completed",
        "uuid": "5b6f917d-2f7f-469f-8cd4-0d5c8e1ef42f",
    }
)

NOT_LOGGED_IN_JSON = json.dumps(
    {
        "type": "result",
        "subtype": "success",
        "is_error": True,
        "api_error_status": None,
        "result": "Not logged in · Please run /login",
        "stop_reason": "stop_sequence",
        "session_id": "abc-123",
        "usage": {"input_tokens": 0, "output_tokens": 0},
    }
)

OVERLOADED_JSON = json.dumps(
    {
        "type": "result",
        "is_error": True,
        "api_error_status": 529,
        "result": "Anthropic API overloaded — please retry later",
        "session_id": "abc-456",
    }
)


# ---------------------------------------------------------------------------
# Registry dispatch
# ---------------------------------------------------------------------------


class TestRegistryDispatch:
    def test_get_adapter_returns_claude_headless_adapter(self):
        adapter = get_adapter(_make_config())
        assert isinstance(adapter, ClaudeHeadlessAdapter)


# ---------------------------------------------------------------------------
# Command construction
# ---------------------------------------------------------------------------


class TestCommandConstruction:
    def test_minimal_command(self):
        adapter = ClaudeHeadlessAdapter(_make_config())
        cmd = adapter._build_command(_make_request(), ModelConfig(), "hello prompt")
        # Required flags
        assert cmd[0] == "claude"
        # -p with the prompt
        idx = cmd.index("-p")
        assert cmd[idx + 1] == "hello prompt"
        # JSON output
        assert "--output-format" in cmd
        assert cmd[cmd.index("--output-format") + 1] == "json"
        # Plan mode (read-only) + no persistence + tools disabled
        assert "--permission-mode" in cmd
        assert cmd[cmd.index("--permission-mode") + 1] == "plan"
        assert "--no-session-persistence" in cmd
        assert "--tools" in cmd
        assert cmd[cmd.index("--tools") + 1] == ""
        # Model flag
        midx = cmd.index("--model")
        assert cmd[midx + 1] == "claude-opus-4-7"
        # CRITICAL: no --bare flag (would force API key, defeat subscription)
        assert "--bare" not in cmd
        # No effort by default
        assert "--effort" not in cmd

    def test_effort_from_metadata(self):
        adapter = ClaudeHeadlessAdapter(_make_config())
        req = _make_request(metadata={"effort": "max"})
        cmd = adapter._build_command(req, adapter.config.models["claude-opus-4-7"], "x")
        assert "--effort" in cmd
        assert cmd[cmd.index("--effort") + 1] == "max"

    def test_effort_from_model_config(self):
        adapter = ClaudeHeadlessAdapter(_make_config(extra={"effort": "high"}))
        cmd = adapter._build_command(_make_request(), adapter.config.models["claude-opus-4-7"], "x")
        assert cmd[cmd.index("--effort") + 1] == "high"

    def test_metadata_overrides_model_config_effort(self):
        adapter = ClaudeHeadlessAdapter(_make_config(extra={"effort": "low"}))
        req = _make_request(metadata={"effort": "max"})
        cmd = adapter._build_command(req, adapter.config.models["claude-opus-4-7"], "x")
        assert cmd[cmd.index("--effort") + 1] == "max"

    def test_reasoning_effort_alias_works(self):
        # Operators familiar with codex-headless may pass `reasoning_effort`
        # instead of `effort`. Both should resolve.
        adapter = ClaudeHeadlessAdapter(_make_config(extra={"reasoning_effort": "xhigh"}))
        cmd = adapter._build_command(_make_request(), adapter.config.models["claude-opus-4-7"], "x")
        assert cmd[cmd.index("--effort") + 1] == "xhigh"

    def test_unknown_effort_falls_through(self):
        adapter = ClaudeHeadlessAdapter(_make_config(extra={"effort": "extreme"}))
        cmd = adapter._build_command(_make_request(), adapter.config.models["claude-opus-4-7"], "x")
        assert "--effort" not in cmd

    def test_system_prompt_replaces_default(self):
        adapter = ClaudeHeadlessAdapter(_make_config(extra={"system_prompt": "You are terse."}))
        cmd = adapter._build_command(_make_request(), adapter.config.models["claude-opus-4-7"], "x")
        assert "--system-prompt" in cmd
        assert cmd[cmd.index("--system-prompt") + 1] == "You are terse."

    def test_append_system_prompt(self):
        adapter = ClaudeHeadlessAdapter(_make_config(extra={"append_system_prompt": "Be terse."}))
        cmd = adapter._build_command(_make_request(), adapter.config.models["claude-opus-4-7"], "x")
        assert "--append-system-prompt" in cmd
        assert cmd[cmd.index("--append-system-prompt") + 1] == "Be terse."

    def test_allowed_tools_override(self):
        adapter = ClaudeHeadlessAdapter(_make_config(extra={"allowed_tools": ["Read", "Grep"]}))
        cmd = adapter._build_command(_make_request(), adapter.config.models["claude-opus-4-7"], "x")
        # The default --tools "" should be replaced with the allowed list
        idx = cmd.index("--tools")
        assert cmd[idx + 1] == "Read,Grep"

    def test_extra_flags_pass_through(self):
        adapter = ClaudeHeadlessAdapter(
            _make_config(extra={"claude_extra_flags": [["--max-budget-usd", "5"], "--verbose"]})
        )
        cmd = adapter._build_command(_make_request(), adapter.config.models["claude-opus-4-7"], "x")
        assert "--max-budget-usd" in cmd
        assert cmd[cmd.index("--max-budget-usd") + 1] == "5"
        assert "--verbose" in cmd

    def test_claude_bin_env_override(self):
        adapter = ClaudeHeadlessAdapter(_make_config())
        with patch.dict(os.environ, {"CLAUDE_HEADLESS_BIN": "/custom/path/claude"}):
            cmd = adapter._build_command(_make_request(), ModelConfig(), "x")
            assert cmd[0] == "/custom/path/claude"


# ---------------------------------------------------------------------------
# Prompt flattening
# ---------------------------------------------------------------------------


class TestPromptFlattening:
    def test_system_user_assistant_sequence(self):
        adapter = ClaudeHeadlessAdapter(_make_config())
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
        adapter = ClaudeHeadlessAdapter(_make_config())
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
    def test_parses_result_and_usage(self):
        adapter = ClaudeHeadlessAdapter(_make_config())
        with patch("loa_cheval.providers.claude_headless_adapter.subprocess.run") as mock_run:
            mock_run.return_value = _ok_proc(SAMPLE_OK_JSON)
            result = adapter.complete(_make_request())
        assert result.content == "pong"
        assert result.usage.input_tokens == 3
        assert result.usage.output_tokens == 5
        assert result.usage.source == "actual"
        assert result.model == "claude-opus-4-7"
        assert result.provider == "claude-headless"
        assert result.interaction_id == "52512b12-7650-4ccb-a014-874c22c76e1a"
        assert result.tool_calls is None

    def test_cache_tokens_propagate_to_metadata(self):
        adapter = ClaudeHeadlessAdapter(_make_config())
        with patch("loa_cheval.providers.claude_headless_adapter.subprocess.run") as mock_run:
            mock_run.return_value = _ok_proc(SAMPLE_OK_JSON)
            result = adapter.complete(_make_request())
        assert result.metadata.get("cache_creation_input_tokens") == 14179
        assert "cache_read_input_tokens" not in result.metadata  # was 0 — skipped
        assert result.metadata.get("total_cost_usd") == pytest.approx(0.053255, rel=1e-4)
        assert result.metadata.get("stop_reason") == "end_turn"

    def test_missing_usage_yields_estimated_source(self):
        no_usage = json.dumps({"type": "result", "is_error": False, "result": "ok", "session_id": "x"})
        adapter = ClaudeHeadlessAdapter(_make_config())
        with patch("loa_cheval.providers.claude_headless_adapter.subprocess.run") as mock_run:
            mock_run.return_value = _ok_proc(no_usage)
            result = adapter.complete(_make_request())
        assert result.content == "ok"
        assert result.usage.source == "estimated"
        assert result.usage.input_tokens == 0

    def test_permission_denials_propagate(self):
        with_denials = json.dumps(
            {
                "type": "result",
                "is_error": False,
                "result": "blocked some things",
                "session_id": "x",
                "permission_denials": [{"tool": "Bash", "reason": "plan mode"}],
            }
        )
        adapter = ClaudeHeadlessAdapter(_make_config())
        with patch("loa_cheval.providers.claude_headless_adapter.subprocess.run") as mock_run:
            mock_run.return_value = _ok_proc(with_denials)
            result = adapter.complete(_make_request())
        assert result.metadata.get("permission_denials")
        assert result.metadata["permission_denials"][0]["tool"] == "Bash"

    def test_actual_model_from_modelUsage(self):
        # When modelUsage is present, prefer it over the requested model.
        with_actual = json.dumps(
            {
                "type": "result",
                "is_error": False,
                "result": "ok",
                "session_id": "x",
                "usage": {"input_tokens": 1, "output_tokens": 1},
                "modelUsage": {"claude-sonnet-4-6": {"inputTokens": 1, "outputTokens": 1}},
            }
        )
        adapter = ClaudeHeadlessAdapter(_make_config())
        with patch("loa_cheval.providers.claude_headless_adapter.subprocess.run") as mock_run:
            mock_run.return_value = _ok_proc(with_actual)
            # Request opus, but server actually used sonnet — adapter should report sonnet.
            result = adapter.complete(_make_request(model="claude-opus-4-7"))
        assert result.model == "claude-sonnet-4-6"


# ---------------------------------------------------------------------------
# Error classification
# ---------------------------------------------------------------------------


class TestErrorClassification:
    def test_not_logged_in_raises_config_error(self):
        adapter = ClaudeHeadlessAdapter(_make_config())
        # Claude Code returns exit 0 even on auth failure but is_error=true in JSON.
        with patch("loa_cheval.providers.claude_headless_adapter.subprocess.run") as mock_run:
            mock_run.return_value = _ok_proc(NOT_LOGGED_IN_JSON)
            with pytest.raises(ConfigError) as exc_info:
                adapter.complete(_make_request())
            assert "claude /login" in str(exc_info.value)

    def test_overloaded_raises_rate_limit(self):
        adapter = ClaudeHeadlessAdapter(_make_config())
        with patch("loa_cheval.providers.claude_headless_adapter.subprocess.run") as mock_run:
            mock_run.return_value = _ok_proc(OVERLOADED_JSON)
            with pytest.raises(RateLimitError):
                adapter.complete(_make_request())

    def test_stderr_429_raises_rate_limit(self):
        adapter = ClaudeHeadlessAdapter(_make_config())
        with patch("loa_cheval.providers.claude_headless_adapter.subprocess.run") as mock_run:
            mock_run.return_value = _fail_proc(1, stderr="HTTP 429 Too Many Requests")
            with pytest.raises(RateLimitError):
                adapter.complete(_make_request())

    def test_generic_failure_raises_provider_unavailable(self):
        adapter = ClaudeHeadlessAdapter(_make_config())
        with patch("loa_cheval.providers.claude_headless_adapter.subprocess.run") as mock_run:
            mock_run.return_value = _fail_proc(2, stderr="some unexpected error")
            with pytest.raises(ProviderUnavailableError) as exc_info:
                adapter.complete(_make_request())
            assert "exit 2" in str(exc_info.value)

    def test_timeout_raises_provider_unavailable(self):
        adapter = ClaudeHeadlessAdapter(_make_config(read_timeout=5.0))
        with patch("loa_cheval.providers.claude_headless_adapter.subprocess.run") as mock_run:
            mock_run.side_effect = subprocess.TimeoutExpired(cmd=["claude"], timeout=5)
            with pytest.raises(ProviderUnavailableError) as exc_info:
                adapter.complete(_make_request())
            assert "timed out" in str(exc_info.value)

    def test_claude_not_on_path_raises_config_error(self):
        adapter = ClaudeHeadlessAdapter(_make_config())
        with patch("loa_cheval.providers.claude_headless_adapter.subprocess.run") as mock_run:
            mock_run.side_effect = FileNotFoundError("claude: command not found")
            with pytest.raises(ConfigError) as exc_info:
                adapter.complete(_make_request())
            assert "not found on PATH" in str(exc_info.value)

    def test_unparseable_stdout_raises_provider_unavailable(self):
        adapter = ClaudeHeadlessAdapter(_make_config())
        with patch("loa_cheval.providers.claude_headless_adapter.subprocess.run") as mock_run:
            mock_run.return_value = _ok_proc("garbage not json")
            with pytest.raises(ProviderUnavailableError) as exc_info:
                adapter.complete(_make_request())
            assert "no parseable JSON" in str(exc_info.value)


# ---------------------------------------------------------------------------
# validate_config + health_check
# ---------------------------------------------------------------------------


class TestValidateAndHealth:
    def test_validate_config_clean_when_claude_present(self):
        adapter = ClaudeHeadlessAdapter(_make_config())
        with patch("loa_cheval.providers.claude_headless_adapter.shutil.which") as mock_which:
            mock_which.return_value = "/usr/local/bin/claude"
            assert adapter.validate_config() == []

    def test_validate_config_complains_when_claude_missing(self):
        adapter = ClaudeHeadlessAdapter(_make_config())
        with patch("loa_cheval.providers.claude_headless_adapter.shutil.which") as mock_which:
            mock_which.return_value = None
            errors = adapter.validate_config()
            assert any("not found on PATH" in e for e in errors)

    def test_validate_config_complains_on_wrong_type(self):
        adapter = ClaudeHeadlessAdapter(_make_config(ptype="anthropic"))
        with patch("loa_cheval.providers.claude_headless_adapter.shutil.which") as mock_which:
            mock_which.return_value = "/usr/local/bin/claude"
            errors = adapter.validate_config()
            assert any("type must be 'claude-headless'" in e for e in errors)

    def test_health_check_returns_true_on_zero_exit(self):
        adapter = ClaudeHeadlessAdapter(_make_config())
        with (
            patch("loa_cheval.providers.claude_headless_adapter.shutil.which") as mock_which,
            patch("loa_cheval.providers.claude_headless_adapter.subprocess.run") as mock_run,
        ):
            mock_which.return_value = "/usr/local/bin/claude"
            mock_run.return_value = _ok_proc("2.1.128 (Claude Code)\n")
            assert adapter.health_check() is True

    def test_health_check_false_when_binary_missing(self):
        adapter = ClaudeHeadlessAdapter(_make_config())
        with patch("loa_cheval.providers.claude_headless_adapter.shutil.which") as mock_which:
            mock_which.return_value = None
            assert adapter.health_check() is False


# ---------------------------------------------------------------------------
# End-to-end happy path (mocked subprocess)
# ---------------------------------------------------------------------------


class TestEndToEnd:
    def test_complete_round_trip(self):
        adapter = ClaudeHeadlessAdapter(_make_config(extra={"effort": "high"}))
        with patch("loa_cheval.providers.claude_headless_adapter.subprocess.run") as mock_run:
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
        assert called_cmd[0] == "claude"
        # Confirm prompt was assembled with role prefixes and passed via -p
        p_idx = called_cmd.index("-p")
        prompt_passed = called_cmd[p_idx + 1]
        assert "## System" in prompt_passed
        assert "be terse" in prompt_passed
        assert "ping" in prompt_passed
        # Confirm safe defaults
        assert "--permission-mode" in called_cmd
        assert called_cmd[called_cmd.index("--permission-mode") + 1] == "plan"
        assert "--no-session-persistence" in called_cmd
        assert called_cmd[called_cmd.index("--tools") + 1] == ""
        assert "--bare" not in called_cmd
        # Effort threaded
        assert "--effort" in called_cmd
        assert called_cmd[called_cmd.index("--effort") + 1] == "high"
        # Result shape
        assert result.content == "pong"
        assert result.provider == "claude-headless"
        assert result.usage.input_tokens == 3

    def test_effort_constants_match_cli_doc(self):
        # Sanity: the five levels documented for claude CLI 2.1+
        assert _ALLOWED_EFFORTS == ("low", "medium", "high", "xhigh", "max")


# ---------------------------------------------------------------------------
# Subprocess env filtering (closes issues #879 / #880)
#
# The claude_headless_adapter MUST strip ANTHROPIC_API_KEY from the subprocess
# environment by default. The CLI's OAuth subscription path is selected only
# when no API key is present; if the parent process exports ANTHROPIC_API_KEY
# (depleted, expired, or just shadowing the subscription), claude -p falls
# back to API mode and the headless adapter's purpose is defeated.
#
# Operator opt-out: LOA_HEADLESS_KEEP_API_KEY=1 preserves the variable for
# operators who explicitly want API-mode routing through the CLI.
# ---------------------------------------------------------------------------


class TestSubprocessEnvFilter:
    def test_anthropic_api_key_stripped_by_default(self, monkeypatch):
        """Default behavior: ANTHROPIC_API_KEY must NOT leak into claude -p subprocess."""
        monkeypatch.setenv("ANTHROPIC_API_KEY", "sk-ant-test-depleted-key")
        monkeypatch.delenv("LOA_HEADLESS_KEEP_API_KEY", raising=False)
        adapter = ClaudeHeadlessAdapter(_make_config())
        with patch("loa_cheval.providers.claude_headless_adapter.subprocess.run") as mock_run:
            mock_run.return_value = _ok_proc(SAMPLE_OK_JSON)
            adapter.complete(_make_request())
        kwargs = mock_run.call_args.kwargs
        assert "env" in kwargs, (
            "subprocess.run MUST be invoked with an explicit env= kwarg so the "
            "OAuth subscription path is reachable when ANTHROPIC_API_KEY is set"
        )
        env = kwargs["env"]
        assert "ANTHROPIC_API_KEY" not in env, (
            f"ANTHROPIC_API_KEY leaked into subprocess env: keys={sorted(env.keys())[:20]}"
        )

    def test_path_and_home_preserved(self, monkeypatch):
        """Auth-class strip MUST NOT collapse the user's basic env (PATH, HOME, etc.)."""
        monkeypatch.setenv("ANTHROPIC_API_KEY", "sk-ant-test")
        monkeypatch.setenv("PATH", "/test/bin:/usr/bin")
        monkeypatch.setenv("HOME", "/test/home")
        adapter = ClaudeHeadlessAdapter(_make_config())
        with patch("loa_cheval.providers.claude_headless_adapter.subprocess.run") as mock_run:
            mock_run.return_value = _ok_proc(SAMPLE_OK_JSON)
            adapter.complete(_make_request())
        env = mock_run.call_args.kwargs.get("env", {})
        assert env.get("PATH") == "/test/bin:/usr/bin"
        assert env.get("HOME") == "/test/home"

    def test_opt_out_keeps_api_key(self, monkeypatch):
        """Operator opt-out: LOA_HEADLESS_KEEP_API_KEY=1 preserves ANTHROPIC_API_KEY."""
        monkeypatch.setenv("ANTHROPIC_API_KEY", "sk-ant-test")
        monkeypatch.setenv("LOA_HEADLESS_KEEP_API_KEY", "1")
        adapter = ClaudeHeadlessAdapter(_make_config())
        with patch("loa_cheval.providers.claude_headless_adapter.subprocess.run") as mock_run:
            mock_run.return_value = _ok_proc(SAMPLE_OK_JSON)
            adapter.complete(_make_request())
        env = mock_run.call_args.kwargs.get("env", {})
        assert env.get("ANTHROPIC_API_KEY") == "sk-ant-test", (
            "LOA_HEADLESS_KEEP_API_KEY=1 must preserve the env var"
        )

    def test_no_api_key_in_parent_env_still_passes_clean_env(self, monkeypatch):
        """When ANTHROPIC_API_KEY isn't in parent env, the env= kwarg is still passed
        explicitly (defense-in-depth — the adapter's invariant is 'never inherit env')."""
        monkeypatch.delenv("ANTHROPIC_API_KEY", raising=False)
        monkeypatch.delenv("LOA_HEADLESS_KEEP_API_KEY", raising=False)
        adapter = ClaudeHeadlessAdapter(_make_config())
        with patch("loa_cheval.providers.claude_headless_adapter.subprocess.run") as mock_run:
            mock_run.return_value = _ok_proc(SAMPLE_OK_JSON)
            adapter.complete(_make_request())
        # env kwarg MUST be present (not None) even when no key needs stripping.
        assert "env" in mock_run.call_args.kwargs
        assert mock_run.call_args.kwargs["env"] is not None
        assert "ANTHROPIC_API_KEY" not in mock_run.call_args.kwargs["env"]


# ---------------------------------------------------------------------------
# Live test (gated)
# ---------------------------------------------------------------------------


@pytest.mark.skipif(
    os.environ.get("LOA_CLAUDE_HEADLESS_LIVE") != "1",
    reason="Set LOA_CLAUDE_HEADLESS_LIVE=1 to run real claude -p invocation",
)
class TestLive:
    def test_live_completion(self):
        """Real claude CLI invocation. Requires `claude /login` (subscription)."""
        adapter = ClaudeHeadlessAdapter(_make_config(model_id="haiku"))
        result = adapter.complete(
            _make_request(
                model="haiku",
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
        assert result.provider == "claude-headless"
