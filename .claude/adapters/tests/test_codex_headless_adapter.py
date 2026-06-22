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
    AuthRevokedError,
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

    def test_agent_tool_surface_disabled(self):
        # #1008 finding 1 (audit): the agent's shell/browser/computer tools must
        # be disabled so a prompt-injected diff cannot execute commands to
        # read + exfiltrate files despite --sandbox read-only.
        adapter = CodexHeadlessAdapter(_make_config())
        cmd = adapter._build_command(_make_request(), ModelConfig())
        disabled = {cmd[i + 1] for i, a in enumerate(cmd) if a == "--disable"}
        for feature in ("shell_tool", "browser_use", "browser_use_external", "computer_use"):
            assert feature in disabled, f"{feature} must be disabled"

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

    def test_extra_codex_config_overrides_allowlisted_key_passes(self):
        # #1008 finding 2: an inference-only key on the allowlist still passes
        # through as `-c key=value`; reasoning_effort is not duplicated.
        extra = {
            "reasoning_effort": "low",
            "codex_config_overrides": {
                "reasoning_summaries": "true",
            },
        }
        adapter = CodexHeadlessAdapter(_make_config(extra=extra))
        cmd = adapter._build_command(_make_request(), adapter.config.models["gpt-5.5"])
        assert "reasoning_summaries=true" in cmd
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
        with patch("loa_cheval.providers.codex_headless_adapter.run_subprocess_pgkill") as mock_run:
            mock_run.return_value = _fail_proc(1, "Error: rate limit exceeded — retry in 60s")
            with pytest.raises(RateLimitError):
                adapter.complete(_make_request())

    def test_429_in_stderr_raises_rate_limit_error(self):
        adapter = CodexHeadlessAdapter(_make_config())
        with patch("loa_cheval.providers.codex_headless_adapter.run_subprocess_pgkill") as mock_run:
            mock_run.return_value = _fail_proc(1, "HTTP 429 Too Many Requests")
            with pytest.raises(RateLimitError):
                adapter.complete(_make_request())

    def test_auth_failure_raises_config_error(self):
        adapter = CodexHeadlessAdapter(_make_config())
        with patch("loa_cheval.providers.codex_headless_adapter.run_subprocess_pgkill") as mock_run:
            mock_run.return_value = _fail_proc(1, "Error: not authenticated. Run codex login.")
            with pytest.raises(ConfigError) as exc_info:
                adapter.complete(_make_request())
            assert "codex login" in str(exc_info.value)

    def test_runtime_token_revocation_raises_auth_revoked(self):
        # KF-017/#1071: a previously-valid token, server-invalidated, must be
        # classified WALKABLE (AuthRevokedError), not a hard-abort ConfigError.
        adapter = CodexHeadlessAdapter(_make_config())
        with patch("loa_cheval.providers.codex_headless_adapter.run_subprocess_pgkill") as mock_run:
            mock_run.return_value = _fail_proc(
                1, "401 Unauthorized: your authentication token has been invalidated"
            )
            with pytest.raises(AuthRevokedError) as exc_info:
                adapter.complete(_make_request())
            assert exc_info.value.code == "AUTH_REVOKED"
            assert exc_info.value.retryable is True

    def test_ambiguous_unauthorized_with_static_marker_still_config_error(self):
        # #1095 safety: "unauthorized" co-occurring with a never-authenticated
        # marker must STILL hard-abort (ConfigError), not be silently walked.
        adapter = CodexHeadlessAdapter(_make_config())
        with patch("loa_cheval.providers.codex_headless_adapter.run_subprocess_pgkill") as mock_run:
            mock_run.return_value = _fail_proc(
                1, "Error: unauthorized — not authenticated. Run: codex login."
            )
            with pytest.raises(ConfigError) as exc_info:
                adapter.complete(_make_request())
            assert "codex login" in str(exc_info.value)

    def test_generic_failure_raises_provider_unavailable(self):
        adapter = CodexHeadlessAdapter(_make_config())
        with patch("loa_cheval.providers.codex_headless_adapter.run_subprocess_pgkill") as mock_run:
            mock_run.return_value = _fail_proc(2, "some unexpected error")
            with pytest.raises(ProviderUnavailableError) as exc_info:
                adapter.complete(_make_request())
            assert "exit 2" in str(exc_info.value)

    def test_timeout_raises_provider_unavailable(self):
        adapter = CodexHeadlessAdapter(_make_config(read_timeout=5.0))
        with patch("loa_cheval.providers.codex_headless_adapter.run_subprocess_pgkill") as mock_run:
            mock_run.side_effect = subprocess.TimeoutExpired(cmd=["codex"], timeout=5)
            with pytest.raises(ProviderUnavailableError) as exc_info:
                adapter.complete(_make_request())
            assert "timed out" in str(exc_info.value)

    def test_codex_not_on_path_raises_config_error(self):
        adapter = CodexHeadlessAdapter(_make_config())
        with patch("loa_cheval.providers.codex_headless_adapter.run_subprocess_pgkill") as mock_run:
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
        with patch("loa_cheval.providers.codex_headless_adapter.run_subprocess_pgkill") as mock_run:
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
        with patch("loa_cheval.providers.codex_headless_adapter.run_subprocess_pgkill") as mock_run:
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
        with patch("loa_cheval.providers.codex_headless_adapter.run_subprocess_pgkill") as mock_run:
            mock_run.return_value = _ok_proc(SAMPLE_JSONL_OUTPUT)
            adapter.complete(_make_request())
        env = mock_run.call_args.kwargs.get("env", {})
        assert env.get("PATH") == "/test/bin:/usr/bin"
        assert env.get("HOME") == "/test/home"

    def test_opt_out_keeps_api_key(self, monkeypatch):
        monkeypatch.setenv("OPENAI_API_KEY", "sk-proj-test")
        monkeypatch.setenv("LOA_HEADLESS_KEEP_API_KEY", "1")
        adapter = CodexHeadlessAdapter(_make_config())
        with patch("loa_cheval.providers.codex_headless_adapter.run_subprocess_pgkill") as mock_run:
            mock_run.return_value = _ok_proc(SAMPLE_JSONL_OUTPUT)
            adapter.complete(_make_request())
        env = mock_run.call_args.kwargs.get("env", {})
        assert env.get("OPENAI_API_KEY") == "sk-proj-test"


