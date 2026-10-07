"""cycle-127 FR-1 — the agy (Antigravity) headless route is opt-in, default off.

`hounfour.headless.agy_opt_in` (a YAML boolean in .loa.config.yaml, default false) is read through the project-config layer.
Off: AgyHeadlessAdapter refuses before any binary discovery or spawn with INVALID_CONFIG, retryable false, failure_class
opt_in_required, naming the key and the reason. On: today's path (discovery, the one-time argv WARN, dispatch).
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from loa_cheval.config.loader import agy_opt_in_enabled
from loa_cheval.providers import get_adapter
from loa_cheval.types import AgyOptInRequiredError, ConfigError, ModelConfig, ProviderConfig, CompletionRequest

_MOD = "loa_cheval.providers.agy_headless_adapter"
_REFUSAL = ("agy headless route is opt-in: set hounfour.headless.agy_opt_in: true (the prompt travels on the CLI's argv, "
            "readable by local users; the CLI must be OAuth-authed)")


def _adapter():
    return get_adapter(ProviderConfig(
        name="gemini-headless", type="gemini-headless", endpoint="", auth=None,
        models={"gemini-3-pro": ModelConfig(context_window=1048576, extra={"cli_model": "Gemini 3.1 Pro (High)"})},
    ))


def _req():
    return CompletionRequest(messages=[{"role": "user", "content": "review this diff"}], model="gemini-3-pro", max_tokens=200)


def _project(tmp_path, body):
    (tmp_path / ".claude").mkdir()
    if body is not None:
        (tmp_path / ".loa.config.yaml").write_text(body)
    return str(tmp_path)


# --- the key, read through the project-config layer -----------------------------------------------------------------

@pytest.mark.parametrize("body,expected", [
    (None, False),                                                         # no .loa.config.yaml
    ("hounfour: {}\n", False),                                             # absent key
    ("hounfour:\n  headless:\n    mode: prefer-api\n", False),
    ("hounfour:\n  headless:\n    agy_opt_in: false\n", False),
    ("hounfour:\n  headless:\n    agy_opt_in: \"true\"\n", False),         # a string is not the boolean
    ("hounfour:\n  headless:\n    agy_opt_in: 1\n", False),
    ("hounfour:\n  headless: on-a-string\n", False),
    ("hounfour:\n  headless:\n    agy_opt_in: true\n", True),
])
def test_the_key_is_a_yaml_boolean_default_false(tmp_path, body, expected):
    assert agy_opt_in_enabled(_project(tmp_path, body)) is expected


def test_an_unparsable_config_reads_as_off(tmp_path):
    assert agy_opt_in_enabled(_project(tmp_path, "hounfour: [unclosed\n")) is False


def test_no_environment_override(tmp_path, monkeypatch):
    for k in ("LOA_AGY_OPT_IN", "AGY_OPT_IN", "LOA_HOUNFOUR_HEADLESS_AGY_OPT_IN"):
        monkeypatch.setenv(k, "true")
    assert agy_opt_in_enabled(_project(tmp_path, "hounfour: {}\n")) is False


def test_the_project_root_defaults_to_the_cwd_walk(tmp_path, monkeypatch):
    root = _project(tmp_path, "hounfour:\n  headless:\n    agy_opt_in: true\n")
    (tmp_path / "sub").mkdir()
    monkeypatch.chdir(tmp_path / "sub")
    assert agy_opt_in_enabled() is True
    assert Path(root).is_dir()


# --- the adapter refuses before discovery ---------------------------------------------------------------------------

def test_off_refuses_before_any_discovery_or_spawn(monkeypatch):
    monkeypatch.setattr(f"{_MOD}.agy_opt_in_enabled", lambda *a, **k: False)
    which, pgkill, run, ws = MagicMock(return_value="/usr/bin/agy"), MagicMock(), MagicMock(), MagicMock(return_value="/x")
    with patch(f"{_MOD}.shutil.which", which), patch(f"{_MOD}.run_subprocess_pgkill", pgkill), \
            patch(f"{_MOD}.subprocess.run", run), patch(f"{_MOD}.private_workspace", ws), \
            patch(f"{_MOD}.subprocess.Popen", MagicMock(side_effect=AssertionError("spawned"))):
        with pytest.raises(AgyOptInRequiredError) as ei:
            _adapter().complete(_req())
    err = ei.value
    assert isinstance(err, ConfigError)
    assert err.code == "INVALID_CONFIG" and err.retryable is False
    assert err.context.get("failure_class") == "opt_in_required"
    assert err.failure_class == "opt_in_required"
    assert _REFUSAL in str(err)
    which.assert_not_called(); pgkill.assert_not_called(); run.assert_not_called(); ws.assert_not_called()


def test_off_never_warns_of_the_argv_prompt(monkeypatch, caplog):
    import logging
    import loa_cheval.providers.agy_headless_adapter as agy
    monkeypatch.setattr(agy, "_ARGV_PROMPT_WARNED", False)
    monkeypatch.setattr(f"{_MOD}.agy_opt_in_enabled", lambda *a, **k: False)
    with caplog.at_level(logging.WARNING, logger="loa_cheval.providers.agy_headless"), pytest.raises(AgyOptInRequiredError):
        _adapter().complete(_req())
    assert not [r for r in caplog.records if "/proc/<pid>/cmdline" in r.getMessage()]
    assert agy._ARGV_PROMPT_WARNED is False


def test_off_health_check_is_false_without_a_spawn(monkeypatch):
    monkeypatch.setattr(f"{_MOD}.agy_opt_in_enabled", lambda *a, **k: False)
    which, run = MagicMock(return_value="/usr/bin/agy"), MagicMock()
    with patch(f"{_MOD}.shutil.which", which), patch(f"{_MOD}.subprocess.run", run):
        assert _adapter().health_check() is False
    which.assert_not_called(); run.assert_not_called()


def test_off_validate_config_names_the_key(monkeypatch):
    monkeypatch.setattr(f"{_MOD}.agy_opt_in_enabled", lambda *a, **k: False)
    with patch(f"{_MOD}.shutil.which", return_value="/usr/bin/agy"):
        errs = _adapter().validate_config()
    assert any("hounfour.headless.agy_opt_in" in e for e in errs)


def test_on_discovery_proceeds_and_an_absent_binary_fails_as_today(monkeypatch):
    monkeypatch.setattr(f"{_MOD}.agy_opt_in_enabled", lambda *a, **k: True)
    pgkill = MagicMock(side_effect=FileNotFoundError("agy"))
    with patch(f"{_MOD}.run_subprocess_pgkill", pgkill):
        with pytest.raises(ConfigError) as ei:
            _adapter().complete(_req())
    pgkill.assert_called_once()
    assert not isinstance(ei.value, AgyOptInRequiredError)
    assert "agy CLI not found on PATH" in str(ei.value)


def test_on_dispatches_as_today(monkeypatch):
    monkeypatch.setattr(f"{_MOD}.agy_opt_in_enabled", lambda *a, **k: True)
    pgkill = MagicMock(return_value=subprocess.CompletedProcess(["agy"], 0, "APPROVED", ""))
    with patch(f"{_MOD}.run_subprocess_pgkill", pgkill):
        assert _adapter().complete(_req()).content == "APPROVED"
    assert pgkill.call_args[0][0][:2] == ["agy", "-p"]


def test_the_adapter_reads_the_real_project_config(tmp_path, monkeypatch):
    """No monkeypatch of the reader: a project whose config carries no key refuses; `true` dispatches."""
    _project(tmp_path, "hounfour:\n  headless:\n    mode: prefer-api\n")
    monkeypatch.chdir(tmp_path)
    pgkill = MagicMock(return_value=subprocess.CompletedProcess(["agy"], 0, "APPROVED", ""))
    with patch(f"{_MOD}.run_subprocess_pgkill", pgkill):
        with pytest.raises(AgyOptInRequiredError):
            _adapter().complete(_req())
        pgkill.assert_not_called()
        (tmp_path / ".loa.config.yaml").write_text("hounfour:\n  headless:\n    agy_opt_in: true\n")
        assert _adapter().complete(_req()).content == "APPROVED"
