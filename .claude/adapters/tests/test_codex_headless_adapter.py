"""Tests for codex-headless provider adapter.

Covers:
  - registry dispatch on type='codex-headless'
  - command construction (model, reasoning_effort, extra config overrides)
  - JSONL output parsing (agent_message, reasoning, usage, thread_id)
  - error classification (auth, rate limit, generic non-zero exit, timeout)
  - validate_config + health_check
  - prompt flattening (system / user / assistant / tool / list-content)

Live test (real codex CLI invocation) is gated behind LOA_CODEX_HEADLESS_LIVE=1
to keep CI deterministic. Run locally with:
    LOA_CODEX_HEADLESS_LIVE=1 pytest tests/test_codex_headless_adapter.py -k live
"""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from loa_cheval.providers import get_adapter
from loa_cheval.providers.codex_headless_adapter import (
    CodexHeadlessAdapter,
    _ALLOWED_REASONING_EFFORTS,
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
    name: str = "codex-headless",
    ptype: str = "codex-headless",
    extra=None,
    read_timeout: float = 600.0,
) -> ProviderConfig:
    return ProviderConfig(
        name=name,
        type=ptype,
        endpoint="",
        auth="",
        connect_timeout=10.0,
        read_timeout=read_timeout,
        models={
            "gpt-5.5": ModelConfig(
                context_window=200000,
                extra=extra,
            ),
        },
    )


