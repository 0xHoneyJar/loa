"""cycle-124 FR-6 (AC-6.4): replay tests spawn cheval for real (credential-gated).

Mirror of .claude/adapters/tests/conftest.py — both ledgers are redirected under
tmp_path unconditionally (Sprint 1 audit, slice B: an operator's own redirect
must not collect replay rows either), so a live replay never appends to a
production ledger.
"""
import pytest


@pytest.fixture(autouse=True)
def _isolate_ledgers(tmp_path, monkeypatch):
    for var, name in (
        ("LOA_COST_LEDGER_PATH", "cost-ledger.jsonl"),
        ("LOA_MODELINV_LOG_PATH", "model-invoke.jsonl"),
    ):
        monkeypatch.setenv(var, str(tmp_path / name))
