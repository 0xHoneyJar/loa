"""cycle-109 Sprint 5 T5.8 — substrate-health journal formatter tests.

Pins SDD §5.5.3 schema invariants:
  - File path: grimoires/loa/substrate-health/YYYY-MM.md
  - Per-day H2 header: '## YYYY-MM-DD (cron run @ 00:00 UTC)'
  - Per-model markdown table
  - Warnings section for non-green bands
  - Idempotency: no-op if today's H2 already present
"""

from __future__ import annotations

import sys
from datetime import datetime, timezone
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _stub_report(*, total: int = 100, succeeded: int = 90, models: dict | None = None):
    """Build a stub aggregator report shape (matches health.aggregate output)."""
    rate = (succeeded / total) if total else 0.0
    band = "green" if rate >= 0.80 else ("yellow" if rate >= 0.50 else "red")
    return {
        "window": "24h",
        "since": "2026-05-13T00:00:00+00:00",
        "now": "2026-05-14T00:00:00+00:00",
        "log_path": "/tmp/test.jsonl",
        "total_invocations": total,
        "overall": {"succeeded": succeeded, "success_rate": rate, "band": band},
        "per_model": models or {},
    }


def _stub_model(invocations: int, succeeded: int, *, chunked: int = 0,
                streaming_aborts: dict | None = None):
    rate = (succeeded / invocations) if invocations else 0.0
    band = "green" if rate >= 0.80 else ("yellow" if rate >= 0.50 else "red")
    return {
        "invocations": invocations,
        "succeeded": succeeded,
        "success_rate": rate,
        "band": band,
        "chain_health": {"ok": succeeded, "degraded": 0, "exhausted": 0},
        "chunked": chunked,
        "streaming_aborts": streaming_aborts or {},
        "verdict_status": {"APPROVED": succeeded, "DEGRADED": 0, "FAILED": 0},
    }


# ---------------------------------------------------------------------------
# Path computation
# ---------------------------------------------------------------------------


def test_journal_path_for_2026_05():
    from loa_cheval.journal import journal_path_for_date

    out = journal_path_for_date(
        Path("/repo/grimoires/loa/substrate-health"),
        datetime(2026, 5, 14, tzinfo=timezone.utc),
    )
    assert out == Path("/repo/grimoires/loa/substrate-health/2026-05.md")


def test_journal_path_for_january():
    from loa_cheval.journal import journal_path_for_date

    out = journal_path_for_date(
        Path("/x"),
        datetime(2026, 1, 3, tzinfo=timezone.utc),
    )
    assert out == Path("/x/2026-01.md")


# ---------------------------------------------------------------------------
# Markdown rendering
# ---------------------------------------------------------------------------


def test_render_day_section_has_h2_header():
    from loa_cheval.journal import render_day_section

    report = _stub_report(models={
        "anthropic:claude-opus-4-7": _stub_model(100, 90),
    })
    out = render_day_section(
        report, run_time=datetime(2026, 5, 14, 0, 0, 0, tzinfo=timezone.utc),
    )
    assert "## 2026-05-14 (cron run @ 00:00 UTC)" in out


def test_render_day_section_includes_per_model_table():
    from loa_cheval.journal import render_day_section

    report = _stub_report(models={
        "anthropic:claude-opus-4-7": _stub_model(234, 204),  # ~87%
        "openai:gpt-5.5-pro": _stub_model(189, 174),  # ~92%
    })
    out = render_day_section(
        report, run_time=datetime(2026, 5, 14, 0, 0, 0, tzinfo=timezone.utc),
    )
    assert "| Model | N | Success" in out
    assert "anthropic:claude-opus-4-7" in out
    assert "openai:gpt-5.5-pro" in out
    assert "234" in out
    assert "189" in out


def test_render_day_section_emits_degraded_warning():
    from loa_cheval.journal import render_day_section

    report = _stub_report(models={
        "google:gemini-3-pro": _stub_model(92, 41),  # 45% → red
    })
    out = render_day_section(
        report, run_time=datetime(2026, 5, 14, 0, 0, 0, tzinfo=timezone.utc),
    )
    assert "Warnings" in out
    assert "google:gemini-3-pro" in out
    # Per SDD §5.5.3 sub-80% triggers DEGRADED warning (KF/role-restrict prompt)
    assert any(token in out for token in ("DEGRADED", "FAILED", "KF"))


