"""cycle-127 review r251-1 G1/G5 — cheval's own chain walk plans around a gated agy hop.

The bash planners drop `gemini-headless` before dispatch; cheval's walk must do the same for the chains it resolves
itself. With `hounfour.headless.agy_opt_in` off:

  * a Google-primary chain whose fallback reaches `google:gemini-headless` (every stock Google chain ends there) never
    dispatches that hop — the hop is recorded in MODELINV `models_not_planned` with `reason: opt_in_required`, it is
    not in `models_requested` (verdict quality counts planned hops only), not a failure, and the walk continues;
  * `hounfour.headless.mode: prefer-cli` (agy first) skips the hop and dispatches the API hop as the PRIMARY;
  * a direct `--model gemini-headless` (agy asked for by name — the chain is agy alone) still refuses with
    INVALID_CONFIG, and the JSON error envelope carries `failure_class: opt_in_required` (G5);
  * one WARN per process names the key.
No model is called: adapters are mocks, the MODELINV emit is captured.
"""

from __future__ import annotations

import json
import logging
import sys
import types
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from loa_cheval.types import AgyOptInRequiredError, CompletionResult, Usage  # noqa: E402

import cheval  # type: ignore[import-not-found]  # noqa: E402


def _args(model=None):
    a = types.SimpleNamespace(
        agent="flatline-reviewer", role=None, skill=None, sprint_kind=None, input=None, prompt="review this", system=None,
        model=model, max_tokens=4096, output_format="text", json_errors=True, timeout=30, include_thinking=False,
        async_mode=False, poll_id=None, cancel_id=None, dry_run=False, print_config=False, validate_bindings=False,
        mock_fixture_dir=None, max_input_tokens=None,
    )
    return a


def _cfg():
    return {
        "aliases": {"gemini-2.5-pro": "google:gemini-2.5-pro", "gemini-headless": "google:gemini-headless"},
        "providers": {
            "google": {
                "type": "google", "endpoint": "https://generativelanguage.googleapis.com/v1beta", "auth": "dummy",
                "models": {
                    "gemini-2.5-pro": {"capabilities": ["chat"], "context_window": 1048576,
                                       "fallback_chain": ["google:gemini-headless"]},
                    "gemini-headless": {"kind": "cli", "auth_type": "headless", "capabilities": ["chat"],
                                        "context_window": 1048576, "extra": {"cli_model": "Gemini 3.1 Pro (High)"}},
                },
            },
        },
        "feature_flags": {"metering": False},
    }


def _result(model_id):
    return CompletionResult(content="ok", model=model_id, provider="google", usage=Usage(input_tokens=10, output_tokens=5),
                            latency_ms=7, tool_calls=None, thinking=None, metadata={})


@pytest.fixture(autouse=True)
def _isolate(monkeypatch):
    monkeypatch.setattr(cheval, "_load_persona", lambda *_a, **_kw: None)
    monkeypatch.setattr(cheval, "_load_persona_parts", lambda *_a, **_kw: (None, None))
    monkeypatch.setattr(cheval, "_check_feature_flags", lambda *_a, **_kw: None)
    monkeypatch.setattr(cheval, "_AGY_NOT_PLANNED_WARNED", False, raising=False)
    monkeypatch.delenv("LOA_HEADLESS_MODE", raising=False)
    # (the D-1.7 availability WARN is pinned by its own test below; host PATH/keys must not change these counts)
    monkeypatch.setattr("loa_cheval.config.loader._AGY_AVAILABLE_WARNED", True)


