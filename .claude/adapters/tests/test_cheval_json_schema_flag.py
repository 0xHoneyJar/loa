"""cycle-124 Sprint 2 Task 2.3 (FR-7 / SDD §2.4): `cheval --json-schema FILE`.

Read once, validated (object root, <= 64 KB, parseable) and hashed over ONE
canonical serialization (`sort_keys`, compact separators — the bytes `jq -cS .`
emits); a bad file is INVALID_INPUT before dispatch; the schema rides on
`base_request` and every per-hop request; the MODELINV envelope carries
`schema_enforced` + `output_schema_sha256` only when a schema was requested;
the CLI JSON always reports `schema_enforced`.
"""

from __future__ import annotations

import json
import subprocess
import sys
import types
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

import cheval  # type: ignore[import-not-found]  # noqa: E402
from loa_cheval.types import CompletionResult, Usage  # noqa: E402

SCHEMA = {"type": "object", "properties": {"ok": {"type": "boolean"}}, "required": ["ok"], "additionalProperties": False}
# sha256 of json.dumps(SCHEMA, sort_keys=True, separators=(",", ":")) — pinned in bats too.
PINNED_SHA = "4528a3c79c4aaee242a31e586366657f8e9a3f11cc8d2cb040d9bf61ab1bbb63"


# --- _read_output_schema -----------------------------------------------------

def test_valid_schema_returns_dict_and_canonical_sha(tmp_path):
    f = tmp_path / "s.json"
    f.write_text(json.dumps(SCHEMA, indent=2))              # pretty-printed on disk
    schema, sha = cheval._read_output_schema(str(f))
    assert schema == SCHEMA and sha == PINNED_SHA
    g = tmp_path / "t.json"
    g.write_text(json.dumps({"additionalProperties": False, "required": ["ok"], "type": "object",
                             "properties": {"ok": {"type": "boolean"}}}))   # other key order
    assert cheval._read_output_schema(str(g))[1] == PINNED_SHA


@pytest.mark.parametrize("content, why", [
    ("[1,2]", "root must be a JSON object"),
    ("{not json", "not readable JSON"),
    ('"str"', "root must be a JSON object"),
])
def test_bad_schema_files_raise(tmp_path, content, why):
    f = tmp_path / "bad.json"
    f.write_text(content)
    with pytest.raises(ValueError, match=why):
        cheval._read_output_schema(str(f))


def test_non_regular_schema_path_raises(tmp_path):
    """A FIFO passed as --json-schema would block cheval on open forever."""
    import os as _os
    fifo = tmp_path / "schema.fifo"
    _os.mkfifo(fifo)
    with pytest.raises(ValueError, match="not a regular file"):
        cheval._read_output_schema(str(fifo))
    with pytest.raises(ValueError, match="not a regular file"):
        cheval._read_output_schema(str(tmp_path))


def test_oversized_and_missing_files_raise(tmp_path):
    big = tmp_path / "big.json"
    big.write_text(json.dumps({"pad": "x" * (64 * 1024 + 1)}))
    with pytest.raises(ValueError, match="exceeds"):
        cheval._read_output_schema(str(big))
    with pytest.raises(ValueError):
        cheval._read_output_schema(str(tmp_path / "missing.json"))


# --- CLI: INVALID_INPUT before dispatch; dry-run reports the hash ------------

def _cli(args, env_extra=None):
    import os
    env = {k: v for k, v in os.environ.items() if k != "ANTHROPIC_API_KEY"}
    env.update(env_extra or {})
    return subprocess.run([sys.executable, str(ROOT / "cheval.py"), *args],
                          capture_output=True, text=True, env=env, timeout=120,
                          cwd=str(ROOT.parents[1]))


def test_cli_rejects_a_bad_schema_before_any_dispatch(tmp_path):
    bad = tmp_path / "bad.json"
    bad.write_text("[]")
    proc = _cli(["--agent", "reviewing-code", "--prompt", "x", "--json-schema", str(bad), "--dry-run", "--json-errors"])
    assert proc.returncode == 2, proc.stderr
    assert "INVALID_INPUT" in proc.stderr and "root must be a JSON object" in proc.stderr


