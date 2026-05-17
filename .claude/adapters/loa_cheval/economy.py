"""cycle-112 Sprint 1 (#166) T1.2 — model-economy roll-up aggregator.

Stream-parses `.run/model-invoke.jsonl` (MODELINV envelope log) over a window
and emits per-(skill, model) cost + quality roll-up per SDD §4.1.2.

Reuses the stream-parse + defaultdict pattern from `health.py:153-309`. Sister
module to `health.py` (substrate-health) — the two cross-reference via the
`substrate_health` injection arg on `aggregate_economy`.

Public surface:
  - aggregate_economy(...) -> Dict
  - render_text(report) -> str
  - render_json(report) -> str   (schema-validated)

CLI entrypoint:
  python -m loa_cheval.economy --window 30d [--json] [...]

NFR-Perf-1: <5s for 30d window over 100K envelopes (single-pass, no full-file load).
NFR-Sec-1: text/json output passes through log-redactor in the bash shim.
NFR-Determinism-1: sort rows by (cost_total_usd desc, model_id asc); skip
                   malformed JSON deterministically; round(x, 4).
"""

from __future__ import annotations

import argparse
import json
import math
import subprocess
import sys
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Dict, Iterator, List, Optional, Tuple


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

DEFAULT_LOG_PATH = ".run/model-invoke.jsonl"
DEFAULT_MODEL_CONFIG_PATH = ".claude/defaults/model-config.yaml"
DEFAULT_WINDOW = "30d"
DEGRADATION_THRESHOLD = 2  # PRD §4 FR-2: DEGRADED + FAILED >= 2 → marker
UNATTRIBUTED = "(unattributed)"
UNKNOWN_MODEL = "(unknown_model)"


# ---------------------------------------------------------------------------
# Window parsing (shared shape with health.py — kept local to avoid coupling)
# ---------------------------------------------------------------------------


def parse_window(window: str) -> timedelta:
    """Parse '24h', '7d', '30d', '60m' into a timedelta."""
    if not window:
        return timedelta(days=30)
    if window.endswith("h"):
        return timedelta(hours=int(window[:-1]))
    if window.endswith("d"):
        return timedelta(days=int(window[:-1]))
    if window.endswith("m"):
        return timedelta(minutes=int(window[:-1]))
    raise ValueError(f"unrecognized window format: {window!r} (expected '24h' / '7d' / '30d' / '60m')")


# ---------------------------------------------------------------------------
# Stream-parse MODELINV envelopes
# ---------------------------------------------------------------------------


def iter_modelinv_entries(
    log_path: Path,
    *,
    since: Optional[datetime] = None,
) -> Iterator[Tuple[Dict[str, Any], Dict[str, Any], int]]:
    """Yield (envelope, payload, malformed_count_delta) for each entry whose
    timestamp is >= since.

    Differs from health.iter_modelinv_entries by:
      - returning both envelope and payload (callers need ts_utc from envelope
        for window arithmetic AND various payload fields for aggregation)
      - returning a per-line malformed_count_delta so callers can roll up
        malformed_lines without re-tracking the file pointer

    malformed_count_delta is always 0 for yielded entries; the caller
    increments its counter from a separate side-channel.

    Filter semantics: timestamp-only here. Skill / model substring filters
    are applied at aggregation time so they can match `final_model_id` and
    `models_requested[]` symmetrically.
    """
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
                    # Caller learns about malformed via a side channel; we
                    # cannot increment here without leaking state. Caller
                    # uses `count_malformed_lines` (below) on the file.
                    continue
                payload = envelope.get("payload")
                if not isinstance(payload, dict):
                    continue
                if since is not None:
                    ts_raw = envelope.get("ts_utc") or envelope.get("timestamp") or envelope.get("ts")
                    if ts_raw:
                        try:
                            ts = datetime.fromisoformat(str(ts_raw).replace("Z", "+00:00"))
                            if ts.tzinfo is None:
                                ts = ts.replace(tzinfo=timezone.utc)
                            if ts < since:
                                continue
                        except (ValueError, TypeError):
                            pass
                yield envelope, payload, 0
    except OSError:
        return