def _invoke(*, opt_in, model=None, provider="google", model_id="gemini-2.5-pro", dispatch=None):
    """Run cmd_invoke; `dispatch(request) -> result` stands in for invoke_with_retry. Returns (exit, payload, err, models)."""
    captured: dict = {}
    seen: list = []

    def _emit(level, event, payload, *_a, **_kw):
        captured.update(payload)

    def _retry(adapter, req, _cfg, budget_hook=None):
        seen.append(req.model)
        return (dispatch or (lambda r: _result(r.model)))(req)

    with patch("loa_cheval.config.loader.agy_opt_in_enabled", lambda *a, **k: opt_in), \
         patch.object(cheval, "load_config", return_value=(_cfg(), {})), \
         patch.object(cheval, "resolve_execution", return_value=(MagicMock(temperature=0.7, capability_class=None),
                                                                 MagicMock(provider=provider, model_id=model_id))), \
         patch.object(cheval, "_build_provider_config", return_value=MagicMock()), \
         patch.object(cheval, "get_adapter", return_value=MagicMock()), \
         patch("loa_cheval.providers.retry.invoke_with_retry", side_effect=_retry), \
         patch("loa_cheval.audit_envelope.audit_emit", _emit), \
         patch("loa_cheval.audit.modelinv.redact_payload_strings", side_effect=lambda x: x), \
         patch("loa_cheval.audit.modelinv.assert_no_secret_shapes_remain"):
        rc = cheval.cmd_invoke(_args(model))
    return rc, captured, seen


def test_a_gated_agy_fallback_is_skipped_and_never_dispatched(capsys, caplog):
    """[gemini-2.5-pro, gemini-headless] with the API hop failing walkably: the agy hop is not dispatched — the walk
    has nothing planned left (single planned hop), so the API hop's own failure is the result, not INVALID_CONFIG."""
    from loa_cheval.types import RetriesExhaustedError

    def _fail(req):
        raise RetriesExhaustedError(total_attempts=4, last_error="503")
    with caplog.at_level(logging.WARNING):
        rc, payload, seen = _invoke(opt_in=False, dispatch=_fail)
    err = capsys.readouterr().err
    assert seen == ["gemini-2.5-pro"], seen
    assert rc == cheval.EXIT_CODES["RETRIES_EXHAUSTED"], err
    assert "INVALID_CONFIG" not in err
    assert payload["models_requested"] == ["google:gemini-2.5-pro"]
    assert payload["models_not_planned"] == [
        {"model": "google:gemini-headless", "provider": "google", "reason": "opt_in_required"}]
    assert [f["model"] for f in payload["models_failed"]] == ["google:gemini-2.5-pro"]


def test_prefer_api_success_records_the_skip_and_the_primary_answers(capsys):
    rc, payload, seen = _invoke(opt_in=False)
    assert rc == 0, capsys.readouterr().err
    assert seen == ["gemini-2.5-pro"]
    assert payload["models_succeeded"] == ["google:gemini-2.5-pro"]
    assert payload["models_not_planned"][0]["reason"] == "opt_in_required"
    assert payload["models_failed"] == []


def test_prefer_cli_puts_agy_first_and_the_api_hop_is_dispatched_as_primary(capsys, monkeypatch):
    monkeypatch.setenv("LOA_HEADLESS_MODE", "prefer-cli")
    rc, payload, seen = _invoke(opt_in=False)
    assert rc == 0, capsys.readouterr().err
    assert seen == ["gemini-2.5-pro"]
    assert payload["models_requested"] == ["google:gemini-2.5-pro"]
    assert payload["final_model_id"] == "google:gemini-2.5-pro"
    vq = payload["verdict_quality"]  # the planned voice answered on its primary — not degraded on the agy hop's account
    assert vq["chain_health"] == "ok" and vq["voices_planned"] == 1 and vq["status"] == "APPROVED", vq


def test_opt_in_on_keeps_the_hop_in_the_walk(capsys, monkeypatch):
    monkeypatch.setenv("LOA_HEADLESS_MODE", "prefer-cli")
    rc, payload, seen = _invoke(opt_in=True)
    assert rc == 0, capsys.readouterr().err
    assert seen == ["gemini-headless"]
    assert "models_not_planned" not in payload
    assert payload["models_requested"] == ["google:gemini-headless", "google:gemini-2.5-pro"]


def test_one_warn_per_process_names_the_key(capsys, caplog):
    with caplog.at_level(logging.WARNING):
        _invoke(opt_in=False)
        _invoke(opt_in=False)
    capsys.readouterr()
    warns = [r for r in caplog.records if "hounfour.headless.agy_opt_in" in r.getMessage()]
    assert len(warns) == 1, [r.getMessage() for r in caplog.records]
    assert "not planned" in warns[0].getMessage()


