"""sprint-bug-216 / #1041 — the preflight-preempt path must emit a MODELINV envelope.

cheval.py's preflight-preempt early-return returns EXIT 7 BEFORE the try/finally
that emits the MODELINV envelope, so a preemption was invisible to
.run/model-invoke.jsonl (the vision-019 M1 silent-degradation surface). This pins
that the preempt path emits an envelope carrying a PREFLIGHT_PREEMPT failure.

Harness mirrors test_chain_walk_audit_envelope.py: mock config/resolution, patch
audit_emit to capture the payload, force a preempt via args.max_input_tokens=1.
"""
from __future__ import annotations

import sys
import types
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import cheval  # type: ignore[import-not-found]


def _make_args() -> object:
    args = types.SimpleNamespace()
    args.agent = "flatline-reviewer"
    args.input = None
    args.prompt = "this is a multi word prompt that is well over one token of input"
    args.system = None
    args.model = None
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
    args.max_input_tokens = 1  # operator ceiling override → preempt a >1-token prompt
    return args


def _single_entry_config():
    return {
        "aliases": {"gpt-5.5-pro": "openai:gpt-5.5-pro"},
        "providers": {
            "openai": {
                "type": "openai",
                "endpoint": "https://api.openai.com/v1",
                "auth": "dummy",
                "models": {"gpt-5.5-pro": {"capabilities": ["chat"], "context_window": 200000}},
            },
        },
        "feature_flags": {"metering": False},
    }


def _capture_modelinv():
    captured: dict = {}

    def _fake(level, event, payload, *_a, **_kw):
        captured.update(payload)

    return captured, _fake


@pytest.fixture(autouse=True)
def _no_persona(monkeypatch):
    monkeypatch.setattr(cheval, "_load_persona", lambda *_a, **_kw: None)
    monkeypatch.setattr(cheval, "_check_feature_flags", lambda *_a, **_kw: None)


def test_preflight_preempt_emits_modelinv(capsys):
    cfg = _single_entry_config()
    fake_binding = MagicMock(temperature=0.7, capability_class=None)
    fake_resolved = MagicMock(provider="openai", model_id="gpt-5.5-pro")
    captured, fake_emit = _capture_modelinv()

    with patch.object(cheval, "load_config", return_value=(cfg, {})), \
         patch.object(cheval, "resolve_execution", return_value=(fake_binding, fake_resolved)), \
         patch.object(cheval, "_build_provider_config", return_value=MagicMock()), \
         patch.object(cheval, "_lookup_capability", return_value=None), \
         patch.object(cheval, "get_adapter", return_value=MagicMock()), \
         patch("loa_cheval.audit_envelope.audit_emit", fake_emit), \
         patch("loa_cheval.audit.modelinv.redact_payload_strings", side_effect=lambda x: x), \
         patch("loa_cheval.audit.modelinv.assert_no_secret_shapes_remain"):
        exit_code = cheval.cmd_invoke(_make_args())

    out = capsys.readouterr()
    assert exit_code == cheval.EXIT_CODES["CONTEXT_TOO_LARGE"], out.err
    assert captured, "preempt path emitted NO MODELINV envelope (#1041 observability gap)"
    failed = captured.get("models_failed", [])
    assert any(f.get("error_class") == "PREFLIGHT_PREEMPT" for f in failed), \
        f"expected a PREFLIGHT_PREEMPT entry in models_failed; got {failed}"
