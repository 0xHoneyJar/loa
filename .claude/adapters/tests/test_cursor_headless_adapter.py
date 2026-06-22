"""Tests for cursor-headless provider adapter.

Covers:
  - registry dispatch on type='cursor-headless'
  - command construction (model, --mode plan, --sandbox enabled, --trust, no -f, cli_model)
  - single-JSON output parsing (result content, usage, session_id, model fallback)
  - error classification (resource_exhausted on exit-0, auth, is_error, generic, timeout,
    output-cap, spawn OSError, semaphore exhaustion, missing CLI)
  - transport-probe safety: a successful review whose `result` quotes 429/unauthorized
    is NOT misclassified as a transport failure (the silencing-attack regression)
  - Bundle-E substrate wiring (review #966): auth_type=headless, pgkill cwd=workspace,
    `--` option terminator, registry-derived kind:cli admission, loader inference entry
  - validate_config + health_check
  - prompt flattening (system / user / assistant / tool / list-content)

Live test (real cursor-agent invocation) is gated behind LOA_CURSOR_HEADLESS_LIVE=1
to keep CI deterministic. Run locally (needs Cursor Pro + cursor-agent login):
    LOA_CURSOR_HEADLESS_LIVE=1 pytest tests/test_cursor_headless_adapter.py -k live
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
from loa_cheval.providers.cursor_headless_adapter import CursorHeadlessAdapter
from loa_cheval.types import (
    CompletionRequest,
    AuthRevokedError,
    ConfigError,
    ModelConfig,
    ProviderConfig,
    ProviderUnavailableError,
    RateLimitError,
)

# Review #966: the adapter dispatches through run_subprocess_pgkill (#982
# shared helper) — the subprocess seam to mock is the helper import in the
# adapter module, not subprocess.Popen. Process-group kill + output-cap
# mechanics are covered by the helper's own tests.
_PGKILL = "loa_cheval.providers.cursor_headless_adapter.run_subprocess_pgkill"
_WHICH = "loa_cheval.providers.cursor_headless_adapter.shutil.which"


# ---------------------------------------------------------------------------
# Fixtures / helpers
# ---------------------------------------------------------------------------

def _cfg(**models) -> ProviderConfig:
    return ProviderConfig(
        name="cursor-headless",
        type="cursor-headless",
        endpoint="",
        auth=None,
        models=models or {"composer-2.5": ModelConfig(context_window=200000)},
    )


def _adapter(**models) -> CursorHeadlessAdapter:
    return get_adapter(_cfg(**models))  # type: ignore[return-value]


def _completed(stdout: str = "", stderr: str = "", returncode: int = 0) -> subprocess.CompletedProcess:
    """A run_subprocess_pgkill result: CompletedProcess[str]."""
    return subprocess.CompletedProcess(["cursor-agent"], returncode, stdout, stderr)


def _req(content: str = "review this", model: str = "composer-2.5") -> CompletionRequest:
    return CompletionRequest(messages=[{"role": "user", "content": content}], model=model, max_tokens=200)


_OK_ENVELOPE = (
    '{"type":"result","subtype":"success","is_error":false,'
    '"result":"{\\"verdict\\":\\"APPROVED\\"}","session_id":"sess-1",'
    '"usage":{"inputTokens":120,"outputTokens":18,"cacheReadTokens":3,"cacheWriteTokens":0}}'
)


# ---------------------------------------------------------------------------
# Registry dispatch
# ---------------------------------------------------------------------------

class TestRegistryDispatch:
    def test_type_resolves_to_cursor_adapter(self):
        assert isinstance(_adapter(), CursorHeadlessAdapter)

    def test_provider_name_set(self):
        assert _adapter().provider == "cursor-headless"


# ---------------------------------------------------------------------------
# Command construction
# ---------------------------------------------------------------------------

class TestCommandConstruction:
    def test_readonly_sandboxed_no_force(self):
        cmd = _adapter()._build_command(_req(), ModelConfig(context_window=200000))
        assert "--mode" in cmd and cmd[cmd.index("--mode") + 1] == "plan"
        assert "--sandbox" in cmd and cmd[cmd.index("--sandbox") + 1] == "enabled"
        assert "--trust" in cmd
        assert "-f" not in cmd and "--force" not in cmd and "--yolo" not in cmd
        assert "--output-format" in cmd and cmd[cmd.index("--output-format") + 1] == "json"

    def test_model_passed(self):
        cmd = _adapter()._build_command(_req(model="composer-2.5"), ModelConfig())
        assert cmd[cmd.index("--model") + 1] == "composer-2.5"

    def test_cli_model_override(self):
        mc = ModelConfig(extra={"cli_model": "composer-2.5-real"})
        cmd = _adapter()._build_command(_req(model="alias"), mc)
        assert cmd[cmd.index("--model") + 1] == "composer-2.5-real"

    def test_bin_override_env(self, monkeypatch):
        monkeypatch.setenv("CURSOR_HEADLESS_BIN", "/opt/cursor-agent")
        cmd = _adapter()._build_command(_req(), ModelConfig())
        assert cmd[0] == "/opt/cursor-agent"


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
        assert r.content == '{"verdict":"APPROVED"}'
        assert r.usage.input_tokens == 120 and r.usage.output_tokens == 18
        assert r.usage.source == "actual"
        assert r.model == "composer-2.5"          # falls back to requested
        assert r.provider == "cursor-headless"
        assert r.interaction_id == "sess-1"

    def test_model_field_when_present(self):
        env = _OK_ENVELOPE.replace('"session_id"', '"model":"composer-2.5-x","session_id"')
        with patch(_PGKILL, return_value=_completed(env)):
            r = _adapter().complete(_req())
        assert r.model == "composer-2.5-x"

    def test_malformed_usage_does_not_crash(self):
        env = ('{"type":"result","is_error":false,"result":"ok",'
               '"usage":{"inputTokens":"oops","outputTokens":null}}')
        with patch(_PGKILL, return_value=_completed(env)):
            r = _adapter().complete(_req())
        assert r.usage.input_tokens == 0 and r.usage.output_tokens == 0


# ---------------------------------------------------------------------------
# Transport-probe safety (the silencing-attack regression)
# ---------------------------------------------------------------------------

class TestTransportProbeSafety:
    def test_result_quoting_error_tokens_not_misclassified(self):
        # A SUCCESSFUL review whose result discusses rate-limit/auth code must be
        # returned as content — never raised as RateLimitError/ConfigError.
        env = (
            '{"type":"result","is_error":false,'
            '"result":"finding: handle 429 / rate limit / unauthorized / resource_exhausted in auth.ts",'
            '"usage":{"inputTokens":10,"outputTokens":5}}'
        )
        with patch(_PGKILL, return_value=_completed(env)):
            r = _adapter().complete(_req())
        assert "429" in r.content and "unauthorized" in r.content  # returned, not raised

    def test_success_meta_429_not_misclassified(self):
        # BB #966 round-2 (HIGH, 2-voice converged): usage token counts and
        # session ids containing "429" as a substring must not classify a
        # billed success as RateLimitError.
        env = (
            '{"type":"result","is_error":false,"result":"ok",'
            '"session_id":"sess-429abc","request_id":"req-14290",'
            '"usage":{"inputTokens":14290,"outputTokens":429}}'
        )
        with patch(_PGKILL, return_value=_completed(env)):
            r = _adapter().complete(_req())
        assert r.content == "ok"
        assert r.usage.input_tokens == 14290 and r.usage.output_tokens == 429

    def test_error_meta_429_with_benign_result_not_ratelimit(self):
        # On is_error, only subtype/result/stderr classify — 429-bearing usage
        # must not turn an unrecognized failure into RateLimitError.
        env = (
            '{"type":"result","is_error":true,"result":"boom",'
            '"usage":{"inputTokens":4290,"outputTokens":1}}'
        )
        with patch(_PGKILL, return_value=_completed(env)):
            with pytest.raises(ProviderUnavailableError, match="reported is_error"):
                _adapter().complete(_req())

    def test_preamble_success_still_parses(self):
        # BB #966 round-2 (MEDIUM): a non-JSON stdout preamble (node warnings)
        # must not turn a billed success into ProviderUnavailableError.
        out = "(node:123) ExperimentalWarning: glob is experimental\n" + _OK_ENVELOPE
        with patch(_PGKILL, return_value=_completed(out)):
            r = _adapter().complete(_req())
        assert r.content == '{"verdict":"APPROVED"}'

    def test_preamble_does_not_reopen_silencing_channel(self):
        # BB #966 round-2 (MEDIUM): with a preamble, the probe must STILL mask
        # the untrusted result — error tokens quoted in a successful review must
        # not raise (the CURSOR-001 regression at the preamble level).
        env = (
            '{"type":"result","is_error":false,'
            '"result":"finding: 429 unauthorized rate limit resource_exhausted",'
            '"usage":{"inputTokens":10,"outputTokens":5}}'
        )
        out = "DeprecationWarning: punycode\n" + env
        with patch(_PGKILL, return_value=_completed(out)):
            r = _adapter().complete(_req())
        assert "429" in r.content  # returned as content, not raised

    def test_stderr_digit_runs_not_misclassified(self):
        # BB #966 round-3 (HIGH): stderr is probe surface even on success —
        # incidental digit runs containing 429 ("14290ms") must not classify
        # a billed success as rate-limited. Standalone 429 still does.
        with patch(_PGKILL, return_value=_completed(_OK_ENVELOPE, stderr="request took 14290ms (id 84293)")):
            r = _adapter().complete(_req())
        assert r.content == '{"verdict":"APPROVED"}'

    def test_standalone_429_in_stderr_still_ratelimit(self):
        with patch(_PGKILL, return_value=_completed(_OK_ENVELOPE, stderr="HTTP 429 from upstream")):
            with pytest.raises(RateLimitError):
                _adapter().complete(_req())

    def test_json_log_line_does_not_shadow_envelope(self):
        # BB #966 round-3 (MEDIUM): a JSON-formatted log line before the result
        # envelope must not be picked as the envelope.
        out = '{"level":"warn","msg":"slow start"}\n' + _OK_ENVELOPE
        with patch(_PGKILL, return_value=_completed(out)):
            r = _adapter().complete(_req())
        assert r.content == '{"verdict":"APPROVED"}'
        assert r.usage.input_tokens == 120

    def test_log_line_only_stdout_is_failure_not_empty_success(self):
        # BB #966 round-4 (MEDIUM): stdout containing ONLY a non-envelope JSON
        # dict must classify as no-parseable-envelope (chain advances), never
        # as a silent EMPTY success.
        out = '{"level":"error","msg":"something broke"}'
        with patch(_PGKILL, return_value=_completed(out)):
            with pytest.raises(ProviderUnavailableError, match="no parseable JSON"):
                _adapter().complete(_req())

    def test_stderr_429ms_not_misclassified(self):
        # BB #966 round-4: alphanumeric-adjacent runs ("429ms") must not
        # rate-limit-classify a billed success; standalone 429 still does.
        with patch(_PGKILL, return_value=_completed(_OK_ENVELOPE, stderr="warmup took 429ms")):
            r = _adapter().complete(_req())
        assert r.content == '{"verdict":"APPROVED"}'


# ---------------------------------------------------------------------------
# Error classification
# ---------------------------------------------------------------------------

class TestErrorClassification:
    def test_resource_exhausted_on_exit0_is_ratelimit(self):
        # cursor surfaces transport errors on stdout WITH a zero exit code (non-JSON).
        with patch(_PGKILL, return_value=_completed("ConnectError: [resource_exhausted] Error", returncode=0)):
            with pytest.raises(RateLimitError):
                _adapter().complete(_req())

    def test_not_logged_in_is_configerror(self):
        with patch(_PGKILL, return_value=_completed("", stderr="Not logged in", returncode=1)):
            with pytest.raises(ConfigError):
                _adapter().complete(_req())

    def test_runtime_token_revocation_raises_auth_revoked(self):
        # KF-017/#1071: server-invalidated token → WALKABLE (AuthRevokedError).
        with patch(_PGKILL, return_value=_completed("", stderr="401 Unauthorized: session expired", returncode=1)):
            with pytest.raises(AuthRevokedError) as exc_info:
                _adapter().complete(_req())
            assert exc_info.value.code == "AUTH_REVOKED"

    def test_ambiguous_unauthorized_with_static_marker_still_config_error(self):
        # #1095 safety: "unauthorized" + a not-logged-in marker → ConfigError.
        with patch(_PGKILL, return_value=_completed("", stderr="unauthorized — please log in", returncode=1)):
            with pytest.raises(ConfigError):
                _adapter().complete(_req())

    def test_is_error_true_generic_raises_unavailable(self):
        # is_error with no recognized token → generic ProviderUnavailableError.
        with patch(_PGKILL, return_value=_completed('{"type":"result","is_error":true,"result":"boom"}')):
            with pytest.raises(ProviderUnavailableError):
                _adapter().complete(_req())

    def test_is_error_with_result_resource_exhausted_is_ratelimit(self):
        # CURSOR-001: on is_error, the diagnostic lives in `result` (cursor's own
        # message) and MUST be classified — not stripped as if it were untrusted output.
        env = '{"type":"result","is_error":true,"result":"ConnectError: [resource_exhausted]"}'
        with patch(_PGKILL, return_value=_completed(env)):
            with pytest.raises(RateLimitError):
                _adapter().complete(_req())

    def test_is_error_with_result_unauthorized_is_configerror(self):
        # CURSOR-001 (auth half): an auth failure delivered via the error envelope
        # must classify as ConfigError, not collapse into a retryable generic outage.
        env = '{"type":"result","is_error":true,"result":"unauthorized — please log in"}'
        with patch(_PGKILL, return_value=_completed(env)):
            with pytest.raises(ConfigError):
                _adapter().complete(_req())

    def test_is_error_auth_diagnostic_preserved_from_stdout(self):
        # BB #966 round-2 (LOW): the ConfigError must carry the diagnostic even
        # when it arrived on stdout (is_error result) and stderr is empty.
        env = '{"type":"result","is_error":true,"result":"unauthorized — please log in"}'
        with patch(_PGKILL, return_value=_completed(env)):
            with pytest.raises(ConfigError, match="unauthorized"):
                _adapter().complete(_req())

    def test_generic_nonzero_is_unavailable(self):
        with patch(_PGKILL, return_value=_completed("", stderr="weird failure", returncode=2)):
            with pytest.raises(ProviderUnavailableError):
                _adapter().complete(_req())

    def test_timeout_raises_unavailable(self):
        # Process-group SIGKILL on timeout now lives inside run_subprocess_pgkill
        # (covered by the helper's own tests); the adapter contract is the
        # chain-advancing ProviderUnavailableError.
        with patch(_PGKILL, side_effect=subprocess.TimeoutExpired(cmd=["cursor-agent"], timeout=5)):
            with pytest.raises(ProviderUnavailableError, match="timed out"):
                _adapter().complete(_req())

    def test_output_cap_exceeded_is_unavailable(self):
        # Review #966: truncated output must never masquerade as success —
        # the cap raises and the chain advances like a timeout.
        from loa_cheval.providers.base import SubprocessOutputCapExceeded
        with patch(_PGKILL, side_effect=SubprocessOutputCapExceeded("stdout exceeded the 10485760-byte cap")):
            with pytest.raises(ProviderUnavailableError, match="cap"):
                _adapter().complete(_req())

    def test_missing_cli_is_configerror(self):
        with patch(_PGKILL, side_effect=FileNotFoundError("cursor-agent: not found")):
            with pytest.raises(ConfigError):
                _adapter().complete(_req())

    def test_spawn_oserror_is_unavailable(self):
        with patch(_PGKILL, side_effect=PermissionError("exec not permitted")):
            with pytest.raises(ProviderUnavailableError, match="failed to spawn"):
                _adapter().complete(_req())

    def test_semaphore_exhausted_is_chain_exhausted_concurrency(self):
        # Review #966: concurrency-slot exhaustion must surface the distinct
        # [CHAIN-EXHAUSTED-CONCURRENCY] class (MODELINV semaphore_exhausted=true),
        # not a generic outage.
        from loa_cheval.adapters.headless_concurrency import SemaphoreExhausted
        with patch(
            "loa_cheval.adapters.headless_concurrency.acquire_slot",
            side_effect=SemaphoreExhausted("cursor-headless", 50, 30.0),
        ):
            with pytest.raises(ProviderUnavailableError, match=r"\[CHAIN-EXHAUSTED-CONCURRENCY\]"):
                _adapter().complete(_req())


# ---------------------------------------------------------------------------
# Bundle-E substrate wiring (review #966)
# ---------------------------------------------------------------------------

class TestSubstrateWiring:
    def test_auth_type_is_headless(self):
        # Circuit-breaker writes route to the (cursor-headless, headless) bucket;
        # headless-mode transforms keep the adapter under cli-only mode.
        assert CursorHeadlessAdapter.auth_type == "headless"

    def test_pgkill_called_with_isolated_workspace_cwd(self):
        # The isolated-workspace defense survives the pgkill swap: the helper
        # must receive cwd=<fresh loa-cursor-ws-* tempdir>.
        with patch(_PGKILL, return_value=_completed(_OK_ENVELOPE)) as pg:
            _adapter().complete(_req())
        kwargs = pg.call_args.kwargs
        assert "loa-cursor-ws-" in (kwargs.get("cwd") or "")

    def test_prompt_delivered_via_stdin_not_argv(self):
        # BB #966 round-4 (HIGH_CONSENSUS): the prompt rides STDIN, never argv —
        # no OS ARG_MAX cliff on large-diff reviews and no flag-parsing surface
        # at all (an injected "--yolo" cannot be an argument).
        with patch(_PGKILL, return_value=_completed(_OK_ENVELOPE)) as pg:
            _adapter().complete(_req("--yolo injected"))
        argv = pg.call_args.args[0]
        assert not any("--yolo injected" in a for a in argv)
        assert "--yolo injected" in pg.call_args.kwargs["input"]

    def test_large_prompt_keeps_argv_small(self):
        # The ARG_MAX regression: a large prompt must not appear in argv.
        # ~0.5MB: far beyond any argv comfort zone, but inside the 200K-token
        # context gate (1MB estimated ~285K tokens and tripped
        # enforce_context_window before reaching subprocess assembly — the
        # test shipped red in the round-4 commit; sprint-bug-209 fix).
        big = "x" * 500_000
        with patch(_PGKILL, return_value=_completed(_OK_ENVELOPE)) as pg:
            _adapter().complete(_req(big))
        argv = pg.call_args.args[0]
        assert sum(len(a) for a in argv) < 10_000
        assert big in pg.call_args.kwargs["input"]

    def test_cli_adapter_types_includes_cursor(self):
        # cheval's kind:cli escape hatch derives from the registry — the gap
        # where cursor-headless was registered but rejected stays closed.
        from loa_cheval.providers import cli_adapter_types
        assert "cursor-headless" in cli_adapter_types()

    def test_cli_adapter_types_attribute_keyed_covers_all_peers(self):
        # BB #966 round-2: admission keys on the auth_type class contract, not
        # the "-headless" name convention. All four CLI adapters must appear;
        # a peer losing its auth_type attr should fail HERE, not at dispatch.
        from loa_cheval.providers import cli_adapter_types
        assert cli_adapter_types() >= {
            "claude-headless",
            "codex-headless",
            "gemini-headless",
            "cursor-headless",
        }

    def test_headless_inference_covers_cursor(self):
        # config loader stamps auth_type/dispatch_group/kind for cursor-headless
        # so the documented custom-provider shape loads ([CONFIG-INVALID] gap).
        from loa_cheval.config.loader import _HEADLESS_TYPE_INFERENCE
        auth, group = _HEADLESS_TYPE_INFERENCE["cursor-headless"]
        assert auth == "headless" and group == "cursor-composer"


# ---------------------------------------------------------------------------
# validate_config + health_check
# ---------------------------------------------------------------------------

class TestValidateAndHealth:
    def test_validate_ok(self):
        with patch(_WHICH, return_value="/usr/local/bin/cursor-agent"):
            assert _adapter().validate_config() == []

    def test_validate_missing_cli(self):
        with patch(_WHICH, return_value=None):
            errs = _adapter().validate_config()
            assert any("not found on PATH" in e for e in errs)

    def test_validate_wrong_type(self):
        cfg = ProviderConfig(name="x", type="not-cursor", endpoint="", auth=None,
                             models={"composer-2.5": ModelConfig()})
        a = CursorHeadlessAdapter(cfg)
        with patch(_WHICH, return_value="/usr/local/bin/cursor-agent"):
            assert any("must be 'cursor-headless'" in e for e in a.validate_config())

    def test_health_check_true(self):
        with patch(_WHICH, return_value="/usr/local/bin/cursor-agent"), \
             patch("loa_cheval.providers.cursor_headless_adapter.subprocess.run") as run:
            run.return_value = MagicMock(returncode=0)
            assert _adapter().health_check() is True

    def test_health_check_missing_cli(self):
        with patch(_WHICH, return_value=None):
            assert _adapter().health_check() is False


# ---------------------------------------------------------------------------
# Live (gated)
# ---------------------------------------------------------------------------

@pytest.mark.skipif(
    os.environ.get("LOA_CURSOR_HEADLESS_LIVE") != "1",
    reason="set LOA_CURSOR_HEADLESS_LIVE=1 (needs Cursor Pro + cursor-agent login)",
)
def test_live_complete():
    r = _adapter().complete(_req("Reply with ONLY this JSON: {\"ok\":true}"))
    assert r.provider == "cursor-headless"
    assert r.content
