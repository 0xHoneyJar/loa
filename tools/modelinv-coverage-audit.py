#!/usr/bin/env python3
"""tools/modelinv-coverage-audit.py — cycle-108 sprint-2 T2.M

SR-7 + [ASSUMPTION-A4] resolution. Audits how comprehensively
.run/model-invoke.jsonl covers actual cheval invocations across the
repository, surfacing gaps where skill traffic isn't producing envelopes.

Three coverage views:

  1. **envelope-side**: fraction of envelopes that carry the cycle-108 v1.2
     marker (payload.writer_version == "1.2"). Proxy for "post-T1.F
     coverage of the substrate". Reported per-cycle (derived from
     invocation_chain entries if present, else "uncategorized").

  2. **ground-truth comparison** (optional, --skill-log <path>): compares
     envelope counts against a caller-supplied JSONL log of actual skill
     invocations. Per-skill coverage = envelopes_for_skill / invocations_for_skill.

  3. **per-skill rollup**: from envelope.payload.invocation_chain[0] (top
     of the chain) as the skill attribution.

Output: JSON to stdout (or --output PATH) AND a Markdown report to
the configured artifact path. The Markdown report is committed under
grimoires/loa/cycles/cycle-108-advisor-strategy/coverage-audit.md.

Exit codes:
  0 — coverage ≥ threshold (or no threshold check)
  3 — coverage < threshold AND --strict-threshold passed
"""
from __future__ import annotations

import argparse
import json
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any, Dict, List, Optional


def _iter_envelopes(log_path: Path):
    """Yield each parsed envelope from a JSONL log; skips seal markers + blanks."""
    if not log_path.exists():
        return
    with log_path.open() as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("["):
                continue
            try:
                yield json.loads(line)
            except json.JSONDecodeError:
                continue


def _compute_envelope_coverage(log_path: Path) -> Dict[str, Any]:
    """Compute v1.2 marker coverage across the audit log."""
    total = 0
    v12_count = 0
    pricing_count = 0
    replay_count = 0
    per_cycle: Dict[str, Dict[str, int]] = defaultdict(
        lambda: {"total": 0, "v12": 0, "pricing": 0, "replay": 0}
    )
    per_skill: Dict[str, Dict[str, int]] = defaultdict(
        lambda: {"total": 0, "v12": 0}
    )

    for env in _iter_envelopes(log_path):
        total += 1
        payload = env.get("payload") or {}
        # Skill attribution: top of invocation_chain, else calling_primitive, else "unknown".
        chain = payload.get("invocation_chain") or []
        skill = chain[0] if chain else (payload.get("calling_primitive") or "unknown")
        # Cycle: parse from invocation_chain if present (e.g. ["sprint-2", "implement"])
        # else fallback to "uncategorized".
        cycle = "uncategorized"
        for piece in chain:
            if piece.startswith("sprint-") or piece.startswith("cycle-"):
                cycle = piece
                break

        is_v12 = payload.get("writer_version") == "1.2"
        has_pricing = payload.get("pricing_snapshot") is not None
        is_replay = payload.get("replay_marker") is True

        if is_v12:
            v12_count += 1
        if has_pricing:
            pricing_count += 1
        if is_replay:
            replay_count += 1

        per_cycle[cycle]["total"] += 1
        if is_v12:
            per_cycle[cycle]["v12"] += 1
        if has_pricing:
            per_cycle[cycle]["pricing"] += 1
        if is_replay:
            per_cycle[cycle]["replay"] += 1

        per_skill[skill]["total"] += 1
        if is_v12:
            per_skill[skill]["v12"] += 1

    v12_pct = (v12_count / total) if total > 0 else 0.0
    pricing_pct = (pricing_count / total) if total > 0 else 0.0

    return {
        "total_envelopes": total,
        "v12_marked": v12_count,
        "v12_coverage_pct": round(v12_pct, 4),
        "pricing_captured": pricing_count,
        "pricing_coverage_pct": round(pricing_pct, 4),
        "replay_marker_count": replay_count,
        "per_cycle": {k: dict(v) for k, v in per_cycle.items()},
        "per_skill": {k: dict(v) for k, v in per_skill.items()},
    }


def _compute_skill_log_comparison(
    envelope_coverage: Dict[str, Any],
    skill_log_path: Path,
) -> Dict[str, Any]:
    """Compare envelope counts per-skill against an external skill-invocation log.

    The skill log is expected to be JSONL with at least {skill: str} per line.
    """
    skill_invocations: Dict[str, int] = defaultdict(int)
    if not skill_log_path.exists():
        return {"error": f"skill-log not found: {skill_log_path}"}
    with skill_log_path.open() as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
                skill = entry.get("skill") or entry.get("name")
                if skill:
                    skill_invocations[skill] += 1
            except json.JSONDecodeError:
                continue

    per_skill_envelopes = envelope_coverage["per_skill"]
    per_skill_coverage: Dict[str, Any] = {}
    total_invocations = sum(skill_invocations.values())
    total_envelopes_matched = 0
    for skill, inv_count in skill_invocations.items():
        env_count = per_skill_envelopes.get(skill, {"total": 0})["total"]
        total_envelopes_matched += min(env_count, inv_count)
        pct = (env_count / inv_count) if inv_count > 0 else 0.0
        per_skill_coverage[skill] = {
            "invocations": inv_count,
            "envelopes": env_count,
            "coverage_pct": round(pct, 4),
        }
    overall_pct = (total_envelopes_matched / total_invocations) if total_invocations > 0 else 0.0
    return {
        "total_invocations": total_invocations,
        "total_envelopes_matched": total_envelopes_matched,
        "overall_coverage_pct": round(overall_pct, 4),
        "per_skill_coverage": per_skill_coverage,
    }


