"""cycle-124 Sprint 1 U0 — MODELINV payload schema optional fields + mixed-writer fixture.

Pins the additive contract from SDD §2.4 / PRD FR-4 AC-4.2, FR-7 AC-7.4, NFR-5:

  - `tokens_cache_read`, `tokens_cache_creation` (int >= 0), `schema_enforced`
    (bool) and `output_schema_sha256` (64 lowercase hex) are OPTIONAL payload
    properties; `additionalProperties: false` still holds; no `writer_version`
    bump.
  - `tests/fixtures/modelinv/mixed-writer-rows.jsonl` mixes pre-cycle-124 rows
    (fields absent), rows with explicit 0/false, and rows with real cache
    tokens + an enforced schema. Every row validates and the file is a valid
    (unsigned, pre-trust-cutoff) hash chain.
  - Every consumer — economy.py, health.py, journal.py, modelinv-rollup.sh,
    modelinv-coverage-audit.py — runs clean over the fixture and produces the
    SAME aggregate whether the four fields are present or stripped. No consumer
    aggregates cache tokens today, so "absent reads as 0" is pinned as
    invariance: presence of the fields (zero or non-zero) changes nothing.
"""

from __future__ import annotations

import copy
import json
import os
import subprocess
import sys
from pathlib import Path

import jsonschema
import pytest
from referencing import Registry, Resource

ADAPTERS = Path(__file__).resolve().parents[1]
REPO = ADAPTERS.parents[1]
sys.path.insert(0, str(ADAPTERS))

from loa_cheval.audit_envelope import (  # noqa: E402
    _chain_input_bytes,
    _sha256_hex,
    audit_verify_chain,
)

SCHEMA_PATH = (
    REPO / ".claude" / "data" / "trajectory-schemas" / "model-events"
    / "model-invoke-complete.payload.schema.json"
)
MODEL_ERROR_SCHEMA_PATH = REPO / ".claude" / "data" / "trajectory-schemas" / "model-error.schema.json"
FIXTURE = REPO / "tests" / "fixtures" / "modelinv" / "mixed-writer-rows.jsonl"
MODEL_CONFIG = REPO / ".claude" / "defaults" / "model-config.yaml"
ROLLUP_SH = REPO / "tools" / "modelinv-rollup.sh"
COVERAGE_PY = REPO / "tools" / "modelinv-coverage-audit.py"

NEW_FIELDS = ("tokens_cache_read", "tokens_cache_creation", "schema_enforced", "output_schema_sha256")
# Fixture rows are dated 2026-05..06; consumers window relative to now().
WINDOW = "36500d"

BASE_PAYLOAD = {
    "models_requested": ["anthropic:claude-opus-5"],
    "models_succeeded": ["anthropic:claude-opus-5"],
    "models_failed": [],
    "operator_visible_warn": False,
}
ALL_FOUR = {
    "tokens_input": 1200,
    "tokens_output": 300,
    "tokens_cache_read": 18432,
    "tokens_cache_creation": 0,
    "schema_enforced": True,
    "output_schema_sha256": "a" * 64,
}


@pytest.fixture(autouse=True)
def _isolate_ledgers(monkeypatch, tmp_path):
    """Nothing here emits, but keep every path that could touch a live ledger
    pointed at tmp (FR-6 discipline)."""
    monkeypatch.setenv("LOA_MODELINV_LOG_PATH", str(tmp_path / "model-invoke.jsonl"))
    monkeypatch.setenv("LOA_COST_LEDGER_PATH", str(tmp_path / "cost-ledger.jsonl"))


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _schema() -> dict:
    return json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))


def _validator() -> jsonschema.protocols.Validator:
    """Same loader idiom as modelinv-v1.3-backcompat.bats: register
    model-error.schema.json under its loa:// $id so the error_class $ref resolves."""
    schema = _schema()
    registry = Registry().with_resource(
        uri="loa://schemas/model-error/v1.0.0",
        resource=Resource.from_contents(json.loads(MODEL_ERROR_SCHEMA_PATH.read_text(encoding="utf-8"))),
    )
    return jsonschema.validators.validator_for(schema)(schema, registry=registry)


