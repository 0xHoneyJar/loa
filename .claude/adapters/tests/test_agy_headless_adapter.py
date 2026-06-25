"""Tests for agy-headless provider adapter (Antigravity CLI — the gemini-headless repoint).

Covers (grounded in the T4.1 spike, agy v1.0.12):
  - registry dispatch: type='gemini-headless' resolves to AgyHeadlessAdapter (FR-5 repoint)
  - command construction: `agy -p <prompt> --model <label> --sandbox
    --dangerously-skip-permissions`; the prompt rides ARGV (no --prompt-file / no stdin);
    --model takes the human-readable label from extra.cli_model; AGY_HEADLESS_BIN override
  - the load-bearing non-TTY pairing: --sandbox AND --dangerously-skip-permissions both present
  - PLAIN-TEXT output parsing: stdout → content, estimated Usage (agy emits no JSON/tokens)
  - empty-text-as-success (peer parity — warn, don't raise)
  - error classification: rate-limit, OAuth token-revocation (walkable), not-authenticated
    (hard-abort), generic nonzero, timeout, output-cap, missing CLI
  - substrate wiring: auth_type=headless, registry kind:cli admission
  - validate_config + health_check (`agy --version`)

Live test (real agy invocation) is gated behind LOA_AGY_HEADLESS_LIVE=1 to keep CI
deterministic. Run locally (needs an OAuth-authed agy on the host):
    LOA_AGY_HEADLESS_LIVE=1 pytest tests/test_agy_headless_adapter.py -k live
"""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from loa_cheval.providers import _ADAPTER_REGISTRY, cli_adapter_types, get_adapter
from loa_cheval.providers.agy_headless_adapter import AgyHeadlessAdapter
from loa_cheval.types import (
    AuthRevokedError,
    CompletionRequest,
    ConfigError,
    ModelConfig,
    ProviderConfig,
    ProviderUnavailableError,
    RateLimitError,
)

# The subprocess seam to mock is the pgkill helper import in the adapter module.
_PGKILL = "loa_cheval.providers.agy_headless_adapter.run_subprocess_pgkill"
_WHICH = "loa_cheval.providers.agy_headless_adapter.shutil.which"

_GEMINI_LABEL = "Gemini 3.1 Pro (High)"


# ---------------------------------------------------------------------------
# Fixtures / helpers
# ---------------------------------------------------------------------------

def _cfg(**models) -> ProviderConfig:
    return ProviderConfig(
        name="gemini-headless",
        type="gemini-headless",
        endpoint="",
        auth=None,
        models=models
        or {"gemini-3-pro": ModelConfig(context_window=1048576, extra={"cli_model": _GEMINI_LABEL})},
    )


def _adapter(**models) -> AgyHeadlessAdapter:
    return get_adapter(_cfg(**models))  # type: ignore[return-value]


def _completed(stdout: str = "", stderr: str = "", returncode: int = 0) -> subprocess.CompletedProcess:
    """A run_subprocess_pgkill result: CompletedProcess[str]."""
    return subprocess.CompletedProcess(["agy"], returncode, stdout, stderr)


def _req(content: str = "review this diff", model: str = "gemini-3-pro") -> CompletionRequest:
    return CompletionRequest(messages=[{"role": "user", "content": content}], model=model, max_tokens=200)


# ---------------------------------------------------------------------------
# Registry dispatch — the FR-5 repoint
# ---------------------------------------------------------------------------

class TestRegistryDispatch:
    def test_gemini_headless_resolves_to_agy_adapter(self):
        # FR-5: the gemini-headless terminal now backs onto agy.
        assert _ADAPTER_REGISTRY["gemini-headless"] is AgyHeadlessAdapter
        assert isinstance(_adapter(), AgyHeadlessAdapter)

    def test_provider_name_preserved(self):
        assert _adapter().provider == "gemini-headless"

    def test_admitted_to_cli_dispatch(self):
        # auth_type=headless → admitted to the kind:cli subprocess path (review #966).
        assert AgyHeadlessAdapter.auth_type == "headless"
        assert "gemini-headless" in cli_adapter_types()


# ---------------------------------------------------------------------------
# Command construction — the spike contract
# ---------------------------------------------------------------------------

