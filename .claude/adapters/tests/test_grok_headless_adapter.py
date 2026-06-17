"""Tests for grok-headless provider adapter (xAI Grok Build CLI).

Covers:
  - registry dispatch on type='grok-headless'
  - command construction (--prompt-file, --output-format json, --model/cli_model,
    --no-plan, --no-subagents, --disable-web-search, --max-turns 1,
    --permission-mode dontAsk, --reasoning-effort, GROK_HEADLESS_BIN override)
  - BOTH models on one port: grok-build + grok-composer-2.5-fast (cli_model)
  - single-JSON output parsing (text→content, thought→thinking, sessionId→
    interaction_id, estimated usage), incl. grok's pretty-printed multi-line JSON
  - the stderr-noise contract: rc==0 + valid envelope + stderr carrying
    "Auth(AuthorizationRequired)" / MCP-spawn noise is a SUCCESS, never an error
  - empty-text-as-success (peer parity)
  - error classification (rate-limit, auth login-action phrases, generic nonzero,
    timeout, output-cap, spawn OSError, semaphore exhaustion, missing CLI, no-JSON)
  - prompt rides --prompt-file (a file in the isolated workspace), NEVER argv
  - substrate wiring: auth_type=headless, isolated cwd, registry kind:cli admission,
    loader inference entry
  - validate_config + health_check

Live test (real grok invocation) is gated behind LOA_GROK_HEADLESS_LIVE=1 to keep
CI deterministic. Run locally (needs an xAI/Grok subscription + `grok login`):
    LOA_GROK_HEADLESS_LIVE=1 pytest tests/test_grok_headless_adapter.py -k live
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
from loa_cheval.providers.grok_headless_adapter import GrokHeadlessAdapter
from loa_cheval.types import (
    CompletionRequest,
    ConfigError,
    ModelConfig,
    ProviderConfig,
    ProviderUnavailableError,
    RateLimitError,
)

# The subprocess seam to mock is the pgkill helper import in the adapter module.
_PGKILL = "loa_cheval.providers.grok_headless_adapter.run_subprocess_pgkill"
_WHICH = "loa_cheval.providers.grok_headless_adapter.shutil.which"


# ---------------------------------------------------------------------------
# Fixtures / helpers
# ---------------------------------------------------------------------------

def _cfg(**models) -> ProviderConfig:
    return ProviderConfig(
        name="xai",
        type="grok-headless",
        endpoint="",
        auth=None,
        models=models
        or {"grok-build": ModelConfig(context_window=256000, extra={"cli_model": "grok-build"})},
    )


def _adapter(**models) -> GrokHeadlessAdapter:
    return get_adapter(_cfg(**models))  # type: ignore[return-value]


def _completed(stdout: str = "", stderr: str = "", returncode: int = 0) -> subprocess.CompletedProcess:
    """A run_subprocess_pgkill result: CompletedProcess[str]."""
    return subprocess.CompletedProcess(["grok"], returncode, stdout, stderr)


def _req(content: str = "review this", model: str = "grok-build") -> CompletionRequest:
    return CompletionRequest(messages=[{"role": "user", "content": content}], model=model, max_tokens=200)


# grok's actual (pretty-printed, multi-line) single-object envelope.
_OK_ENVELOPE = (
    "{\n"
    '  "text": "PONG",\n'
    '  "stopReason": "EndTurn",\n'
    '  "sessionId": "sess-1",\n'
    '  "requestId": "req-1",\n'
    '  "thought": "the user wants PONG"\n'
    "}"
)

# The non-fatal noise grok emits on EVERY call (operator MCP workers).
_STDERR_NOISE = (
    "ERROR Failed to spawn MCP server 'Playwright': No such file or directory\n"
    "ERROR worker quit with fatal: Transport channel closed, when Auth(AuthorizationRequired)\n"
)


# ---------------------------------------------------------------------------
# Registry dispatch
# ---------------------------------------------------------------------------

class TestRegistryDispatch:
    def test_type_resolves_to_grok_adapter(self):
        assert isinstance(_adapter(), GrokHeadlessAdapter)

    def test_provider_name_set(self):
        assert _adapter().provider == "xai"


# ---------------------------------------------------------------------------
# Command construction
# ---------------------------------------------------------------------------

class TestCommandConstruction:
    def test_pure_inference_flags(self):
        cmd = _adapter()._build_command(_req(), ModelConfig(extra={"cli_model": "grok-build"}), "/tmp/p.txt")
        assert "--prompt-file" in cmd and cmd[cmd.index("--prompt-file") + 1] == "/tmp/p.txt"
        assert "--output-format" in cmd and cmd[cmd.index("--output-format") + 1] == "json"
        assert "--no-plan" in cmd
        assert "--no-subagents" in cmd
        assert "--disable-web-search" in cmd
        assert "--max-turns" in cmd and cmd[cmd.index("--max-turns") + 1] == "1"
        assert "--permission-mode" in cmd and cmd[cmd.index("--permission-mode") + 1] == "dontAsk"
        # NEVER force-approve tools.
        assert "--always-approve" not in cmd and "bypassPermissions" not in cmd

    def test_cli_model_grok_build(self):
        mc = ModelConfig(extra={"cli_model": "grok-build"})
        cmd = _adapter()._build_command(_req(model="alias"), mc, "/tmp/p.txt")
        assert cmd[cmd.index("--model") + 1] == "grok-build"

    def test_cli_model_grok_composer(self):
        # The SECOND model on the same port.
        mc = ModelConfig(extra={"cli_model": "grok-composer-2.5-fast"})
        cmd = _adapter()._build_command(_req(model="grok-fast"), mc, "/tmp/p.txt")
        assert cmd[cmd.index("--model") + 1] == "grok-composer-2.5-fast"

    def test_cli_model_falls_back_to_request_model(self):
        cmd = _adapter()._build_command(_req(model="grok-build"), ModelConfig(), "/tmp/p.txt")
        assert cmd[cmd.index("--model") + 1] == "grok-build"

    def test_reasoning_effort_from_extra(self):
        mc = ModelConfig(extra={"cli_model": "grok-build", "reasoning_effort": "high"})
        cmd = _adapter()._build_command(_req(), mc, "/tmp/p.txt")
        assert cmd[cmd.index("--reasoning-effort") + 1] == "high"

    def test_reasoning_effort_per_call_override(self):
        req = CompletionRequest(
            messages=[{"role": "user", "content": "x"}],
            model="grok-build",
            max_tokens=200,
            metadata={"reasoning_effort": "max"},
        )
        mc = ModelConfig(extra={"cli_model": "grok-build", "reasoning_effort": "low"})
        cmd = _adapter()._build_command(req, mc, "/tmp/p.txt")
        assert cmd[cmd.index("--reasoning-effort") + 1] == "max"

    def test_unknown_reasoning_effort_dropped(self):
        mc = ModelConfig(extra={"cli_model": "grok-build", "reasoning_effort": "ultra"})
        cmd = _adapter()._build_command(_req(), mc, "/tmp/p.txt")
        assert "--reasoning-effort" not in cmd

    def test_bin_override_env(self, monkeypatch):
        monkeypatch.setenv("GROK_HEADLESS_BIN", "/opt/grok")
        cmd = _adapter()._build_command(_req(), ModelConfig(), "/tmp/p.txt")
        assert cmd[0] == "/opt/grok"


# ---------------------------------------------------------------------------
# Prompt flattening
# ---------------------------------------------------------------------------

class TestPromptFlattening:
    def test_roles_prefixed(self):
        out = _adapter()._build_prompt([
            {"role": "system", "content": "be strict"},
            {"role": "user", "content": "the diff"},
        ])
        assert "## System" in out and "be strict" in out
        assert "## User" in out and "the diff" in out

    def test_list_content_blocks(self):
        out = _adapter()._build_prompt([{"role": "user", "content": [{"text": "block-a"}, {"text": "block-b"}]}])
        assert "block-a" in out and "block-b" in out


# ---------------------------------------------------------------------------
# Output parsing
# ---------------------------------------------------------------------------

class TestOutputParsing:
    def test_success_envelope(self):
        with patch(_PGKILL, return_value=_completed(_OK_ENVELOPE)):
            r = _adapter().complete(_req())
        assert r.content == "PONG"
        assert r.thinking == "the user wants PONG"
        assert r.usage.source == "estimated"
        assert r.usage.input_tokens > 0
        assert r.model == "grok-build"            # falls back to requested
        assert r.provider == "xai"
        assert r.interaction_id == "sess-1"

    def test_preamble_before_envelope_still_parses(self):
        out = "(node) ExperimentalWarning: glob\n" + _OK_ENVELOPE
        with patch(_PGKILL, return_value=_completed(out)):
            r = _adapter().complete(_req())
        assert r.content == "PONG"

    def test_json_log_line_does_not_shadow_envelope(self):
        out = '{"level":"warn","msg":"slow start"}\n' + _OK_ENVELOPE
        with patch(_PGKILL, return_value=_completed(out)):
            r = _adapter().complete(_req())
        assert r.content == "PONG"

    def test_empty_text_is_success(self):
        env = '{"text":"","stopReason":"EndTurn","sessionId":"s2"}'
        with patch(_PGKILL, return_value=_completed(env)):
            r = _adapter().complete(_req())
        assert r.content == ""
        assert r.interaction_id == "s2"

    def test_text_carrying_preamble_does_not_shadow_envelope(self):
        # BB #1057 (F4): a JSON preamble/log line that carries a "text" key but
        # NO stable identifier must not be mistaken for the result envelope.
        # The old `"text" in obj or "stopReason" in obj` gate would have shadowed.
        out = '{"text":"booting model grok-build..."}\n' + _OK_ENVELOPE
        with patch(_PGKILL, return_value=_completed(out)):
            r = _adapter().complete(_req())
        assert r.content == "PONG"            # the real envelope, not the preamble
        assert r.interaction_id == "sess-1"

    def test_non_string_session_id_falls_back_to_request_id(self):
        # BB #1057 (low-001/002): a numeric sessionId must not leak a non-string
        # interaction_id — prefer sessionId (str), else the requestId fallback.
        env = ('{"text":"PONG","stopReason":"EndTurn",'
               '"sessionId":12345,"requestId":"req-9"}')
        with patch(_PGKILL, return_value=_completed(env)):
            r = _adapter().complete(_req())
        assert r.interaction_id == "req-9"
        assert r.content == "PONG"

    def test_null_ids_normalize_interaction_id_to_none(self):
        env = ('{"text":"PONG","stopReason":"EndTurn",'
               '"sessionId":null,"requestId":null}')
        with patch(_PGKILL, return_value=_completed(env)):
            r = _adapter().complete(_req())
        assert r.interaction_id is None
        assert r.content == "PONG"


# ---------------------------------------------------------------------------
# The stderr-noise contract (the misclassification trap)
# ---------------------------------------------------------------------------

class TestStderrNoiseSafety:
    def test_authorizationrequired_noise_is_not_a_failure(self):
        # rc==0 + valid envelope + the standard MCP-worker
        # "Auth(AuthorizationRequired)" noise on stderr → SUCCESS, never ConfigError.
        with patch(_PGKILL, return_value=_completed(_OK_ENVELOPE, stderr=_STDERR_NOISE)):
            r = _adapter().complete(_req())
        assert r.content == "PONG"

    def test_review_quoting_error_tokens_not_misclassified(self):
        # A successful review whose ANSWER discusses rate-limit/auth tokens must be
        # returned as content — the success path never scans for error tokens.
        env = (
            '{"text":"finding: handle 429 / rate limit / unauthorized / '
            'resource_exhausted in auth.ts","stopReason":"EndTurn","sessionId":"s3"}'
        )
        with patch(_PGKILL, return_value=_completed(env, stderr=_STDERR_NOISE)):
            r = _adapter().complete(_req())
        assert "429" in r.content and "unauthorized" in r.content  # returned, not raised


# ---------------------------------------------------------------------------
# Error classification (no valid envelope OR non-zero exit)
# ---------------------------------------------------------------------------

class TestErrorClassification:
    def test_rate_limit_429_standalone(self):
        with patch(_PGKILL, return_value=_completed("", stderr="HTTP 429 from upstream", returncode=1)):
            with pytest.raises(RateLimitError):
                _adapter().complete(_req())

    def test_rate_limit_resource_exhausted(self):
        with patch(_PGKILL, return_value=_completed("error: resource_exhausted", returncode=1)):
            with pytest.raises(RateLimitError):
                _adapter().complete(_req())

    def test_rate_limit_quota(self):
        with patch(_PGKILL, return_value=_completed("", stderr="subscription quota exceeded", returncode=1)):
            with pytest.raises(RateLimitError):
                _adapter().complete(_req())

    def test_auth_not_logged_in(self):
        with patch(_PGKILL, return_value=_completed("", stderr="Not logged in. Run grok login.", returncode=1)):
            with pytest.raises(ConfigError):
                _adapter().complete(_req())

    def test_authorizationrequired_alone_is_not_configerror(self):
        # The bare MCP-noise token must NOT classify as auth failure — only the
        # login-action phrases do. A non-zero exit carrying ONLY the noise is a
        # generic unavailable (chain advances), not a misfired ConfigError.
        with patch(_PGKILL, return_value=_completed("", stderr=_STDERR_NOISE, returncode=1)):
            with pytest.raises(ProviderUnavailableError):
                _adapter().complete(_req())

    def test_generic_nonzero_is_unavailable(self):
        with patch(_PGKILL, return_value=_completed("", stderr="weird failure", returncode=2)):
            with pytest.raises(ProviderUnavailableError):
                _adapter().complete(_req())

    def test_no_parseable_json_on_exit0_is_unavailable(self):
        with patch(_PGKILL, return_value=_completed("not json at all", returncode=0)):
            with pytest.raises(ProviderUnavailableError, match="no parseable JSON"):
                _adapter().complete(_req())

    def test_timeout_raises_unavailable(self):
        with patch(_PGKILL, side_effect=subprocess.TimeoutExpired(cmd=["grok"], timeout=5)):
            with pytest.raises(ProviderUnavailableError, match="timed out"):
                _adapter().complete(_req())

    def test_output_cap_exceeded_is_unavailable(self):
        from loa_cheval.providers.base import SubprocessOutputCapExceeded
        with patch(_PGKILL, side_effect=SubprocessOutputCapExceeded("stdout exceeded the 10485760-byte cap")):
            with pytest.raises(ProviderUnavailableError, match="cap"):
                _adapter().complete(_req())

    def test_missing_cli_is_configerror(self):
        with patch(_PGKILL, side_effect=FileNotFoundError("grok: not found")):
            with pytest.raises(ConfigError):
                _adapter().complete(_req())

    def test_spawn_oserror_is_unavailable(self):
        with patch(_PGKILL, side_effect=PermissionError("exec not permitted")):
            with pytest.raises(ProviderUnavailableError, match="failed to spawn"):
                _adapter().complete(_req())

    def test_semaphore_exhausted_is_chain_exhausted_concurrency(self):
        from loa_cheval.adapters.headless_concurrency import SemaphoreExhausted
        with patch(
            "loa_cheval.adapters.headless_concurrency.acquire_slot",
            side_effect=SemaphoreExhausted("grok-headless", 50, 30.0),
        ):
            with pytest.raises(ProviderUnavailableError, match=r"\[CHAIN-EXHAUSTED-CONCURRENCY\]"):
                _adapter().complete(_req())


# ---------------------------------------------------------------------------
# Prompt rides --prompt-file, never argv
# ---------------------------------------------------------------------------

class TestPromptViaFile:
    def _read_prompt_file(self, pg_mock) -> str:
        argv = pg_mock.call_args.args[0]
        path = argv[argv.index("--prompt-file") + 1]
        return Path(path).read_text(encoding="utf-8")

    def test_prompt_not_in_argv_and_in_file(self):
        captured = {}

        def _side(cmd, **kwargs):
            path = cmd[cmd.index("--prompt-file") + 1]
            captured["content"] = Path(path).read_text(encoding="utf-8")
            return _completed(_OK_ENVELOPE)

        with patch(_PGKILL, side_effect=_side) as pg:
            _adapter().complete(_req("--always-approve injected"))
        argv = pg.call_args.args[0]
        assert not any("--always-approve injected" in a for a in argv)
        assert "--always-approve injected" in captured["content"]

    def test_large_prompt_keeps_argv_small(self):
        # ARG_MAX regression: a large prompt must not appear in argv.
        big = "x" * 500_000
        captured = {}

        def _side(cmd, **kwargs):
            path = cmd[cmd.index("--prompt-file") + 1]
            captured["content"] = Path(path).read_text(encoding="utf-8")
            return _completed(_OK_ENVELOPE)

        with patch(_PGKILL, side_effect=_side) as pg:
            _adapter().complete(_req(big))
        argv = pg.call_args.args[0]
        assert sum(len(a) for a in argv) < 10_000
        assert big in captured["content"]


# ---------------------------------------------------------------------------
# Substrate wiring
# ---------------------------------------------------------------------------

class TestSubstrateWiring:
    def test_auth_type_is_headless(self):
        assert GrokHeadlessAdapter.auth_type == "headless"

    def test_pgkill_called_with_isolated_workspace_cwd(self):
        with patch(_PGKILL, return_value=_completed(_OK_ENVELOPE)) as pg:
            _adapter().complete(_req())
        kwargs = pg.call_args.kwargs
        assert "loa-grok-ws-" in (kwargs.get("cwd") or "")

    def test_cli_adapter_types_includes_grok(self):
        from loa_cheval.providers import cli_adapter_types
        assert "grok-headless" in cli_adapter_types()

    def test_cli_adapter_types_covers_all_peers(self):
        from loa_cheval.providers import cli_adapter_types
        assert cli_adapter_types() >= {
            "claude-headless",
            "codex-headless",
            "gemini-headless",
            "cursor-headless",
            "grok-headless",
        }

    def test_headless_inference_covers_grok(self):
        # config loader stamps auth_type/dispatch_group/kind so the minimal
        # documented xai provider shape loads (no [CONFIG-INVALID]).
        from loa_cheval.config.loader import _HEADLESS_TYPE_INFERENCE
        auth, group = _HEADLESS_TYPE_INFERENCE["grok-headless"]
        assert auth == "headless" and group == "xai-grok"


# ---------------------------------------------------------------------------
# validate_config + health_check
# ---------------------------------------------------------------------------

class TestValidateAndHealth:
    def test_validate_ok(self):
        with patch(_WHICH, return_value="/usr/local/bin/grok"):
            assert _adapter().validate_config() == []

    def test_validate_missing_cli(self):
        with patch(_WHICH, return_value=None):
            errs = _adapter().validate_config()
            assert any("not found on PATH" in e for e in errs)

    def test_validate_wrong_type(self):
        cfg = ProviderConfig(name="x", type="not-grok", endpoint="", auth=None,
                             models={"grok-build": ModelConfig()})
        a = GrokHeadlessAdapter(cfg)
        with patch(_WHICH, return_value="/usr/local/bin/grok"):
            assert any("must be 'grok-headless'" in e for e in a.validate_config())

    def test_health_check_true(self):
        with patch(_WHICH, return_value="/usr/local/bin/grok"), \
             patch("loa_cheval.providers.grok_headless_adapter.subprocess.run") as run:
            run.return_value = MagicMock(returncode=0)
            assert _adapter().health_check() is True

    def test_health_check_missing_cli(self):
        with patch(_WHICH, return_value=None):
            assert _adapter().health_check() is False


# ---------------------------------------------------------------------------
# Live (gated)
# ---------------------------------------------------------------------------

@pytest.mark.skipif(
    os.environ.get("LOA_GROK_HEADLESS_LIVE") != "1",
    reason="set LOA_GROK_HEADLESS_LIVE=1 (needs an xAI/Grok subscription + grok login)",
)
def test_live_complete():
    r = _adapter().complete(_req("Reply with ONLY the word PONG"))
    assert r.provider == "xai"
    assert r.content


# ---------------------------------------------------------------------------
# Subprocess env filter — xAI/Grok auth-key stripping (#1057 review gap)
# ---------------------------------------------------------------------------
# grok persists OIDC auth in ~/.grok/auth.json; an xAI API-key env in the parent
# process flips the CLI off that OAuth path. base._HEADLESS_STRIPPED_AUTH_VARS
# appends XAI_API_KEY / GROK_CODE_XAI_API_KEY / GROK_API_KEY, but no test pinned
# that the grok-specific keys are actually stripped (only the Google keys were
# covered, in test_gemini_headless_adapter.py). This closes that gap so a future
# base.py refactor can't silently drop a grok var. Mirrors the gemini coverage.


class TestSubprocessEnvFilter:
    def test_xai_grok_keys_stripped_by_default(self, monkeypatch):
        monkeypatch.setenv("XAI_API_KEY", "test-xai-key")
        monkeypatch.setenv("GROK_CODE_XAI_API_KEY", "test-grok-code-key")
        monkeypatch.setenv("GROK_API_KEY", "test-grok-key")
        monkeypatch.delenv("LOA_HEADLESS_KEEP_API_KEY", raising=False)
        with patch(_PGKILL) as mock_run:
            mock_run.return_value = _completed(_OK_ENVELOPE)
            _adapter().complete(_req())
        kwargs = mock_run.call_args.kwargs
        assert "env" in kwargs, "subprocess.run must pass explicit env="
        assert "XAI_API_KEY" not in kwargs["env"]
        assert "GROK_CODE_XAI_API_KEY" not in kwargs["env"]
        assert "GROK_API_KEY" not in kwargs["env"]
