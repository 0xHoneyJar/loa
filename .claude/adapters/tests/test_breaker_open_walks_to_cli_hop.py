"""cycle-125 Sprint 4 (PRD FR-4 AC 3, SDD §1.5) — an OPEN provider breaker
self-heals through the within-company chain: with `anthropic/http_api` OPEN,
invoking the `opus` alias never calls the HTTP adapter and lands on the
configured `claude-headless` CLI hop. Runs cheval.cmd_invoke() with mocked
adapters and the REAL retry/breaker path (state files in a temp .run/).
No network. Modelled on test_chain_walk_audit_envelope.py.
"""
from __future__ import annotations

import json
import sys
import time
import types
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from loa_cheval.types import CompletionResult, Usage  # noqa: E402

import cheval  # type: ignore[import-not-found]  # noqa: E402


def _make_args() -> object:
    args = types.SimpleNamespace()
    args.agent = "flatline-reviewer"
    args.role = None
    args.skill = None
    args.sprint_kind = None
    args.input = None
    args.prompt = "test prompt"
    args.system = None
    args.model = "opus"
    args.max_tokens = 4096
    args.output_format = "text"
    args.json_errors = True
    args.timeout = 30
    args.include_thinking = False
    args.async_mode = False
    args.poll_id = None
    args.cancel_id = None
    args.dry_run = False
    args.print_config = False
    args.validate_bindings = False
    args.mock_fixture_dir = None
    args.max_input_tokens = None
    args.reset_breaker = None
    return args


def _anthropic_chain_config():
    """opus → anthropic:claude-opus-5 (http_api) with claude-headless (cli) as the fallback."""
    return {
        "aliases": {
            "opus": "anthropic:claude-opus-5",
            "claude-headless": "anthropic:claude-headless",
        },
        "providers": {
            "anthropic": {
                "type": "anthropic",
                "endpoint": "https://api.anthropic.com/v1",
                "auth": "dummy",
                "models": {
                    "claude-opus-5": {
                        "auth_type": "http_api",
                        "capabilities": ["chat"],
                        "context_window": 200000,
                        "fallback_chain": ["anthropic:claude-headless"],
                    },
                    "claude-headless": {
                        "auth_type": "headless",
                        "kind": "cli",
                        "capabilities": ["chat"],
                        "context_window": 200000,
                        "extra": {"cli_model": "fable"},
                    },
                },
            },
        },
        "routing": {"circuit_breaker": {"reset_timeout_seconds": 3600, "failure_threshold": 5}},
        "feature_flags": {"metering": False},
    }


def _result(model_id: str) -> CompletionResult:
    return CompletionResult(
        content="ok", model=model_id, provider="anthropic",
        usage=Usage(input_tokens=10, output_tokens=5), latency_ms=42,
        tool_calls=None, thinking=None, metadata={"transport": "cli:claude"},
    )


def _capture_modelinv():
    captured: dict = {}

    def _fake(level, event, payload, *_a, **_kw):
        captured.update(payload)

    return captured, _fake


@pytest.fixture(autouse=True)
def _no_persona(monkeypatch):
    monkeypatch.setattr(cheval, "_load_persona", lambda *_a, **_kw: None)
    monkeypatch.setattr(cheval, "_load_persona_parts", lambda *_a, **_kw: (None, None))
    monkeypatch.setattr(cheval, "_check_feature_flags", lambda *_a, **_kw: None)


def _seed_open(run_dir: Path, provider: str, auth: str) -> None:
    run_dir.mkdir(parents=True, exist_ok=True)
    (run_dir / f"circuit-breaker-{provider}-{auth}.json").write_text(json.dumps({
        "provider": provider, "auth_type": auth, "state": "OPEN", "failure_count": 5,
        "last_failure_ts": time.time(), "opened_at": time.time(), "half_open_probes": 0,
    }))


