"""#1026: rehome legacy walker assertions onto production resolution/dispatch."""

import copy
import sys
from pathlib import Path
from unittest.mock import patch

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import cheval
import loa_cheval.routing as routing
from loa_cheval.routing.capability_gate import check
from loa_cheval.routing.chain_resolver import resolve
from loa_cheval.routing.circuit_breaker import record_failure
from loa_cheval.routing.resolver import resolve_execution
from loa_cheval.types import (
    CompletionRequest, CompletionResult, ConfigError, NativeRuntimeRequired,
    ProviderUnavailableError, Usage,
)
from tests.test_chain_walk_audit_envelope import _make_args


def _config():
    return {
        "aliases": {"reviewer": "anthropic:primary", "fallback": "anthropic:cli"},
        "providers": {
            "anthropic": {"type": "anthropic", "models": {
                "primary": {"capabilities": ["chat"], "fallback_chain": ["fallback"]},
                "cli": {"kind": "cli", "auth_type": "headless", "capabilities": ["chat"]},
            }},
            "openai": {"type": "openai", "models": {"other": {"capabilities": ["chat"]}}},
        },
        "agents": {"flatline-reviewer": {"model": "reviewer"}},
        "feature_flags": {"metering": False},
        "retry": {"max_retries": 0},
    }


def test_no_legacy_walker_module_or_exports():
    assert not (Path(routing.__file__).parent / "chains.py").exists()
    for name in ("walk_fallback_chain", "walk_downgrade_chain", "validate_chains"):
        assert not hasattr(routing, name)


def test_alias_chain_is_resolved_upfront_and_config_is_unchanged():
    config = _config()
    config["aliases"]["nested"] = "fallback"
    config["providers"]["anthropic"]["models"]["primary"]["fallback_chain"] = ["nested"]
    original = copy.deepcopy(config)
    chain = resolve("reviewer", model_config=config)
    assert [e.canonical for e in chain.entries] == ["anthropic:primary", "anthropic:cli"]
    assert config == original


@pytest.mark.parametrize("chain", [["reviewer"], ["fallback", "fallback"]])
def test_duplicate_or_cycle_rejected_before_dispatch(chain):
    config = _config()
    config["providers"]["anthropic"]["models"]["primary"]["fallback_chain"] = chain
    with pytest.raises(ConfigError, match="duplicate"):
        resolve("reviewer", model_config=config)


@pytest.mark.parametrize("target", ["missing", "missing:model", "anthropic:missing"])
def test_unresolvable_chain_entry_is_configuration_error(target):
    config = _config()
    config["providers"]["anthropic"]["models"]["primary"]["fallback_chain"] = [target]
    with pytest.raises(ConfigError):
        resolve("reviewer", model_config=config)


@pytest.mark.parametrize("mode", ["prefer-api", "prefer-cli", "api-only", "cli-only"])
@pytest.mark.parametrize("source,target", [
    ("anthropic", "openai"), ("openai", "anthropic"), ("google", "openai"),
])
def test_cross_company_is_rejected_even_if_mode_would_filter_it(mode, source, target):
    config = _config()
    primary = config["providers"]["anthropic"]["models"]["primary"]
    config["providers"] = {
        source: {"type": source, "models": {"primary": primary}},
        target: {"type": target, "models": {"other": {"capabilities": ["chat"]}}},
    }
    config["aliases"]["reviewer"] = f"{source}:primary"
    primary["fallback_chain"] = [f"{target}:other"]
    with pytest.raises(ConfigError, match="company boundary"):
        resolve("reviewer", model_config=config, headless_mode=mode)


def test_absent_chain_retains_primary_and_ignores_dead_provider_routing():
    config = _config()
    del config["providers"]["anthropic"]["models"]["primary"]["fallback_chain"]
    config["routing"] = {"fallback": {"anthropic": ["openai:other"]},
                         "downgrade": {"reviewer": ["openai:other"]}}
    assert [e.canonical for e in resolve("reviewer", model_config=config).entries] == [
        "anthropic:primary",
    ]


@pytest.mark.parametrize("capability", ["thinking_traces", "deep_research", "tools"])
def test_capability_gate_rejects_ineligible_fallback(capability):
    entry = resolve("reviewer", model_config=_config()).entries[1]
    request = CompletionRequest(
        model=entry.model_id, messages=[{"role": "user", "content": "hi"}],
        metadata={"requires_capabilities": [capability]},
    )
    verdict = check(request, entry)
    assert not verdict.ok
    assert verdict.missing == (capability,)


@pytest.mark.parametrize("override", ["reviewer", "openai:other"])
def test_native_binding_cannot_be_overridden_to_remote(override):
    config = _config()
    config["agents"]["native-worker"] = {
        "model": "native", "requires": {"native_runtime": True},
    }
    with pytest.raises(NativeRuntimeRequired):
        resolve_execution("native-worker", config, model_override=override)


@pytest.mark.parametrize("scenario,expected_calls", [
    ("healthy", ["primary"]), ("failure", ["primary", "cli"]),
    ("circuit_open", ["cli"]), ("capability_miss", ["cli"]),
    ("budget_block", []),
])
def test_production_dispatch_walks_with_real_retry_and_gates(
    tmp_path, monkeypatch, capsys, scenario, expected_calls,
):
    config = _config()
    monkeypatch.chdir(tmp_path)
    monkeypatch.setenv("LOA_HEADLESS_MODE", "prefer-api")
    monkeypatch.setattr(cheval, "_load_persona", lambda *a, **kw: None)
    if scenario == "capability_miss":
        config["providers"]["anthropic"]["models"]["primary"]["capabilities"] = []
    if scenario == "circuit_open":
        config["routing"] = {"circuit_breaker": {"failure_threshold": 1}}
        record_failure("anthropic", "http_api", config)
    if scenario == "budget_block":
        config["feature_flags"]["metering"] = True
        config["metering"] = {
            "ledger_path": str(tmp_path / "cost.jsonl"),
            "budget": {"daily_micro_usd": 0, "on_exceeded": "block"},
        }
    calls = []

    class LocalAdapter:
        def __init__(self, entry):
            self.provider = entry.provider
            self.auth_type = "headless" if entry.adapter_kind == "cli" else "http_api"

        def complete(self, request):
            calls.append(request.model)
            if scenario == "failure" and request.model == "primary":
                raise ProviderUnavailableError(self.provider, "local failure")
            return CompletionResult(
                content="ok", tool_calls=None, thinking=None, usage=Usage(1, 1),
                model=request.model, provider=self.provider, latency_ms=1,
            )

    captured = {}
    with patch.object(cheval, "load_config", return_value=(config, {})), \
         patch.object(cheval, "_get_adapter_for_entry", side_effect=lambda e, c: LocalAdapter(e)), \
         patch("loa_cheval.audit_envelope.audit_emit",
               side_effect=lambda level, event, payload, *a, **kw: captured.update(payload)):
        code = cheval.cmd_invoke(_make_args())
    assert calls == expected_calls
    if scenario == "budget_block":
        assert code == cheval.EXIT_CODES["BUDGET_EXCEEDED"], capsys.readouterr().err
    else:
        assert code == 0, capsys.readouterr().err
        assert captured["final_model_id"] == f"anthropic:{expected_calls[-1]}"
        if expected_calls[-1] == "cli":
            assert captured["models_failed"]
