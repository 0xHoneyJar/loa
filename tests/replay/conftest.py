"""cycle-124 FR-6 (AC-6.4): replay tests spawn cheval for real (credential-gated).

Mirror of .claude/adapters/tests/conftest.py — both ledgers are redirected under
tmp_path unless the operator already pointed them somewhere, so a live replay
never appends to .run/cost-ledger.jsonl or .run/model-invoke.jsonl.
"""
import os

import pytest


@pytest.fixture(autouse=True)
def _isolate_ledgers(tmp_path, monkeypatch):
    for var, name in (
        ("LOA_COST_LEDGER_PATH", "cost-ledger.jsonl"),
        ("LOA_MODELINV_LOG_PATH", "model-invoke.jsonl"),
    ):
        if not os.environ.get(var):
            monkeypatch.setenv(var, str(tmp_path / name))
