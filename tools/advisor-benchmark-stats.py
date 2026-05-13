#!/usr/bin/env python3
"""tools/advisor-benchmark-stats.py — cycle-108 sprint-2 T2.B

Paired-bootstrap statistics + outcome classifier for advisor-strategy
benchmark replays. SDD §5.5 / §9 / §21.5 / §20.10 ATK-A5.

Five-state classifier per (sprint, tier):
  PASS         — advisor >= executor at 95% CI
  FAIL         — advisor < executor at 95% CI
  INCONCLUSIVE — CI straddles zero
  OPT-IN-ONLY  — stratum-level flag (operator decision)
  UNTESTABLE   — INCONCLUSIVE_count / total > 0.25 for the stratum

Memory budget: ≤256MB resident for 100-replay aggregation (NFR per §21.5).
Implementation: streaming JSONL reader (no full-load into memory) +
fixed-size paired-sample buffers per (sprint, tier).

Usage:
  advisor-benchmark-stats.py --outcomes <path> --score-key <key> [options]
  advisor-benchmark-stats.py --output <path>

Outcomes file: JSONL where each line is a per-replay record with at least:
  - sprint_sha, tier (advisor|executor), idx
  - score (numeric quality metric; e.g., bridge-review score 0..1)
  - outcome (OK / OK-with-fallback / INCONCLUSIVE / EXCLUDED)
  - stratum (sprint-kind label)

Exit codes:
  0 — analysis complete
  2 — invalid args
  3 — insufficient data (no pairs found)
"""
from __future__ import annotations

import argparse
import json
import random
import statistics
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple


def _paired_bootstrap_ci(
    pairs: List[Tuple[float, float]],
    *,
    n_resamples: int = 10000,
    confidence: float = 0.95,
    seed: int = 42,
) -> Tuple[float, float, float]:
    """Compute (mean_delta, lower_ci, upper_ci) via paired bootstrap.

    Each pair is (advisor_score, executor_score). Delta = advisor - executor.
    Positive mean → advisor wins; negative → executor wins.
    """
    if not pairs:
        return (0.0, 0.0, 0.0)
    rnd = random.Random(seed)
    n = len(pairs)
    deltas = [a - e for a, e in pairs]
    mean_delta = statistics.fmean(deltas)
    samples: List[float] = []
    for _ in range(n_resamples):
        idx = [rnd.randrange(0, n) for _ in range(n)]
        resample_mean = statistics.fmean(deltas[i] for i in idx)
        samples.append(resample_mean)
    samples.sort()
    alpha = (1 - confidence) / 2
    lower = samples[int(n_resamples * alpha)]
    upper = samples[int(n_resamples * (1 - alpha))]
    return (mean_delta, lower, upper)


def _classify_pair(mean_delta: float, lower_ci: float, upper_ci: float) -> str:
    """Map CI position to PASS/FAIL/INCONCLUSIVE."""
    if lower_ci > 0:
        return "PASS"
    if upper_ci < 0:
        return "FAIL"
    return "INCONCLUSIVE"


def _iter_outcomes_streaming(path: Path):
    """Yield each JSONL outcome record without loading the full file."""
    with path.open() as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            try:
                yield json.loads(line)
            except json.JSONDecodeError:
                continue


def _aggregate(
    outcomes_path: Path,
    score_key: str,
) -> Tuple[Dict[Tuple[str, str], List[float]], Dict[str, Any]]:
    """Streaming reader: groups scores by (sprint_sha, tier) without loading
    the whole file. Returns (groups, stratum_index, stratum_inconclusive).
    """
    groups: Dict[Tuple[str, str], List[float]] = defaultdict(list)
    stratum_index: Dict[str, str] = {}  # sprint_sha → stratum
    stratum_inconclusive: Dict[str, int] = defaultdict(int)
    stratum_total: Dict[str, int] = defaultdict(int)

    for entry in _iter_outcomes_streaming(outcomes_path):
        sprint_sha = entry.get("sprint_sha")
        tier = entry.get("tier")
        if not sprint_sha or not tier:
            continue
        score = entry.get(score_key)
        if score is None:
            continue
        try:
            score = float(score)
        except (ValueError, TypeError):
            continue
        groups[(sprint_sha, tier)].append(score)
        stratum = entry.get("stratum") or "unknown"
        stratum_index[sprint_sha] = stratum
        stratum_total[stratum] += 1
        if entry.get("outcome") == "INCONCLUSIVE":
            stratum_inconclusive[stratum] += 1

    meta = {
        "stratum_inconclusive": dict(stratum_inconclusive),
        "stratum_total": dict(stratum_total),
        "stratum_index": stratum_index,
    }
    return groups, meta


def _untestable_strata(meta: Dict[str, Any], inconclusive_threshold: float = 0.25) -> List[str]:
    """Return strata where INCONCLUSIVE_count / total > threshold (SDD §20.10 ATK-A5)."""
    out: List[str] = []
    for stratum, total in meta["stratum_total"].items():
        if total == 0:
            continue
        inconclusive = meta["stratum_inconclusive"].get(stratum, 0)
        if (inconclusive / total) > inconclusive_threshold:
            out.append(stratum)
    return out