def test_cli_dry_run_reports_the_schema_hash(tmp_path):
    good = tmp_path / "good.json"
    good.write_text(json.dumps(SCHEMA))
    proc = _cli(["--agent", "reviewing-code", "--prompt", "x", "--json-schema", str(good), "--dry-run"])
    assert proc.returncode == 0, proc.stderr
    assert json.loads(proc.stdout)["output_schema_sha256"] == PINNED_SHA


# --- in-process: request threading, MODELINV envelope, CLI JSON --------------

def _args(schema_file, output_format="text"):
    a = types.SimpleNamespace()
    a.agent = "agentx"; a.role = None; a.skill = None; a.sprint_kind = None
    a.input = None; a.prompt = "review"; a.system = None; a.model = None
    a.max_tokens = None; a.effort = None; a.output_format = output_format
    a.json_errors = True; a.timeout = 30; a.include_thinking = False; a.async_mode = False
    a.poll_id = None; a.cancel_id = None; a.dry_run = False; a.print_config = False
    a.validate_bindings = False; a.mock_fixture_dir = None; a.max_input_tokens = None
    a.json_schema = schema_file
    return a


def _cfg():
    return {
        "aliases": {"claude-opus-5": "anthropic:claude-opus-5"},
        "providers": {"anthropic": {"type": "anthropic", "endpoint": "https://x", "auth": "dummy",
                                    "models": {"claude-opus-5": {"capabilities": ["chat", "structured_json"],
                                                                 "context_window": 1_000_000, "max_output_tokens": 128_000}}}},
        "feature_flags": {"metering": False},
    }


def _invoke(monkeypatch, schema_file, enforced: bool, output_format="text", meta=None, cfg=None, fail_first=False):
    monkeypatch.setattr(cheval, "_check_feature_flags", lambda *_a, **_kw: None)
    monkeypatch.setattr(cheval, "_load_persona_parts", lambda *_a, **_kw: (None, None))
    monkeypatch.setattr(cheval, "_load_persona", lambda *_a, **_kw: None)
    seen, captured = [], {}
    result_meta = meta if meta is not None else {"streaming": True, "schema_enforced": enforced}

    def _retry_side(_adapter, req, _cfg, budget_hook=None):
        seen.append(req)
        if fail_first and len(seen) == 1:
            from loa_cheval.types import ProviderUnavailableError
            raise ProviderUnavailableError("anthropic", "hop 1 down (test)")
        return CompletionResult(content='{"ok": true}', model=req.model, provider="anthropic",
                                usage=Usage(input_tokens=10, output_tokens=5), latency_ms=1, tool_calls=None,
                                thinking=None, metadata=dict(result_meta))

    with patch.object(cheval, "load_config", return_value=(cfg if cfg is not None else _cfg(), {})), \
         patch.object(cheval, "resolve_execution", return_value=(MagicMock(temperature=0.7, capability_class=None),
                                                                  MagicMock(provider="anthropic", model_id="claude-opus-5"))), \
         patch.object(cheval, "_build_provider_config", return_value=MagicMock()), \
         patch.object(cheval, "get_adapter", return_value=MagicMock()), \
         patch("loa_cheval.providers.retry.invoke_with_retry", side_effect=_retry_side), \
         patch("loa_cheval.audit_envelope.audit_emit", lambda level, event, payload, *a, **k: captured.update(payload)), \
         patch("loa_cheval.audit.modelinv.redact_payload_strings", side_effect=lambda x: x), \
         patch("loa_cheval.audit.modelinv.assert_no_secret_shapes_remain"):
        code = cheval.cmd_invoke(_args(schema_file, output_format))
    return code, seen, captured


def test_schema_rides_on_the_request_and_the_envelope_records_enforcement(tmp_path, monkeypatch, capsys):
    f = tmp_path / "s.json"
    f.write_text(json.dumps(SCHEMA))
    code, seen, captured = _invoke(monkeypatch, str(f), enforced=True, output_format="json")
    assert code == 0
    assert seen[0].output_schema == SCHEMA
    assert captured["schema_enforced"] is True
    assert captured["output_schema_sha256"] == PINNED_SHA
    assert json.loads(capsys.readouterr().out)["schema_enforced"] is True