class TestCommandConstruction:
    def _cmd(self, **extra):
        mc = ModelConfig(context_window=1048576, extra=extra or {"cli_model": _GEMINI_LABEL})
        return _adapter()._build_command(_req(), mc, "FLAT PROMPT")

    def test_argv_shape(self):
        cmd = self._cmd()
        assert cmd[0] == "agy"
        assert cmd[1] == "-p"
        # the prompt rides ARGV (spike: no --prompt-file flag exists; not stdin)
        assert cmd[2] == "FLAT PROMPT"
        assert "--prompt-file" not in cmd

    def test_model_label_from_cli_model(self):
        cmd = self._cmd(cli_model=_GEMINI_LABEL)
        i = cmd.index("--model")
        assert cmd[i + 1] == _GEMINI_LABEL  # the human-readable label, NOT an api id

    def test_nontty_pairing_present(self):
        # the load-bearing pairing — both flags, never skip-perms alone (spike safety)
        cmd = self._cmd()
        assert "--sandbox" in cmd
        assert "--dangerously-skip-permissions" in cmd

    def test_no_devnull_in_argv(self):
        # the stdin-close is a subprocess setting, NOT an argv element (council iter-4)
        cmd = self._cmd()
        assert "</dev/null" not in cmd
        assert all("/dev/null" not in str(a) for a in cmd)

    def test_bin_override(self):
        with patch.dict(os.environ, {"AGY_HEADLESS_BIN": "/opt/agy-test"}):
            cmd = self._cmd()
            assert cmd[0] == "/opt/agy-test"

    def test_build_command_requires_cli_model(self):
        # council #1109: no silent fallback to request.model (agy rejects internal ids).
        with pytest.raises(ConfigError):
            self._cmd(some_key="x")  # extra present but no cli_model

    def test_no_operator_extra_flags_surface(self):
        # council #1109: agy_extra_flags is deliberately NOT supported — an operator
        # escape hatch on an untrusted-input path was a sandbox-bypass foothold (a
        # split-token bypass a denylist can't reliably close). The argv is FIXED, so a
        # would-be bypass flag (even split across tokens) never reaches agy.
        cmd = self._cmd(cli_model=_GEMINI_LABEL, agy_extra_flags=["--no-sandbox", "false"])
        assert "--no-sandbox" not in cmd and "false" not in cmd
        assert cmd == [
            "agy", "-p", "FLAT PROMPT", "--model", _GEMINI_LABEL,
            "--sandbox", "--dangerously-skip-permissions",
        ]


# ---------------------------------------------------------------------------
# Plain-text output parsing (agy emits no JSON / no token stats)
# ---------------------------------------------------------------------------

class TestParsing:
    def test_plaintext_stdout_becomes_content(self):
        with patch(_WHICH, return_value="/usr/bin/agy"), \
             patch(_PGKILL, return_value=_completed(stdout="CHANGES_REQUIRED: line 5 leaks a key\n")):
            res = _adapter().complete(_req())
        assert res.content == "CHANGES_REQUIRED: line 5 leaks a key"
        assert res.usage.source == "estimated"  # no real token counts from agy
        assert res.usage.input_tokens > 0
        assert res.model == "gemini-3-pro"
        assert res.provider == "gemini-headless"

    def test_empty_stdout_is_success_not_error(self):
        # peer parity: empty-as-success (warn, don't raise)
        with patch(_WHICH, return_value="/usr/bin/agy"), \
             patch(_PGKILL, return_value=_completed(stdout="")):
            res = _adapter().complete(_req())
        assert res.content == ""


# ---------------------------------------------------------------------------
# Error classification
# ---------------------------------------------------------------------------

