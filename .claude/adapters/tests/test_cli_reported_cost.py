"""#1099: exercise CLI cost through parsing, retry, ledger, and MODELINV."""

import json
import logging
import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import cheval
from loa_cheval.metering.budget import BudgetEnforcer
from loa_cheval.metering.ledger import read_daily_spend, read_ledger
from loa_cheval.metering.rollup import rollup_entries
from loa_cheval.providers.claude_headless_adapter import ClaudeHeadlessAdapter
from loa_cheval.types import CompletionResult, Usage
from tests.test_claude_headless_adapter import _make_config
from tests.test_chain_walk_audit_envelope import _make_args


def _parse(cost, session="cost-test"):
    return ClaudeHeadlessAdapter(_make_config())._parse_json_output(
        parsed={
            "result": "ok", "total_cost_usd": cost, "session_id": session,
            "usage": {"input_tokens": 100, "output_tokens": 10},
            "modelUsage": {"claude-opus-4-7": {}},
        },
        requested_model="claude-headless", latency_ms=1,
    )


def _priced_config():
    return {"providers": {"claude-headless": {"models": {
        "claude-opus-4-7": {"pricing": {
            "input_per_mtok": 5000000, "output_per_mtok": 25000000,
        }},
    }}}}


@pytest.mark.parametrize("reported,expected", [
    (0.053255, 53255), ("0.000001", 1), (0, 0), ("0.0000009", 0),
])
def test_cli_reported_cost_replaces_config_and_deduplicates(tmp_path, reported, expected):
    result = _parse(reported)
    ledger = str(tmp_path / "cost.jsonl")
    hook = BudgetEnforcer(_priced_config(), ledger)
    hook.post_call(result)
    hook.post_call(result)
    rows = read_ledger(ledger)
    assert len(rows) == 1
    assert rows[0]["cost_micro_usd"] == expected
    assert rows[0]["pricing_source"] == "cli_reported"
    assert result.cost_micro_usd == expected
    assert read_daily_spend(ledger) == expected


@pytest.mark.parametrize("cost", [None, True, -1, "bad", "NaN", "Infinity", {}, "1e100"])
def test_invalid_cli_cost_is_not_reported_as_money(cost):
    result = _parse(cost)
    assert getattr(result, "cost_micro_usd", None) is None
    assert result.metadata.get("pricing_source") != "cli_reported"


def test_http_cost_still_uses_config(tmp_path):
    result = CompletionResult(
        content="ok", tool_calls=None, thinking=None, usage=Usage(100, 10),
        model="claude-opus-4-7", provider="claude-headless", latency_ms=1,
        metadata={"total_cost_usd": 99},
    )
    ledger = str(tmp_path / "cost.jsonl")
    BudgetEnforcer(_priced_config(), ledger).post_call(result)
    row = read_ledger(ledger)[0]
    assert row["pricing_source"] == "config"
    assert row["cost_micro_usd"] == 750


@pytest.mark.parametrize("positive", [0.01, 0.0000009])
def test_cli_cost_warning_once_across_adapter_instances(caplog, monkeypatch, positive):
    import loa_cheval.providers.claude_headless_adapter as module
    monkeypatch.setattr(module, "_CLI_COST_WARNED", False, raising=False)
    with caplog.at_level(logging.WARNING):
        _parse(0)
        _parse(positive, "first")
        assert any("CLI-reported cost" in r.message for r in caplog.records)
        _parse(0.02, "second")
    warnings = [r.message for r in caplog.records if "CLI-reported cost" in r.message]
    assert len(warnings) == 1
    assert "api-only" in warnings[0]
    assert "billing" in warnings[0]


def test_rollup_recognizes_cli_reported_cost_as_priced(tmp_path):
    ledger = str(tmp_path / "cost.jsonl")
    BudgetEnforcer(_priced_config(), ledger).post_call(_parse(0.053255))
    rows = rollup_entries(read_ledger(ledger))
    assert rows[0]["cost_micro_usd"] == 53255
    assert rows[0]["unpriced_calls"] == 0


def test_real_cli_dispatch_records_same_cost_in_ledger_and_modelinv(tmp_path, monkeypatch, capsys):
    """Real executable + cmd_invoke + retry + budget; no mock-fixture bypass."""
    binary = tmp_path / "claude"
    binary.write_text(
        "#!/usr/bin/env python3\nimport json\n"
        "print(json.dumps({'result':'ok','total_cost_usd':0.053255,"
        "'session_id':'local-cost-cli','usage':{'input_tokens':100,'output_tokens':10},"
        "'modelUsage':{'claude-opus-4-7':{}}}))\n"
    )
    binary.chmod(0o755)
    monkeypatch.chdir(tmp_path)
    # cycle-124 FR-6: LOA_COST_LEDGER_PATH (set by conftest) outranks metering.ledger_path;
    # this test reads the config-supplied ledger, so drop the env override.
    monkeypatch.delenv("LOA_COST_LEDGER_PATH", raising=False)
    monkeypatch.setenv("CLAUDE_HEADLESS_BIN", str(binary))
    monkeypatch.setenv("LOA_HEADLESS_MODE", "cli-only")
    monkeypatch.setattr(cheval, "_load_persona", lambda *a, **kw: None)
    monkeypatch.setattr(cheval, "_load_persona_parts", lambda *a, **kw: (None, None))
    monkeypatch.setattr(cheval, "_check_feature_flags", lambda *a, **kw: None)
    ledger = tmp_path / "cost.jsonl"
    cfg = {
        "providers": {"anthropic": {
            "type": "anthropic", "endpoint": "", "auth": "",
            "models": {"claude-headless": {
                "kind": "cli", "auth_type": "headless", "capabilities": ["chat"],
                "context_window": 200000, "extra": {"cli_model": "opus"},
            }},
        }},
        "metering": {"ledger_path": str(ledger)},
        "retry": {"max_retries": 0},
    }
    captured = {}
    with patch.object(cheval, "load_config", return_value=(cfg, {})), \
         patch.object(cheval, "resolve_execution", return_value=(
             MagicMock(temperature=0.7, capability_class=None),
             MagicMock(provider="anthropic", model_id="claude-headless"),
         )), \
         patch("loa_cheval.audit_envelope.audit_emit",
               side_effect=lambda level, event, payload, *a, **kw: captured.update(payload)):
        code = cheval.cmd_invoke(_make_args())
    assert code == 0, capsys.readouterr().err
    assert read_ledger(str(ledger))[0]["cost_micro_usd"] == 53255
    assert read_ledger(str(ledger))[0]["pricing_source"] == "cli_reported"
    assert captured["cost_micro_usd"] == 53255