def test_direct_gemini_headless_still_refuses_with_failure_class(capsys):
    """G1 + G5: the operator asked for agy by name — INVALID_CONFIG, and the JSON envelope names the failure class."""
    def _refuse(req):
        raise AgyOptInRequiredError()
    rc, payload, seen = _invoke(opt_in=False, model="gemini-headless", model_id="gemini-headless", dispatch=_refuse)
    err = capsys.readouterr().err
    assert rc == cheval.EXIT_CODES["INVALID_CONFIG"], err
    env = next(json.loads(l) for l in err.splitlines() if l.strip().startswith("{") and "INVALID_CONFIG" in l)
    assert env["code"] == "INVALID_CONFIG" and env["failure_class"] == "opt_in_required", env
    assert env["retryable"] is False
    # the MODELINV record says the hop was not planned, not that a voice failed
    assert payload["models_not_planned"] == [
        {"model": "google:gemini-headless", "provider": "google", "reason": "opt_in_required"}]
    assert payload["models_failed"] == []


def test_cli_only_google_voice_is_agy_alone_and_refuses(capsys, monkeypatch):
    monkeypatch.setenv("LOA_HEADLESS_MODE", "cli-only")

    def _refuse(req):
        raise AgyOptInRequiredError()
    rc, payload, seen = _invoke(opt_in=False, dispatch=_refuse)
    err = capsys.readouterr().err
    assert rc == cheval.EXIT_CODES["INVALID_CONFIG"], err
    assert '"failure_class": "opt_in_required"' in err


def test_the_modelinv_schema_declares_models_not_planned():
    root = Path(__file__).resolve().parents[3]
    schema = json.loads((root / ".claude/data/trajectory-schemas/model-events/model-invoke-complete.payload.schema.json").read_text())
    prop = schema["properties"]["models_not_planned"]
    assert prop["items"]["properties"]["reason"]["enum"] == ["opt_in_required"]


def test_the_emitted_payloads_validate_against_the_payload_schema(capsys, monkeypatch):
    jsonschema = pytest.importorskip("jsonschema")
    from referencing import Registry, Resource
    root = Path(__file__).resolve().parents[3] / ".claude/data/trajectory-schemas"
    schema = json.loads((root / "model-events/model-invoke-complete.payload.schema.json").read_text())
    registry = Registry().with_resource(uri="loa://schemas/model-error/v1.0.0",
                                        resource=Resource.from_contents(json.loads((root / "model-error.schema.json").read_text())))
    validator = jsonschema.validators.validator_for(schema)(schema, registry=registry)
    _, ok_payload, _ = _invoke(opt_in=False)

    def _refuse(req):
        raise AgyOptInRequiredError()
    _, refused_payload, _ = _invoke(opt_in=False, model="gemini-headless", model_id="gemini-headless", dispatch=_refuse)
    capsys.readouterr()
    for payload in (ok_payload, refused_payload):
        assert "models_not_planned" in payload
        validator.validate(payload)


def test_g18_cheval_says_once_that_an_available_agy_route_is_gated_and_spawns_nothing(tmp_path, capsys, caplog, monkeypatch):
    """SDD D-1.7: opt-in off + a fake `agy` on PATH → one availability WARN for the process (two invocations), no spawn."""
    bindir = tmp_path / "bin"
    bindir.mkdir()
    marker = tmp_path / "spawned"
    (bindir / "agy").write_text(f"#!/bin/sh\necho spawned > {marker}\n")
    (bindir / "agy").chmod(0o755)
    monkeypatch.setenv("PATH", f"{bindir}:/usr/bin:/bin")
    monkeypatch.setattr("loa_cheval.config.loader._AGY_AVAILABLE_WARNED", False)
    with caplog.at_level(logging.WARNING), \
            patch("loa_cheval.config.loader.load_project_config", return_value={}):
        _invoke(opt_in=False)
        _invoke(opt_in=False)
    capsys.readouterr()
    warns = [r for r in caplog.records if "available here" in r.getMessage()]
    assert len(warns) == 1, [r.getMessage() for r in caplog.records]
    assert "agy on PATH" in warns[0].getMessage() and "hounfour.headless.agy_opt_in" in warns[0].getMessage()
    assert not marker.exists()