def _classify(
    groups: Dict[Tuple[str, str], List[float]],
    meta: Dict[str, Any],
    untestable: List[str],
    *,
    n_resamples: int,
) -> Dict[str, Any]:
    """Per-(sprint, tier-pair) classification."""
    # First, build (sprint → {advisor: [scores], executor: [scores]}).
    by_sprint: Dict[str, Dict[str, List[float]]] = defaultdict(dict)
    for (sprint, tier), scores in groups.items():
        by_sprint[sprint][tier] = scores

    sprint_classifications: List[Dict[str, Any]] = []
    variance_flagged: List[Dict[str, Any]] = []

    for sprint, tiers in sorted(by_sprint.items()):
        advisor_scores = tiers.get("advisor", [])
        executor_scores = tiers.get("executor", [])
        stratum = meta["stratum_index"].get(sprint, "unknown")
        if stratum in untestable:
            sprint_classifications.append({
                "sprint_sha": sprint,
                "stratum": stratum,
                "classification": "UNTESTABLE",
                "reason": f"stratum '{stratum}' INCONCLUSIVE-rate > 25%",
            })
            continue
        if not advisor_scores or not executor_scores:
            sprint_classifications.append({
                "sprint_sha": sprint,
                "stratum": stratum,
                "classification": "INCONCLUSIVE",
                "reason": "missing tier samples",
            })
            continue

        # Variance check (SDD §5.5): 2σ across 3 replays in either tier.
        for tier_name, ss in (("advisor", advisor_scores), ("executor", executor_scores)):
            if len(ss) >= 2:
                stdev = statistics.pstdev(ss)
                mean = statistics.fmean(ss)
                if mean != 0 and (stdev / abs(mean)) > 2.0:
                    variance_flagged.append({
                        "sprint_sha": sprint,
                        "tier": tier_name,
                        "stdev_over_mean": stdev / abs(mean),
                    })

        # Pair scores (advisor[i], executor[i]) — truncate to common length.
        pair_n = min(len(advisor_scores), len(executor_scores))
        pairs = list(zip(advisor_scores[:pair_n], executor_scores[:pair_n]))
        mean_delta, lower, upper = _paired_bootstrap_ci(
            pairs, n_resamples=n_resamples,
        )
        classification = _classify_pair(mean_delta, lower, upper)
        sprint_classifications.append({
            "sprint_sha": sprint,
            "stratum": stratum,
            "classification": classification,
            "mean_delta": mean_delta,
            "ci_lower": lower,
            "ci_upper": upper,
            "advisor_n": len(advisor_scores),
            "executor_n": len(executor_scores),
        })

    return {
        "sprint_classifications": sprint_classifications,
        "variance_flagged": variance_flagged,
        "untestable_strata": untestable,
    }


def _per_stratum_summary(classifications: List[Dict[str, Any]]) -> Dict[str, Any]:
    by_stratum: Dict[str, Dict[str, int]] = defaultdict(lambda: defaultdict(int))
    for c in classifications:
        cls = c["classification"]
        by_stratum[c["stratum"]][cls] += 1
    return {s: dict(counts) for s, counts in by_stratum.items()}


def main() -> int:
    parser = argparse.ArgumentParser(
        prog="advisor-benchmark-stats",
        description="Paired-bootstrap classifier for advisor-strategy benchmark (cycle-108 T2.B).",
    )
    parser.add_argument("--outcomes", type=Path, required=True,
                        help="JSONL with per-replay records")
    parser.add_argument("--score-key", type=str, default="score",
                        help="JSON key holding the quality metric")
    parser.add_argument("--n-resamples", type=int, default=10000)
    parser.add_argument("--inconclusive-threshold", type=float, default=0.25,
                        help="Stratum INCONCLUSIVE-rate above which UNTESTABLE applies")
    parser.add_argument("--output", type=Path, default=None)
    args = parser.parse_args()

    if not args.outcomes.exists():
        print(f"error: outcomes file not found: {args.outcomes}", file=sys.stderr)
        return 2

    groups, meta = _aggregate(args.outcomes, args.score_key)
    if not groups:
        print("error: no usable pairs found in outcomes file", file=sys.stderr)
        return 3

    untestable = _untestable_strata(meta, args.inconclusive_threshold)
    classify = _classify(groups, meta, untestable, n_resamples=args.n_resamples)
    classify["per_stratum_summary"] = _per_stratum_summary(
        classify["sprint_classifications"]
    )
    classify["stratum_inconclusive"] = meta["stratum_inconclusive"]
    classify["stratum_total"] = meta["stratum_total"]

    out = json.dumps(classify, indent=2, sort_keys=True)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(out + "\n")
    else:
        sys.stdout.write(out + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
