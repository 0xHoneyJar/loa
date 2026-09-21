#!/usr/bin/env python3
"""cycle-109 Sprint 1 T1.7 — ceiling-probe protocol (PRD §FR-1.6, IMP-007).

Empirical binary-search derivation of `effective_input_ceiling` per
(provider, model_id). Probes ``N prompts × M input sizes`` and selects
the ceiling as the LARGEST probed size whose empty-content rate is
≤ ``empty_threshold`` (default 5%). When every size is empty-free, the
ceiling is the maximum probed size. When the smallest probed size
already exceeds the threshold, the ceiling collapses to the smallest
probed size (defensive lower bound — the substrate refuses to dispatch
above a known-bad ceiling).

Per PRD §FR-1.6 the canonical probe geometry is ``5 prompts × 5 sizes``
at ``[10K, 20K, 30K, 40K, 50K]`` input tokens. Operators can override
the geometry via ``--sizes`` and ``--samples-per-size``.

Probe backends
---------------
``fixture`` — read a deterministic JSON file mapping ``size`` →
``(empty_count, sample_count)``. The fixture mode is used by the bats
suite (no network) and by operators who want to replay a prior
calibration trace. Schema::

    {
      "provider": "anthropic",
      "model_id": "claude-opus-4-7",
      "trials": [
        { "size": 10000, "empty_count": 0, "sample_count": 5 },
        ...
      ]
    }

``live`` — invoke cheval.cmd_invoke in batch against the real provider.
**Currently disabled** under the cycle-109 substrate-degraded posture
(Anthropic credit-too-low + OpenAI Responses API insufficient_quota).
Live calibration is the cycle-109 operator-driven track per
``grimoires/loa/cycles/cycle-109-substrate-hardening/operator-approval.md::C109.OP-6``
and the T1.10 baselines artifact. The ``live`` backend exits 6 with a
clear message pointing the operator at the runbook.

Output
------
``--apply``  writes the calibration record back to model-config.yaml
under ``providers.<p>.models.<m>.ceiling_calibration`` and updates
``effective_input_ceiling`` in place.

Without ``--apply`` the script emits the calibration record as compact
JSON on stdout (dry-run; no file mutation).
"""

from __future__ import annotations

import argparse
import datetime
import json
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

try:
    import yaml
except ImportError:  # pragma: no cover
    print("[ceiling-probe] FATAL: PyYAML required.", file=sys.stderr)
    raise

DEFAULT_SIZES = [10000, 20000, 30000, 40000, 50000]
DEFAULT_SAMPLES_PER_SIZE = 5
DEFAULT_EMPTY_THRESHOLD = 0.05  # 5%
DEFAULT_STALE_AFTER_DAYS = 30


# ---------------------------------------------------------------------------
# Fixture probe backend
# ---------------------------------------------------------------------------

def load_fixture(path: Path) -> List[Tuple[int, int, int]]:
    """Load a probe-fixture JSON file and return [(size, empty, sample), ...].

    Raises ValueError on malformed fixtures (missing keys, type errors,
    empty trials list).
    """
    if not path.is_file():
        raise ValueError(f"fixture not found: {path}")
    raw = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(raw, dict):
        raise ValueError(f"fixture root must be an object: {path}")
    trials = raw.get("trials")
    if not isinstance(trials, list) or len(trials) == 0:
        raise ValueError(f"fixture missing or empty 'trials' list: {path}")
    out: List[Tuple[int, int, int]] = []
    for idx, t in enumerate(trials):
        if not isinstance(t, dict):
            raise ValueError(f"fixture trial[{idx}] not a dict: {path}")
        for key in ("size", "empty_count", "sample_count"):
            if key not in t:
                raise ValueError(f"fixture trial[{idx}] missing '{key}': {path}")
            if not isinstance(t[key], int):
                raise ValueError(
                    f"fixture trial[{idx}].{key} must be int: {path}"
                )
        if t["sample_count"] <= 0:
            raise ValueError(f"fixture trial[{idx}].sample_count must be >0: {path}")
        if t["empty_count"] < 0 or t["empty_count"] > t["sample_count"]:
            raise ValueError(
                f"fixture trial[{idx}] empty_count out of range: {path}"
            )
        out.append((t["size"], t["empty_count"], t["sample_count"]))
    out.sort(key=lambda x: x[0])
    return out


# ---------------------------------------------------------------------------
# Ceiling-pick logic
# ---------------------------------------------------------------------------

def pick_ceiling(
    trials: List[Tuple[int, int, int]],
    empty_threshold: float = DEFAULT_EMPTY_THRESHOLD,
) -> Tuple[int, int]:
    """Pick the ceiling per PRD §FR-1.6.

    Returns (ceiling_tokens, total_sample_size).

    Rules:
      - safe_size = largest size whose empty_rate <= empty_threshold.
      - If a safe_size exists → ceiling = safe_size.
      - If no safe_size exists (smallest probed already over threshold)
        → ceiling = smallest probed size (defensive lower bound).
    """
    if not trials:
        raise ValueError("pick_ceiling: empty trials list")
    safe_sizes: List[int] = []
    total_samples = 0
    for size, empty_count, sample_count in trials:
        total_samples += sample_count
        rate = empty_count / sample_count
        if rate <= empty_threshold:
            safe_sizes.append(size)
    if safe_sizes:
        ceiling = max(safe_sizes)
    else:
        # No safe size — defensive bound is the smallest probed size.
        ceiling = min(t[0] for t in trials)
    return ceiling, total_samples