def _emit_markdown(
    envelope_coverage: Dict[str, Any],
    skill_log_comparison: Optional[Dict[str, Any]],
    markdown_path: Path,
    threshold: Optional[float],
) -> None:
    """Write a human-readable Markdown report."""
    markdown_path.parent.mkdir(parents=True, exist_ok=True)
    lines: List[str] = []
    lines.append("# MODELINV coverage audit")
    lines.append("")
    lines.append(f"**Total envelopes**: {envelope_coverage['total_envelopes']}")
    lines.append(f"**v1.2-marked envelopes**: {envelope_coverage['v12_marked']} "
                 f"({envelope_coverage['v12_coverage_pct']*100:.1f}%)")
    lines.append(f"**Pricing-captured envelopes**: {envelope_coverage['pricing_captured']} "
                 f"({envelope_coverage['pricing_coverage_pct']*100:.1f}%)")
    lines.append(f"**Replay-marked envelopes**: {envelope_coverage['replay_marker_count']}")
    if threshold is not None:
        gate = "PASS" if envelope_coverage["v12_coverage_pct"] >= threshold else "FAIL"
        lines.append(f"**Threshold gate** (≥ {threshold*100:.0f}%): **{gate}**")
    lines.append("")
    lines.append("## Per-cycle breakdown")
    lines.append("")
    lines.append("| Cycle | Total | v1.2 | Pricing | Replays |")
    lines.append("| --- | --- | --- | --- | --- |")
    for cycle, counts in sorted(envelope_coverage["per_cycle"].items()):
        lines.append(f"| {cycle} | {counts['total']} | {counts['v12']} | "
                     f"{counts['pricing']} | {counts['replay']} |")
    lines.append("")
    lines.append("## Per-skill breakdown (envelope-side)")
    lines.append("")
    lines.append("| Skill | Total | v1.2 |")
    lines.append("| --- | --- | --- |")
    for skill, counts in sorted(envelope_coverage["per_skill"].items()):
        lines.append(f"| {skill} | {counts['total']} | {counts['v12']} |")
    if skill_log_comparison:
        lines.append("")
        lines.append("## Ground-truth comparison (envelope vs skill-log)")
        lines.append("")
        if "error" in skill_log_comparison:
            lines.append(f"_{skill_log_comparison['error']}_")
        else:
            lines.append(f"**Total invocations**: {skill_log_comparison['total_invocations']}")
            lines.append(f"**Total matched**: {skill_log_comparison['total_envelopes_matched']}")
            lines.append(f"**Overall**: {skill_log_comparison['overall_coverage_pct']*100:.1f}%")
            lines.append("")
            lines.append("| Skill | Invocations | Envelopes | Coverage |")
            lines.append("| --- | --- | --- | --- |")
            for skill, info in sorted(skill_log_comparison["per_skill_coverage"].items()):
                lines.append(f"| {skill} | {info['invocations']} | {info['envelopes']} | "
                             f"{info['coverage_pct']*100:.1f}% |")
    markdown_path.write_text("\n".join(lines) + "\n")


def main() -> int:
    parser = argparse.ArgumentParser(
        prog="modelinv-coverage-audit",
        description="MODELINV envelope coverage audit (cycle-108 T2.M).",
    )
    parser.add_argument("--input", type=Path,
                        default=Path(".run/model-invoke.jsonl"))
    parser.add_argument("--skill-log", type=Path, default=None,
                        help="Optional JSONL with skill invocations for ground-truth comparison")
    parser.add_argument("--output", type=Path, default=None,
                        help="JSON output path (default stdout)")
    parser.add_argument("--markdown", type=Path,
                        default=Path("grimoires/loa/cycles/cycle-108-advisor-strategy/coverage-audit.md"))
    parser.add_argument("--threshold", type=float, default=None,
                        help="Required v1.2 coverage fraction (e.g. 0.90 for SR-7 90%)")
    parser.add_argument("--strict-threshold", action="store_true",
                        help="Exit 3 if coverage < --threshold")
    args = parser.parse_args()

    envelope_coverage = _compute_envelope_coverage(args.input)
    skill_log_comparison = None
    if args.skill_log:
        skill_log_comparison = _compute_skill_log_comparison(envelope_coverage, args.skill_log)

    full: Dict[str, Any] = {
        "envelope_coverage": envelope_coverage,
    }
    if skill_log_comparison is not None:
        full["skill_log_comparison"] = skill_log_comparison
    if args.threshold is not None:
        full["threshold"] = args.threshold
        full["threshold_pass"] = envelope_coverage["v12_coverage_pct"] >= args.threshold

    out = json.dumps(full, indent=2, sort_keys=True)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(out + "\n")
    else:
        sys.stdout.write(out + "\n")

    _emit_markdown(envelope_coverage, skill_log_comparison, args.markdown, args.threshold)

    if args.strict_threshold and args.threshold is not None:
        if envelope_coverage["v12_coverage_pct"] < args.threshold:
            print(f"[COVERAGE-AUDIT-FAIL] v1.2 coverage "
                  f"{envelope_coverage['v12_coverage_pct']*100:.1f}% < "
                  f"required {args.threshold*100:.0f}%", file=sys.stderr)
            return 3
    return 0


if __name__ == "__main__":
    sys.exit(main())
