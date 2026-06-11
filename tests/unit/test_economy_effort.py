"""cycle-114 FR-8 — effort observability in the model-economy roll-up.

The MODELINV envelope carries an optional `effort`; the economy aggregator
tallies it per (skill, model) cell as an additive `effort_counts` field
(without changing the cell key) so `/loa status --economy` can attribute cost
to reasoning depth. Absence of effort → empty {} (no regression).
"""
from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / ".claude" / "adapters"))

from loa_cheval import economy  # noqa: E402

MODEL_CONFIG = ROOT / ".claude" / "defaults" / "model-config.yaml"
FIXED_NOW = datetime(2026, 6, 1, 12, 0, 0, tzinfo=timezone.utc)


def _envelope(skill: str, model: str, effort=None) -> dict:
    payload = {
        "skill": skill,
        "models_requested": [model],
        "models_succeeded": [model],
        "final_model_id": model,
        "invocation_latency_ms": 1000,
        "pricing_snapshot": {"input_per_mtok": 5000000, "output_per_mtok": 25000000},
        "capability_evaluation": {"estimated_input_tokens": 1000},
        "verdict_quality": {"status": "APPROVED", "chain_health": "ok"},
    }
    if effort is not None:
        payload["effort"] = effort
    return {
        "primitive_id": "MODELINV",
        "event_type": "model.invoke.complete",
        "ts_utc": "2026-06-01T10:00:00.000000Z",
        "payload": payload,
    }


def _write_log(tmp_path: Path, entries) -> Path:
    p = tmp_path / "model-invoke.jsonl"
    p.write_text("\n".join(json.dumps(e) for e in entries) + "\n", encoding="utf-8")
    return p


def _agg(log_path: Path):
    return economy.aggregate_economy(
        log_path=log_path,
        model_config_path=MODEL_CONFIG,
        window="9999d",
        now=FIXED_NOW,
    )


def test_effort_counts_tallied_per_cell(tmp_path):
    model = "anthropic:claude-opus-4-8"
    entries = [
        _envelope("/audit", model, "xhigh"),
        _envelope("/audit", model, "xhigh"),
        _envelope("/audit", model, "high"),
    ]
    rep = _agg(_write_log(tmp_path, entries))
    rows = list(rep["per_skill_model"].values())
    assert len(rows) == 1
    assert rows[0]["effort_counts"] == {"xhigh": 2, "high": 1}


def test_no_effort_yields_empty_counts(tmp_path):
    model = "anthropic:claude-opus-4-8"
    rep = _agg(_write_log(tmp_path, [_envelope("/review-sprint", model)]))
    rows = list(rep["per_skill_model"].values())
    assert rows[0]["effort_counts"] == {}


def test_invalid_effort_ignored(tmp_path):
    model = "anthropic:claude-opus-4-8"
    rep = _agg(_write_log(tmp_path, [_envelope("/audit", model, "turbo")]))
    rows = list(rep["per_skill_model"].values())
    assert rows[0]["effort_counts"] == {}


def test_rollup_validates_against_schema_with_effort(tmp_path):
    """The roll-up output (now carrying effort_counts) must still validate."""
    jsonschema = __import__("importlib").util.find_spec("jsonschema")
    if jsonschema is None:
        # Structural fallback when jsonschema isn't installed.
        rep = _agg(_write_log(tmp_path, [_envelope("/audit", "anthropic:claude-opus-4-8", "max")]))
        row = next(iter(rep["per_skill_model"].values()))
        assert isinstance(row["effort_counts"], dict)
        return
    import jsonschema as js  # noqa
    schema = json.loads((ROOT / ".claude" / "data" / "schemas" / "model-economy-rollup.schema.json").read_text())
    rep = _agg(_write_log(tmp_path, [_envelope("/audit", "anthropic:claude-opus-4-8", "max")]))
    js.validate(rep, schema)
