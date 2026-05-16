#!/usr/bin/env python3
"""Deterministic sprint-selection algorithm for cycle-108 advisor-strategy
benchmark replays (cycle-108 sprint-2 T2.J — SDD §20.2 ATK-A19 closure).

Inputs:
  - Stratifier output for last N days of merged PRs (JSON; per-PR stratum
    assignment from `tools/sprint-kind-classify.py`).
  - `--min-replays-per-stratum N`  (default 3 per SDD §20.2).
  - `--days N`                     (default 90).
  - `--manual-selection sha1,sha2` (operator override; requires --rationale).
  - `--rationale "text"`           (mandatory companion to --manual-selection).

Algorithm (deterministic — same input → same selection):
  1. Group candidate sprints by stratum.
  2. Find the LARGEST N such that ALL strata have ≥N candidates (cap = N=min-replays).
     If any stratum has <min-replays-per-stratum candidates, that stratum is
     reported as UNDERREPRESENTED; cycle-108 SDD §20.10 ATK-A9 ties stratum
     priority to break selection ties; underrepresented strata surface in the
     report but do not block selection of the remaining strata.
  3. From each stratum, pick the MOST RECENT N sprints by merge timestamp.
  4. Emit a JSON manifest at `--output` (or stdout) with:
       - selection_method: "deterministic" | "manual"
       - per-stratum picks (sha, merged_at, stratum, confidence)
       - underrepresented strata
       - input_provenance (stratifier sha + days window)

Override semantics (--manual-selection):
  - The operator pins a specific comma-separated list of PR SHAs.
  - --rationale is REQUIRED (audit-log entry).
  - The override is recorded with `selection_method: "manual"` and ALSO
    appended to .run/cycles/cycle-108-advisor-strategy/audit/selection.jsonl
    via audit_emit_signed (when available).

Exit codes:
  0 — success
  2 — invalid input / missing rationale
  3 — underrepresented stratum AND --require-full-coverage was passed
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from collections import defaultdict
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional


# Stratum priority for tie-breaking (SDD §20.10 ATK-A9).
_STRATUM_PRIORITY = [
    "cryptographic",
    "parser",
    "audit-envelope",
    "testing",
    "infrastructure",
    "glue",
    "frontend",
]


@dataclass(frozen=True)
class SprintCandidate:
    """A single candidate sprint for benchmark replay."""
    sha: str
    merged_at: str        # ISO-8601
    stratum: str
    confidence: float
    pr_number: Optional[int] = None


def _read_stratifier_output(path: Path) -> List[SprintCandidate]:
    """Read JSON output of tools/sprint-kind-classify.py.

    Expected shape:
        [{"sha": "...", "merged_at": "...", "stratum": "...",
          "confidence": 0.95, "pr_number": 123}, ...]
    """
    if not path.exists():
        raise FileNotFoundError(f"Stratifier output not found: {path}")
    raw = json.loads(path.read_text())
    candidates: List[SprintCandidate] = []
    for entry in raw:
        candidates.append(SprintCandidate(
            sha=entry["sha"],
            merged_at=entry["merged_at"],
            stratum=entry["stratum"],
            confidence=float(entry.get("confidence", 0.0)),
            pr_number=entry.get("pr_number"),
        ))
    return candidates


def _select_deterministic(
    candidates: List[SprintCandidate],
    min_replays: int,
) -> Dict[str, Any]:
    """Deterministic per-stratum picker. See module docstring algorithm."""
    by_stratum: Dict[str, List[SprintCandidate]] = defaultdict(list)
    for c in candidates:
        by_stratum[c.stratum].append(c)

    # Sort each stratum's candidates by merged_at DESC (most recent first).
    for stratum in by_stratum:
        by_stratum[stratum].sort(key=lambda c: c.merged_at, reverse=True)

    underrepresented: List[Dict[str, Any]] = []
    selected: Dict[str, List[Dict[str, Any]]] = {}

    # Iterate strata in priority order so the manifest is deterministic.
    all_strata = sorted(
        by_stratum.keys(),
        key=lambda s: (_STRATUM_PRIORITY.index(s) if s in _STRATUM_PRIORITY else 999, s),
    )
    for stratum in all_strata:
        picks = by_stratum[stratum][:min_replays]
        selected[stratum] = [asdict(p) for p in picks]
        if len(by_stratum[stratum]) < min_replays:
            underrepresented.append({
                "stratum": stratum,
                "available": len(by_stratum[stratum]),
                "required": min_replays,
            })

    return {
        "selection_method": "deterministic",
        "min_replays_per_stratum": min_replays,
        "selected": selected,
        "underrepresented": underrepresented,
        "total_selected": sum(len(v) for v in selected.values()),
    }


def _select_manual(
    candidates: List[SprintCandidate],
    sha_list: List[str],
    rationale: str,
) -> Dict[str, Any]:
    """Operator manual-selection mode. Looks up each sha in candidates;
    unknown shas surface as warnings but do not abort.
    """
    by_sha = {c.sha: c for c in candidates}
    picks: List[Dict[str, Any]] = []
    unknown: List[str] = []
    for sha in sha_list:
        if sha in by_sha:
            picks.append(asdict(by_sha[sha]))
        else:
            unknown.append(sha)
    selected: Dict[str, List[Dict[str, Any]]] = defaultdict(list)
    for p in picks:
        selected[p["stratum"]].append(p)
    return {
        "selection_method": "manual",
        "operator_rationale": rationale,
        "selected": dict(selected),
        "unknown_shas": unknown,
        "total_selected": len(picks),
    }


def _try_audit_emit_signed(manifest: Dict[str, Any], rationale: str) -> None:
    """Attempt to append the manual-selection record to the cycle-108 audit log
    via audit_emit_signed. Fail-soft — missing audit infrastructure or signing
    key does not abort the selection.
    """
    audit_log = Path(".run/cycles/cycle-108-advisor-strategy/audit/selection.jsonl")
    audit_log.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "event": "benchmark.manual_selection",
        "rationale": rationale,
        "manifest_summary": {
            "total_selected": manifest["total_selected"],
            "strata": list(manifest["selected"].keys()),
        },
    }
    # Best-effort call to audit_emit_signed; if not available, fall back to
    # plain append. The benchmark pipeline's hash-chain verification is in T2.G.
    #
    # BB iter-2 F001 closure (same class as iter-1 F006): pass payload via
    # env vars rather than f-string interpolation into `bash -c`. Operator-
    # supplied `rationale` string previously flowed unchecked into argv —
    # a literal single-quote in rationale would have broken parsing or
    # opened a shell-injection surface.
    payload_json = json.dumps(payload)
    script = (
        'source .claude/scripts/audit-envelope.sh && '
        'audit_emit_signed "$LOA_AUDIT_PRIMITIVE" "$LOA_AUDIT_EVENT_TYPE" '
        '"$LOA_AUDIT_PAYLOAD" "$LOA_AUDIT_LOG_PATH"'
    )
    env = {
        **os.environ,
        "LOA_AUDIT_PRIMITIVE": "CYCLE_108_SELECTION",
        "LOA_AUDIT_EVENT_TYPE": "benchmark.manual_selection",
        "LOA_AUDIT_PAYLOAD": payload_json,
        "LOA_AUDIT_LOG_PATH": str(audit_log),
    }
    try:
        result = subprocess.run(
            ["bash", "-c", script],
            capture_output=True, text=True, check=False, timeout=10,
            env=env,
        )
        if result.returncode != 0:
            # Fall back to plain unsigned append.
            with audit_log.open("a") as f:
                f.write(json.dumps({"signed": False, **payload}) + "\n")
    except (subprocess.SubprocessError, OSError):
        try:
            with audit_log.open("a") as f:
                f.write(json.dumps({"signed": False, **payload}) + "\n")
        except OSError:
            pass


def main() -> int:
    parser = argparse.ArgumentParser(
        prog="select-benchmark-sprints",
        description="Deterministic sprint-selection for cycle-108 advisor-strategy benchmark.",
    )
    parser.add_argument(
        "--stratifier-output", type=Path, required=True,
        help="JSON file produced by tools/sprint-kind-classify.py",
    )
    parser.add_argument(
        "--min-replays-per-stratum", type=int, default=3,
        help="Minimum replays per stratum (default: 3 per SDD §20.2)",
    )
    parser.add_argument(
        "--days", type=int, default=90,
        help="Window size (informational; stratifier filters before us)",
    )
    parser.add_argument(
        "--output", type=Path, default=None,
        help="Output manifest path (default: stdout)",
    )
    parser.add_argument(
        "--manual-selection", type=str, default=None,
        help="Comma-separated SHA list for operator override; requires --rationale",
    )
    parser.add_argument(
        "--rationale", type=str, default=None,
        help="Required when --manual-selection is set",
    )
    parser.add_argument(
        "--require-full-coverage", action="store_true",
        help="Exit 3 if any stratum is underrepresented",
    )
    args = parser.parse_args()

    if args.manual_selection and not args.rationale:
        print("error: --manual-selection requires --rationale", file=sys.stderr)
        return 2
    if args.rationale and not args.manual_selection:
        print("error: --rationale only valid with --manual-selection", file=sys.stderr)
        return 2

    candidates = _read_stratifier_output(args.stratifier_output)
    if args.manual_selection:
        sha_list = [s.strip() for s in args.manual_selection.split(",") if s.strip()]
        manifest = _select_manual(candidates, sha_list, args.rationale)
        _try_audit_emit_signed(manifest, args.rationale)
    else:
        manifest = _select_deterministic(candidates, args.min_replays_per_stratum)

    manifest["input_provenance"] = {
        "stratifier_output_path": str(args.stratifier_output),
        "stratifier_sha": _hash_file(args.stratifier_output),
        "days_window": args.days,
    }

    out = json.dumps(manifest, indent=2, sort_keys=True)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(out + "\n")
    else:
        sys.stdout.write(out + "\n")

    if args.require_full_coverage and manifest.get("underrepresented"):
        return 3
    return 0


def _hash_file(path: Path) -> str:
    """Return SHA256 of a file for input-provenance pinning."""
    import hashlib
    h = hashlib.sha256()
    if path.exists():
        h.update(path.read_bytes())
    return h.hexdigest()


if __name__ == "__main__":
    sys.exit(main())
