"""cycle-109 Sprint 2 T2.4 — verdict_quality sidecar transport (cheval-side).

Per T2.4 design: cheval's verdict_quality envelope is built in the
``finally`` block of ``cmd_invoke`` AFTER the stdout JSON has already
been printed, so call_model in flatline-orchestrator.sh cannot read
the envelope from stdout. Instead, when the ``LOA_VERDICT_QUALITY_SIDECAR``
environment variable is set to a file path, cheval writes the validated
envelope JSON to that file in addition to attaching it to the MODELINV
envelope. This gives FL orchestrator (CONSUMER #2) a per-call channel
to read the envelope back without racing on the shared MODELINV log.

Contract:

  - Env var unset → no sidecar file written; MODELINV emit unchanged.
  - Env var set to writeable path → file is created/overwritten with
    the envelope JSON (compact, single line, no trailing newline). The
    write is atomic-friendly enough for per-call usage (FL allocates a
    fresh path per call so no race).
  - Env var set to unwriteable path → fail-soft; stderr logs the failure
    with ``[verdict-quality-sidecar-failed]`` marker; cheval exit code
    is unchanged.
  - When envelope construction fails (invariant violation), no sidecar
    is written (the file is left absent so consumers can distinguish
    "envelope build error" from "successful empty content").

The tests below run ``emit_model_invoke_complete`` directly with the
sidecar env var set; the cmd_invoke-side integration (building the
envelope first, then writing the sidecar) is exercised by the FL
integration bats test that pairs with this file.

Pair with: tests/integration/flatline-verdict-quality-sidecar.bats
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))


def _baseline_envelope():
    return {
        "status": "APPROVED",
        "consensus_outcome": "consensus",
        "truncation_waiver_applied": False,
        "voices_planned": 1,
        "voices_succeeded": 1,
        "voices_succeeded_ids": ["claude-opus-4-7"],
        "voices_dropped": [],
        "chain_health": "ok",
        "confidence_floor": "low",
        "rationale": "single-voice cheval invoke; chain_health=ok",
        "single_voice_call": True,
    }


def test_sidecar_module_exposes_write_helper():
    """The sidecar write logic must be importable as a helper so the
    cheval finally-block call site is testable in isolation. Lives in
    loa_cheval.verdict.sidecar to keep cheval.py finally block thin."""
    from loa_cheval.verdict.sidecar import write_sidecar  # noqa: F401


def test_sidecar_written_to_env_var_path(tmp_path, monkeypatch):
    from loa_cheval.verdict.sidecar import write_sidecar

    target = tmp_path / "verdict.json"
    monkeypatch.setenv("LOA_VERDICT_QUALITY_SIDECAR", str(target))
    envelope = _baseline_envelope()
    write_sidecar(envelope)

    assert target.exists(), "sidecar file was not written"
    loaded = json.loads(target.read_text())
    assert loaded["status"] == "APPROVED"
    assert loaded["voices_planned"] == 1


def test_no_sidecar_when_env_var_unset(tmp_path, monkeypatch):
    from loa_cheval.verdict.sidecar import write_sidecar

    monkeypatch.delenv("LOA_VERDICT_QUALITY_SIDECAR", raising=False)
    write_sidecar(_baseline_envelope())
    # tmp_path is empty — function should not have created anything
    assert list(tmp_path.iterdir()) == []


def test_no_sidecar_when_env_var_empty(tmp_path, monkeypatch):
    """Empty-string env var is treated as unset (POSIX convention)."""
    from loa_cheval.verdict.sidecar import write_sidecar

    monkeypatch.setenv("LOA_VERDICT_QUALITY_SIDECAR", "")
    write_sidecar(_baseline_envelope())
    assert list(tmp_path.iterdir()) == []


def test_no_sidecar_when_envelope_is_none(tmp_path, monkeypatch):
    """When the producer's envelope build failed, write_sidecar(None)
    leaves the file ABSENT so consumers can distinguish 'build error'
    from 'successful empty content'."""
    from loa_cheval.verdict.sidecar import write_sidecar

    target = tmp_path / "verdict.json"
    monkeypatch.setenv("LOA_VERDICT_QUALITY_SIDECAR", str(target))
    write_sidecar(None)
    assert not target.exists()


def test_sidecar_fails_soft_on_unwritable_path(tmp_path, monkeypatch, capsys):
    """Sidecar write failure MUST NOT raise — cheval cmd_invoke is in
    the finally block; an exception here would mask the actual exit code."""
    from loa_cheval.verdict.sidecar import write_sidecar

    # /nonexistent path can't be created
    monkeypatch.setenv(
        "LOA_VERDICT_QUALITY_SIDECAR",
        "/nonexistent-dir-cycle-109/verdict.json",
    )
    # Must not raise
    write_sidecar(_baseline_envelope())
    captured = capsys.readouterr()
    assert "[verdict-quality-sidecar-failed]" in captured.err


def test_sidecar_content_is_compact_json(tmp_path, monkeypatch):
    """Sidecar JSON MUST be compact (no whitespace) for byte-counting
    consumers + faster parse."""
    from loa_cheval.verdict.sidecar import write_sidecar

    target = tmp_path / "verdict.json"
    monkeypatch.setenv("LOA_VERDICT_QUALITY_SIDECAR", str(target))
    write_sidecar(_baseline_envelope())
    content = target.read_text()
    # Compact: no spaces after colon/comma in JSON object separators
    assert ": " not in content, f"sidecar JSON is not compact: {content!r}"
    assert ", " not in content, f"sidecar JSON is not compact: {content!r}"


def test_sidecar_overwrites_existing_file(tmp_path, monkeypatch):
    """Per-call FL usage assumes overwrite semantics — the sidecar path
    may already exist from a previous invocation of the same FL run."""
    from loa_cheval.verdict.sidecar import write_sidecar

    target = tmp_path / "verdict.json"
    target.write_text('{"stale": "data"}')
    monkeypatch.setenv("LOA_VERDICT_QUALITY_SIDECAR", str(target))
    write_sidecar(_baseline_envelope())
    loaded = json.loads(target.read_text())
    assert loaded["status"] == "APPROVED"
    assert "stale" not in loaded
