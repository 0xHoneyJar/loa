"""cycle-109 Sprint 5 T5.8 — substrate-health journal formatter (SDD §5.5.3).

Renders aggregator output (from ``loa_cheval.health.aggregate_substrate_health``)
as a markdown day-section and appends it to
``grimoires/loa/substrate-health/YYYY-MM.md``. Idempotent: re-running on the
same UTC day is a no-op.

Public API
----------
  journal_path_for_date(dir, when) -> Path        # YYYY-MM.md
  render_day_section(report, run_time) -> str     # markdown block
  append_day_section(dir, report, run_time) -> dict
    # action: 'appended' | 'skipped' | 'created'

CLI
---
  python -m loa_cheval.journal \\
      --journal-dir grimoires/loa/substrate-health \\
      --log-path .run/model-invoke.jsonl \\
      --window 24h

Composes T5.4's aggregator (no duplicate aggregation logic).
"""

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional


# ---------------------------------------------------------------------------
# Path computation
# ---------------------------------------------------------------------------


def journal_path_for_date(journal_dir: Path, when: datetime) -> Path:
    """Return ``<journal_dir>/YYYY-MM.md`` for ``when``."""
    when_utc = when.astimezone(timezone.utc) if when.tzinfo else when.replace(tzinfo=timezone.utc)
    return journal_dir / f"{when_utc.year:04d}-{when_utc.month:02d}.md"


def _day_header(when: datetime) -> str:
    """Per-day H2 header per SDD §5.5.3."""
    when_utc = when.astimezone(timezone.utc) if when.tzinfo else when.replace(tzinfo=timezone.utc)
    return f"## {when_utc.year:04d}-{when_utc.month:02d}-{when_utc.day:02d} (cron run @ 00:00 UTC)"


# ---------------------------------------------------------------------------
# Markdown rendering
# ---------------------------------------------------------------------------


def _band_for_label(band: str) -> str:
    return {"green": "OK", "yellow": "DEGRADED", "red": "FAILED"}.get(band, band.upper())


def _format_pct(rate: float) -> str:
    return f"{rate * 100:.0f}%"


def render_day_section(report: Dict[str, Any], *, run_time: datetime) -> str:
    """Render a complete day-section markdown block from a health report.

    Schema per SDD §5.5.3:
      ## YYYY-MM-DD (cron run @ 00:00 UTC)

      ### Per-model 24h health

      | Model | N | Success | Drop | Exhaust | Chunked |
      |-------|---|---------|------|---------|---------|
      | <id>  | N | XX%     | XX%  | XX%     | N       |

      ### Warnings
      - ⚠ <model>: success_rate XX% < 80% ...

      ---
    """
    lines: List[str] = []
    lines.append(_day_header(run_time))
    lines.append("")
    lines.append(f"### Per-model {report.get('window', '24h')} health")
    lines.append("")
    lines.append("| Model | N | Success | Drop | Exhaust | Chunked |")
    lines.append("|-------|---|---------|------|---------|---------|")

    warnings: List[str] = []
    for model_id in sorted(report.get("per_model", {}).keys()):
        m = report["per_model"][model_id]
        n = m.get("invocations", 0)
        rate = m.get("success_rate", 0.0)
        band = m.get("band", "green")
        ch = m.get("chain_health", {})
        drop_pct = (ch.get("degraded", 0) / n * 100) if n else 0
        exh_pct = (ch.get("exhausted", 0) / n * 100) if n else 0

        success_cell = _format_pct(rate)
        if band != "green":
            success_cell = f"**{success_cell} ({_band_for_label(band)})**"

        lines.append(
            f"| {model_id} | {n} | {success_cell} | "
            f"{drop_pct:.0f}% | {exh_pct:.0f}% | {m.get('chunked', 0)} |"
        )

        if band == "yellow":
            warnings.append(
                f"- ⚠ {model_id}: success_rate {_format_pct(rate)} below 80% threshold "
                f"({report.get('window', '24h')} window). "
                "Recommend: review trends, consider role restriction."
            )
        elif band == "red":
            warnings.append(
                f"- ❌ {model_id}: success_rate {_format_pct(rate)} below 50% threshold "
                f"({report.get('window', '24h')} window). "
                "Recommend: file a KF entry and restrict role."
            )

    if warnings:
        lines.append("")
        lines.append("### Warnings")
        for w in warnings:
            lines.append(w)

    # Total invocations footer for at-a-glance scanning
    total = report.get("total_invocations", 0)
    overall = report.get("overall", {})
    lines.append("")
    lines.append(
        f"_Total invocations: {total} · "
        f"overall success: {_format_pct(overall.get('success_rate', 0.0))} "
        f"({_band_for_label(overall.get('band', 'green'))})_"
    )
    lines.append("")
    lines.append("---")
    lines.append("")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Append + idempotency