def _errors(payload: dict) -> list:
    return list(_validator().iter_errors(payload))


def _fixture_rows() -> list:
    return [json.loads(line) for line in FIXTURE.read_text(encoding="utf-8").splitlines() if line.strip()]


def _strip_new_fields(rows: list) -> list:
    out = copy.deepcopy(rows)
    for env in out:
        for f in NEW_FIELDS:
            env["payload"].pop(f, None)
    return out


def _rechain(rows: list) -> list:
    """Recompute prev_hash over rows in file order (GENESIS-rooted, unsigned)."""
    prev = "GENESIS"
    for env in rows:
        env["prev_hash"] = prev
        prev = _sha256_hex(_chain_input_bytes(env))
    return rows


def _write_jsonl(path: Path, rows: list) -> Path:
    path.write_text("".join(json.dumps(r, separators=(",", ":")) + "\n" for r in rows), encoding="utf-8")
    return path


def _stripped_copy(tmp_path: Path) -> Path:
    return _write_jsonl(tmp_path / "stripped.jsonl", _rechain(_strip_new_fields(_fixture_rows())))


# ---------------------------------------------------------------------------
# Schema contract
# ---------------------------------------------------------------------------


def test_schema_declares_four_optional_fields_not_required():
    schema = _schema()
    props = schema["properties"]
    for f in NEW_FIELDS:
        assert f in props, f"missing property {f}"
        assert f not in schema["required"], f"{f} must stay optional"
    assert schema["additionalProperties"] is False
    assert props["tokens_cache_read"] == {**props["tokens_cache_read"], "type": "integer", "minimum": 0}
    assert props["tokens_cache_creation"] == {**props["tokens_cache_creation"], "type": "integer", "minimum": 0}
    assert props["schema_enforced"]["type"] == "boolean"
    assert props["output_schema_sha256"]["type"] == "string"
    assert props["output_schema_sha256"]["pattern"] == "^[0-9a-f]{64}$"


def test_schema_rejects_unknown_field():
    errs = _errors({**BASE_PAYLOAD, "not_a_modelinv_field": 1})
    assert errs, "additionalProperties: false must still reject unknown fields"
    assert any("not_a_modelinv_field" in e.message for e in errs)


def test_row_without_new_fields_validates():
    assert _errors(BASE_PAYLOAD) == []


def test_row_with_all_four_validates():
    assert _errors({**BASE_PAYLOAD, **ALL_FOUR}) == []


def test_row_with_explicit_zero_false_validates():
    payload = {**BASE_PAYLOAD, "tokens_cache_read": 0, "tokens_cache_creation": 0, "schema_enforced": False}
    assert _errors(payload) == []


@pytest.mark.parametrize("field", ["tokens_cache_read", "tokens_cache_creation"])
@pytest.mark.parametrize("bad", [-1, 1.5, "12", None])
def test_cache_token_fields_reject_negative_and_non_integer(field, bad):
    assert _errors({**BASE_PAYLOAD, field: bad}), f"{field}={bad!r} must be rejected"


@pytest.mark.parametrize(
    "bad",
    [
        "z" * 64,                     # non-hex
        "A" * 64,                     # uppercase hex — pattern is lowercase (hexdigest output)
        "ab" * 31,                    # 62 chars
        "ab" * 33,                    # 66 chars
        "",
        "sha256:" + "ab" * 32,        # prefixed
        None,
    ],
)
def test_output_schema_sha256_rejects_non_hex(bad):
    assert _errors({**BASE_PAYLOAD, "output_schema_sha256": bad}), f"{bad!r} must be rejected"


def test_output_schema_sha256_accepts_real_hexdigest():
    import hashlib

    digest = hashlib.sha256(b'{"type":"object"}').hexdigest()
    assert _errors({**BASE_PAYLOAD, "output_schema_sha256": digest}) == []


@pytest.mark.parametrize("bad", ["true", 1, None])
def test_schema_enforced_must_be_boolean(bad):
    assert _errors({**BASE_PAYLOAD, "schema_enforced": bad})