def test_render_day_section_no_warning_when_all_green():
    from loa_cheval.journal import render_day_section

    report = _stub_report(models={
        "anthropic:claude-opus-4-7": _stub_model(100, 95),
        "openai:gpt-5.5-pro": _stub_model(100, 90),
    })
    out = render_day_section(
        report, run_time=datetime(2026, 5, 14, 0, 0, 0, tzinfo=timezone.utc),
    )
    # Either no "Warnings" section, or one that's effectively empty.
    if "Warnings" in out:
        warnings_block = out.split("Warnings", 1)[1]
        # No degraded/failed model mentions in the warnings block.
        assert "DEGRADED" not in warnings_block
        assert "FAILED" not in warnings_block


# ---------------------------------------------------------------------------
# Idempotency
# ---------------------------------------------------------------------------


def test_append_day_section_creates_file_with_month_header(tmp_path):
    from loa_cheval.journal import append_day_section

    journal_dir = tmp_path / "substrate-health"
    journal_dir.mkdir()
    report = _stub_report(models={
        "anthropic:claude-opus-4-7": _stub_model(100, 95),
    })
    result = append_day_section(
        journal_dir, report,
        run_time=datetime(2026, 5, 14, 0, 0, 0, tzinfo=timezone.utc),
    )
    # Either 'created' (new file) or 'appended' (existing) — both write the day
    assert result["action"] in ("created", "appended")
    file_path = journal_dir / "2026-05.md"
    assert file_path.exists()
    content = file_path.read_text()
    assert "# Substrate Health Journal — 2026-05" in content
    assert "## 2026-05-14" in content


def test_append_day_section_idempotent_for_same_day(tmp_path):
    """SDD §5.5.3: cron is no-op if today's H2 already in journal."""
    from loa_cheval.journal import append_day_section

    journal_dir = tmp_path / "substrate-health"
    journal_dir.mkdir()
    report = _stub_report(models={
        "anthropic:claude-opus-4-7": _stub_model(100, 95),
    })
    when = datetime(2026, 5, 14, 0, 0, 0, tzinfo=timezone.utc)
    append_day_section(journal_dir, report, run_time=when)
    result2 = append_day_section(journal_dir, report, run_time=when)
    assert result2["action"] == "skipped"
    # File only appears once
    content = (journal_dir / "2026-05.md").read_text()
    assert content.count("## 2026-05-14") == 1


def test_append_day_section_appends_new_day_to_existing_file(tmp_path):
    from loa_cheval.journal import append_day_section

    journal_dir = tmp_path / "substrate-health"
    journal_dir.mkdir()
    report = _stub_report(models={
        "anthropic:claude-opus-4-7": _stub_model(100, 95),
    })
    append_day_section(
        journal_dir, report,
        run_time=datetime(2026, 5, 14, 0, 0, 0, tzinfo=timezone.utc),
    )
    append_day_section(
        journal_dir, report,
        run_time=datetime(2026, 5, 15, 0, 0, 0, tzinfo=timezone.utc),
    )
    content = (journal_dir / "2026-05.md").read_text()
    assert "## 2026-05-14" in content
    assert "## 2026-05-15" in content
    # Both sections present, no duplicates
    assert content.count("## 2026-05-14") == 1
    assert content.count("## 2026-05-15") == 1


def test_append_day_section_separate_files_per_month(tmp_path):
    """A new month's run lands in a different file."""
    from loa_cheval.journal import append_day_section

    journal_dir = tmp_path / "substrate-health"
    journal_dir.mkdir()
    report = _stub_report(models={
        "anthropic:claude-opus-4-7": _stub_model(100, 95),
    })
    append_day_section(
        journal_dir, report,
        run_time=datetime(2026, 5, 31, 0, 0, 0, tzinfo=timezone.utc),
    )
    append_day_section(
        journal_dir, report,
        run_time=datetime(2026, 6, 1, 0, 0, 0, tzinfo=timezone.utc),
    )
    assert (journal_dir / "2026-05.md").exists()
    assert (journal_dir / "2026-06.md").exists()


# ---------------------------------------------------------------------------
# CLI shape
# ---------------------------------------------------------------------------


def test_cli_help_includes_journal_keyword():
    """Sanity: the module's CLI exposes a recognizable help blurb."""
    import subprocess

    res = subprocess.run(
        [sys.executable, "-m", "loa_cheval.journal", "--help"],
        env={"PYTHONPATH": str(ROOT), "PATH": ""},
        capture_output=True, text=True, timeout=10,
    )
    assert res.returncode == 0, res.stderr
    assert "journal" in res.stdout.lower()
