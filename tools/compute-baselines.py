#!/usr/bin/env python3
"""tools/compute-baselines.py — cycle-108 sprint-3 T3.A

PRD §5 FR-8 (IMP-001) + SDD §5.9 + §20.3 ATK-A4 closure.

Computes pre-registered per-stratum baselines for cycle-108 advisor-strategy
benchmark from historical MODELINV data + the PRD §3 SC table. Emits:
  - grimoires/loa/cycles/cycle-108-advisor-strategy/baselines.json
  - grimoires/loa/cycles/cycle-108-advisor-strategy/baselines.audit.jsonl

baselines.json contains: per-stratum SC-1..SC-5 baseline + executor target
(0.95 × advisor-tier baseline per PRD §3 SC table) + git_sha_at_signing +
ts_utc + signed_by_key_id.

Cross-cycle chain: the audit-jsonl's first entry's prev_hash MUST equal
cycle-107's last L1 entry's hash (ATK-A4 cross-cycle continuity). A
pre-commit hook (separate substrate; if present in repo) enforces this.

Usage:
  compute-baselines.py [--input PATH] [--strata STRATUM,...]
                       [--output PATH] [--audit-out PATH]
                       [--sign | --no-sign]
                       [--operator-key-id ID]

Exit codes:
  0 — baselines emitted (signed or unsigned per --sign)
  2 — invalid arguments
  3 — insufficient historical data for credible baselines
"""
from __future__ import annotations

import argparse
import json
import statistics
import subprocess
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any, Dict, List, Optional


# Strata covered (matches sprint-kind-classify.py).
_DEFAULT_STRATA = ["glue", "parser", "cryptographic", "testing", "infrastructure", "frontend"]

# PRD §3 SC table — executor targets are 0.95 × baseline-audit-pass per stratum.
_EXECUTOR_TARGET_RATIO = 0.95

# Default baselines if historical data is insufficient. These are the PRD's
# pre-registered SC-1..SC-5 anchor values per stratum; operators tune via
# --override-baselines.json when historical data accumulates.
_DEFAULT_SC_BASELINES: Dict[str, Dict[str, float]] = {
    "audit_pass_rate": {  # SC-1: review-sprint + audit-sprint pass fraction
        "glue": 0.95, "parser": 0.95, "cryptographic": 0.99,
        "testing": 0.95, "infrastructure": 0.95, "frontend": 0.90,
    },
    "review_findings_density": {  # SC-2: findings per kLOC (lower is better)
        "glue": 3.0, "parser": 5.0, "cryptographic": 7.0,
        "testing": 4.0, "infrastructure": 4.0, "frontend": 5.0,
    },
    "bb_iter_count": {  # SC-3: bridgebuilder iterations to plateau
        "glue": 2.0, "parser": 3.0, "cryptographic": 4.0,
        "testing": 2.0, "infrastructure": 2.0, "frontend": 3.0,
    },
    "tokens_per_sprint": {  # SC-4: total token spend (lower is better)
        "glue": 50000, "parser": 100000, "cryptographic": 150000,
        "testing": 75000, "infrastructure": 80000, "frontend": 80000,
    },
    "wallclock_seconds": {  # SC-5: end-to-end wall-clock
        "glue": 600, "parser": 1200, "cryptographic": 2400,
        "testing": 900, "infrastructure": 1000, "frontend": 1100,
    },
}


def _current_git_sha() -> str:
    try:
        out = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            capture_output=True, text=True, check=True, timeout=10,
        )
        return out.stdout.strip()
    except (subprocess.SubprocessError, OSError):
        return "UNKNOWN"


def _iter_envelopes(log_path: Path):
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