class TestErrors:
    def _fail(self, stderr="", stdout="", rc=1):
        with patch(_WHICH, return_value="/usr/bin/agy"), \
             patch(_PGKILL, return_value=_completed(stdout=stdout, stderr=stderr, returncode=rc)):
            _adapter().complete(_req())

    def test_rate_limit(self):
        with pytest.raises(RateLimitError):
            self._fail(stderr="Error: 429 rate limit exceeded")

    def test_oauth_revoked_is_walkable(self):
        with pytest.raises(AuthRevokedError):
            self._fail(stderr="session expired; please re-authenticate")

    def test_not_authenticated_is_config_error(self):
        with pytest.raises(ConfigError):
            self._fail(stderr="not authenticated: please log in")

    def test_generic_nonzero_is_provider_unavailable(self):
        with pytest.raises(ProviderUnavailableError):
            self._fail(stderr="some unexpected agy failure", rc=3)

    def test_timeout_walks_chain(self):
        with patch(_WHICH, return_value="/usr/bin/agy"), \
             patch(_PGKILL, side_effect=subprocess.TimeoutExpired("agy", 1)):
            with pytest.raises(ProviderUnavailableError):
                _adapter().complete(_req())

    def test_missing_cli_is_config_error(self):
        with patch(_PGKILL, side_effect=FileNotFoundError("agy")):
            with pytest.raises(ConfigError):
                _adapter().complete(_req())

    def test_oversized_prompt_oserror_walks(self):
        # council #1109: ARG_MAX/E2BIG (huge diff on argv) → walkable, not a raw OSError crash
        with patch(_WHICH, return_value="/usr/bin/agy"), \
             patch(_PGKILL, side_effect=OSError(7, "Argument list too long")):
            with pytest.raises(ProviderUnavailableError):
                _adapter().complete(_req())

    def test_never_authed_with_401_is_hard_abort(self):
        # council #1109: a never-authed failure carrying "401" must NOT walk (static guard)
        with pytest.raises(ConfigError):
            self._fail(stderr="not authenticated (401)")

    def test_ambiguous_401_without_static_marker_walks(self):
        with pytest.raises(AuthRevokedError):
            self._fail(stderr="request failed: 401")

    def test_permission_denied_is_walkable(self):
        # council #1109: permission_denied is ambiguous for OAuth → walkable, not hard-abort
        with pytest.raises(ProviderUnavailableError):
            self._fail(stderr="permission_denied: blocked")

    def test_stdout_does_not_drive_classification(self):
        # council #1109: untrusted review TEXT in stdout must NEVER classify — only stderr.
        # stdout mentions rate-limit/401/429 but stderr is empty → generic walkable, not a
        # mis-typed RateLimitError/AuthRevokedError.
        with pytest.raises(ProviderUnavailableError):
            self._fail(stdout="the review notes a rate limit near line 429 and a 401 path", stderr="")


# ---------------------------------------------------------------------------
# validate_config + health_check
# ---------------------------------------------------------------------------

class TestValidateAndHealth:
    def test_validate_ok_when_on_path(self):
        with patch(_WHICH, return_value="/usr/bin/agy"):
            assert _adapter().validate_config() == []

    def test_validate_flags_missing_cli(self):
        with patch(_WHICH, return_value=None):
            errs = _adapter().validate_config()
            assert any("not found on PATH" in e for e in errs)

    def test_validate_flags_missing_cli_model(self):
        # council #1109: a model without extra.cli_model would fail at dispatch — catch early
        with patch(_WHICH, return_value="/usr/bin/agy"):
            errs = _adapter(gemini_3_pro=ModelConfig(context_window=1048576, extra={})).validate_config()
            assert any("cli_model" in e for e in errs)


    def test_health_check_runs_version(self):
        with patch(_WHICH, return_value="/usr/bin/agy"), \
             patch("loa_cheval.providers.agy_headless_adapter.subprocess.run",
                   return_value=subprocess.CompletedProcess(["agy", "--version"], 0, "1.0.12\n", "")) as m:
            assert _adapter().health_check() is True
            # health_check runs `<bin> --version`; the bin is the name (agy), not which()'s path
            assert m.call_args[0][0] == ["agy", "--version"]


# ---------------------------------------------------------------------------
# Live (gated) — real agy dispatch of a Gemini model
# ---------------------------------------------------------------------------

@pytest.mark.skipif(os.environ.get("LOA_AGY_HEADLESS_LIVE") != "1", reason="needs an OAuth-authed agy on host")
class TestLive:
    def test_real_gemini_dispatch(self):
        res = _adapter().complete(_req(content="Reply with exactly: GEMINI-OK"))
        assert "GEMINI-OK" in res.content