def count_malformed_lines(log_path: Path) -> int:
    """Return the number of non-empty lines that fail json.loads. Deterministic.

    Kept separate from iter_modelinv_entries so the iterator stays a pure
    generator (no shared mutable state). Cheap: one extra file scan, json
    parse only.
    """
    if not log_path.is_file():
        return 0
    n = 0
    try:
        with log_path.open("r", encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    json.loads(line)
                except json.JSONDecodeError:
                    n += 1
    except OSError:
        return 0
    return n


# ---------------------------------------------------------------------------
# Pricing lookup
# ---------------------------------------------------------------------------


def load_pricing(
    model_config_path: Path,
    *,
    cost_snapshot_ref: Optional[str] = None,
) -> Dict[str, Dict[str, int]]:
    """Load pricing entries from model-config.yaml.

    Returns:
      {
        "<provider>:<model_id>": {
          "input_per_mtok": int,    # micro-USD per million tokens
          "output_per_mtok": int,
        }
      }

    When cost_snapshot_ref is set, read model-config.yaml from that git
    ref instead of the working tree (PRD R-2 — historical-pricing
    reproducibility).
    """
    if cost_snapshot_ref:
        try:
            blob = subprocess.run(
                ["git", "show", f"{cost_snapshot_ref}:{model_config_path}"],
                check=True,
                capture_output=True,
                text=True,
            ).stdout
        except subprocess.CalledProcessError as e:
            raise FileNotFoundError(
                f"git ref not found or path missing in ref: {cost_snapshot_ref}:{model_config_path}"
            ) from e
        config_text = blob
    else:
        if not model_config_path.is_file():
            raise FileNotFoundError(f"model-config.yaml unreadable at {model_config_path}")
        config_text = model_config_path.read_text(encoding="utf-8")

    try:
        import yaml  # local import: keeps cold-start cheap for callers that pass pricing in
    except ImportError as e:
        raise RuntimeError("PyYAML required for pricing load; install via `pip install pyyaml`") from e

    data = yaml.safe_load(config_text) or {}
    providers = data.get("providers") or {}
    out: Dict[str, Dict[str, int]] = {}
    for provider_name, provider in providers.items():
        if not isinstance(provider, dict):
            continue
        models = provider.get("models") or {}
        for model_id, model in models.items():
            if not isinstance(model, dict):
                continue
            pricing = model.get("pricing")
            if not isinstance(pricing, dict):
                continue
            input_per_mtok = pricing.get("input_per_mtok")
            output_per_mtok = pricing.get("output_per_mtok")
            if input_per_mtok is None and output_per_mtok is None:
                continue
            out[f"{provider_name}:{model_id}"] = {
                "input_per_mtok": int(input_per_mtok) if input_per_mtok is not None else 0,
                "output_per_mtok": int(output_per_mtok) if output_per_mtok is not None else 0,
            }
    return out


def envelope_cost_usd(
    payload: Dict[str, Any],
    *,
    fallback_pricing: Optional[Dict[str, int]] = None,
) -> Optional[float]:
    """Compute the input-side cost for one envelope in USD.

    Formula (SDD §4.1.2):
      input_cost_micro_usd = (input_per_mtok * estimated_input_tokens) / 1_000_000
      envelope_cost_usd    = input_cost_micro_usd / 1_000_000

    `input_per_mtok` is micro-USD per million tokens. Two /1_000_000 gets
    us to USD per envelope.

    Returns None when either pricing or capability data is missing for the
    envelope — the caller buckets these to `unpriced_runs`.
    """
    ps = payload.get("pricing_snapshot") or {}
    ce = payload.get("capability_evaluation") or {}
    tokens = ce.get("estimated_input_tokens")
    if tokens is None:
        return None
    input_per_mtok = ps.get("input_per_mtok")
    if input_per_mtok is None and fallback_pricing is not None:
        input_per_mtok = fallback_pricing.get("input_per_mtok")
    if input_per_mtok is None:
        return None
    try:
        tokens_int = int(tokens)
        input_per_mtok_int = int(input_per_mtok)
    except (TypeError, ValueError):
        return None
    if tokens_int < 0 or input_per_mtok_int < 0:
        return None
    return (input_per_mtok_int * tokens_int) / 1_000_000.0 / 1_000_000.0


# ---------------------------------------------------------------------------
# Verdict-quality classification
# ---------------------------------------------------------------------------


def is_clean_output(payload: Dict[str, Any]) -> bool:
    """SDD §3.3: clean iff verdict_quality.status == APPROVED AND chain_health == ok.

    Note the nesting correction vs PRD §4 wording (PRD said 'APPROVED' but
    the SDD found chain_health is the additional gate).
    """
    vq = payload.get("verdict_quality") or {}
    return vq.get("status") == "APPROVED" and vq.get("chain_health") == "ok"


def classify_verdict_quality(payload: Dict[str, Any]) -> str:
    """Return one of APPROVED / DEGRADED / FAILED / UNKNOWN."""
    vq = payload.get("verdict_quality")
    if not isinstance(vq, dict):
        return "UNKNOWN"
    status = vq.get("status")
    if status in ("APPROVED", "DEGRADED", "FAILED"):
        return status
    return "UNKNOWN"


# ---------------------------------------------------------------------------
# Skill / model extraction
# ---------------------------------------------------------------------------

# Skill attribution candidate fields, in priority order. Today's writer
# carries none of these (SDD §0.3 finding: 0/808). D-6 wires the first one;
# the others are defensive — if the writer evolves we pick up attribution
# without code changes.
SKILL_FIELDS = ("skill", "calling_primitive", "phase", "role", "tier")


def extract_skill(payload: Dict[str, Any]) -> str:
    """Return a skill identifier. Walks SKILL_FIELDS in priority order.

    Falls back to UNATTRIBUTED when nothing matches. Per SDD §0.3 this is
    100% of envelopes today — that's the honest reality the roll-up surfaces.
    """
    for field in SKILL_FIELDS:
        val = payload.get(field)
        if isinstance(val, str) and val:
            return val
    return UNATTRIBUTED


def extract_model(payload: Dict[str, Any]) -> str:
    """Return final_model_id, falling back to models_succeeded[0], then
    models_requested[0], then UNKNOWN_MODEL."""
    final = payload.get("final_model_id")
    if isinstance(final, str) and final:
        return final
    succeeded = payload.get("models_succeeded") or []
    if succeeded:
        return str(succeeded[0])
    requested = payload.get("models_requested") or []
    if requested:
        return str(requested[0])
    return UNKNOWN_MODEL


# ---------------------------------------------------------------------------
# Percentile helper
# ---------------------------------------------------------------------------


def p95(values: List[int]) -> Optional[int]:
    """Return 95th percentile (nearest-rank). None when input is empty.

    Deterministic across re-runs of the same input. Uses ceil(0.95 * n).
    """
    if not values:
        return None
    sorted_vals = sorted(values)
    n = len(sorted_vals)
    # nearest-rank: rank = ceil(0.95 * n), 1-indexed
    rank = max(1, int(math.ceil(0.95 * n)))
    return int(sorted_vals[rank - 1])


# ---------------------------------------------------------------------------
# Main aggregator
# ---------------------------------------------------------------------------


def aggregate_economy(
    log_path: Path,
    model_config_path: Optional[Path] = None,
    *,
    window: str = DEFAULT_WINDOW,
    skill_filter: Optional[str] = None,
    model_filter: Optional[str] = None,
    cost_snapshot_ref: Optional[str] = None,
    now: Optional[datetime] = None,
    substrate_health: Optional[Dict[str, Any]] = None,
    pricing: Optional[Dict[str, Dict[str, int]]] = None,
) -> Dict[str, Any]:
    """Aggregate (skill, model) cost + quality roll-up over the window.

    Returns a dict conforming to model-economy-rollup.schema.json.

    Args:
      log_path: Path to MODELINV JSONL (default `.run/model-invoke.jsonl`).
      model_config_path: Path to model-config.yaml for pricing fallback.
        When None and `pricing` is also None, pricing fallback is disabled
        (only envelope-embedded pricing_snapshot is honored).
      window: '24h' / '7d' / '30d' / etc.
      skill_filter: substring filter on extracted skill identifier.
      model_filter: substring filter on extracted model identifier.
      cost_snapshot_ref: git ref to read model-config.yaml from (PRD R-2).
      now: anchor time (default UTC now).
      substrate_health: optional pre-computed result of
        health.aggregate_substrate_health for the same window. When
        provided, the footer carries the cross-ref (PRD R-5 mitigation).
      pricing: optional pre-loaded pricing dict; takes priority over
        model_config_path. Useful for tests + when the caller has already
        loaded the file.

    Conditional EARS bucketing (SDD §4.1.3): envelopes lacking attribution
    bucket to `(unattributed, <model>)` rather than skip — total cost is
    conserved across rows.
    """
    now = now or datetime.now(timezone.utc)
    delta = parse_window(window)
    since = now - delta

    if pricing is None and model_config_path is not None:
        try:
            pricing = load_pricing(model_config_path, cost_snapshot_ref=cost_snapshot_ref)
        except FileNotFoundError:
            raise
    if pricing is None:
        pricing = {}

    # Coverage counters (rolled across all envelopes in the window —
    # before skill/model filtering, so coverage reflects the underlying
    # log state, not the filtered subset).
    cov_total = 0
    cov_skill = 0
    cov_pricing = 0
    cov_verdict = 0
    cov_capability = 0
    cov_priceable = 0  # both pricing_snapshot AND capability_evaluation

    # Per-cell aggregation
    def _empty_cell() -> Dict[str, Any]:
        return {
            "skill": "",
            "model": "",
            "runs": 0,
            "_cost_priced_sum": 0.0,
            "_cost_priced_count": 0,
            "_cost_clean_sum": 0.0,
            "_cost_clean_count": 0,
            "_latencies": [],
            "verdict_quality_distribution": {
                "APPROVED": 0, "DEGRADED": 0, "FAILED": 0, "UNKNOWN": 0,
            },
            "_vq_known": 0,         # runs with non-UNKNOWN verdict_quality
            "_vq_healthy": 0,       # runs that are is_clean_output
            "first_try_success": 0,
            "attempts": 0,
            "unpriced_runs": 0,
        }

    cells: Dict[Tuple[str, str], Dict[str, Any]] = defaultdict(_empty_cell)

    for envelope, payload, _ in iter_modelinv_entries(log_path, since=since):
        cov_total += 1
        has_skill = any(isinstance(payload.get(f), str) and payload.get(f) for f in SKILL_FIELDS)
        has_pricing = isinstance(payload.get("pricing_snapshot"), dict)
        has_verdict = isinstance(payload.get("verdict_quality"), dict)
        has_capability = (
            isinstance(payload.get("capability_evaluation"), dict)
            and payload["capability_evaluation"].get("estimated_input_tokens") is not None
        )
        if has_skill:
            cov_skill += 1
        if has_pricing:
            cov_pricing += 1
        if has_verdict:
            cov_verdict += 1
        if has_capability:
            cov_capability += 1
        if has_pricing and has_capability:
            cov_priceable += 1

        skill = extract_skill(payload)
        model = extract_model(payload)

        # Apply substring filters
        if skill_filter and skill_filter not in skill:
            continue
        if model_filter and model_filter not in model:
            continue

        cell = cells[(skill, model)]
        cell["skill"] = skill
        cell["model"] = model
        cell["runs"] += 1

        # Cost
        fallback = pricing.get(model)
        cost = envelope_cost_usd(payload, fallback_pricing=fallback)
        if cost is None:
            cell["unpriced_runs"] += 1
        else:
            cell["_cost_priced_sum"] += cost
            cell["_cost_priced_count"] += 1
            if is_clean_output(payload):
                cell["_cost_clean_sum"] += cost
                cell["_cost_clean_count"] += 1

        # Latency
        lat = payload.get("invocation_latency_ms")
        if isinstance(lat, (int, float)) and lat >= 0:
            cell["_latencies"].append(int(lat))

        # Verdict quality
        vq_status = classify_verdict_quality(payload)
        cell["verdict_quality_distribution"][vq_status] += 1
        if vq_status != "UNKNOWN":
            cell["_vq_known"] += 1
            if is_clean_output(payload):
                cell["_vq_healthy"] += 1

        # First-try success + attempts (mirrors health.py)
        models_requested = payload.get("models_requested") or []
        models_succeeded = payload.get("models_succeeded") or []
        for requested in models_requested:
            if str(requested) == model:
                cell["attempts"] += 1
        if (
            models_requested
            and models_succeeded
            and str(models_requested[0]) == str(models_succeeded[0]) == model
        ):
            cell["first_try_success"] += 1

    # Finalize per-cell rows
    per_skill_model: Dict[str, Dict[str, Any]] = {}
    for (skill, model), cell in cells.items():
        runs = cell["runs"]
        cost_priced_count = cell["_cost_priced_count"]
        cost_priced_sum = cell["_cost_priced_sum"]
        cost_total_usd = round(cost_priced_sum, 6) if cost_priced_count > 0 else None
        cost_per_run_usd = (
            round(cost_priced_sum / cost_priced_count, 6) if cost_priced_count > 0 else None
        )
        cost_per_clean_output_usd = (
            round(cell["_cost_clean_sum"] / cell["_cost_clean_count"], 6)
            if cell["_cost_clean_count"] > 0
            else None
        )
        p95_latency_ms = p95(cell["_latencies"])

        vq_dist = cell["verdict_quality_distribution"]
        vq_healthy_pct: Optional[float]
        if cell["_vq_known"] > 0:
            vq_healthy_pct = round(100.0 * cell["_vq_healthy"] / cell["_vq_known"], 2)
        else:
            vq_healthy_pct = None

        degradation_marker = (vq_dist["DEGRADED"] + vq_dist["FAILED"]) >= DEGRADATION_THRESHOLD

        key = f"{skill}|{model}"
        per_skill_model[key] = {
            "skill": skill,
            "model": model,
            "runs": runs,
            "cost_total_usd": cost_total_usd,
            "cost_per_run_usd": cost_per_run_usd,
            "cost_per_clean_output_usd": cost_per_clean_output_usd,
            "cost_input_only": True,  # D-7 follow-up flips this
            "p95_latency_ms": p95_latency_ms,
            "verdict_quality_distribution": vq_dist,
            "verdict_quality_healthy_pct": vq_healthy_pct,
            "degradation_marker": degradation_marker,
            "first_try_success": cell["first_try_success"],
            "attempts": cell["attempts"],
            "unpriced_runs": cell["unpriced_runs"],
        }

    # Footer cross-ref
    footer_health: Optional[Dict[str, Any]] = None
    if substrate_health is not None:
        overall = (substrate_health.get("overall") or {}) if isinstance(substrate_health, dict) else {}
        footer_health = {
            "overall_success_rate": overall.get("success_rate"),
            "overall_band": overall.get("band"),
            "degradation_events_in_window": int(substrate_health.get("degradation_events_in_window", 0))
            if isinstance(substrate_health.get("degradation_events_in_window"), int)
            else 0,
        }

    model_config_ref = (
        f"{model_config_path}@{cost_snapshot_ref}"
        if cost_snapshot_ref and model_config_path
        else (str(model_config_path) if model_config_path else "(none)")
    )

    coverage = {
        "total_envelopes": cov_total,
        "with_skill_attribution": cov_skill,
        "with_pricing_snapshot": cov_pricing,
        "with_verdict_quality": cov_verdict,
        "with_capability_evaluation": cov_capability,
        "skill_attribution_pct": round(100.0 * cov_skill / cov_total, 2) if cov_total else 0.0,
        "cost_coverage_pct": round(100.0 * cov_priceable / cov_total, 2) if cov_total else 0.0,
        "verdict_quality_coverage_pct": round(100.0 * cov_verdict / cov_total, 2) if cov_total else 0.0,
        "malformed_lines": count_malformed_lines(log_path),
    }

    return {
        "window": window,
        "since": since.isoformat().replace("+00:00", "Z"),
        "now": now.isoformat().replace("+00:00", "Z"),
        "log_path": str(log_path),
        "coverage": coverage,
        "per_skill_model": per_skill_model,
        "footer": {
            "model_config_ref": model_config_ref,
            "substrate_health_window_summary": footer_health,
        },
    }


# ---------------------------------------------------------------------------
# Text rendering
# ---------------------------------------------------------------------------


def _format_usd(val: Optional[float]) -> str:
    if val is None:
        return "—"
    if val < 0.01:
        return f"${val:.4f}"
    return f"${val:.2f}"


def _format_pct(val: Optional[float]) -> str:
    if val is None:
        return "—"
    return f"{val:.0f}%"


def _format_ms(val: Optional[int]) -> str:
    if val is None:
        return "—"
    return f"{val}ms"


def _sort_key(item: Tuple[str, Dict[str, Any]]) -> Tuple[float, str, str]:
    """Sort rows by (cost_total_usd desc, model asc, skill asc). None costs
    sort last among 'has data' but before truly empty cells."""
    _, row = item
    cost = row.get("cost_total_usd")
    # Negate cost for descending; rows with None cost go after priced rows.
    # Use math.inf as a marker so None-cost rows sort consistently among themselves.
    cost_sort = -cost if cost is not None else math.inf
    return (cost_sort, row.get("model", ""), row.get("skill", ""))


def render_text(report: Dict[str, Any], *, no_ts_banner: bool = False) -> str:
    """Deterministic text-mode rendering per SDD §3.2.2."""
    lines: List[str] = []
    coverage = report["coverage"]
    window = report["window"]
    since = report["since"]
    log_path = report["log_path"]
    total = coverage["total_envelopes"]

    if not no_ts_banner:
        lines.append(f"Model-Economy Roll-Up — last {window} (since {since})")
    else:
        lines.append(f"Model-Economy Roll-Up — last {window}")
    lines.append(f"Source: {log_path} ({total} envelopes)")
    lines.append(
        f"Coverage: skill attribution {_format_pct(coverage['skill_attribution_pct'])} "
        f"(D-6 follow-up) · cost {_format_pct(coverage['cost_coverage_pct'])} · "
        f"verdict_quality {_format_pct(coverage['verdict_quality_coverage_pct'])}"
    )
    if coverage["malformed_lines"] > 0:
        lines.append(f"  (malformed JSON lines skipped: {coverage['malformed_lines']})")
    lines.append("")

    if not report["per_skill_model"]:
        lines.append("No envelopes matched the window + filters.")
    else:
        header = f"{'Skill':<24} {'Model':<38} {'Runs':>6}  {'Cost/run':>10}  {'p95-latency':>12}  {'VQ-healthy':>11}"
        lines.append(header)
        lines.append("-" * len(header))
        sorted_rows = sorted(report["per_skill_model"].items(), key=_sort_key)
        for _, row in sorted_rows:
            marker = "  ⚠ degraded" if row["degradation_marker"] else ""
            cost_marker = " *" if row["cost_per_run_usd"] is not None else ""
            cost_disp = f"{_format_usd(row['cost_per_run_usd'])}{cost_marker}"
            line = (
                f"{row['skill']:<24} {row['model']:<38} {row['runs']:>6}  "
                f"{cost_disp:>10}  "
                f"{_format_ms(row['p95_latency_ms']):>12}  "
                f"{_format_pct(row['verdict_quality_healthy_pct']):>11}{marker}"
            )
            lines.append(line)
        lines.append("")
        lines.append(
            "* cost shown only when envelope has both pricing_snapshot and capability_evaluation;"
        )
        lines.append("  rows without cost data show \"—\". Coverage line above quantifies the gap.")

    lines.append("")
    lines.append("Footer:")
    lines.append(f"  model-config.yaml ref: {report['footer']['model_config_ref']}")
    sh = report["footer"]["substrate_health_window_summary"]
    if sh is not None:
        sr = sh.get("overall_success_rate")
        band = sh.get("overall_band")
        deg = sh.get("degradation_events_in_window", 0)
        sr_disp = f"{sr:.2f}" if isinstance(sr, (int, float)) else "—"
        band_disp = band or "—"
        lines.append(
            f"  substrate-health ({window}): success_rate={sr_disp} "
            f"band={band_disp} degradation_events={deg}"
        )
        lines.append(
            f"  (See: bash .claude/scripts/loa-substrate-health.sh --window {window} for details)"
        )
    else:
        lines.append(
            f"  substrate-health: not cross-referenced "
            f"(run loa-substrate-health.sh --window {window} for the partner view)"
        )
    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------------------
# JSON rendering (schema-validated)
# ---------------------------------------------------------------------------


def _schema_path() -> Path:
    """Return path to model-economy-rollup.schema.json relative to repo root.

    This module lives at .claude/adapters/loa_cheval/economy.py; the schema
    is at .claude/data/schemas/model-economy-rollup.schema.json. Two parents
    up from __file__ → .claude/adapters/loa_cheval → .claude/adapters →
    .claude → data/schemas/...
    """
    return Path(__file__).resolve().parent.parent.parent / "data" / "schemas" / "model-economy-rollup.schema.json"


def render_json(report: Dict[str, Any], *, validate: bool = True) -> str:
    """Schema-validated JSON output per SDD §3.2.1.

    Raises on schema violation when validate=True (caller-set false only in
    tests that explicitly target malformed-output paths).
    """
    if validate:
        try:
            import jsonschema
        except ImportError as e:
            raise RuntimeError(
                "jsonschema required for --json output validation; install via `pip install jsonschema`"
            ) from e
        schema_path = _schema_path()
        if not schema_path.is_file():
            raise FileNotFoundError(f"schema not found at {schema_path}")
        schema = json.loads(schema_path.read_text(encoding="utf-8"))
        jsonschema.Draft202012Validator(schema).validate(report)
    return json.dumps(report, indent=2, sort_keys=True, default=str)


# ---------------------------------------------------------------------------
# CLI entrypoint
# ---------------------------------------------------------------------------


def _cli_main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        prog="loa_cheval.economy",
        description="Model-economy roll-up aggregator (cycle-112 Sprint 1 / FR-1)",
    )
    parser.add_argument(
        "--window", default=DEFAULT_WINDOW,
        help="Aggregation window (e.g., 24h / 7d / 30d). Default 30d.",
    )
    parser.add_argument("--json", action="store_true", help="Emit JSON (schema-validated) instead of text")
    parser.add_argument("--skill", default=None, help="Substring filter on skill identifier")
    parser.add_argument("--model", default=None, help="Substring filter on model identifier")
    parser.add_argument(
        "--log-path", default=DEFAULT_LOG_PATH,
        help="MODELINV JSONL log path (default .run/model-invoke.jsonl)",
    )
    parser.add_argument(
        "--model-config", default=DEFAULT_MODEL_CONFIG_PATH,
        help="Pricing fallback source (default .claude/defaults/model-config.yaml)",
    )
    parser.add_argument(
        "--cost-snapshot", default=None,
        help="Git ref to read model-config.yaml from (PRD R-2 historical pricing)",
    )
    parser.add_argument(
        "--no-ts-banner", action="store_true",
        help="Omit since-timestamp from text banner (for NFR-Determinism-1 tests)",
    )
    parser.add_argument(
        "--with-substrate-health", action="store_true",
        help="Cross-reference substrate-health for the same window (PRD R-5)",
    )
    args = parser.parse_args(argv)

    log_path = Path(args.log_path)
    model_config_path = Path(args.model_config) if args.model_config else None

    substrate_health: Optional[Dict[str, Any]] = None
    if args.with_substrate_health:
        try:
            from loa_cheval.health import aggregate_substrate_health  # type: ignore
            substrate_health = aggregate_substrate_health(
                log_path=log_path, window=args.window, model_filter=args.model,
            )
        except Exception as e:  # noqa: BLE001 — cross-ref is advisory
            print(f"[economy] warning: substrate-health cross-ref failed: {e}", file=sys.stderr)

    try:
        report = aggregate_economy(
            log_path=log_path,
            model_config_path=model_config_path,
            window=args.window,
            skill_filter=args.skill,
            model_filter=args.model,
            cost_snapshot_ref=args.cost_snapshot,
            substrate_health=substrate_health,
        )
    except FileNotFoundError as e:
        msg = str(e)
        if "git ref" in msg:
            print(f"[economy] error: {msg}", file=sys.stderr)
            return 5
        print(f"[economy] error: {msg}", file=sys.stderr)
        return 3
    except ValueError as e:
        print(f"[economy] error: {e}", file=sys.stderr)
        return 2

    try:
        if args.json:
            sys.stdout.write(render_json(report))
            sys.stdout.write("\n")
        else:
            sys.stdout.write(render_text(report, no_ts_banner=args.no_ts_banner))
    except Exception as e:  # noqa: BLE001 — schema/validation surface
        if "jsonschema" in str(type(e)).lower() or "ValidationError" in str(type(e).__name__):
            print(f"[economy] schema validation failed: {e}", file=sys.stderr)
            return 4
        raise
    return 0


if __name__ == "__main__":  # pragma: no cover
    sys.exit(_cli_main())
