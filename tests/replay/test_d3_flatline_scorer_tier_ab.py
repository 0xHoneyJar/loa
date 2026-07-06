"""Cycle-116 D3 (bd-c116-d3-tiering) — flatline-scorer tier A/B (live).

Empirical A/B for the per-stage tier-routing PoC stage (flatline-scorer). The
whole D3 request rests on PR #885's finding that the *executor* tier is UNSAFE
for Bridgebuilder REVIEW (6x cheaper, missed 1 HIGH_CONSENSUS finding, -60%
total findings). That test measured BB review, NOT structured scoring — so it
does NOT transfer to flatline-scorer by assumption. This test measures the thing
#885 never did: does the cheaper executor tier agree with a hand-labeled gold
set as well as the advisor tier does, on the flatline-scorer scoring task?

**Gated behind `LOA_RUN_LIVE_TESTS=1`.** Without the env var every test skips —
no API calls, no budget consumption.

**Operator-deployment task.** Estimated budget: ~$3 cap (well under in practice).
Run with:

    LOA_RUN_LIVE_TESTS=1 \\
    ANTHROPIC_API_KEY=sk-ant-... \\
    python3 -m pytest tests/replay/test_d3_flatline_scorer_tier_ab.py -v

Budget math:
    2 tiers x 5 trials = 10 calls. Gold prompt is ~1.5K input tokens; scorer
    output ~1K tokens. At advisor (claude-opus-4-8) + executor (claude-sonnet-4-6)
    pricing the full sweep is well under $0.50; the $3 cap is a generous ceiling
    matching the tests/replay/test_kf003_* convention.

Output:
- Per-trial JSONL at
  grimoires/loa/cycles/cycle-116-quality-per-token/d3-flatline-scorer-ab/trials-<ts>.jsonl
- Stats-ready outcomes.jsonl (the exact shape tools/advisor-benchmark-stats.py
  consumes: {sprint_sha, tier, idx, score, outcome, stratum}) alongside it.
- Print the outcomes path in the report so the operator can run:
    python3 tools/advisor-benchmark-stats.py --outcomes <path> --score-key score

Verdict handling (LEAD DECISION): regardless of the A/B result the flag default
stays false. This test RECORDS the metrics for a future operator decision; it
does NOT flip advisor_strategy.stage_routing.flatline_scorer. A provider/auth
failure is recorded honestly (INCONCLUSIVE outcome) and does not fail the run
into a KF-002-class retry wall.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
CHEVAL = REPO_ROOT / ".claude" / "adapters" / "cheval.py"
CONFIG = REPO_ROOT / ".loa.config.yaml"
GOLD = REPO_ROOT / "tests" / "fixtures" / "stage-tier-benchmark" / "flatline-scorer-gold.json"
RESULTS_DIR = (
    REPO_ROOT / "grimoires" / "loa" / "cycles"
    / "cycle-116-quality-per-token" / "d3-flatline-scorer-ab"
)

TRIALS_PER_TIER = 5
TIERS = ["advisor", "executor"]
PROVIDER = "anthropic"

# ---- Gate ------------------------------------------------------------------

pytestmark = pytest.mark.skipif(
    os.environ.get("LOA_RUN_LIVE_TESTS") != "1",
    reason=(
        "Live flatline-scorer tier A/B requires LOA_RUN_LIVE_TESTS=1. "
        "Estimated budget ~$3 across 10 trials. See module docstring."
    ),
)


# ---- Per-trial record ------------------------------------------------------


@dataclass(frozen=True)
class TrialResult:
    timestamp: str
    tier: str
    idx: int
    model: str
    cheval_exit_code: int
    agreement: float | None      # fraction of findings whose would_integrate matches gold
    band_hit_rate: float | None  # fraction whose score landed in the gold band
    n_scored: int
    outcome: str                 # OK | INCONCLUSIVE
    raw_stderr_preview: str


# ---- Helpers ---------------------------------------------------------------


def _tier_model(tier: str) -> str:
    """Resolve advisor_strategy.tier_aliases.<tier>.<provider> from the live config."""
    import yaml
    with CONFIG.open() as f:
        cfg = yaml.safe_load(f)
    aliases = (cfg.get("advisor_strategy", {}) or {}).get("tier_aliases", {}) or {}
    model = (aliases.get(tier, {}) or {}).get(PROVIDER)
    if not model:
        pytest.skip(f"no tier_alias advisor_strategy.tier_aliases.{tier}.{PROVIDER} in config")
    return model


def _load_gold() -> tuple[dict[str, Any], dict[str, Any]]:
    data = json.loads(GOLD.read_text())
    return {"improvements": data["improvements"]}, data["gold"]


def _invoke_scorer(model: str, scorer_input: dict[str, Any]) -> tuple[int, str, str]:
    """Invoke flatline-scorer via cheval with an explicit tier model. Returns
    (exit_code, stdout, stderr_preview)."""
    if not CHEVAL.is_file():
        pytest.skip(f"cheval.py not at {CHEVAL}")
    import tempfile
    inp = tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False, encoding="utf-8")
    try:
        json.dump(scorer_input, inp)
        inp.flush()
        inp.close()
        cmd = [
            sys.executable, str(CHEVAL),
            "--agent", "flatline-scorer",
            "--skill", "flatline-scorer",
            # provider:model-id form — tier_aliases store bare model-ids, but
            # cheval --model wants an alias OR provider:model-id. claude-opus-4-8
            # happens to also be an alias; claude-sonnet-4-6 is NOT (its alias is
            # 'cheap'), so the qualified form is required for tier parity.
            "--model", f"{PROVIDER}:{model}",
            "--input", inp.name,
            "--output-format", "json",
            "--json-errors",
            "--timeout", "180",
        ]
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=200)
        return proc.returncode, proc.stdout, proc.stderr[:500]
    finally:
        Path(inp.name).unlink(missing_ok=True)


def _score_against_gold(stdout: str, gold: dict[str, Any]) -> tuple[float | None, float | None, int]:
    """Parse the scorer's {scores:[{id, score, would_integrate}]} output and
    compute (would_integrate agreement rate, score-band hit rate, n_scored)."""
    try:
        env = json.loads(stdout)
        content = env.get("content", env)
        if isinstance(content, str):
            content = json.loads(content)
        scores = content.get("scores", [])
    except (json.JSONDecodeError, AttributeError, TypeError):
        return None, None, 0
    matches = band_hits = n = 0
    for s in scores:
        sid = s.get("id")
        if sid not in gold:
            continue
        n += 1
        g = gold[sid]
        if bool(s.get("would_integrate")) == bool(g["would_integrate"]):
            matches += 1
        try:
            lo, hi = g["expected_band"]
            if lo <= int(s.get("score", -1)) <= hi:
                band_hits += 1
        except (KeyError, ValueError, TypeError):
            pass
    if n == 0:
        return None, None, 0
    return matches / n, band_hits / n, n


# ---- Result persistence ----------------------------------------------------

_TS = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def _results_path() -> Path:
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    return RESULTS_DIR / f"trials-{_TS}.jsonl"


def _outcomes_path() -> Path:
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    return RESULTS_DIR / f"outcomes-{_TS}.jsonl"


# ---- The A/B matrix --------------------------------------------------------


@pytest.mark.parametrize("idx", list(range(1, TRIALS_PER_TIER + 1)))
@pytest.mark.parametrize("tier", TIERS)
def test_scorer_tier_trial(tier: str, idx: int) -> None:
    """One (tier, trial) cell. Records the trial; the aggregate test reports."""
    model = _tier_model(tier)
    scorer_input, gold = _load_gold()
    exit_code, stdout, stderr = _invoke_scorer(model, scorer_input)
    agreement, band_hit, n = _score_against_gold(stdout, gold)
    outcome = "OK" if (exit_code == 0 and n > 0) else "INCONCLUSIVE"

    result = TrialResult(
        timestamp=datetime.now(timezone.utc).isoformat(),
        tier=tier, idx=idx, model=model,
        cheval_exit_code=exit_code,
        agreement=agreement, band_hit_rate=band_hit, n_scored=n,
        outcome=outcome, raw_stderr_preview=stderr,
    )
    with _results_path().open("a", encoding="utf-8") as f:
        f.write(json.dumps(asdict(result)) + "\n")
    # Stats-ready record (advisor-benchmark-stats.py shape). score = agreement.
    with _outcomes_path().open("a", encoding="utf-8") as f:
        f.write(json.dumps({
            "sprint_sha": f"d3-scorer-ab-{_TS}",
            "tier": tier, "idx": idx,
            "score": agreement,
            "outcome": outcome, "stratum": "flatline-scorer-gold",
        }) + "\n")

    # Do NOT hard-fail on provider/auth degradation (LEAD DECISION: record
    # honestly, no KF-002-class retry). Only assert cheval didn't crash the
    # harness itself with an unexpected non-API exit.
    assert exit_code in (0, 12), (
        f"unexpected cheval exit {exit_code} for {tier}#{idx}; stderr={stderr!r}"
    )


def test_report_tier_ab() -> None:
    """Aggregate: mean agreement per tier + print outcomes path for the stats
    tool. Records the verdict; NEVER flips the flag (stays false regardless)."""
    op = _outcomes_path()
    if not op.exists():
        pytest.skip("no outcomes produced; run the parametrized cells first (same session)")
    rows = [json.loads(l) for l in op.read_text().splitlines() if l.strip()]
    by_tier: dict[str, list[float]] = {}
    for r in rows:
        if r["score"] is not None:
            by_tier.setdefault(r["tier"], []).append(r["score"])

    lines = ["=== D3 flatline-scorer tier A/B ==="]
    for tier in TIERS:
        vals = by_tier.get(tier, [])
        mean = sum(vals) / len(vals) if vals else None
        lines.append(f"  {tier:9s}: n={len(vals)} mean_agreement={mean}")
    lines.append(f"  outcomes: {op}")
    lines.append(f"  stats: python3 tools/advisor-benchmark-stats.py --outcomes {op} --score-key score")
    lines.append("  NOTE: flag default stays false regardless of this result (operator decision).")
    report = "\n".join(lines)
    print(report, file=sys.stderr)

    # No pass/fail threshold — this is a measurement run for an operator
    # decision, not a gate. Assert only that at least one tier produced a
    # usable score so the report is meaningful; skip (not fail) if the whole
    # run degraded (provider/auth), per LEAD DECISION.
    if not by_tier:
        pytest.skip("all trials INCONCLUSIVE (provider/auth degradation) — recorded, not fatal")