# ---------------------------------------------------------------------------
# #1008 finding 1 — isolate the agent read-surface (workspace cwd + -C)
#
# `--sandbox read-only` prevents writes, not reads. Untrusted flattened prompt
# content (review diffs / issue bodies) could instruct the codex agent to read
# workspace files and return them via the normal CompletionResult path. Mirror
# the audit-blessed cursor_headless defense: run codex in a fresh empty tempdir
# (cwd=workspace + `-C <workspace>`), removed in a finally even on raise.
# ---------------------------------------------------------------------------


class TestWorkspaceIsolation:
    def test_build_command_includes_cd_workspace(self):
        adapter = CodexHeadlessAdapter(_make_config())
        cmd = adapter._build_command(
            _make_request(), ModelConfig(), workspace="/tmp/loa-codex-ws-XXXX"
        )
        idx = cmd.index("-C")
        assert cmd[idx + 1] == "/tmp/loa-codex-ws-XXXX"
        # The read-only sandbox is retained alongside the isolation.
        assert "read-only" in cmd

    def test_pgkill_called_with_isolated_workspace_cwd(self):
        # The helper must receive cwd=<fresh loa-codex-ws-* tempdir> so a
        # (read-only-but-still-capable) agent tool call has nothing to reach.
        adapter = CodexHeadlessAdapter(_make_config())
        with patch(
            "loa_cheval.providers.codex_headless_adapter.run_subprocess_pgkill"
        ) as mock_run:
            mock_run.return_value = _ok_proc(SAMPLE_JSONL_OUTPUT)
            adapter.complete(_make_request())
        kwargs = mock_run.call_args.kwargs
        assert "loa-codex-ws-" in (kwargs.get("cwd") or "")

    def test_workspace_removed_after_completion(self):
        adapter = CodexHeadlessAdapter(_make_config())
        with patch(
            "loa_cheval.providers.codex_headless_adapter.run_subprocess_pgkill"
        ) as mock_run:
            mock_run.return_value = _ok_proc(SAMPLE_JSONL_OUTPUT)
            adapter.complete(_make_request())
            ws = mock_run.call_args.kwargs.get("cwd")
        assert ws and "loa-codex-ws-" in ws
        assert not os.path.exists(ws), "workspace tempdir must be cleaned up"

    def test_workspace_removed_even_on_failure(self):
        adapter = CodexHeadlessAdapter(_make_config())
        captured = {}
        with patch(
            "loa_cheval.providers.codex_headless_adapter.run_subprocess_pgkill"
        ) as mock_run:
            def _capture(*args, **kwargs):
                captured["cwd"] = kwargs.get("cwd")
                return _fail_proc(2, "some unexpected error")

            mock_run.side_effect = _capture
            with pytest.raises(ProviderUnavailableError):
                adapter.complete(_make_request())
        ws = captured.get("cwd")
        assert ws and "loa-codex-ws-" in ws
        assert not os.path.exists(ws), "workspace must be cleaned up on the failure path too"

    def test_mkdtemp_failure_raises_typed_provider_error(self):
        # DISS-002 (review): a tempdir-creation failure must surface as a typed
        # ProviderUnavailableError so the fallback chain still reacts — not a
        # raw OSError — and must not leave the rmtree path dereferencing None.
        adapter = CodexHeadlessAdapter(_make_config())
        with patch(
            "loa_cheval.providers.codex_headless_adapter.tempfile.mkdtemp",
            side_effect=OSError("No space left on device"),
        ):
            with pytest.raises(ProviderUnavailableError):
                adapter.complete(_make_request())