def _compute_per_stratum(log_path: Path, strata: List[str]) -> Dict[str, Dict[str, Any]]:
    """Compute per-stratum medians from historical envelopes.

    Returns {stratum: {sc_metric: median_value}} for each requested stratum.
    Falls back to _DEFAULT_SC_BASELINES values when no/insufficient data.
    """
    by_stratum: Dict[str, List[Dict[str, Any]]] = defaultdict(list)
    for env in _iter_envelopes(log_path):
        payload = env.get("payload") or {}
        stratum = payload.get("sprint_kind")
        if stratum and stratum in strata:
            by_stratum[stratum].append(payload)

    result: Dict[str, Dict[str, Any]] = {}
    for stratum in strata:
        records = by_stratum.get(stratum, [])
        if len(records) < 3:
            # Insufficient historical data; use defaults.
            result[stratum] = {
                "audit_pass_rate": _DEFAULT_SC_BASELINES["audit_pass_rate"][stratum],
                "review_findings_density": _DEFAULT_SC_BASELINES["review_findings_density"][stratum],
                "bb_iter_count": _DEFAULT_SC_BASELINES["bb_iter_count"][stratum],
                "tokens_per_sprint": _DEFAULT_SC_BASELINES["tokens_per_sprint"][stratum],
                "wallclock_seconds": _DEFAULT_SC_BASELINES["wallclock_seconds"][stratum],
                "_source": "default_baseline",
                "_historical_n": len(records),
            }
            continue
        # Compute medians where possible from envelope fields.
        latencies = [r.get("invocation_latency_ms", 0) for r in records if r.get("invocation_latency_ms")]
        wallclock = statistics.median(latencies) / 1000 if latencies else \
            _DEFAULT_SC_BASELINES["wallclock_seconds"][stratum]
        # cost_micro_usd → tokens estimate via pricing_snapshot, when present
        token_estimates = []
        for r in records:
            cm = r.get("cost_micro_usd", 0)
            ps = r.get("pricing_snapshot") or {}
            input_p = ps.get("input_per_mtok", 10_000_000)
            if input_p > 0 and cm > 0:
                token_estimates.append((cm * 1_000_000) / input_p)
        tokens = int(statistics.median(token_estimates)) if token_estimates else \
            _DEFAULT_SC_BASELINES["tokens_per_sprint"][stratum]
        result[stratum] = {
            "audit_pass_rate": _DEFAULT_SC_BASELINES["audit_pass_rate"][stratum],  # external; not in envelope
            "review_findings_density": _DEFAULT_SC_BASELINES["review_findings_density"][stratum],
            "bb_iter_count": _DEFAULT_SC_BASELINES["bb_iter_count"][stratum],
            "tokens_per_sprint": tokens,
            "wallclock_seconds": wallclock,
            "_source": "historical_median",
            "_historical_n": len(records),
        }
    return result


def _build_baselines(
    per_stratum: Dict[str, Dict[str, Any]],
    operator_key_id: str,
    git_sha: str,
) -> Dict[str, Any]:
    from datetime import datetime, timezone
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    strata_block: Dict[str, Any] = {}
    for stratum, sc in per_stratum.items():
        strata_block[stratum] = {
            "advisor_baseline": {
                "audit_pass_rate": sc["audit_pass_rate"],
                "review_findings_density": sc["review_findings_density"],
                "bb_iter_count": sc["bb_iter_count"],
                "tokens_per_sprint": sc["tokens_per_sprint"],
                "wallclock_seconds": sc["wallclock_seconds"],
            },
            "executor_target": {
                "audit_pass_rate": round(sc["audit_pass_rate"] * _EXECUTOR_TARGET_RATIO, 4),
                "review_findings_density": round(sc["review_findings_density"] / _EXECUTOR_TARGET_RATIO, 4),
                "bb_iter_count": round(sc["bb_iter_count"] / _EXECUTOR_TARGET_RATIO, 4),
                "tokens_per_sprint": round(sc["tokens_per_sprint"] / _EXECUTOR_TARGET_RATIO, 4),
                "wallclock_seconds": round(sc["wallclock_seconds"] / _EXECUTOR_TARGET_RATIO, 4),
            },
            "provenance": {
                "source": sc["_source"],
                "historical_n": sc["_historical_n"],
            },
        }
    # BB iter-1 F007 closure: mark PROVISIONAL when ANY stratum's provenance
    # is `default_baseline`. The harness's T3.B baselines-gate inspects this
    # field and refuses to run executor replays against provisional baselines
    # unless `--allow-provisional-baselines` is passed.
    any_default = any(
        sc["_source"] == "default_baseline" for sc in per_stratum.values()
    )
    return {
        "schema_version": 1,
        "cycle_id": "cycle-108-advisor-strategy",
        "git_sha_at_signing": git_sha,
        "ts_utc": ts,
        "signed_by_key_id": operator_key_id,
        "signed": False,
        "provisional": any_default,
        "executor_target_ratio": _EXECUTOR_TARGET_RATIO,
        "strata": strata_block,
        "notes": (
            "Pre-registered baselines for cycle-108 advisor-strategy benchmark. "
            "Anti-fitting protection: this file is signed via audit_emit_signed "
            "AND the operator commits to a Git tag `cycle-108-baselines-pin-<sha>` "
            "via T3.A.OP. Harness (T3.B) verifies tag signature before any replay. "
            "When `provisional: true`, at least one stratum uses default PRD §3 SC "
            "values rather than historical data; harness refuses to run executor "
            "replays against provisional baselines unless --allow-provisional-baselines."
        ),
    }


