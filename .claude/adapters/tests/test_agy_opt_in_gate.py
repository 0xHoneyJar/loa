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


# --- review r251-1 ---------------------------------------------------------------------------------------------------

def test_g4_a_root_discovery_failure_reads_as_off(monkeypatch):
    """finding 3: the root walk sits inside the fail-closed try."""
    import loa_cheval.config.loader as loader

    def _boom():
        raise OSError("cwd vanished")
    monkeypatch.setattr(loader, "_find_project_root", _boom)
    assert agy_opt_in_enabled() is False


def test_g5_the_refusal_carries_its_failure_class_through_the_base_constructor():
    """finding 5: context is passed to ChevalError, not patched on after it."""
    import inspect
    from loa_cheval.types import ChevalError
    err = AgyOptInRequiredError()
    assert err.context == {"failure_class": "opt_in_required"}
    assert "self.context =" not in inspect.getsource(AgyOptInRequiredError)
    # a plain ConfigError still constructs with an empty context
    assert ConfigError("x").context == {}
    assert isinstance(err, ChevalError) and err.code == "INVALID_CONFIG"


def test_g6_off_validate_config_reports_only_the_opt_in(monkeypatch):
    """finding 4: the binary is irrelevant while the route is off — no PATH lookup, no 'CLI not found' line."""
    monkeypatch.setattr(f"{_MOD}.agy_opt_in_enabled", lambda *a, **k: False)
    which = MagicMock(return_value=None)
    with patch(f"{_MOD}.shutil.which", which):
        errs = _adapter().validate_config()
    assert len(errs) == 1 and "hounfour.headless.agy_opt_in" in errs[0], errs
    which.assert_not_called()


def test_g6_on_validate_config_still_checks_the_binary(monkeypatch):
    monkeypatch.setattr(f"{_MOD}.agy_opt_in_enabled", lambda *a, **k: True)
    with patch(f"{_MOD}.shutil.which", return_value=None):
        errs = _adapter().validate_config()
    assert any("CLI not found on PATH" in e for e in errs)
    assert not any("hounfour.headless.agy_opt_in" in e for e in errs)


# --- review r251-1 G2: the Python twin of the bash routes_to_agy predicate ------------------------------------------

@pytest.mark.parametrize("model,mode,expected", [
    ("gemini-headless", None, True),
    ("google:gemini-headless", None, True),
    ("gemini-headless:any", None, True),
    ("gemini-headless", "prefer-api", True),
    ("gemini-2.5-pro", "prefer-api", False),
    ("gemini-2.5-pro", None, False),
    ("gemini-2.5-pro", "cli-only", True),
    ("google:gemini-3.1-pro", "cli-only", True),
    ("gemini-2.5-pro", "prefer-cli", False),
    ("claude-headless", "cli-only", False),
    ("gpt-5.5", "cli-only", False),
    ("", "cli-only", False),
])
def test_routes_to_agy_matches_the_bash_rule(model, mode, expected):
    from loa_cheval.config.loader import routes_to_agy
    assert routes_to_agy(model, mode) is expected


# --- review r251-1 G9: the opt-in is operator-only (project config), never satisfied by framework defaults -------------

def test_g9_system_defaults_alone_never_opt_in(tmp_path):
    root = _project(tmp_path, "hounfour:\n  headless:\n    mode: prefer-api\n")
    (tmp_path / ".claude" / "defaults").mkdir(parents=True)
    (tmp_path / ".claude" / "defaults" / "model-config.yaml").write_text("headless:\n  agy_opt_in: true\n")
    assert agy_opt_in_enabled(root) is False
    (tmp_path / ".loa.config.yaml").write_text("hounfour:\n  headless:\n    agy_opt_in: true\n")
    assert agy_opt_in_enabled(root) is True


# --- review r251-1 G12: a present non-boolean value reads off and is said once, naming the key and the type ------------

def test_g12_a_string_true_reads_off_with_one_warn(tmp_path, monkeypatch, caplog):
    import logging
    import loa_cheval.config.loader as loader
    monkeypatch.setattr(loader, "_AGY_TYPE_WARNED", False, raising=False)
    root = _project(tmp_path, "hounfour:\n  headless:\n    agy_opt_in: \"true\"\n")
    with caplog.at_level(logging.WARNING):
        for _ in range(3):
            assert agy_opt_in_enabled(root) is False
    warns = [r for r in caplog.records if "hounfour.headless.agy_opt_in" in r.getMessage()]
    assert len(warns) == 1, [r.getMessage() for r in caplog.records]
    assert "boolean" in warns[0].getMessage() and "str" in warns[0].getMessage()


