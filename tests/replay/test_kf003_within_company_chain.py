"""Cycle-104 sprint-2 T2.10 — KF-003 within-company chain replay (live).

Empirical evidence that the cycle-104 chain walk (T2.5) actually absorbs
the KF-003 EMPTY_CONTENT failure class. Pre-cycle-104, KF-003 surfaced as
a terminal API_ERROR for the operator; with the within-company fallback
chain populated (T2.3) and the chain walker landed (T2.5), an
EMPTY_CONTENT response from a primary should trigger a walk to the next
chain entry rather than burn the caller.

**Gated behind `LOA_RUN_LIVE_TESTS=1`.** Without the env var, every test
in this file is skipped — no API calls, no budget consumption.

**Operator-deployment task.** Estimated budget: ~$3 (PRD §8 / SDD §7.4).
Run with:

    LOA_RUN_LIVE_TESTS=1 \\
    ANTHROPIC_API_KEY=sk-ant-... \\
    OPENAI_API_KEY=sk-... \\
    pytest tests/replay/test_kf003_within_company_chain.py -v

Output:
- Per-trial JSONL at `grimoires/loa/cycles/cycle-104-multi-model-stabilization/sprint-2-replay-corpus/kf003-results-<timestamp>.jsonl`
- Final test outcome: PASS if ≥80% of chain-walked trials produced
  content (`final_model_id` non-null and != models_requested[0])
  across the size sweep; FAIL otherwise.

Per SDD §7.4 budget math:
    5 prompts × 5 input sizes (30K/40K/50K/60K/80K input tokens) = 25 runs.
    At gpt-5.5-pro pricing (~$1.75 per 1M input tokens), full sweep ≈ $1.20.
    With chain-walk doubling on failures (each trial may invoke 2 entries),
    budget cap is $3.

Closing-evidence written under KF-005 attempts row in
`grimoires/loa/known-failures.md` if the empirical result either
confirms chain absorption (success path) or surfaces a NEW failure
mode (refines the KF entry).
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
CHEVAL = REPO_ROOT / ".claude" / "adapters" / "cheval.py"
RESULTS_DIR = (
    REPO_ROOT
    / "grimoires"
    / "loa"
    / "cycles"
    / "cycle-104-multi-model-stabilization"
    / "sprint-2-replay-corpus"
)

# ---- 1. Gate ---------------------------------------------------------------

pytestmark = pytest.mark.skipif(
    os.environ.get("LOA_RUN_LIVE_TESTS") != "1",
    reason=(
        "Live KF-003 chain replay requires LOA_RUN_LIVE_TESTS=1. "
        "Estimated budget ~$3 across 25 trials. "
        "See module docstring for invocation."
    ),
)


# ---- 2. Per-trial record ---------------------------------------------------


@dataclass(frozen=True)
class TrialResult:
    timestamp: str
    input_tokens_target: int
    prompt_id: str
    cheval_exit_code: int
    latency_ms: int
    final_model_id: str | None
    transport: str | None
    models_requested: list[str]
    models_failed: list[dict[str, Any]]
    chain_walked: bool
    chain_exhausted: bool
    raw_stderr_preview: str


# ---- 3. Prompt corpus ------------------------------------------------------
#
# Five prompts at five input sizes is the FR-S2.8 budget envelope. The
# prompts are designed to BE walk-stressful: each carries a synthetic
# pre-amble that empirically tends to trigger EMPTY_CONTENT on
# gpt-5.5-pro at ≥40K input tokens (per cycle-102 KF-003 origin).
#
# A deterministic salt avoids cache hits across trials.


SIZES = [30_000, 40_000, 50_000, 60_000, 80_000]
PROMPT_IDS = ["P1", "P2", "P3", "P4", "P5"]
SALT_BASE = 0xC104  # cycle-104 marker


def _build_prompt(prompt_id: str, target_tokens: int, salt: int) -> str:
    """Build a deterministic prompt of approximately `target_tokens` tokens.

    Token estimate uses chars/4 ≈ tokens. The synthetic pre-amble is the
    KF-003-trigger pattern from cycle-102 prior art: a long sequence of
    factual lookups that historically empties content on gpt-5.5-pro at
    ≥40K input.
    """
    # ~4 chars per token estimate
    target_chars = target_tokens * 4
    preamble = (
        f"# KF-003 chain replay {prompt_id} (salt={salt:#x})\n"
        "Provide a structured response. Each numbered item references a\n"
        "prior section verbatim and must be elaborated in two sentences.\n\n"
    )
    body_unit = (
        "Section A: factual lookup of arbitrary technical detail "
        "without ambiguity. Section B: cross-reference Section A as "
        "the lookup target. Section C: assert Section B's claim in "
        "isolation, then refer back to Section A.\n\n"
    )
    repeats = max(1, (target_chars - len(preamble)) // len(body_unit))
    return preamble + (body_unit * repeats) + (
        f"\n\nFinal question for {prompt_id}: emit a JSON object with key "
        "'summary' (one sentence) and key 'classification' "
        "(one of: 'aligned', 'partial', 'misaligned')."
    )


# ---- 4. cheval invocation --------------------------------------------------


def _invoke_cheval_chain(prompt: str, model_alias: str) -> tuple[int, str, str, dict[str, Any]]:
    """Invoke cheval with an alias whose fallback_chain is populated.

    Returns (exit_code, stdout, stderr_preview, parsed_audit_record).

    Per-trial isolation: each call sets `LOA_MODELINV_LOG_PATH` to a
    fresh tempfile so the trial's MODELINV envelope is recoverable
    deterministically, without grepping the project-shared
    `.run/model-invoke.jsonl` for the most-recent entry (which would
    race across parallel pytest workers).

    ARG_MAX defense: prompts at 80K tokens (~320K chars) exceed Linux
    ARG_MAX as an argv string; we write to a tempfile and use
    `--input <path>` instead of `--prompt <text>`.
    """
    if not CHEVAL.is_file():
        pytest.skip(f"cheval.py not at {CHEVAL}")

    import tempfile
    prompt_file = tempfile.NamedTemporaryFile(
        mode="w", suffix=".txt", delete=False, encoding="utf-8"
    )
    modelinv_log = tempfile.NamedTemporaryFile(
        mode="w", suffix=".jsonl", delete=False, encoding="utf-8"
    )
    modelinv_log.close()
    try:
        prompt_file.write(prompt)
        prompt_file.flush()
        prompt_file.close()

        env = {**os.environ, "LOA_MODELINV_LOG_PATH": modelinv_log.name}

        cmd = [
            sys.executable,
            str(CHEVAL),
            "--agent",
            "flatline-reviewer",
            "--model",
            model_alias,
            "--input",
            prompt_file.name,
            "--output-format",
            "json",
            "--json-errors",
            "--timeout",
            "300",
        ]
        started = datetime.now(timezone.utc)
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=320, env=env)
        latency_ms = int((datetime.now(timezone.utc) - started).total_seconds() * 1000)

        # Read the per-trial MODELINV envelope from its dedicated log.
        # The audit envelope is wrapped (audit-emit envelope contains
        # `payload` with the MODELINV body); extract the payload.
        audit: dict[str, Any] = {}
        try:
            with open(modelinv_log.name, "r", encoding="utf-8") as f:
                # Last line should be the model.invoke.complete envelope
                lines = [ln for ln in f if ln.strip()]
                if lines:
                    envelope = json.loads(lines[-1])
                    # audit_emit envelope shape: {..., "payload": {...}, ...}
                    audit = envelope.get("payload") or envelope
        except (OSError, json.JSONDecodeError):
            pass
    finally:
        Path(prompt_file.name).unlink(missing_ok=True)
        Path(modelinv_log.name).unlink(missing_ok=True)

    return proc.returncode, proc.stdout, proc.stderr[:500], audit | {"_latency_ms": latency_ms}


# ---- 5. Result persistence -------------------------------------------------


def _ensure_results_dir() -> Path:
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    return RESULTS_DIR


# Session-scoped output file: every trial in one pytest invocation
# appends to the same JSONL so the aggregate test can read the whole
# matrix. Computed once at module load.
_SESSION_RESULTS_TS = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def _results_path() -> Path:
    _ensure_results_dir()
    return RESULTS_DIR / f"kf003-results-{_SESSION_RESULTS_TS}.jsonl"


# ---- 6. The replay matrix --------------------------------------------------


@pytest.mark.parametrize("size_tokens", SIZES)
@pytest.mark.parametrize("prompt_id", PROMPT_IDS)
def test_kf003_chain_absorbs_empty_content(prompt_id: str, size_tokens: int) -> None:
    """Per-cell of the 5×5 matrix.

    The aggregate `test_kf003_chain_absorption_rate` test below reads
    the per-trial JSONL and asserts the ≥80% absorption rate; this
    test just records the trial's result.
    """
    salt = SALT_BASE ^ (size_tokens & 0xFFFF) ^ hash(prompt_id) & 0xFFFF
    prompt = _build_prompt(prompt_id, size_tokens, salt)
    exit_code, stdout, stderr, audit = _invoke_cheval_chain(
        prompt=prompt,
        # Use an OpenAI primary because cycle-102 origin had KF-003
        # surface on gpt-5.5-pro at ≥40K tokens.
        model_alias="gpt-5.5-pro",
    )

    models_req = list(audit.get("models_requested", []) or [])
    models_failed = list(audit.get("models_failed", []) or [])
    final_model = audit.get("final_model_id")
    transport = audit.get("transport")
    chain_walked = bool(final_model and models_req and final_model != models_req[0])
    chain_exhausted = exit_code == 12  # CHAIN_EXHAUSTED

    result = TrialResult(
        timestamp=datetime.now(timezone.utc).isoformat(),
        input_tokens_target=size_tokens,
        prompt_id=prompt_id,
        cheval_exit_code=exit_code,
        latency_ms=int(audit.get("_latency_ms") or 0),
        final_model_id=final_model,
        transport=transport,
        models_requested=models_req,
        models_failed=models_failed,
        chain_walked=chain_walked,
        chain_exhausted=chain_exhausted,
        raw_stderr_preview=stderr,
    )
    path = _results_path()
    with path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(asdict(result)) + "\n")

    # Per-trial assertion: cheval must either (a) succeed via primary,
    # (b) walk and succeed at a later entry, or (c) exhaust gracefully
    # with exit 12. Hard NETWORK / TIMEOUT / API_ERROR exits indicate
    # an unmitigated bug that the chain wasn't designed to absorb.
    acceptable_exits = {0, 12}
    assert exit_code in acceptable_exits, (
        f"Unacceptable cheval exit {exit_code} for {prompt_id}@{size_tokens}K — "
        f"chain neither succeeded nor exhausted gracefully. "
        f"stderr={stderr!r}"
    )


# ---- 7. Aggregate ≥80% absorption test -------------------------------------


def test_kf003_chain_absorption_rate() -> None:
    """Across all 25 trials, ≥80% of trials whose primary returned
    EMPTY_CONTENT MUST have produced a non-null final_model_id (chain
    walked successfully). Trials where primary succeeded directly are
    not counted in the denominator.

    Per SDD §6.5 / FR-S2.3: the chain is the load-bearing absorption
    primitive for KF-003; without ≥80% absorption, the architecture
    has not delivered its core promise and T2.9 (code_review revert)
    must NOT ship.
    """
    _ensure_results_dir()
    # Find the most recent results file produced by the per-trial tests.
    candidates = sorted(
        RESULTS_DIR.glob("kf003-results-*.jsonl"),
        key=lambda p: p.stat().st_mtime,
        reverse=True,
    )
    if not candidates:
        pytest.skip(
            "No results file produced by per-trial tests. Run the "
            "parametrized cell tests first (same pytest session)."
        )
    latest = candidates[0]
    trials: list[dict[str, Any]] = []
    with latest.open("r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                trials.append(json.loads(line))

    # Filter to trials where the primary failed with EMPTY_CONTENT
    # (the KF-003 signature). models_failed[] carries error_class per
    # MODELINV v1.1.
    kf003_trials = [
        t
        for t in trials
        if any(
            f.get("error_class") == "EMPTY_CONTENT"
            and f.get("model") == (t["models_requested"] or [None])[0]
            for f in t["models_failed"]
        )
    ]
    if not kf003_trials:
        pytest.skip(
            f"No KF-003 trials surfaced across {len(trials)} runs — the "
            "primary did not produce EMPTY_CONTENT for any size/prompt. "
            "Either KF-003 has been provider-side fixed (good!) or the "
            "prompt corpus needs a refresh. Cannot empirically validate "
            "the chain's absorption rate; T2.9 stays gated."
        )

    absorbed = [t for t in kf003_trials if t["chain_walked"] and t["final_model_id"]]
    rate = len(absorbed) / len(kf003_trials)
    msg = (
        f"KF-003 chain absorption rate: {rate:.1%} "
        f"({len(absorbed)}/{len(kf003_trials)} trials). "
        f"Results file: {latest.name}"
    )
    print(msg, file=sys.stderr)
    assert rate >= 0.80, msg + " — below SDD §7.4 ≥80% threshold; "
    "T2.9 code_review revert MUST NOT ship until rate improves."