# ---------------------------------------------------------------------------
# #1008 finding 2 — default-deny allowlist for codex_config_overrides
#
# Every key under ModelConfig.extra.codex_config_overrides used to be appended
# as `-c key=value` with no allowlist, letting (potentially untrusted) project
# config alter codex's security posture (provider routing, sandbox, approval,
# network, mcp/features/tools, auth). Only inference/display knobs may pass.
# ---------------------------------------------------------------------------


class TestConfigOverrideAllowlist:
    def _cmd_with_overrides(self, overrides):
        extra = {"codex_config_overrides": overrides}
        adapter = CodexHeadlessAdapter(_make_config(extra=extra))
        return adapter._build_command(_make_request(), adapter.config.models["gpt-5.5"])

    def test_security_posture_key_rejected(self, caplog):
        import logging

        with caplog.at_level(logging.WARNING):
            cmd = self._cmd_with_overrides({"model_provider": "oss"})
        # The provider-routing key never reaches the argv.
        assert not any("model_provider" in arg for arg in cmd)
        assert any("model_provider" in rec.getMessage() for rec in caplog.records)

    def test_multiple_security_keys_all_rejected(self):
        cmd = self._cmd_with_overrides(
            {
                "sandbox_mode": "danger-full-access",
                "approval_policy": "never",
                "model_provider": "oss",
                "shell_environment_policy": "all",
                "mcp_servers": "x",
            }
        )
        for bad in (
            "sandbox_mode",
            "approval_policy",
            "model_provider",
            "shell_environment_policy",
            "mcp_servers",
        ):
            assert not any(bad in arg for arg in cmd), f"{bad} must be rejected"

    def test_dotted_nested_key_rejected(self):
        cmd = self._cmd_with_overrides({"model_providers.oss.base_url": "http://evil"})
        assert not any("base_url" in arg for arg in cmd)
        assert not any("model_providers" in arg for arg in cmd)

    def test_allowlisted_key_passes(self):
        cmd = self._cmd_with_overrides({"reasoning_summaries": "true"})
        assert "reasoning_summaries=true" in cmd

    def test_rejection_does_not_raise(self):
        # Parity with reasoning_effort fall-through: a bad key is dropped with a
        # warning; the request still proceeds (cmd is built, not an exception).
        cmd = self._cmd_with_overrides({"model_provider": "oss", "reasoning_summaries": "true"})
        assert "reasoning_summaries=true" in cmd
        assert not any("model_provider" in arg for arg in cmd)

    def test_allowlisted_key_with_injection_value_rejected(self):
        # sprint-bug-214 audit (cross-model DISS): an allowlisted key carrying a
        # TOML/newline injection value must NOT reach argv — the smuggled second
        # assignment (sandbox_mode) must never appear.
        cmd = self._cmd_with_overrides(
            {"reasoning_summaries": 'true\nsandbox_mode="danger-full-access"'}
        )
        assert not any("sandbox_mode" in arg for arg in cmd)
        assert not any("danger-full-access" in arg for arg in cmd)
        assert not any("reasoning_summaries=true\n" in arg for arg in cmd)

    def test_allowlisted_key_safe_scalar_value_passes(self):
        # Sanity: a normal scalar value still passes after value-charset hardening.
        cmd = self._cmd_with_overrides({"model_verbosity": "high"})
        assert "model_verbosity=high" in cmd


