"""cycle-127 Sprint 1 Task 1.3 (FR-2 / SDD D-2.1 … D-2.3): the Opus 5.5
catalog effort default, resolved once at the cheval chokepoint.

Claude Opus 5.5's vendor effort default is `medium`, one below Opus 5's
`high`; the catalog entry carries `params.default_effort: high` and cheval
resolves `resolve_effort(args, entry) -> (value, source)`:

    explicit --effort            -> (value, "caller")
    entry.params.default_effort  -> (value, "catalog")
    a CLI entry's extra.effort   -> (value, "extra")     # the headless adapter's legacy rung
    otherwise                    -> (None,  "none")      # vendor default, nothing on the wire

The catalog is not schema-validated at load, so an invalid default_effort is
skipped with one WARN (never a crash); `effort_effective` records the wire
value after the adapter's per-family mapping (xhigh -> high on Opus 4.6).

The entry is the RESOLVED one (`opus` -> claude-opus-5-5). Both adapters keep
their contracts: the HTTP adapter emits `output_config.effort` for
`request.effort`, the CLI adapter passes `--effort` first; the MODELINV
envelope records `effort_source` next to `effort`; `--dry-run` reports both
and prints `effort: high (catalog default)` / `effort: low (caller)`.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import types
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest
import yaml

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

import cheval  # type: ignore[import-not-found]  # noqa: E402
from loa_cheval.providers import claude_headless_adapter as headless_mod  # noqa: E402
from loa_cheval.providers.anthropic_adapter import AnthropicAdapter  # noqa: E402
from loa_cheval.providers.claude_headless_adapter import ClaudeHeadlessAdapter  # noqa: E402
from loa_cheval.types import (  # noqa: E402
    CompletionResult,
    ModelConfig,
    ProviderConfig,
    Usage,
)

REPO_ROOT = ROOT.parents[1]
CATALOG = REPO_ROOT / ".claude" / "defaults" / "model-config.yaml"
CHEVAL = ROOT / "cheval.py"


@pytest.fixture(scope="module")
def catalog() -> dict:
    with CATALOG.open() as fh:
        return yaml.safe_load(fh)


def _ns(effort=None):
    return types.SimpleNamespace(effort=effort)


# --- the catalog value -------------------------------------------------------

def test_opus_5_5_catalog_sets_default_effort_high(catalog):
    params = catalog["providers"]["anthropic"]["models"]["claude-opus-5-5"]["params"]
    assert params["default_effort"] == "high"
    # the entry's other gates are kept
    assert params["thinking_adaptive"] is True and params["temperature_supported"] is False


def test_no_other_entry_sets_default_effort_this_cycle(catalog):
    setters = [
        f"{p}:{m}"
        for p, prov in (catalog.get("providers") or {}).items()
        for m, e in ((prov or {}).get("models") or {}).items()
        if isinstance(e, dict) and "default_effort" in ((e.get("params") or {}))
    ]
    assert setters == ["anthropic:claude-opus-5-5"]


# --- resolve_effort precedence ----------------------------------------------

def test_caller_wins_over_the_catalog(catalog):
    entry = catalog["providers"]["anthropic"]["models"]["claude-opus-5-5"]
    assert cheval.resolve_effort(_ns("low"), entry) == ("low", "caller")
    assert cheval.resolve_effort(_ns("max"), entry) == ("max", "caller")


def test_catalog_default_when_no_caller_value(catalog):
    entry = catalog["providers"]["anthropic"]["models"]["claude-opus-5-5"]
    assert cheval.resolve_effort(_ns(None), entry) == ("high", "catalog")


def test_none_when_neither(catalog):
    entry = catalog["providers"]["anthropic"]["models"]["claude-opus-5"]
    assert cheval.resolve_effort(_ns(None), entry) == (None, "none")
    assert cheval.resolve_effort(_ns(None), {}) == (None, "none")
    assert cheval.resolve_effort(_ns(None), None) == (None, "none")
    assert cheval.resolve_effort(types.SimpleNamespace(), None) == (None, "none")


@pytest.fixture(autouse=True)
def _fresh_warn_once(monkeypatch):
    monkeypatch.setattr(cheval, "_EFFORT_WARNED", set())


def test_entry_without_params_or_without_default_effort_is_none():
    assert cheval.resolve_effort(_ns(None), {"context_window": 1}) == (None, "none")
    assert cheval.resolve_effort(_ns(None), {"params": {"thinking_adaptive": True}}) == (None, "none")
    assert cheval.resolve_effort(_ns(None), {"params": None}) == (None, "none")


@pytest.mark.parametrize("bad", ["ultra", "HIGH", 3, True, ["high"], None])
def test_invalid_catalog_value_is_none_with_one_warn_never_a_crash(bad, caplog):
    entry = {"params": {"default_effort": bad}}
    with caplog.at_level("WARNING"):
        assert cheval.resolve_effort(_ns(None), entry, model_key="anthropic:m") == (None, "none")
        assert cheval.resolve_effort(_ns(None), entry, model_key="anthropic:m") == (None, "none")
    warns = [r for r in caplog.records if "default_effort" in r.getMessage() and "ignored" in r.getMessage()]
    assert len(warns) == 1


def test_invalid_catalog_value_does_not_shadow_an_explicit_caller_value():
    assert cheval.resolve_effort(_ns("low"), {"params": {"default_effort": "ultra"}}) == ("low", "caller")


def test_extra_rung_applies_to_a_cli_entry_only_and_sits_below_the_catalog():
    cli = {"kind": "cli", "extra": {"effort": "Medium "}}
    assert cheval.resolve_effort(_ns(None), cli) == ("medium", "extra")
    assert cheval.resolve_effort(_ns(None), {"auth_type": "headless", "extra": {"reasoning_effort": "max"}}) == ("max", "extra")
    # an HTTP entry's extra is never read (its adapter does not read it either)
    assert cheval.resolve_effort(_ns(None), {"auth_type": "http_api", "extra": {"effort": "low"}}) == (None, "none")
    both = {"kind": "cli", "extra": {"effort": "low"}, "params": {"default_effort": "high"}}
    assert cheval.resolve_effort(_ns(None), both) == ("high", "catalog")
    assert cheval.resolve_effort(_ns("max"), both) == ("max", "caller")
    assert cheval.resolve_effort(_ns(None), {"kind": "cli", "extra": {"effort": "ultra"}}) == (None, "none")


def test_an_entry_setting_both_rungs_warns_once(caplog):
    both = {"kind": "cli", "extra": {"effort": "low"}, "params": {"default_effort": "high"}}
    with caplog.at_level("WARNING"):
        for _ in range(3):
            cheval.resolve_effort(_ns(None), both, model_key="anthropic:claude-headless")
    warns = [r for r in caplog.records if "sets both params.default_effort and extra.effort" in r.getMessage()]
    assert len(warns) == 1 and "anthropic:claude-headless" in warns[0].getMessage()


def test_alias_resolves_to_the_entry_before_the_catalog_rung(catalog):
    """`opus` is a string alias without params: the default comes from the
    entry it resolves to, through the production resolver."""
    from loa_cheval.config.loader import load_config
    from loa_cheval.routing.resolver import resolve_execution
    hounfour, _ = load_config(project_root=str(REPO_ROOT))
    assert isinstance(hounfour["aliases"]["opus"], str)
    _, resolved = resolve_execution("reviewing-code", hounfour, model_override="opus")
    assert (resolved.provider, resolved.model_id) == ("anthropic", "claude-opus-5-5")
    entry = cheval._raw_model_entry(resolved.provider, resolved.model_id, hounfour)
    assert cheval.resolve_effort(_ns(None), entry) == ("high", "catalog")


def test_effort_on_wire_follows_the_adapter_mapping(catalog):
    assert cheval._effort_on_wire("anthropic", "claude-opus-4-6", "xhigh", catalog) == "high"
    assert cheval._effort_on_wire("anthropic", "claude-opus-5-5", "high", catalog) == "high"
    assert cheval._effort_on_wire("anthropic", "claude-haiku-4-5-20251001", "high", catalog) is None
    assert cheval._effort_on_wire("anthropic", "claude-headless", "xhigh", catalog) == "xhigh"
    assert cheval._effort_on_wire("openai", "gpt-5.5", "high", catalog) is None
    assert cheval._effort_on_wire("anthropic", "claude-opus-5-5", None, catalog) is None


# --- dry-run over the LIVE catalog (alias resolution included) ---------------

def _no_claude_path() -> str:
    """The host PATH minus every directory that holds a `claude` / `claude-bedrock`."""
    keep = [d for d in os.environ.get("PATH", "").split(os.pathsep)
            if d and not any(os.path.exists(os.path.join(d, n)) for n in ("claude", "claude-bedrock"))]
    return os.pathsep.join(keep) or os.defpath


def _dry(*argv: str) -> subprocess.CompletedProcess:
    # r251-4 T6 (n31): a regressed --dry-run that walks to the headless hop must never
    # reach the real CLI — CLAUDE_HEADLESS_BIN points at a path that does not exist and
    # no PATH directory holds a `claude`
    env = {k: v for k, v in os.environ.items() if k not in ("ANTHROPIC_API_KEY", "AWS_BEARER_TOKEN_BEDROCK")}
    env["CLAUDE_HEADLESS_BIN"] = str(REPO_ROOT / ".run" / "loa-test-claude-must-not-run")
    env["PATH"] = _no_claude_path()
    assert not os.path.exists(env["CLAUDE_HEADLESS_BIN"])
    return subprocess.run(
        [sys.executable, str(CHEVAL), "--agent", "reviewing-code", "--prompt", "c127-effort",
         "--dry-run", "--json-errors", *argv],
        capture_output=True, text=True, env=env, cwd=str(REPO_ROOT), timeout=120,
    )


def test_dry_env_cannot_reach_a_real_claude():
    import shutil
    path = _no_claude_path()
    assert shutil.which("claude", path=path) is None and shutil.which("claude-bedrock", path=path) is None


def test_dry_run_opus_without_effort_reports_the_catalog_high():
    proc = _dry("--model", "opus")
    assert proc.returncode == 0, proc.stderr
    out = json.loads(proc.stdout)
    # the alias resolves first; only then is the entry's default read
    assert out["resolved_provider"] == "anthropic" and out["resolved_model"] == "claude-opus-5-5"
    assert out["effort"] == "high" and out["effort_effective"] == "high"
    assert out["effort_source"] == "catalog"
    assert "effort: high (catalog default)" in proc.stderr


def test_dry_run_explicit_effort_reports_the_caller_value():
    proc = _dry("--model", "opus", "--effort", "low")
    assert proc.returncode == 0, proc.stderr
    out = json.loads(proc.stdout)
    assert out["effort"] == "low" and out["effort_source"] == "caller"
    assert "effort: low (caller)" in proc.stderr
    assert "catalog default" not in proc.stderr


def test_dry_run_names_the_effective_wire_value_when_the_adapter_maps_it():
    """No live alias reaches an xhigh-less family any more (4-6 aliases to 4-7);
    the omission mapping is live (Haiku 4.5 predates output_config.effort).
    The xhigh → high downgrade is covered in-process and at unit level."""
    proc = _dry("--model", "tiny", "--effort", "high")
    assert proc.returncode == 0, proc.stderr
    out = json.loads(proc.stdout)
    assert out["resolved_model"] == "claude-haiku-4-5-20251001"
    assert out["effort"] == "high" and out["effort_source"] == "caller" and out["effort_effective"] is None
    assert "effort: high (caller) → effective none (omitted on claude-haiku-4-5-20251001)" in proc.stderr


def test_dry_run_opus_5_has_no_default_and_prints_nothing():
    proc = _dry("--model", "claude-opus-5")
    assert proc.returncode == 0, proc.stderr
    out = json.loads(proc.stdout)
    assert out["resolved_model"] == "claude-opus-5"
    assert out["effort"] is None and out["effort_source"] == "none"
    assert "effort:" not in proc.stderr


# --- in-process invoke: request threading + MODELINV envelope ---------------

def _args(effort=None):
    a = types.SimpleNamespace()
    a.agent = "agentx"; a.role = None; a.skill = None; a.sprint_kind = None
    a.input = None; a.prompt = "review"; a.system = None; a.model = None
    a.max_tokens = None; a.effort = effort; a.output_format = "text"
    a.json_errors = True; a.timeout = 30; a.include_thinking = False; a.async_mode = False
    a.poll_id = None; a.cancel_id = None; a.dry_run = False; a.print_config = False
    a.validate_bindings = False; a.mock_fixture_dir = None; a.max_input_tokens = None
    a.json_schema = None
    return a


def _cfg(params_55=None):
    p55 = {"temperature_supported": False, "thinking_adaptive": True, "default_effort": "high"}
    if params_55 is not None:
        p55 = params_55
    return {
        "aliases": {"claude-opus-5-5": "anthropic:claude-opus-5-5", "claude-opus-5": "anthropic:claude-opus-5"},
        "providers": {"anthropic": {"type": "anthropic", "endpoint": "https://x", "auth": "dummy", "models": {
            "claude-opus-5-5": {"capabilities": ["chat"], "context_window": 1_000_000,
                                "max_output_tokens": 128_000, "params": p55},
            "claude-opus-5": {"capabilities": ["chat"], "context_window": 1_000_000,
                              "max_output_tokens": 128_000,
                              "params": {"temperature_supported": False, "thinking_adaptive": True}},
        }}},
        "feature_flags": {"metering": False},
    }


def _invoke(monkeypatch, *, model_id="claude-opus-5-5", effort=None, cfg=None):
    monkeypatch.setattr(cheval, "_check_feature_flags", lambda *_a, **_kw: None)
    monkeypatch.setattr(cheval, "_load_persona_parts", lambda *_a, **_kw: (None, None))
    monkeypatch.setattr(cheval, "_load_persona", lambda *_a, **_kw: None)
    seen, captured = [], {}

    def _retry_side(_adapter, req, _cfg, budget_hook=None):
        seen.append(req)
        return CompletionResult(content="ok", model=req.model, provider="anthropic",
                                usage=Usage(input_tokens=10, output_tokens=5), latency_ms=1, tool_calls=None,
                                thinking=None, metadata={"streaming": True})

    with patch.object(cheval, "load_config", return_value=(cfg if cfg is not None else _cfg(), {})), \
         patch.object(cheval, "resolve_execution", return_value=(MagicMock(temperature=None, capability_class=None),
                                                                  MagicMock(provider="anthropic", model_id=model_id))), \
         patch.object(cheval, "_build_provider_config", return_value=MagicMock()), \
         patch.object(cheval, "get_adapter", return_value=MagicMock()), \
         patch("loa_cheval.providers.retry.invoke_with_retry", side_effect=_retry_side), \
         patch("loa_cheval.audit_envelope.audit_emit", lambda level, event, payload, *a, **k: captured.update(payload)), \
         patch("loa_cheval.audit.modelinv.redact_payload_strings", side_effect=lambda x: x), \
         patch("loa_cheval.audit.modelinv.assert_no_secret_shapes_remain"):
        code = cheval.cmd_invoke(_args(effort))
    return code, seen, captured


def test_invoke_threads_the_catalog_default_and_records_its_source(monkeypatch):
    code, seen, captured = _invoke(monkeypatch)
    assert code == 0
    assert seen and seen[0].effort == "high"
    assert captured["effort"] == "high"
    assert captured["effort_source"] == "catalog"
    assert captured["effort_effective"] == "high"


def test_invoke_caller_value_wins_and_is_recorded_as_caller(monkeypatch):
    code, seen, captured = _invoke(monkeypatch, effort="low")
    assert code == 0
    assert seen[0].effort == "low"
    assert captured["effort"] == "low" and captured["effort_source"] == "caller"


def test_invoke_without_any_default_sends_nothing(monkeypatch):
    code, seen, captured = _invoke(monkeypatch, model_id="claude-opus-5")
    assert code == 0
    assert seen[0].effort is None
    assert "effort" not in captured and "effort_effective" not in captured
    assert captured["effort_source"] == "none"


def test_invoke_invalid_catalog_value_dispatches_with_nothing_and_warns(monkeypatch, caplog):
    cfg = _cfg(params_55={"temperature_supported": False, "default_effort": "ultra"})
    with caplog.at_level("WARNING"):
        code, seen, captured = _invoke(monkeypatch, cfg=cfg)
    assert code == 0
    assert seen[0].effort is None and captured["effort_source"] == "none"
    assert any("default_effort" in r.getMessage() and "ignored" in r.getMessage() for r in caplog.records)


def test_invoke_records_the_downgraded_wire_value(monkeypatch):
    cfg = _cfg()
    cfg["providers"]["anthropic"]["models"]["claude-opus-4-6"] = {"capabilities": ["chat"], "context_window": 1_000_000,
                                                                 "max_output_tokens": 128_000}
    code, seen, captured = _invoke(monkeypatch, model_id="claude-opus-4-6", effort="xhigh", cfg=cfg)
    assert code == 0
    assert seen[0].effort == "xhigh"            # the adapter maps it; the request carries the caller's value
    assert captured["effort"] == "xhigh" and captured["effort_effective"] == "high"


# --- both adapters emit the resolved default (contracts unchanged) ----------

def _anthropic_body(monkeypatch, request) -> dict:
    monkeypatch.setenv("LOA_CHEVAL_DISABLE_STREAMING", "1")
    cfg = ProviderConfig(name="anthropic", type="anthropic", endpoint="https://api.anthropic.com/v1",
                         auth="sk-ant-test", connect_timeout=10.0, read_timeout=30.0,
                         models={"claude-opus-5-5": ModelConfig(capabilities=["chat"], context_window=1_000_000,
                                                                params={"temperature_supported": False,
                                                                        "thinking_adaptive": True,
                                                                        "default_effort": "high"})})
    adapter = AnthropicAdapter(cfg)
    captured: dict = {}

    def _fake_ns(url, headers, body):
        captured["body"] = body
        return "sentinel"

    monkeypatch.setattr(adapter, "_complete_nonstreaming", _fake_ns)
    adapter.complete(request)
    return captured["body"]


def test_http_adapter_emits_output_config_effort_high_for_the_default(monkeypatch):
    _, seen, _ = _invoke(monkeypatch)
    body = _anthropic_body(monkeypatch, seen[0])
    assert body["output_config"]["effort"] == "high"


def test_http_adapter_sends_no_effort_for_a_model_without_default(monkeypatch):
    _, seen, _ = _invoke(monkeypatch, model_id="claude-opus-5")
    req = seen[0]
    req.model = "claude-opus-5-5"   # same body builder; only the effort field matters here
    body = _anthropic_body(monkeypatch, req)
    assert "effort" not in (body.get("output_config") or {})


def test_cli_adapter_command_carries_effort_high_for_the_default(monkeypatch):
    monkeypatch.setattr(headless_mod, "_JSON_SCHEMA_FLAG", False)
    _, seen, _ = _invoke(monkeypatch)
    adapter = ClaudeHeadlessAdapter(ProviderConfig(
        name="claude-headless", type="claude-headless", endpoint="", auth="",
        connect_timeout=10.0, read_timeout=600.0,
        models={"claude-opus-5-5": ModelConfig(context_window=1_000_000)}))
    cmd = adapter._build_command(seen[0], adapter.config.models["claude-opus-5-5"], None)
    assert cmd[cmd.index("--effort") + 1] == "high"


def test_cli_adapter_extra_effort_stays_below_the_chokepoint_value(monkeypatch):
    monkeypatch.setattr(headless_mod, "_JSON_SCHEMA_FLAG", False)
    _, seen, _ = _invoke(monkeypatch)
    model_cfg = ModelConfig(context_window=1_000_000, extra={"effort": "low"})
    adapter = ClaudeHeadlessAdapter(ProviderConfig(
        name="claude-headless", type="claude-headless", endpoint="", auth="",
        connect_timeout=10.0, read_timeout=600.0, models={"claude-opus-5-5": model_cfg}))
    cmd = adapter._build_command(seen[0], model_cfg, None)
    assert cmd[cmd.index("--effort") + 1] == "high"
    _, seen_none, _ = _invoke(monkeypatch, model_id="claude-opus-5")
    cmd = adapter._build_command(seen_none[0], model_cfg, None)
    assert cmd[cmd.index("--effort") + 1] == "low"   # legacy rung still applies when nothing is resolved


# --- MODELINV schema --------------------------------------------------------

def test_modelinv_schema_declares_effort_source():
    schema_path = REPO_ROOT / ".claude" / "data" / "trajectory-schemas" / "model-events" / \
        "model-invoke-complete.payload.schema.json"
    schema = json.loads(schema_path.read_text())
    assert schema["properties"]["effort_source"]["enum"] == ["caller", "catalog", "extra", "none"]
    assert schema["properties"]["effort_effective"]["enum"] == ["low", "medium", "high", "xhigh", "max"]
    assert not {"effort_source", "effort_effective"} & set(schema.get("required", []))


# --- review r251-1 G7 (finding 25): an invalid CLI extra.effort is not silently skipped -------------------------------

@pytest.mark.parametrize("key", ["effort", "reasoning_effort"])
def test_invalid_extra_effort_warns_once_per_model_and_reason(key, caplog):
    entry = {"kind": "cli", "extra": {key: "ultra"}}
    with caplog.at_level("WARNING"):
        for _ in range(3):
            assert cheval.resolve_effort(_ns(None), entry, model_key="anthropic:claude-headless") == (None, "none")
    warns = [r for r in caplog.records if "extra." in r.getMessage() and "ignored" in r.getMessage()]
    assert len(warns) == 1, [r.getMessage() for r in caplog.records]
    assert "anthropic:claude-headless" in warns[0].getMessage() and "'ultra'" in warns[0].getMessage()


def test_invalid_extra_effort_on_an_http_entry_is_not_read_and_not_warned(caplog):
    with caplog.at_level("WARNING"):
        assert cheval.resolve_effort(_ns(None), {"auth_type": "http_api", "extra": {"effort": "ultra"}}) == (None, "none")
    assert not [r for r in caplog.records if "extra." in r.getMessage()]


def test_extra_rung_iterates_both_keys_in_the_adapter_order(caplog):
    """r251-1 G7 (refined): like ClaudeHeadlessAdapter._resolve_effort — extra.effort, then extra.reasoning_effort — an
    invalid first key does not hide a valid second one, and the invalid one is said once."""
    entry = {"kind": "cli", "extra": {"effort": "ultra", "reasoning_effort": "low"}}
    with caplog.at_level("WARNING"):
        for _ in range(2):
            assert cheval.resolve_effort(_ns(None), entry, model_key="anthropic:claude-headless") == ("low", "extra")
    warns = [r for r in caplog.records if "extra.effort" in r.getMessage() and "ignored" in r.getMessage()]
    assert len(warns) == 1, [r.getMessage() for r in caplog.records]
    assert cheval.resolve_effort(_ns(None), {"kind": "cli", "extra": {"effort": "high", "reasoning_effort": "low"}}) == ("high", "extra")


def test_r251_4_a_wire_effort_failure_never_loses_the_modelinv_envelope(monkeypatch, caplog):
    """r251-4 S8 (audit n29/n30): `_effort_on_wire` runs inside the MODELINV emit's try — an exception there used to lose
    the whole envelope ([AUDIT-EMIT-FAILED]). It is now evaluated in its own try: the field records None, one WARN."""
    import logging
    def _boom(*_a, **_k):
        raise RuntimeError("wire_effort exploded")
    monkeypatch.setattr(cheval, "_effort_on_wire", _boom)
    with caplog.at_level(logging.WARNING):
        code, seen, captured = _invoke(monkeypatch)
    assert code == 0
    assert captured.get("effort") == "high" and captured.get("effort_source") == "catalog", captured
    assert captured.get("effort_effective") is None
    assert any("effort_effective" in r.getMessage() and "wire_effort exploded" in r.getMessage() for r in caplog.records), \
        [r.getMessage() for r in caplog.records]