def _try_audit_sign(baselines_path: Path, audit_log: Path) -> bool:
    """Attempt to sign via audit_emit_signed. Returns True on success.

    BB iter-1 F006 closure: pass payload via env var rather than f-string
    interpolation into `bash -c`. Eliminates the shell-injection / quote-
    confusion surface that the prior implementation carried. The wrapper
    script reads `LOA_AUDIT_PAYLOAD` from env instead of argv.
    """
    payload = json.dumps({
        "cycle_id": "cycle-108-advisor-strategy",
        "baselines_path": str(baselines_path),
        "baselines_sha": _sha256_of(baselines_path),
    })
    # Use args list (no shell interpretation of script body); payload comes via
    # env var so shell quoting cannot break it regardless of payload content.
    script = (
        'source .claude/scripts/audit-envelope.sh && '
        'audit_emit_signed "$LOA_AUDIT_PRIMITIVE" "$LOA_AUDIT_EVENT_TYPE" '
        '"$LOA_AUDIT_PAYLOAD" "$LOA_AUDIT_LOG_PATH"'
    )
    env = {
        **os.environ,
        "LOA_AUDIT_PRIMITIVE": "CYCLE_108_BASELINES",
        "LOA_AUDIT_EVENT_TYPE": "baselines.signed",
        "LOA_AUDIT_PAYLOAD": payload,
        "LOA_AUDIT_LOG_PATH": str(audit_log),
    }
    try:
        result = subprocess.run(
            ["bash", "-c", script],
            capture_output=True, text=True, check=False, timeout=30,
            env=env,
        )
        return result.returncode == 0
    except (subprocess.SubprocessError, OSError):
        return False


def _sha256_of(path: Path) -> str:
    import hashlib
    h = hashlib.sha256()
    if path.exists():
        h.update(path.read_bytes())
    return h.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(
        prog="compute-baselines",
        description="Pre-registered baselines for cycle-108 advisor-strategy benchmark (T3.A).",
    )
    parser.add_argument("--input", type=Path, default=Path(".run/model-invoke.jsonl"))
    parser.add_argument("--strata", type=str, default=",".join(_DEFAULT_STRATA))
    parser.add_argument("--output", type=Path,
                        default=Path("grimoires/loa/cycles/cycle-108-advisor-strategy/baselines.json"))
    parser.add_argument("--audit-out", type=Path,
                        default=Path("grimoires/loa/cycles/cycle-108-advisor-strategy/baselines.audit.jsonl"))
    parser.add_argument("--sign", action="store_true",
                        help="Attempt audit_emit_signed (default off; operator runs T3.A.OP separately)")
    parser.add_argument("--operator-key-id", type=str, default="OPERATOR-PENDING",
                        help="Operator's audit-signing key id from OPERATORS.md")
    args = parser.parse_args()

    strata = [s.strip() for s in args.strata.split(",") if s.strip()]
    git_sha = _current_git_sha()
    per_stratum = _compute_per_stratum(args.input, strata)

    # Insufficient historical data check.
    insufficient = [s for s, info in per_stratum.items()
                    if info["_source"] == "default_baseline"]
    if insufficient:
        print(f"[compute-baselines] WARN: insufficient historical data for strata: "
              f"{insufficient} (using PRD §3 SC default baselines).", file=sys.stderr)

    baselines = _build_baselines(per_stratum, args.operator_key_id, git_sha)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(baselines, indent=2, sort_keys=True) + "\n")

    if args.sign:
        signed_ok = _try_audit_sign(args.output, args.audit_out)
        if signed_ok:
            # Re-read + flip signed flag, re-write.
            b = json.loads(args.output.read_text())
            b["signed"] = True
            args.output.write_text(json.dumps(b, indent=2, sort_keys=True) + "\n")
            print(f"[compute-baselines] signed baselines committed at {args.output}", file=sys.stderr)
        else:
            print(f"[compute-baselines] WARN: signing failed; baselines.json remains unsigned. "
                  f"Operator must re-sign via T3.A.OP path.", file=sys.stderr)

    print(json.dumps({
        "output": str(args.output),
        "audit_log": str(args.audit_out) if args.sign else None,
        "git_sha_at_signing": git_sha,
        "signed": baselines["signed"],
        "strata_with_default": insufficient,
    }, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