# ---------------------------------------------------------------------------


def _month_header(when: datetime) -> str:
    when_utc = when.astimezone(timezone.utc) if when.tzinfo else when.replace(tzinfo=timezone.utc)
    return f"# Substrate Health Journal — {when_utc.year:04d}-{when_utc.month:02d}"


def append_day_section(
    journal_dir: Path,
    report: Dict[str, Any],
    *,
    run_time: datetime,
) -> Dict[str, Any]:
    """Append today's day-section to YYYY-MM.md, or no-op if already present.

    Returns ``{"action": "appended"|"skipped"|"created", "path": str}``.

    SDD §5.5.3 idempotency: cron is no-op if the day's H2 already exists.
    """
    journal_dir.mkdir(parents=True, exist_ok=True)
    path = journal_path_for_date(journal_dir, run_time)
    day_header = _day_header(run_time)
    rendered = render_day_section(report, run_time=run_time)

    if not path.exists():
        content = _month_header(run_time) + "\n\n" + rendered
        path.write_text(content, encoding="utf-8")
        return {"action": "created", "path": str(path)}

    existing = path.read_text(encoding="utf-8")
    if day_header in existing:
        return {"action": "skipped", "path": str(path)}

    # Append new day below existing content
    if not existing.endswith("\n"):
        existing += "\n"
    path.write_text(existing + rendered, encoding="utf-8")
    return {"action": "appended", "path": str(path)}


# ---------------------------------------------------------------------------
# CLI entrypoint
# ---------------------------------------------------------------------------


def _cli_main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        prog="loa_cheval.journal",
        description=(
            "cycle-109 Sprint 5 T5.8 — substrate-health journal writer. "
            "Aggregates the MODELINV log over a window and appends a "
            "markdown day-section to grimoires/loa/substrate-health/YYYY-MM.md. "
            "Idempotent: re-running on the same UTC day is a no-op."
        ),
    )
    parser.add_argument(
        "--journal-dir", default="grimoires/loa/substrate-health",
        help="Directory containing YYYY-MM.md journal files",
    )
    parser.add_argument(
        "--log-path", default=".run/model-invoke.jsonl",
        help="MODELINV JSONL log path",
    )
    parser.add_argument("--window", default="24h", help="Aggregation window")
    parser.add_argument(
        "--run-time", default=None,
        help="Override run timestamp (ISO 8601 UTC) — for tests/replay",
    )
    parser.add_argument(
        "--json", action="store_true",
        help="Print result envelope (action, path) as JSON instead of text",
    )
    args = parser.parse_args(argv)

    # Resolve run_time
    if args.run_time:
        when = datetime.fromisoformat(args.run_time.replace("Z", "+00:00"))
    else:
        when = datetime.now(timezone.utc)

    # Aggregate via T5.4 health module
    from loa_cheval.health import aggregate_substrate_health
    report = aggregate_substrate_health(
        Path(args.log_path), window=args.window, now=when,
    )

    result = append_day_section(Path(args.journal_dir), report, run_time=when)
    if args.json:
        print(json.dumps(result))
    else:
        print(f"[journal] {result['action']}: {result['path']}")
    return 0


if __name__ == "__main__":  # pragma: no cover
    sys.exit(_cli_main())