def _make_request(
    model: str = "gpt-5.5",
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


def _fail_proc(returncode: int, stderr: str) -> MagicMock:
    proc = MagicMock(spec=subprocess.CompletedProcess)
    proc.returncode = returncode
    proc.stdout = ""
    proc.stderr = stderr
    return proc


SAMPLE_JSONL_OUTPUT = (
    '{"type":"thread.started","thread_id":"019df536-12f3-71b2-a23a-3b49a2e31d72"}\n'
    '{"type":"turn.started"}\n'
    '{"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"pong"}}\n'
    '{"type":"turn.completed","usage":'
    '{"input_tokens":24086,"cached_input_tokens":3456,'
    '"output_tokens":18,"reasoning_output_tokens":11}}\n'
)


# ---------------------------------------------------------------------------
# Registry dispatch
# ---------------------------------------------------------------------------


class TestRegistryDispatch:
    def test_get_adapter_returns_codex_headless_adapter(self):
        adapter = get_adapter(_make_config())
        assert isinstance(adapter, CodexHeadlessAdapter)

    def test_get_adapter_unknown_type_raises(self):
        from loa_cheval.types import ConfigError

        cfg = _make_config(ptype="bogus-type")
        with pytest.raises(ConfigError) as exc_info:
            get_adapter(cfg)
        assert "Unknown provider type" in str(exc_info.value)


# ---------------------------------------------------------------------------
# Command construction
# ---------------------------------------------------------------------------


class TestCommandConstruction:
    def test_minimal_command(self):
        adapter = CodexHeadlessAdapter(_make_config())
        cmd = adapter._build_command(_make_request(), ModelConfig())
        # Required flags for safe single-shot invocation
        assert cmd[0] == "codex"
        assert "exec" in cmd
        assert "--json" in cmd
        assert "--skip-git-repo-check" in cmd
        assert "--ephemeral" in cmd
        assert "--ignore-user-config" in cmd
        assert "read-only" in cmd
        # Model flag
        idx = cmd.index("--model")
        assert cmd[idx + 1] == "gpt-5.5"
        # No reasoning_effort by default
        for arg in cmd:
            assert "model_reasoning_effort" not in arg

    def test_reasoning_effort_from_metadata_overrides_model_config(self):
        adapter = CodexHeadlessAdapter(_make_config(extra={"reasoning_effort": "high"}))
        req = _make_request(metadata={"reasoning_effort": "low"})
        cmd = adapter._build_command(req, adapter.config.models["gpt-5.5"])
        assert "model_reasoning_effort=low" in cmd
        assert "model_reasoning_effort=high" not in cmd

    def test_reasoning_effort_from_model_config(self):
        adapter = CodexHeadlessAdapter(_make_config(extra={"reasoning_effort": "xhigh"}))
        cmd = adapter._build_command(_make_request(), adapter.config.models["gpt-5.5"])
        assert "model_reasoning_effort=xhigh" in cmd

    def test_unknown_reasoning_effort_falls_through(self):
        adapter = CodexHeadlessAdapter(_make_config(extra={"reasoning_effort": "extreme"}))
        cmd = adapter._build_command(_make_request(), adapter.config.models["gpt-5.5"])
        # "extreme" is not in allowed set; should be dropped silently with a WARN
        assert not any("model_reasoning_effort=" in arg for arg in cmd)

    def test_extra_codex_config_overrides_passed_through(self):
        extra = {
            "reasoning_effort": "low",
            "codex_config_overrides": {
                "reasoning_summaries": "true",
                "model_provider": "oss",
            },
        }
        adapter = CodexHeadlessAdapter(_make_config(extra=extra))
        cmd = adapter._build_command(_make_request(), adapter.config.models["gpt-5.5"])
        assert "reasoning_summaries=true" in cmd
        assert "model_provider=oss" in cmd
        # reasoning_effort still present once (not duplicated by extra dict)
        effort_count = sum(1 for arg in cmd if "model_reasoning_effort=" in arg)
        assert effort_count == 1

    def test_codex_bin_env_override(self):
        adapter = CodexHeadlessAdapter(_make_config())
        with patch.dict(os.environ, {"CODEX_HEADLESS_BIN": "/custom/path/codex"}):
            cmd = adapter._build_command(_make_request(), ModelConfig())
            assert cmd[0] == "/custom/path/codex"


# ---------------------------------------------------------------------------
# Prompt flattening
# ---------------------------------------------------------------------------


class TestPromptFlattening:
    def test_single_user_message(self):
        adapter = CodexHeadlessAdapter(_make_config())
        prompt = adapter._build_prompt([{"role": "user", "content": "ping"}])
        assert "## User" in prompt
        assert "ping" in prompt

    def test_system_user_assistant_sequence(self):
        adapter = CodexHeadlessAdapter(_make_config())
        prompt = adapter._build_prompt(
            [
                {"role": "system", "content": "be terse"},
                {"role": "user", "content": "hi"},
                {"role": "assistant", "content": "hello"},
                {"role": "user", "content": "again"},
            ]
        )
        # All four sections present
        assert "## System" in prompt
        assert "## User" in prompt
        assert "## Assistant" in prompt
        # Conversation order preserved
        assert prompt.index("be terse") < prompt.index("hello")
        assert prompt.index("hello") < prompt.rindex("again")

    def test_anthropic_style_list_content(self):
        adapter = CodexHeadlessAdapter(_make_config())
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

    def test_tool_role_inlined(self):
        adapter = CodexHeadlessAdapter(_make_config())
        prompt = adapter._build_prompt(
            [
                {"role": "user", "content": "call tool"},
                {"role": "tool", "content": '{"result":42}', "tool_call_id": "x"},
            ]
        )
        assert "## Tool result" in prompt
        assert '"result":42' in prompt


# ---------------------------------------------------------------------------
# JSONL parsing
# ---------------------------------------------------------------------------


class TestJsonlParsing:
    def test_parses_agent_message_and_usage(self):
        adapter = CodexHeadlessAdapter(_make_config())
        result = adapter._parse_jsonl_output(
            stdout=SAMPLE_JSONL_OUTPUT,
            stderr="",
            requested_model="gpt-5.5",
            latency_ms=1234,
        )
        assert result.content == "pong"
        assert result.usage.input_tokens == 24086
        assert result.usage.output_tokens == 18
        assert result.usage.reasoning_tokens == 11
        assert result.usage.source == "actual"
        assert result.model == "gpt-5.5"
        assert result.provider == "codex-headless"
        assert result.latency_ms == 1234
        assert result.interaction_id == "019df536-12f3-71b2-a23a-3b49a2e31d72"
        assert result.tool_calls is None
        assert result.thinking is None

    def test_concatenates_multiple_agent_messages(self):
        adapter = CodexHeadlessAdapter(_make_config())
        stdout = (
            '{"type":"item.completed","item":{"type":"agent_message","text":"part one"}}\n'
            '{"type":"item.completed","item":{"type":"agent_message","text":"part two"}}\n'
            '{"type":"turn.completed","usage":{"input_tokens":1,"output_tokens":2}}\n'
        )
        result = adapter._parse_jsonl_output(stdout, "", "gpt-5.5", 100)
        assert "part one" in result.content
        assert "part two" in result.content

    def test_captures_reasoning_traces_as_thinking(self):
        adapter = CodexHeadlessAdapter(_make_config())
        stdout = (
            '{"type":"item.completed","item":{"type":"reasoning","text":"thinking..."}}\n'
            '{"type":"item.completed","item":{"type":"agent_message","text":"answer"}}\n'
            '{"type":"turn.completed","usage":{"input_tokens":1,"output_tokens":1}}\n'
        )
        result = adapter._parse_jsonl_output(stdout, "", "gpt-5.5", 100)
        assert result.content == "answer"
        assert result.thinking == "thinking..."

    def test_skips_non_json_lines(self):
        adapter = CodexHeadlessAdapter(_make_config())
        stdout = (
            "Reading prompt from stdin...\n"
            '{"type":"item.completed","item":{"type":"agent_message","text":"ok"}}\n'
            "non-json garbage line\n"
            '{"type":"turn.completed","usage":{"input_tokens":1,"output_tokens":1}}\n'
        )
        result = adapter._parse_jsonl_output(stdout, "", "gpt-5.5", 100)
        assert result.content == "ok"

    def test_empty_output_warns_and_returns_empty_content(self, caplog):
        adapter = CodexHeadlessAdapter(_make_config())
        stdout = (
            '{"type":"thread.started","thread_id":"abc"}\n'
            '{"type":"turn.completed","usage":{"input_tokens":1,"output_tokens":0}}\n'
        )
        result = adapter._parse_jsonl_output(stdout, "", "gpt-5.5", 100)
        assert result.content == ""
        assert result.usage.input_tokens == 1
        assert result.usage.output_tokens == 0

    def test_unknown_event_type_does_not_raise(self):
        # Forward-compat: codex CLI ships new event types frequently.
        adapter = CodexHeadlessAdapter(_make_config())
        stdout = (
            '{"type":"future.unknown.event","data":"whatever"}\n'
            '{"type":"item.completed","item":{"type":"agent_message","text":"ok"}}\n'
            '{"type":"turn.completed","usage":{"input_tokens":1,"output_tokens":1}}\n'
        )
        # Should not raise
        result = adapter._parse_jsonl_output(stdout, "", "gpt-5.5", 100)
        assert result.content == "ok"


# ---------------------------------------------------------------------------
# Error classification
# ---------------------------------------------------------------------------


class TestErrorClassification:
    def test_rate_limit_in_stderr_raises_rate_limit_error(self):
        adapter = CodexHeadlessAdapter(_make_config())
        with patch("loa_cheval.providers.codex_headless_adapter.subprocess.run") as mock_run:
            mock_run.return_value = _fail_proc(1, "Error: rate limit exceeded — retry in 60s")
            with pytest.raises(RateLimitError):
                adapter.complete(_make_request())

    def test_429_in_stderr_raises_rate_limit_error(self):
        adapter = CodexHeadlessAdapter(_make_config())
        with patch("loa_cheval.providers.codex_headless_adapter.subprocess.run") as mock_run:
            mock_run.return_value = _fail_proc(1, "HTTP 429 Too Many Requests")
            with pytest.raises(RateLimitError):
                adapter.complete(_make_request())

    def test_auth_failure_raises_config_error(self):
        adapter = CodexHeadlessAdapter(_make_config())
        with patch("loa_cheval.providers.codex_headless_adapter.subprocess.run") as mock_run:
            mock_run.return_value = _fail_proc(1, "Error: not authenticated. Run codex login.")
            with pytest.raises(ConfigError) as exc_info:
                adapter.complete(_make_request())
            assert "codex login" in str(exc_info.value)

    def test_generic_failure_raises_provider_unavailable(self):
        adapter = CodexHeadlessAdapter(_make_config())
        with patch("loa_cheval.providers.codex_headless_adapter.subprocess.run") as mock_run:
            mock_run.return_value = _fail_proc(2, "some unexpected error")
            with pytest.raises(ProviderUnavailableError) as exc_info:
                adapter.complete(_make_request())
            assert "exit 2" in str(exc_info.value)

    def test_timeout_raises_provider_unavailable(self):
        adapter = CodexHeadlessAdapter(_make_config(read_timeout=5.0))
        with patch("loa_cheval.providers.codex_headless_adapter.subprocess.run") as mock_run:
            mock_run.side_effect = subprocess.TimeoutExpired(cmd=["codex"], timeout=5)
            with pytest.raises(ProviderUnavailableError) as exc_info:
                adapter.complete(_make_request())
            assert "timed out" in str(exc_info.value)

    def test_codex_not_on_path_raises_config_error(self):
        adapter = CodexHeadlessAdapter(_make_config())
        with patch("loa_cheval.providers.codex_headless_adapter.subprocess.run") as mock_run:
            mock_run.side_effect = FileNotFoundError("codex: command not found")
            with pytest.raises(ConfigError) as exc_info:
                adapter.complete(_make_request())
            assert "not found on PATH" in str(exc_info.value)


# ---------------------------------------------------------------------------
# validate_config + health_check
# ---------------------------------------------------------------------------


class TestValidateAndHealth:
    def test_validate_config_clean_when_codex_present(self):
        adapter = CodexHeadlessAdapter(_make_config())
        with patch("loa_cheval.providers.codex_headless_adapter.shutil.which") as mock_which:
            mock_which.return_value = "/usr/local/bin/codex"
            errors = adapter.validate_config()
            assert errors == []

    def test_validate_config_complains_when_codex_missing(self):
        adapter = CodexHeadlessAdapter(_make_config())
        with patch("loa_cheval.providers.codex_headless_adapter.shutil.which") as mock_which:
            mock_which.return_value = None
            errors = adapter.validate_config()
            assert any("not found on PATH" in e for e in errors)

    def test_validate_config_complains_on_wrong_type(self):
        adapter = CodexHeadlessAdapter(_make_config(ptype="openai"))
        with patch("loa_cheval.providers.codex_headless_adapter.shutil.which") as mock_which:
            mock_which.return_value = "/usr/local/bin/codex"
            errors = adapter.validate_config()
            assert any("type must be 'codex-headless'" in e for e in errors)

    def test_health_check_returns_true_on_zero_exit(self):
        adapter = CodexHeadlessAdapter(_make_config())
        with (
            patch("loa_cheval.providers.codex_headless_adapter.shutil.which") as mock_which,
            patch("loa_cheval.providers.codex_headless_adapter.subprocess.run") as mock_run,
        ):
            mock_which.return_value = "/usr/local/bin/codex"
            mock_run.return_value = _ok_proc("codex-cli 0.125.0\n")
            assert adapter.health_check() is True

    def test_health_check_false_when_binary_missing(self):
        adapter = CodexHeadlessAdapter(_make_config())
        with patch("loa_cheval.providers.codex_headless_adapter.shutil.which") as mock_which:
            mock_which.return_value = None
            assert adapter.health_check() is False


# ---------------------------------------------------------------------------
# End-to-end happy path (mocked subprocess)
# ---------------------------------------------------------------------------


class TestEndToEnd:
    def test_complete_round_trip(self):
        adapter = CodexHeadlessAdapter(_make_config(extra={"reasoning_effort": "high"}))
        with patch("loa_cheval.providers.codex_headless_adapter.subprocess.run") as mock_run:
            mock_run.return_value = _ok_proc(SAMPLE_JSONL_OUTPUT)
            result = adapter.complete(
                _make_request(
                    messages=[
                        {"role": "system", "content": "be terse"},
                        {"role": "user", "content": "ping"},
                    ]
                )
            )
        # Verify call args
        called_cmd = mock_run.call_args.args[0]
        assert "codex" in called_cmd[0]
        assert "exec" in called_cmd
        assert "--json" in called_cmd
        assert "model_reasoning_effort=high" in called_cmd
        # Verify result shape
        assert result.content == "pong"
        assert result.provider == "codex-headless"
        assert result.usage.input_tokens == 24086

    def test_reasoning_effort_constants_match_codex_doc(self):
        # Sanity: the four levels documented for codex CLI 0.125.0+
        assert _ALLOWED_REASONING_EFFORTS == ("low", "medium", "high", "xhigh")


# ---------------------------------------------------------------------------
# Subprocess env filtering (closes issues #879 / #880 — codex symmetric)
#
# codex CLI uses OAuth via `codex login` (stored at ~/.codex/auth.json). When
# OPENAI_API_KEY is exported in the parent process, codex prefers API mode
# over the OAuth subscription. The headless adapter must strip OPENAI_API_KEY
# from the subprocess env so the OAuth path is reachable.
# ---------------------------------------------------------------------------


class TestSubprocessEnvFilter:
    def test_openai_api_key_stripped_by_default(self, monkeypatch):
        monkeypatch.setenv("OPENAI_API_KEY", "sk-proj-test-depleted")
        monkeypatch.delenv("LOA_HEADLESS_KEEP_API_KEY", raising=False)
        adapter = CodexHeadlessAdapter(_make_config())
        with patch("loa_cheval.providers.codex_headless_adapter.subprocess.run") as mock_run:
            mock_run.return_value = _ok_proc(SAMPLE_JSONL_OUTPUT)
            adapter.complete(_make_request())
        kwargs = mock_run.call_args.kwargs
        assert "env" in kwargs, "subprocess.run must pass explicit env="
        assert "OPENAI_API_KEY" not in kwargs["env"]

    def test_path_and_home_preserved(self, monkeypatch):
        monkeypatch.setenv("OPENAI_API_KEY", "sk-proj-test")
        monkeypatch.setenv("PATH", "/test/bin:/usr/bin")
        monkeypatch.setenv("HOME", "/test/home")
        adapter = CodexHeadlessAdapter(_make_config())
        with patch("loa_cheval.providers.codex_headless_adapter.subprocess.run") as mock_run:
            mock_run.return_value = _ok_proc(SAMPLE_JSONL_OUTPUT)
            adapter.complete(_make_request())
        env = mock_run.call_args.kwargs.get("env", {})
        assert env.get("PATH") == "/test/bin:/usr/bin"
        assert env.get("HOME") == "/test/home"

    def test_opt_out_keeps_api_key(self, monkeypatch):
        monkeypatch.setenv("OPENAI_API_KEY", "sk-proj-test")
        monkeypatch.setenv("LOA_HEADLESS_KEEP_API_KEY", "1")
        adapter = CodexHeadlessAdapter(_make_config())
        with patch("loa_cheval.providers.codex_headless_adapter.subprocess.run") as mock_run:
            mock_run.return_value = _ok_proc(SAMPLE_JSONL_OUTPUT)
            adapter.complete(_make_request())
        env = mock_run.call_args.kwargs.get("env", {})
        assert env.get("OPENAI_API_KEY") == "sk-proj-test"


# ---------------------------------------------------------------------------
# Live test (gated)
# ---------------------------------------------------------------------------


@pytest.mark.skipif(
    os.environ.get("LOA_CODEX_HEADLESS_LIVE") != "1",
    reason="Set LOA_CODEX_HEADLESS_LIVE=1 to run real codex exec invocation",
)
class TestLive:
    def test_live_completion(self):
        """Real codex CLI invocation. Requires `codex login` + ~/.codex/auth.json."""
        adapter = CodexHeadlessAdapter(_make_config(extra={"reasoning_effort": "low"}))
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
        assert result.usage.output_tokens > 0
        assert result.provider == "codex-headless"