def test_g12_absent_and_boolean_values_never_warn(tmp_path, monkeypatch, caplog):
    import logging
    import loa_cheval.config.loader as loader
    monkeypatch.setattr(loader, "_AGY_TYPE_WARNED", False, raising=False)
    with caplog.at_level(logging.WARNING):
        for body in ("hounfour: {}\n", "hounfour:\n  headless:\n    agy_opt_in: false\n", "hounfour:\n  headless:\n    agy_opt_in: true\n"):
            sub = tmp_path / str(abs(hash(body)))
            sub.mkdir()
            agy_opt_in_enabled(_project(sub, body))
    assert not [r for r in caplog.records if "hounfour.headless.agy_opt_in" in r.getMessage()]


# --- review r251-1 G18 (SDD D-1.7): the route is available here but not opted in — one WARN per process --------------

def _fake_agy(tmp_path, monkeypatch):
    bindir = tmp_path / "bin"
    bindir.mkdir()
    marker = tmp_path / "spawned"
    agy = bindir / "agy"
    agy.write_text(f"#!/bin/sh\necho spawned > {marker}\n")
    agy.chmod(0o755)
    monkeypatch.setenv("PATH", f"{bindir}:/usr/bin:/bin")
    return marker


def test_g18_agy_on_path_with_the_opt_in_off_warns_once_and_spawns_nothing(tmp_path, monkeypatch, caplog):
    import logging
    import loa_cheval.config.loader as loader
    monkeypatch.setattr(loader, "_AGY_AVAILABLE_WARNED", False, raising=False)
    for k in ("GOOGLE_API_KEY", "GEMINI_API_KEY"):
        monkeypatch.delenv(k, raising=False)
    marker = _fake_agy(tmp_path, monkeypatch)
    root = _project(tmp_path, "hounfour: {}\n")
    with caplog.at_level(logging.WARNING):
        for _ in range(3):
            loader.warn_agy_available_once(root)
    warns = [r for r in caplog.records if "hounfour.headless.agy_opt_in" in r.getMessage()]
    assert len(warns) == 1, [r.getMessage() for r in caplog.records]
    assert "argv" in warns[0].getMessage() and "agy on PATH" in warns[0].getMessage()
    assert not marker.exists()


def test_g18_a_gemini_key_alone_warns_too_and_the_opt_in_on_is_silent(tmp_path, monkeypatch, caplog):
    import logging
    import loa_cheval.config.loader as loader
    monkeypatch.setenv("PATH", "/usr/bin:/bin")
    monkeypatch.setenv("GEMINI_API_KEY", "fixture-not-a-key")
    monkeypatch.setattr(loader, "_AGY_AVAILABLE_WARNED", False, raising=False)
    root = _project(tmp_path, "hounfour: {}\n")
    with caplog.at_level(logging.WARNING):
        loader.warn_agy_available_once(root)
    assert len([r for r in caplog.records if "hounfour.headless.agy_opt_in" in r.getMessage()]) == 1
    caplog.clear()
    monkeypatch.setattr(loader, "_AGY_AVAILABLE_WARNED", False, raising=False)
    (tmp_path / ".loa.config.yaml").write_text("hounfour:\n  headless:\n    agy_opt_in: true\n")
    with caplog.at_level(logging.WARNING):
        loader.warn_agy_available_once(root)
    assert not [r for r in caplog.records if "hounfour.headless.agy_opt_in" in r.getMessage()]


def test_g18_nothing_available_is_silent(tmp_path, monkeypatch, caplog):
    import logging
    import loa_cheval.config.loader as loader
    monkeypatch.setenv("PATH", "/usr/bin:/bin")
    for k in ("GOOGLE_API_KEY", "GEMINI_API_KEY"):
        monkeypatch.delenv(k, raising=False)
    monkeypatch.setattr(loader, "_AGY_AVAILABLE_WARNED", False, raising=False)
    import shutil
    if shutil.which("agy"):
        pytest.skip("agy is on the system PATH")
    with caplog.at_level(logging.WARNING):
        loader.warn_agy_available_once(_project(tmp_path, "hounfour: {}\n"))
    assert not [r for r in caplog.records if "hounfour.headless.agy_opt_in" in r.getMessage()]


# --- review r251-1 G5 (extended, D-1.6): an opt-in refusal never touches the circuit breaker ---------------------------

def test_g5_an_opt_in_refusal_leaves_the_breaker_count_unchanged(monkeypatch):
    from loa_cheval.providers import retry
    monkeypatch.setattr(f"{_MOD}.agy_opt_in_enabled", lambda *a, **k: False)
    recorded = MagicMock()
    monkeypatch.setattr(retry, "_record_failure", recorded)
    monkeypatch.setattr(retry, "_check_circuit_breaker", lambda *a, **k: "CLOSED")
    with pytest.raises(AgyOptInRequiredError):
        retry.invoke_with_retry(_adapter(), _req(), {"routing": {}, "retry": {"max_retries": 2}})
    recorded.assert_not_called()
