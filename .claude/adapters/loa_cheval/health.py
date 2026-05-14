"""cycle-109 Sprint 5 T5.4 — substrate-health aggregator.

Reads `.run/model-invoke.jsonl` (MODELINV envelope log) over a window
and emits per-model + overall substrate-health summary. Surfaces:

  - success rate per model (over the window)
  - chain_health distribution (ok / degraded / exhausted)
  - chunked dispatch frequency (T4.7 chunked_review field)
  - streaming-recovery aborts (T4.7 streaming_recovery field)
  - verdict_quality status distribution (T2.3+T2.4)

The aggregator is pure (no I/O outside the input file path) and
deterministic. CLI shim at `.claude/scripts/loa-substrate-health.sh`
shells out to `python -m loa_cheval.health` for the canonical Python
implementation per SDD §5.2.1.

NFR-Perf-3: <2s for 24h window on 100K-entry log. Stream-parse (no
full-file load); aggregate as we go.

NFR-Sec-3: output piped through log-redactor before stdout (rationale
text from verdict_quality may carry shapes the redactor scrubs).
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Dict, Iterator, List, Optional


# ---------------------------------------------------------------------------
# Threshold bands (FR-5.7)
# ---------------------------------------------------------------------------

THRESHOLD_GREEN_MIN = 0.80  # ≥ 80% success → green
THRESHOLD_YELLOW_MIN = 0.50  # 50-80% success → yellow + warning
# < 50% → red + KF-suggest


def classify_band(success_rate: float) -> str:
    """Return 'green' / 'yellow' / 'red' per FR-5.7 health-threshold bands."""
    if success_rate >= THRESHOLD_GREEN_MIN:
        return "green"
    if success_rate >= THRESHOLD_YELLOW_MIN:
        return "yellow"
    return "red"


# ---------------------------------------------------------------------------
# Window parsing
# ---------------------------------------------------------------------------


def parse_window(window: str) -> timedelta:
    """Parse '24h', '7d', '30d', etc. into a timedelta."""
    if not window:
        return timedelta(hours=24)
    if window.endswith("h"):
        return timedelta(hours=int(window[:-1]))
    if window.endswith("d"):
        return timedelta(days=int(window[:-1]))
    if window.endswith("m"):
        return timedelta(minutes=int(window[:-1]))
    raise ValueError(f"unrecognized window format: {window!r} (expected '24h' / '7d' / etc.)")


# ---------------------------------------------------------------------------
# Aggregation
# ---------------------------------------------------------------------------


def iter_modelinv_entries(
    log_path: Path,
    *,
    since: Optional[datetime] = None,
    model_filter: Optional[str] = None,
) -> Iterator[Dict[str, Any]]:
    """Stream-parse the MODELINV JSONL log. Yields each entry's payload
    (the inner dict, not the envelope wrapper). Filters by timestamp
    (since) and model_filter when supplied."""
    if not log_path.is_file():
        return
    try:
        with log_path.open("r", encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    envelope = json.loads(line)
                except json.JSONDecodeError:
                    continue
                # Envelope shape: {primitive_id, event_type, payload: {...}, ...}
                payload = envelope.get("payload")
                if not isinstance(payload, dict):
                    continue
                # Timestamp filter
                if since is not None:
                    ts_raw = envelope.get("timestamp") or envelope.get("ts")
                    if ts_raw:
                        try:
                            ts = datetime.fromisoformat(ts_raw.replace("Z", "+00:00"))
                            if ts < since:
                                continue
                        except (ValueError, TypeError):
                            pass
                # Model filter
                if model_filter:
                    requested = payload.get("models_requested") or []
                    if not any(model_filter in r for r in requested):
                        continue
                yield payload
    except OSError:
        return


def aggregate_substrate_health(
    log_path: Path,
    *,
    window: str = "24h",
    model_filter: Optional[str] = None,
    now: Optional[datetime] = None,
) -> Dict[str, Any]:
    """Aggregate substrate-health metrics over the window.

    Returns:
      {
        "window": "24h",
        "since": "ISO timestamp",
        "total_invocations": int,
        "per_model": {
          "<model_id>": {
            "invocations": int,
            "succeeded": int,
            "success_rate": float,
            "band": "green"|"yellow"|"red",
            "chain_health": {"ok": N, "degraded": N, "exhausted": N},
            "chunked": int,
            "streaming_aborts": {"first_token_deadline": N, ...},
            "verdict_status": {"APPROVED": N, "DEGRADED": N, "FAILED": N}
          }
        },
        "overall": {success_rate, band, ...}
      }
    """
    now = now or datetime.now(timezone.utc)
    delta = parse_window(window)
    since = now - delta

    per_model: Dict[str, Dict[str, Any]] = defaultdict(lambda: {
        "invocations": 0,
        "succeeded": 0,
        "chain_health": {"ok": 0, "degraded": 0, "exhausted": 0},
        "chunked": 0,
        "streaming_aborts": defaultdict(int),
        "verdict_status": {"APPROVED": 0, "DEGRADED": 0, "FAILED": 0},
    })

    for payload in iter_modelinv_entries(
        log_path, since=since, model_filter=model_filter,
    ):
        models_succeeded = payload.get("models_succeeded") or []
        models_requested = payload.get("models_requested") or []
        final_model = (
            payload.get("final_model_id")
            or (models_succeeded[0] if models_succeeded else
                (models_requested[0] if models_requested else "unknown"))
        )
        bucket = per_model[final_model]
        bucket["invocations"] += 1
        if models_succeeded:
            bucket["succeeded"] += 1

        # verdict_quality envelope
        vq = payload.get("verdict_quality") or {}
        status = vq.get("status")
        if status in bucket["verdict_status"]:
            bucket["verdict_status"][status] += 1
        ch = vq.get("chain_health")
        if ch in bucket["chain_health"]:
            bucket["chain_health"][ch] += 1

        # chunked_review (T4.7)
        cr = payload.get("chunked_review") or {}
        if cr.get("chunked"):
            bucket["chunked"] += 1

        # streaming_recovery (T4.7)
        sr = payload.get("streaming_recovery") or {}
        if sr.get("triggered"):
            reason = sr.get("reason") or "unknown"
            bucket["streaming_aborts"][reason] += 1

    # Compute derived fields
    total = 0
    overall_succeeded = 0
    for model_id, bucket in per_model.items():
        n = bucket["invocations"]
        s = bucket["succeeded"]
        rate = (s / n) if n > 0 else 0.0
        bucket["success_rate"] = round(rate, 4)
        bucket["band"] = classify_band(rate)
        bucket["streaming_aborts"] = dict(bucket["streaming_aborts"])
        total += n
        overall_succeeded += s

    overall_rate = (overall_succeeded / total) if total > 0 else 0.0

    return {
        "window": window,
        "since": since.isoformat(),
        "now": now.isoformat(),
        "log_path": str(log_path),
        "total_invocations": total,
        "overall": {
            "succeeded": overall_succeeded,
            "success_rate": round(overall_rate, 4),
            "band": classify_band(overall_rate),
        },
        "per_model": dict(per_model),
    }


# ---------------------------------------------------------------------------
# Text rendering
# ---------------------------------------------------------------------------


def render_text(report: Dict[str, Any]) -> str:
    """Human-readable text rendering with FR-5.7 threshold warnings."""
    lines: List[str] = []
    lines.append(f"# Substrate Health — window={report['window']}")
    lines.append(f"  log: {report['log_path']}")
    lines.append(f"  since: {report['since']}")
    lines.append(f"  total invocations: {report['total_invocations']}")
    overall = report["overall"]
    band_marker = {"green": "✓", "yellow": "⚠", "red": "❌"}.get(overall["band"], "?")
    lines.append(
        f"  overall: {overall['succeeded']}/{report['total_invocations']} "
        f"= {overall['success_rate']:.1%} {band_marker} {overall['band'].upper()}"
    )
    # Only emit band-warning text when there's actual data — a zero-
    # invocation report (missing log or empty window) computes 0/0 = 0.0
    # which classifies as 'red' but is not a real degradation signal.
    if report["total_invocations"] > 0:
        if overall["band"] == "red":
            lines.append("  ❌ RED band — substrate is degraded. Consider filing a KF entry.")
        elif overall["band"] == "yellow":
            lines.append("  ⚠ YELLOW band — substrate showing some degradation. Watch for trends.")
    lines.append("")
    lines.append("## Per-model:")
    for model_id in sorted(report["per_model"].keys()):
        b = report["per_model"][model_id]
        marker = {"green": "✓", "yellow": "⚠", "red": "❌"}.get(b["band"], "?")
        lines.append(
            f"  {marker} {model_id}: {b['succeeded']}/{b['invocations']} "
            f"= {b['success_rate']:.1%} ({b['band']})"
        )
        if b["chunked"] > 0:
            lines.append(f"    chunked: {b['chunked']} invocations")
        if b["streaming_aborts"]:
            lines.append(f"    streaming aborts: {dict(b['streaming_aborts'])}")
        ch_nonzero = {k: v for k, v in b["chain_health"].items() if v > 0}
        if ch_nonzero:
            lines.append(f"    chain_health: {ch_nonzero}")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# CLI entrypoint
# ---------------------------------------------------------------------------


def _cli_main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        prog="loa_cheval.health",
        description="Substrate-health aggregator (cycle-109 Sprint 5 T5.4 / FR-5.4)",
    )
    parser.add_argument("--window", default="24h", help="Aggregation window (24h / 7d / 30d)")
    parser.add_argument("--json", action="store_true", help="Output JSON instead of text")
    parser.add_argument("--model", default=None, help="Filter to a single model id")
    parser.add_argument(
        "--log-path",
        default=".run/model-invoke.jsonl",
        help="MODELINV JSONL log path (default .run/model-invoke.jsonl)",
    )
    args = parser.parse_args(argv)

    try:
        report = aggregate_substrate_health(
            log_path=Path(args.log_path),
            window=args.window,
            model_filter=args.model,
        )
    except ValueError as e:
        print(f"[substrate-health] error: {e}", file=sys.stderr)
        return 2

    if args.json:
        print(json.dumps(report, indent=2, default=str))
    else:
        print(render_text(report))
    return 0


if __name__ == "__main__":  # pragma: no cover
    sys.exit(_cli_main())
