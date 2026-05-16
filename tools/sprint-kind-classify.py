#!/usr/bin/env python3
"""tools/sprint-kind-classify.py — cycle-108 sprint-2 T2.I

PRD Appendix A IMP-006 + SDD §20.10 ATK-A9 closure (multi-feature scored).

Classifies a sprint (by pre/post SHA range) into one of the strata:
  cryptographic, parser, audit-envelope, testing, infrastructure, glue, frontend

Algorithm:
  1. For the given <pre_sha>..<post_sha>, read git diff stats:
     - files touched
     - LOC delta
     - schema/migration changes (heuristic)
  2. Each rule emits (stratum, confidence). Confidence ∈ [0.0, 1.0].
  3. Final stratum = HIGHEST confidence. Ties broken by priority:
     cryptographic > parser > audit-envelope > testing > infrastructure > glue > frontend
  4. Operator override: --stratum-override <name> --rationale <text>
     requires audit-log entry (jsonl append to a configurable path).

Usage:
  sprint-kind-classify.py --pre-sha <sha> --post-sha <sha> [--repo-root <dir>]
  sprint-kind-classify.py --pr-number <N>             # via gh pr view
  sprint-kind-classify.py --bulk-from-prs-json <file> # batch mode
  sprint-kind-classify.py --stratum-override <name> --rationale <text>

Output (single-classify mode): JSON to stdout.
Output (bulk mode): JSON array.

Exit codes:
  0 — success
  2 — invalid args (missing rationale on override etc.)
  3 — git diff failed
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple


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


# Heuristic rules — each (stratum, [path_substrings + extensions],
# base_confidence_at_first_hit, per_additional_hit_increment).
# Confidence saturates at 0.99.
#
# Design: high-signal strata (crypto/parser/audit-envelope) get a HIGH base
# confidence on first hit, then small per-hit increments. Low-signal strata
# (glue) get LOW base + small increments so even many glue hits cannot
# outvote a single high-signal hit. This matches SDD §20.10 ATK-A9 intent
# ("multi-feature scored not first-match; ties by priority").
_RULES: List[Tuple[str, List[str], float, float]] = [
    ("cryptographic", [
        "sodium", "ed25519", "rsa", "crypto/", "signature", "signing",
        "audit-keys-bootstrap", "key-rotation", "trust-store", "JWT", "jwt",
    ], 0.85, 0.03),
    ("parser", [
        "parser.", "lexer.", "tokeniz", "grammar.", "jcs.", "canonical",
        ".g4", ".bnf", "ast.", "syntax.", "schema-bump",
    ], 0.80, 0.03),
    ("audit-envelope", [
        "audit-envelope", "audit_envelope", "audit-emit", "audit-recover",
        "modelinv-", "model-invoke", ".jsonl",
        "trajectory-schemas", "envelope.schema",
    ], 0.75, 0.03),
    ("testing", [
        "tests/", "/test/", "_test.", ".test.", ".spec.", ".bats", "test_",
        "fixtures/", "fixture_", "mock", "stub",
    ], 0.65, 0.03),
    ("infrastructure", [
        ".github/workflows/", "Dockerfile", "docker-compose",
        "terraform/", "ansible/", ".loa.config", "scheduled_tasks",
        "cron.d/", "systemd",
    ], 0.60, 0.03),
    ("frontend", [
        ".tsx", ".jsx", "components/", "frontend/", ".vue", ".svelte",
        "package.json", "tailwind.config", "next.config",
    ], 0.55, 0.03),
    ("glue", [
        ".sh", "scripts/", "tools/", ".md", ".yaml", ".yml", "CLAUDE.md",
    ], 0.30, 0.02),
]


@dataclass
class ClassificationResult:
    sha: str
    merged_at: Optional[str]
    pr_number: Optional[int]
    stratum: str
    confidence: float
    rule_hits: Dict[str, int]
    files_count: int
    loc_delta: int


def _run_git(*args: str, repo_root: Path) -> Tuple[int, str, str]:
    proc = subprocess.run(
        ["git", "-C", str(repo_root), *args],
        capture_output=True, text=True, check=False, timeout=60,
    )
    return proc.returncode, proc.stdout, proc.stderr


def _files_in_range(pre_sha: str, post_sha: str, repo_root: Path) -> Tuple[List[str], int]:
    """Return (file paths, total LOC delta) for the SHA range."""
    rc, out, err = _run_git("diff", "--name-only", f"{pre_sha}..{post_sha}", repo_root=repo_root)
    if rc != 0:
        raise RuntimeError(f"git diff failed: {err.strip()}")
    files = [line for line in out.splitlines() if line.strip()]

    # Numeric stats for LOC delta (sum of added + deleted).
    rc, stat, _ = _run_git("diff", "--numstat", f"{pre_sha}..{post_sha}", repo_root=repo_root)
    loc_delta = 0
    if rc == 0:
        for line in stat.splitlines():
            parts = line.split("\t")
            if len(parts) >= 2:
                # binary files show "-" for added/deleted
                try:
                    loc_delta += int(parts[0]) + int(parts[1])
                except ValueError:
                    pass
    return files, loc_delta


def _score_files(files: List[str]) -> Dict[str, Dict[str, Any]]:
    """For each stratum, count matching files + compute aggregated confidence.

    Confidence model: base for first hit, then small per-additional-hit
    increment. This makes a SINGLE crypto hit beat MANY glue hits, matching
    the SDD §20.10 ATK-A9 intent (signal-strength > raw-count).
    """
    results: Dict[str, Dict[str, Any]] = {}
    for stratum, substrings, base, increment in _RULES:
        hits = 0
        for f in files:
            if any(s in f for s in substrings):
                hits += 1
        if hits == 0:
            confidence = 0.0
        else:
            confidence = min(0.99, base + (increment * (hits - 1)))
        results[stratum] = {"hits": hits, "confidence": confidence}
    return results


def _pick_stratum(scores: Dict[str, Dict[str, Any]]) -> Tuple[str, float, Dict[str, int]]:
    """Pick the highest-confidence stratum; ties broken by priority."""
    candidates: List[Tuple[float, int, str]] = []
    for stratum, info in scores.items():
        if info["confidence"] <= 0:
            continue
        priority = _STRATUM_PRIORITY.index(stratum) if stratum in _STRATUM_PRIORITY else 999
        # Sort key: (-confidence, priority, stratum) → highest confidence first;
        # for ties, lower priority index (higher rank).
        candidates.append((-info["confidence"], priority, stratum))
    if not candidates:
        # No rule matched at all → default to glue (the catch-all).
        rule_hits = {s: scores[s]["hits"] for s in scores}
        return "glue", 0.1, rule_hits
    candidates.sort()
    _, _, picked = candidates[0]
    rule_hits = {s: scores[s]["hits"] for s in scores}
    return picked, scores[picked]["confidence"], rule_hits


def classify_sprint(
    pre_sha: str,
    post_sha: str,
    repo_root: Path,
    pr_number: Optional[int] = None,
    merged_at: Optional[str] = None,
) -> ClassificationResult:
    files, loc = _files_in_range(pre_sha, post_sha, repo_root)
    scores = _score_files(files)
    stratum, confidence, hits = _pick_stratum(scores)
    return ClassificationResult(
        sha=post_sha,
        merged_at=merged_at,
        pr_number=pr_number,
        stratum=stratum,
        confidence=confidence,
        rule_hits=hits,
        files_count=len(files),
        loc_delta=loc,
    )


def _log_override(stratum: str, rationale: str, audit_log_path: Path) -> None:
    """Append operator override to audit log; fail-soft."""
    audit_log_path.parent.mkdir(parents=True, exist_ok=True)
    record = {
        "event": "stratum.override",
        "stratum": stratum,
        "rationale": rationale,
    }
    try:
        with audit_log_path.open("a") as f:
            f.write(json.dumps(record) + "\n")
    except OSError:
        pass


def main() -> int:
    parser = argparse.ArgumentParser(
        prog="sprint-kind-classify",
        description="Multi-feature scored sprint-kind classifier (cycle-108 T2.I).",
    )
    parser.add_argument("--pre-sha", type=str, default=None)
    parser.add_argument("--post-sha", type=str, default=None)
    parser.add_argument("--repo-root", type=Path, default=Path.cwd())
    parser.add_argument("--pr-number", type=int, default=None,
                        help="PR number for output annotation (optional)")
    parser.add_argument("--merged-at", type=str, default=None,
                        help="ISO-8601 merge timestamp for output annotation")
    parser.add_argument("--bulk-from-prs-json", type=Path, default=None,
                        help="Batch mode: JSON array of {pre_sha, post_sha, pr_number, merged_at}")
    parser.add_argument("--stratum-override", type=str, default=None,
                        help="Operator-specified stratum; requires --rationale")
    parser.add_argument("--rationale", type=str, default=None,
                        help="Required for --stratum-override")
    parser.add_argument("--audit-log", type=Path,
                        default=Path(".run/cycles/cycle-108-advisor-strategy/audit/classification.jsonl"))
    parser.add_argument("--output", type=Path, default=None)
    args = parser.parse_args()

    if args.stratum_override and not args.rationale:
        print("error: --stratum-override requires --rationale", file=sys.stderr)
        return 2

    if args.stratum_override:
        if args.stratum_override not in _STRATUM_PRIORITY:
            print(f"error: unknown stratum {args.stratum_override!r}; "
                  f"valid: {_STRATUM_PRIORITY}", file=sys.stderr)
            return 2

    if args.bulk_from_prs_json:
        # Batch mode.
        raw = json.loads(args.bulk_from_prs_json.read_text())
        results: List[Dict[str, Any]] = []
        for entry in raw:
            try:
                r = classify_sprint(
                    pre_sha=entry["pre_sha"],
                    post_sha=entry["post_sha"],
                    repo_root=args.repo_root,
                    pr_number=entry.get("pr_number"),
                    merged_at=entry.get("merged_at"),
                )
                results.append(asdict(r))
            except Exception as e:  # noqa: BLE001
                results.append({
                    "sha": entry.get("post_sha"),
                    "error": str(e),
                })
        out = json.dumps(results, indent=2)
        if args.output:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(out + "\n")
        else:
            sys.stdout.write(out + "\n")
        return 0

    # Single-classify mode.
    if not args.pre_sha or not args.post_sha:
        print("error: --pre-sha and --post-sha required (or use --bulk-from-prs-json)",
              file=sys.stderr)
        return 2

    try:
        result = classify_sprint(
            pre_sha=args.pre_sha,
            post_sha=args.post_sha,
            repo_root=args.repo_root,
            pr_number=args.pr_number,
            merged_at=args.merged_at,
        )
    except RuntimeError as e:
        print(f"error: {e}", file=sys.stderr)
        return 3

    if args.stratum_override:
        original_stratum = result.stratum
        original_conf = result.confidence
        result.stratum = args.stratum_override
        result.confidence = 1.0  # Operator-pinned
        _log_override(args.stratum_override, args.rationale, args.audit_log)
        # Annotate in output for traceability.
        result_dict = asdict(result)
        result_dict["override_origin"] = {
            "original_stratum": original_stratum,
            "original_confidence": original_conf,
            "rationale": args.rationale,
        }
    else:
        result_dict = asdict(result)

    out = json.dumps(result_dict, indent=2, sort_keys=True)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(out + "\n")
    else:
        sys.stdout.write(out + "\n")

    return 0


if __name__ == "__main__":
    sys.exit(main())
