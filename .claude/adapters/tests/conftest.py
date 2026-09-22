"""Ledger isolation for every adapter test (cycle-124 FR-6, AC-6.1).

Any test that reaches cheval's dispatch path — in-process or through a
subprocess (``os.environ`` is inherited) — appends a cost-ledger row and a
MODELINV envelope. Before this fixture those rows landed in the operator's
real ``.run/`` ledgers (155 mock rows / 106 tmp-path rows on 2026-09-17).

Unconditional (Sprint 1 audit, slice B): an operator who exports the two
variables for their own redirected ledgers must not receive test rows there
either — the hygiene tripwire only scans ``.run/``. A test that wants the
config fallback ``monkeypatch.delenv``s the variable (test_cli_reported_cost).
"""

import pytest

_LEDGER_ENV = {
    "LOA_COST_LEDGER_PATH": "cost-ledger.jsonl",
    "LOA_MODELINV_LOG_PATH": "model-invoke.jsonl",
}


@pytest.fixture(autouse=True)
def _isolate_ledgers(monkeypatch, tmp_path):
    for var, basename in _LEDGER_ENV.items():
        monkeypatch.setenv(var, str(tmp_path / basename))
