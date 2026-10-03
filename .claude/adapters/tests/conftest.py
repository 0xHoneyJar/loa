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

import os

import pytest

_LEDGER_ENV = {
    "LOA_COST_LEDGER_PATH": "cost-ledger.jsonl",
    "LOA_MODELINV_LOG_PATH": "model-invoke.jsonl",
    # cycle-126 D-1.1b: the observed-ceiling store is state too.
    "LOA_CHEVAL_CEILING_OBSERVED_PATH": "ceiling-observed.json",
}


@pytest.fixture(autouse=True)
def _isolate_ledgers(monkeypatch, tmp_path):
    for var, basename in _LEDGER_ENV.items():
        monkeypatch.setenv(var, str(tmp_path / basename))


def _reset_gate_around():
    """The fixture's body, a plain generator so a test can drive both halves (run 25, c2e DISS-C-001)."""
    from loa_cheval.types import reset_headless_timeout_reports
    reset_headless_timeout_reports()
    yield
    reset_headless_timeout_reports()


@pytest.fixture(autouse=True)
def _reset_headless_timeout_gate():
    """The once-per-process headless_timeout_seconds report gate is module state: reset it around every test,
    so a key one test seeds never silences a warning another test asserts (run 23, c2e DISS-C-001)."""
    yield from _reset_gate_around()


@pytest.fixture(autouse=True)
def _private_headless_workspace(monkeypatch, tmp_path_factory):
    """The headless CLIs' private working directory is this test's own, never the operator's per-user one (cycle-126
    thirty-second run, e1 DISS-C-001): the base is a 0700 root of the suite's, and the ancestors above it — pytest's
    temporary tree, under /tmp — are not judged."""
    from loa_cheval.providers import headless_cli
    root = tmp_path_factory.mktemp("headless-ws")
    os.chmod(root, 0o700)
    monkeypatch.setattr(headless_cli, "_TRUSTED_ABOVE", str(root.resolve()), raising=False)
    monkeypatch.setenv("XDG_RUNTIME_DIR", str(root))