# ---------------------------------------------------------------------------
# Calibration record + model-config write
# ---------------------------------------------------------------------------

def build_calibration_record(
    ceiling: int,
    sample_size: int,
    *,
    stale_after_days: int = DEFAULT_STALE_AFTER_DAYS,
    now: Optional[datetime.datetime] = None,
) -> Dict[str, Any]:
    now = now or datetime.datetime.now(datetime.timezone.utc)
    return {
        "source": "empirical_probe",
        "calibrated_at": now.isoformat().replace("+00:00", "Z"),
        "sample_size": sample_size,
        "stale_after_days": stale_after_days,
        "reprobe_trigger": (
            "first KF entry referencing model OR "
            f"{stale_after_days}d elapsed OR operator-forced"
        ),
    }


def apply_calibration(
    model_config_path: Path,
    provider: str,
    model_id: str,
    ceiling: int,
    calibration: Dict[str, Any],
) -> None:
    cfg = yaml.safe_load(model_config_path.read_text(encoding="utf-8")) or {}
    providers = cfg.setdefault("providers", {})
    prov_block = providers.setdefault(provider, {})
    models = prov_block.setdefault("models", {})
    model_entry = models.get(model_id)
    if not isinstance(model_entry, dict):
        raise ValueError(
            f"model not found in config: {provider}:{model_id}"
        )
    model_entry["effective_input_ceiling"] = ceiling
    model_entry["ceiling_calibration"] = calibration
    with model_config_path.open("w", encoding="utf-8") as fh:
        yaml.safe_dump(cfg, fh, sort_keys=False, default_flow_style=None, allow_unicode=True)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        description="cycle-109 T1.7 — empirical ceiling probe (PRD §FR-1.6).",
    )
    parser.add_argument("--provider", required=True)
    parser.add_argument("--model-id", required=True, dest="model_id")
    parser.add_argument(
        "--model-config",
        required=True,
        type=Path,
        help="Path to model-config.yaml (v3 schema).",
    )
    parser.add_argument(
        "--probe-backend",
        choices=("fixture", "live"),
        default="fixture",
        dest="probe_backend",
        help="Probe backend. 'fixture' replays a JSON trace (test mode); "
             "'live' invokes cheval against the real provider — DISABLED "
             "under cycle-109 substrate-degraded posture.",
    )
    parser.add_argument(
        "--fixture",
        type=Path,
        default=None,
        help="JSON fixture path (required for --probe-backend fixture).",
    )
    parser.add_argument(
        "--sizes",
        default=",".join(str(s) for s in DEFAULT_SIZES),
        help="Comma-separated input sizes in tokens (live mode only).",
    )
    parser.add_argument(
        "--samples-per-size",
        type=int,
        default=DEFAULT_SAMPLES_PER_SIZE,
        dest="samples_per_size",
        help="Number of probe prompts per size (live mode only).",
    )
    parser.add_argument(
        "--empty-threshold",
        type=float,
        default=DEFAULT_EMPTY_THRESHOLD,
        dest="empty_threshold",
        help="Empty-content rate above which a size is considered unsafe.",
    )
    parser.add_argument(
        "--stale-after-days",
        type=int,
        default=DEFAULT_STALE_AFTER_DAYS,
        dest="stale_after_days",
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Write the result to model-config.yaml; without --apply the "
             "result JSON is emitted to stdout (dry-run).",
    )
    args = parser.parse_args(argv)

    if args.probe_backend == "live":
        print(
            "[ceiling-probe] live backend is disabled in cycle-109 "
            "(substrate-degraded — Anthropic credit-too-low + OpenAI "
            "Responses API insufficient_quota). Live calibration is "
            "operator-driven per C109.OP-6 and the T1.10 baselines "
            "artifact. Re-enable after operator-side billing restoration.",
            file=sys.stderr,
        )
        return 6

    if args.fixture is None:
        print(
            "[ceiling-probe] --fixture <path> required when "
            "--probe-backend fixture (the cycle-109 default).",
            file=sys.stderr,
        )
        return 2

    try:
        trials = load_fixture(args.fixture)
    except ValueError as e:
        print(f"[ceiling-probe] ERROR: {e}", file=sys.stderr)
        return 2

    ceiling, sample_size = pick_ceiling(trials, args.empty_threshold)
    calibration = build_calibration_record(
        ceiling, sample_size,
        stale_after_days=args.stale_after_days,
    )

    result = {
        "provider": args.provider,
        "model_id": args.model_id,
        "effective_input_ceiling": ceiling,
        "ceiling_calibration": calibration,
    }

    if args.apply:
        try:
            apply_calibration(
                args.model_config,
                args.provider,
                args.model_id,
                ceiling,
                calibration,
            )
        except ValueError as e:
            print(f"[ceiling-probe] ERROR: {e}", file=sys.stderr)
            return 2

    print(json.dumps(result, separators=(",", ":"), ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
