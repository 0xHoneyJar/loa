"""Tests for cursor-headless provider adapter.

Covers:
  - registry dispatch on type='cursor-headless'
  - command construction (model, --mode plan, --sandbox enabled, --trust, no -f, cli_model)
  - single-JSON output parsing (result content, usage, session_id, model fallback)
  - error classification (resource_exhausted on exit-0, auth, is_error, generic, timeout, missing CLI)
  - transport-probe safety: a successful review whose `result` quotes 429/unauthorized
    is NOT misclassified as a transport failure (the silencing-attack regression)
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
    ConfigError,
    ModelConfig,
    ProviderConfig,
    ProviderUnavailableError,
    RateLimitError,
)

_POPEN = "loa_cheval.providers.cursor_headless_adapter.subprocess.Popen"
_WHICH = "loa_cheval.providers.cursor_headless_adapter.shutil.which"
_KILLPG = "loa_cheval.providers.cursor_headless_adapter.os.killpg"
_GETPGID = "loa_cheval.providers.cursor_headless_adapter.os.getpgid"


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


def _popen(stdout: str = "", stderr: str = "", returncode: int = 0) -> MagicMock:
    """A Popen-like mock: communicate() returns (stdout, stderr); returncode set."""
    p = MagicMock()
    p.communicate.return_value = (stdout, stderr)
    p.returncode = returncode
    p.pid = 4242
    return p


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
        with patch(_POPEN, return_value=_popen(_OK_ENVELOPE)):
            r = _adapter().complete(_req())
        assert r.content == '{"verdict":"APPROVED"}'
        assert r.usage.input_tokens == 120 and r.usage.output_tokens == 18
        assert r.usage.source == "actual"
        assert r.model == "composer-2.5"          # falls back to requested
        assert r.provider == "cursor-headless"
        assert r.interaction_id == "sess-1"

    def test_model_field_when_present(self):
        env = _OK_ENVELOPE.replace('"session_id"', '"model":"composer-2.5-x","session_id"')
        with patch(_POPEN, return_value=_popen(env)):
            r = _adapter().complete(_req())
        assert r.model == "composer-2.5-x"

    def test_malformed_usage_does_not_crash(self):
        env = ('{"type":"result","is_error":false,"result":"ok",'
               '"usage":{"inputTokens":"oops","outputTokens":null}}')
        with patch(_POPEN, return_value=_popen(env)):
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
        with patch(_POPEN, return_value=_popen(env)):
            r = _adapter().complete(_req())
        assert "429" in r.content and "unauthorized" in r.content  # returned, not raised


# ---------------------------------------------------------------------------
# Error classification
# ---------------------------------------------------------------------------

class TestErrorClassification:
    def test_resource_exhausted_on_exit0_is_ratelimit(self):
        # cursor surfaces transport errors on stdout WITH a zero exit code (non-JSON).
        with patch(_POPEN, return_value=_popen("ConnectError: [resource_exhausted] Error", returncode=0)):
            with pytest.raises(RateLimitError):
                _adapter().complete(_req())

    def test_not_logged_in_is_configerror(self):
        with patch(_POPEN, return_value=_popen("", stderr="Not logged in", returncode=1)):
            with pytest.raises(ConfigError):
                _adapter().complete(_req())

    def test_is_error_true_raises(self):
        with patch(_POPEN, return_value=_popen('{"type":"result","is_error":true,"result":"boom"}')):
            with pytest.raises(ProviderUnavailableError):
                _adapter().complete(_req())

    def test_generic_nonzero_is_unavailable(self):
        with patch(_POPEN, return_value=_popen("", stderr="weird failure", returncode=2)):
            with pytest.raises(ProviderUnavailableError):
                _adapter().complete(_req())

    def test_timeout_kills_group_and_raises(self):
        p = MagicMock()
        p.pid = 4242
        p.communicate.side_effect = [subprocess.TimeoutExpired(cmd=["cursor-agent"], timeout=5), ("", "")]
        with patch(_POPEN, return_value=p), \
             patch(_KILLPG) as killpg, patch(_GETPGID, return_value=4242):
            with pytest.raises(ProviderUnavailableError):
                _adapter().complete(_req())
            killpg.assert_called_once()  # whole process group SIGKILLed, no leak

    def test_missing_cli_is_configerror(self):
        with patch(_POPEN, side_effect=FileNotFoundError("cursor-agent: not found")):
            with pytest.raises(ConfigError):
                _adapter().complete(_req())


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