def test_unenforced_hop_is_recorded_false_not_absent(tmp_path, monkeypatch, capsys):
    f = tmp_path / "s.json"
    f.write_text(json.dumps(SCHEMA))
    code, _, captured = _invoke(monkeypatch, str(f), enforced=False, output_format="json")
    assert code == 0
    assert captured["schema_enforced"] is False
    assert captured["output_schema_sha256"] == PINNED_SHA
    assert json.loads(capsys.readouterr().out)["schema_enforced"] is False


def test_no_schema_means_no_envelope_fields_and_cli_false(monkeypatch, capsys):
    code, seen, captured = _invoke(monkeypatch, None, enforced=False, output_format="json")
    assert code == 0
    assert seen[0].output_schema is None
    assert "schema_enforced" not in captured and "output_schema_sha256" not in captured
    assert json.loads(capsys.readouterr().out)["schema_enforced"] is False


# --- late Sprint 2 review (slice A) -------------------------------------------

def test_openai_style_truncation_reads_as_stop_reason_max_tokens(tmp_path, monkeypatch, capsys):
    """The OpenAI adapters record truncation as metadata.truncated, not
    stop_reason; the dissent's enforced branch keys its 'raise the output
    budget' hint on stop_reason == max_tokens, so the CLI JSON must say so."""
    f = tmp_path / "s.json"
    f.write_text(json.dumps(SCHEMA))
    code, _, _ = _invoke(monkeypatch, str(f), enforced=True, output_format="json",
                         meta={"schema_enforced": True, "truncated": True, "truncation_reason": "max_output_tokens"})
    assert code == 0
    out = json.loads(capsys.readouterr().out)
    assert out["schema_enforced"] is True
    assert out["stop_reason"] == "max_tokens"


def test_explicit_stop_reason_wins_over_the_truncated_flag(tmp_path, monkeypatch, capsys):
    f = tmp_path / "s.json"
    f.write_text(json.dumps(SCHEMA))
    code, _, _ = _invoke(monkeypatch, str(f), enforced=True, output_format="json",
                         meta={"schema_enforced": True, "stop_reason": "end_turn", "truncated": False})
    assert code == 0
    assert json.loads(capsys.readouterr().out)["stop_reason"] == "end_turn"


def test_empty_json_schema_path_is_invalid_input_not_no_schema(monkeypatch, capsys):
    """`--json-schema ""` (an unset shell variable) must fail loudly instead of
    running unenforced with the envelope reading as 'no schema requested'."""
    code, seen, captured = _invoke(monkeypatch, "", enforced=True, output_format="json")
    assert code == 2
    assert seen == []
    assert "schema_enforced" not in captured
    err = capsys.readouterr().err
    assert "INVALID_INPUT" in err


def _cfg_two_hops():
    cfg = _cfg()
    models = cfg["providers"]["anthropic"]["models"]
    models["claude-opus-5"] = dict(models["claude-opus-5"], fallback_chain=["anthropic:claude-sonnet-5"])
    models["claude-sonnet-5"] = {"capabilities": ["chat", "structured_json"], "context_window": 1_000_000, "max_output_tokens": 64_000}
    cfg["aliases"]["claude-sonnet-5"] = "anthropic:claude-sonnet-5"
    return cfg


def test_schema_rides_on_every_hop_of_a_chain_walk(tmp_path, monkeypatch, capsys):
    """Late Sprint 2 review (slice C, MEDIUM): only hop 0 was asserted. Hop 1
    fails with a retryable error; the per-hop rebuild for hop 2 must still
    carry the schema and the envelope must report the hop that answered."""
    f = tmp_path / "s.json"
    f.write_text(json.dumps(SCHEMA))
    code, seen, captured = _invoke(monkeypatch, str(f), enforced=True, output_format="json",
                                   cfg=_cfg_two_hops(), fail_first=True)
    assert code == 0, capsys.readouterr().err
    assert len(seen) == 2
    assert [r.model for r in seen] == ["claude-opus-5", "claude-sonnet-5"]
    assert all(r.output_schema == SCHEMA for r in seen)
    assert captured["schema_enforced"] is True
    assert captured["output_schema_sha256"] == PINNED_SHA
