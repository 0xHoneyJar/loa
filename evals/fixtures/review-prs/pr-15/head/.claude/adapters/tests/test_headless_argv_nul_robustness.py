"""bd-q0o: argv-prompt headless adapters must WALK (not crash) on un-execable argv.

Only gemini-headless (agy) passes the UNTRUSTED prompt on ARGV (`-p <prompt>`), so only it is reachable by an
embedded-NUL ValueError or an ARG_MAX OSError from a crafted/oversized diff. (grok uses --prompt-file; claude, codex
and cursor use stdin via input= — their prompt never touches argv; claude since cycle-126's thirtieth run, e1 DISS-C-001.
Verified: a NUL in stdin does NOT raise, a NUL in argv does.) claude-headless stays in the table: a spawn error on its
flags still walks the chain.

Found by the Gemini council voice (agy) reviewing the agy adapter on loa#1109 — a bug codex+
cursor missed. The agy adapter is fixed there; this covers the two vulnerable siblings.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path
from unittest.mock import patch

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from loa_cheval.providers import get_adapter
from loa_cheval.types import (
    CompletionRequest,
    ModelConfig,
    ProviderConfig,
    ProviderUnavailableError,
)


@pytest.fixture(autouse=True)
def _agy_opted_in(monkeypatch):
    """The agy rows pin the opted-in path (cycle-127 FR-1: the route is opt-in; the gate is test_agy_opt_in_gate.py)."""
    monkeypatch.setattr("loa_cheval.providers.agy_headless_adapter.agy_opt_in_enabled", lambda *a, **k: True)

# (module-seam, provider-type, model-id, extra) — ARGV-prompt adapters only.
_ARGV_ADAPTERS = [
    ("agy_headless_adapter", "gemini-headless", "gemini-3-pro", {"cli_model": "Gemini 3.1 Pro (High)"}),
    ("claude_headless_adapter", "claude-headless", "sonnet", {"cli_model": "sonnet"}),
]


def _adapter(ptype, model_id, extra):
    cfg = ProviderConfig(
        name=ptype, type=ptype, endpoint="", auth=None,
        models={model_id: ModelConfig(context_window=200000, extra=extra)},
    )
    return get_adapter(cfg)


def _req(model_id):
    return CompletionRequest(messages=[{"role": "user", "content": "x"}], model=model_id, max_tokens=50)


@pytest.mark.parametrize("mod,ptype,model_id,extra", _ARGV_ADAPTERS)
def test_nul_byte_prompt_walks_not_crashes(mod, ptype, model_id, extra):
    # embedded NUL in an argv arg → subprocess raises ValueError (not OSError) → must WALK.
    with patch(f"loa_cheval.providers.{mod}.shutil.which", return_value="/usr/bin/x"), \
         patch(f"loa_cheval.providers.{mod}.run_subprocess_pgkill",
               side_effect=ValueError("embedded null byte")):
        with pytest.raises(ProviderUnavailableError):
            _adapter(ptype, model_id, extra).complete(_req(model_id))


@pytest.mark.parametrize("mod,ptype,model_id,extra", _ARGV_ADAPTERS)
def test_argmax_oserror_walks_not_crashes(mod, ptype, model_id, extra):
    # oversized prompt on argv → ARG_MAX/E2BIG OSError → must WALK, not crash the chain.
    with patch(f"loa_cheval.providers.{mod}.shutil.which", return_value="/usr/bin/x"), \
         patch(f"loa_cheval.providers.{mod}.run_subprocess_pgkill",
               side_effect=OSError(7, "Argument list too long")):
        with pytest.raises(ProviderUnavailableError):
            _adapter(ptype, model_id, extra).complete(_req(model_id))


# (cycle-126 thirty-ninth run, d DISS-C-002) an exec-time failure is never read as a preparation failure: a binary that is
# present but not executable names the *_BIN override like a missing one, and codex's spawn OSError is "spawn failed",
# never the outer "could not prepare its run" a refused workspace or slot file earns
_SPAWN_ADAPTERS = [
    ("claude_headless_adapter", "claude-headless", "sonnet", {"cli_model": "sonnet"}, "CLAUDE_HEADLESS_BIN"),
    ("codex_headless_adapter", "codex-headless", "gpt-5.5", {"cli_model": "gpt-5.5"}, "CODEX_HEADLESS_BIN"),
]


@pytest.mark.parametrize("mod,ptype,model_id,extra,env_name", _SPAWN_ADAPTERS)
def test_non_executable_binary_names_the_bin_override(mod, ptype, model_id, extra, env_name):
    from loa_cheval.types import ConfigError
    with patch(f"loa_cheval.providers.{mod}.shutil.which", return_value="/usr/bin/x"), \
         patch(f"loa_cheval.providers.{mod}.run_subprocess_pgkill",
               side_effect=PermissionError(13, "Permission denied", "/usr/bin/x")):
        with pytest.raises(ConfigError) as ei:
            _adapter(ptype, model_id, extra).complete(_req(model_id))
    assert env_name in str(ei.value) and "not executable" in str(ei.value), str(ei.value)


@pytest.mark.parametrize("mod,ptype,model_id,extra,env_name", _SPAWN_ADAPTERS)
def test_exec_oserror_is_a_spawn_failure_never_a_preparation_one(mod, ptype, model_id, extra, env_name):
    for exc in (OSError(7, "Argument list too long"), PermissionError(13, "Permission denied")):
        with patch(f"loa_cheval.providers.{mod}.shutil.which", return_value="/usr/bin/x"), \
             patch(f"loa_cheval.providers.{mod}.run_subprocess_pgkill", side_effect=exc):
            with pytest.raises(ProviderUnavailableError) as ei:
                _adapter(ptype, model_id, extra).complete(_req(model_id))
        msg = str(ei.value)
        assert "could not prepare its run" not in msg and "spawn" in msg, msg