# ---------------------------------------------------------------------------
# #1008 finding 3 — sanitize codex stderr before embedding in exceptions
#
# Both the auth (ConfigError) and generic (ProviderUnavailableError) branches
# embedded up to 300-500 chars of raw stderr, which can carry prompt fragments,
# paths, or account/secret tokens into caller-visible error output.
# ---------------------------------------------------------------------------


class TestStderrSanitization:
    def test_generic_failure_redacts_secret_in_stderr(self):
        adapter = CodexHeadlessAdapter(_make_config())
        secret = "sk-proj-abcdEFGH1234ijklMNOP5678qrstUVWX"
        with patch(
            "loa_cheval.providers.codex_headless_adapter.run_subprocess_pgkill"
        ) as mock_run:
            mock_run.return_value = _fail_proc(2, f"boom leaked {secret} in trace")
            with pytest.raises(ProviderUnavailableError) as exc_info:
                adapter.complete(_make_request())
        msg = str(exc_info.value)
        assert secret not in msg
        assert "[REDACTED" in msg

    def test_auth_failure_redacts_secret_in_stderr(self):
        adapter = CodexHeadlessAdapter(_make_config())
        secret = "sk-proj-abcdEFGH1234ijklMNOP5678qrstUVWX"
        with patch(
            "loa_cheval.providers.codex_headless_adapter.run_subprocess_pgkill"
        ) as mock_run:
            mock_run.return_value = _fail_proc(
                1, f"Error: not authenticated; token {secret}; run codex login"
            )
            with pytest.raises(ConfigError) as exc_info:
                adapter.complete(_make_request())
        msg = str(exc_info.value)
        assert secret not in msg
        # Actionable guidance is preserved even after redaction.
        assert "codex login" in msg

    def test_sanitize_then_truncate_no_prefix_leak(self):
        # A secret near the 300/500-char truncation boundary must not survive as
        # a leaked prefix: sanitize happens BEFORE truncation.
        adapter = CodexHeadlessAdapter(_make_config())
        secret = "sk-proj-" + "Z" * 60
        padding = "x" * 470
        with patch(
            "loa_cheval.providers.codex_headless_adapter.run_subprocess_pgkill"
        ) as mock_run:
            mock_run.return_value = _fail_proc(2, padding + secret)
            with pytest.raises(ProviderUnavailableError) as exc_info:
                adapter.complete(_make_request())
        msg = str(exc_info.value)
        assert "sk-proj-ZZZ" not in msg


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