def test_open_http_api_breaker_walks_to_the_cli_hop(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)               # the breaker reads ./.run relative to cwd
    _seed_open(tmp_path / ".run", "anthropic", "http_api")
    cfg = _anthropic_chain_config()

    fake_binding = MagicMock(temperature=0.7, capability_class=None)
    fake_resolved = MagicMock(provider="anthropic", model_id="claude-opus-5")

    primary = MagicMock()
    primary.provider = "anthropic"
    primary.auth_type = "http_api"
    primary.complete.return_value = _result("claude-opus-5")
    fallback = MagicMock()
    fallback.provider = "anthropic"
    fallback.auth_type = "headless"
    fallback.complete.return_value = _result("claude-headless")

    captured, fake_emit = _capture_modelinv()
    with patch.object(cheval, "load_config", return_value=(cfg, {})), \
         patch.object(cheval, "resolve_execution", return_value=(fake_binding, fake_resolved)), \
         patch.object(cheval, "_build_provider_config", return_value=MagicMock()), \
         patch.object(cheval, "get_adapter", side_effect=[primary, fallback]), \
         patch("loa_cheval.audit_envelope.audit_emit", fake_emit), \
         patch("loa_cheval.audit.modelinv.redact_payload_strings", side_effect=lambda x: x), \
         patch("loa_cheval.audit.modelinv.assert_no_secret_shapes_remain"), \
         patch("time.sleep", lambda *_a, **_kw: None):
        exit_code = cheval.cmd_invoke(_make_args())

    out = capsys.readouterr()
    assert exit_code == cheval.EXIT_CODES["SUCCESS"], out.err
    # The OPEN bucket is skipped BEFORE any call: the HTTP adapter never ran.
    assert primary.complete.call_count == 0
    assert fallback.complete.call_count == 1
    assert captured["models_requested"] == ["anthropic:claude-opus-5", "anthropic:claude-headless"]
    assert captured["models_succeeded"] == ["anthropic:claude-headless"]
    failed = captured["models_failed"]
    assert failed and failed[0]["model"] == "anthropic:claude-opus-5"
    assert "Circuit open" in failed[0]["message_redacted"]
    # the OPEN bucket stays OPEN (no dispatch happened against it)
    st = json.loads((tmp_path / ".run" / "circuit-breaker-anthropic-http_api.json").read_text())
    assert st["state"] == "OPEN"


def test_closed_breaker_uses_the_primary_and_never_walks(tmp_path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    (tmp_path / ".run").mkdir()
    cfg = _anthropic_chain_config()
    fake_binding = MagicMock(temperature=0.7, capability_class=None)
    fake_resolved = MagicMock(provider="anthropic", model_id="claude-opus-5")
    primary = MagicMock(); primary.provider = "anthropic"; primary.auth_type = "http_api"
    primary.complete.return_value = _result("claude-opus-5")
    fallback = MagicMock(); fallback.provider = "anthropic"; fallback.auth_type = "headless"
    captured, fake_emit = _capture_modelinv()
    with patch.object(cheval, "load_config", return_value=(cfg, {})), \
         patch.object(cheval, "resolve_execution", return_value=(fake_binding, fake_resolved)), \
         patch.object(cheval, "_build_provider_config", return_value=MagicMock()), \
         patch.object(cheval, "get_adapter", side_effect=[primary, fallback]), \
         patch("loa_cheval.audit_envelope.audit_emit", fake_emit), \
         patch("loa_cheval.audit.modelinv.redact_payload_strings", side_effect=lambda x: x), \
         patch("loa_cheval.audit.modelinv.assert_no_secret_shapes_remain"):
        exit_code = cheval.cmd_invoke(_make_args())
    assert exit_code == cheval.EXIT_CODES["SUCCESS"], capsys.readouterr().err
    assert primary.complete.call_count == 1 and fallback.complete.call_count == 0
    assert captured["models_succeeded"] == ["anthropic:claude-opus-5"]