# ---------------------------------------------------------------------------
# Fixture contract
# ---------------------------------------------------------------------------


def test_fixture_every_row_validates():
    rows = _fixture_rows()
    assert len(rows) >= 8
    validator = _validator()
    for lineno, env in enumerate(rows, start=1):
        assert env["primitive_id"] == "MODELINV" and env["event_type"] == "model.invoke.complete"
        errs = list(validator.iter_errors(env["payload"]))
        assert errs == [], f"fixture line {lineno}: {errs[0].message if errs else ''}"


def test_fixture_mixes_writers_and_transports():
    payloads = [env["payload"] for env in _fixture_rows()]
    absent = [p for p in payloads if not any(f in p for f in NEW_FIELDS)]
    zeros = [
        p for p in payloads
        if p.get("tokens_cache_read") == 0 and p.get("tokens_cache_creation") == 0 and p.get("schema_enforced") is False
    ]
    live = [
        p for p in payloads
        if (p.get("tokens_cache_read", 0) > 0 or p.get("tokens_cache_creation", 0) > 0)
        and p.get("schema_enforced") is True and "output_schema_sha256" in p
    ]
    assert len(absent) >= 3, "need pre-cycle-124 rows (all four fields absent)"
    assert zeros, "need a row with explicit 0/0/false"
    assert live, "need a row with non-zero cache tokens + schema_enforced + sha256"
    # legacy v1.1 writer (no writer_version) AND v1.3 writer both present
    assert any("writer_version" not in p for p in payloads)
    assert any(p.get("writer_version") == "1.3" for p in payloads)
    # transports / providers / failure shapes
    assert any(p.get("transport") == "http" and str(p.get("final_model_id", "")).startswith("anthropic:") for p in payloads)
    assert any(p.get("final_model_id") == "anthropic:claude-headless" for p in payloads)
    assert any(p.get("final_model_id") == "openai:codex-headless" for p in payloads)
    assert any(not p["models_succeeded"] and p["models_failed"] for p in payloads), "need a failed-chain row"
    assert any(p["models_succeeded"] and p["models_failed"] for p in payloads), "need a chain-walked row"


def test_fixture_is_a_valid_unsigned_hash_chain():
    """modelinv-rollup.sh fail-closes on chain verification (T2.G), so the
    committed fixture must verify under DEFAULT policy — no --no-chain-verify,
    no LOA_AUDIT_VERIFY_SIGS=0. Unsigned rows are grandfathered only while
    ts_utc < trust_cutoff.default_strict_after (grimoires/loa/trust-store.yaml)."""
    ok, message = audit_verify_chain(FIXTURE)
    assert ok, message
    assert message == f"OK {len(_fixture_rows())} entries"
    # Bit-exact: rechaining reproduces the committed prev_hash values.
    assert [e["prev_hash"] for e in _rechain(_fixture_rows())] == [e["prev_hash"] for e in _fixture_rows()]


def test_fixture_contains_no_ledger_hygiene_violations():
    text = FIXTURE.read_text(encoding="utf-8")
    assert "/tmp/cheval-e2e-" not in text
    assert '"mock-' not in text


# ---------------------------------------------------------------------------
# Python consumers (in-process CLI entrypoints)
# ---------------------------------------------------------------------------


def _economy_report(log: Path, capsys) -> dict:
    from loa_cheval.economy import _cli_main

    rc = _cli_main(["--log-path", str(log), "--window", WINDOW, "--json", "--model-config", str(MODEL_CONFIG)])
    out = capsys.readouterr().out
    assert rc == 0, out
    report = json.loads(out)
    for volatile in ("now", "since", "log_path"):
        report.pop(volatile, None)
    return report


def test_economy_runs_clean_and_is_invariant_to_new_fields(tmp_path, capsys):
    rows = _fixture_rows()
    with_fields = _economy_report(FIXTURE, capsys)
    assert with_fields["coverage"]["total_envelopes"] == len(rows)
    assert sum(cell["runs"] for cell in with_fields["per_skill_model"].values()) == len(rows)
    # economy.py does not aggregate cache tokens today (cost derives from
    # capability_evaluation.estimated_input_tokens x pricing); presence of the
    # four fields — zero or non-zero — must not move a single number.
    assert _economy_report(_stripped_copy(tmp_path), capsys) == with_fields


def _health_report(log: Path, capsys) -> dict:
    from loa_cheval.health import _cli_main

    rc = _cli_main(["--log-path", str(log), "--window", WINDOW, "--json"])
    out = capsys.readouterr().out
    assert rc == 0, out
    report = json.loads(out)
    for volatile in ("now", "since", "log_path"):
        report.pop(volatile, None)
    return report


def test_health_runs_clean_and_is_invariant_to_new_fields(tmp_path, capsys):
    rows = _fixture_rows()
    with_fields = _health_report(FIXTURE, capsys)
    assert with_fields["total_invocations"] == len(rows)
    assert _health_report(_stripped_copy(tmp_path), capsys) == with_fields


def test_journal_runs_clean_and_is_invariant_to_new_fields(tmp_path, capsys):
    from loa_cheval.journal import _cli_main

    def _run(log: Path, journal_dir: Path) -> str:
        rc = _cli_main([
            "--journal-dir", str(journal_dir), "--log-path", str(log),
            "--window", WINDOW, "--run-time", "2026-09-17T00:00:00Z", "--json",
        ])
        out = capsys.readouterr().out
        assert rc == 0, out
        result = json.loads(out)
        assert result["action"] == "created"
        return Path(result["path"]).read_text(encoding="utf-8")

    with_fields = _run(FIXTURE, tmp_path / "j1")
    assert f"_Total invocations: {len(_fixture_rows())}" in with_fields
    assert _run(_stripped_copy(tmp_path), tmp_path / "j2") == with_fields


# ---------------------------------------------------------------------------
# Shell / script consumers (subprocess, default flags)
# ---------------------------------------------------------------------------


def _rollup(log: Path, out_json: Path) -> dict:
    proc = subprocess.run(
        ["bash", str(ROLLUP_SH), "--input", str(log), "--per-model", "--per-skill", "--output-json", str(out_json)],
        cwd=str(REPO), capture_output=True, text=True, env=os.environ.copy(), timeout=120,
    )
    assert proc.returncode == 0, f"rc={proc.returncode}\nstdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
    assert "STRIP-ATTACK-DETECTED" not in proc.stderr and "CHAIN-VERIFY-FAILED" not in proc.stderr
    report = json.loads(out_json.read_text(encoding="utf-8"))
    report.pop("generated_at", None)
    return report


def test_rollup_sh_runs_clean_with_default_verification_and_is_invariant(tmp_path):
    rows = _fixture_rows()
    with_fields = _rollup(FIXTURE, tmp_path / "rollup.json")
    assert with_fields["total_envelopes"] == len(rows)
    assert sum(g["count"] for g in with_fields["groups"]) == len(rows)
    assert sum(g["total_cost_micro_usd"] for g in with_fields["groups"]) == sum(
        e["payload"].get("cost_micro_usd", 0) for e in rows
    )
    assert _rollup(_stripped_copy(tmp_path), tmp_path / "rollup-stripped.json") == with_fields


def _coverage(log: Path, tmp_path: Path, tag: str) -> dict:
    out_json = tmp_path / f"coverage-{tag}.json"
    proc = subprocess.run(
        [sys.executable, str(COVERAGE_PY), "--input", str(log), "--output", str(out_json),
         "--markdown", str(tmp_path / f"coverage-{tag}.md")],
        cwd=str(REPO), capture_output=True, text=True, env=os.environ.copy(), timeout=60,
    )
    assert proc.returncode == 0, f"rc={proc.returncode}\nstdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
    return json.loads(out_json.read_text(encoding="utf-8"))


def test_coverage_audit_runs_clean_and_is_invariant(tmp_path):
    rows = _fixture_rows()
    with_fields = _coverage(FIXTURE, tmp_path, "a")
    assert with_fields["envelope_coverage"]["total_envelopes"] == len(rows)
    assert _coverage(_stripped_copy(tmp_path), tmp_path, "b") == with_fields
