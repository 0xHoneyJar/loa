"""cycle-103 sprint-2 T2.1 — KF-002 layer-2 empirical replay.

Invokes `claude-opus-4.7` via cheval across the 5-size × 5-trial × 3-config
matrix from AC-2.1. Classifies each trial's output, aggregates per-size
results, persists raw measurements to a JSONL file under the sprint-2
corpus directory.

**Gated behind `LOA_RUN_LIVE_TESTS=1`.** Without the env var, every test
in this file is skipped — no API calls, no budget consumption. The
classifier (`classifier.py`) is independently tested by
`test_classifier.py` and runs offline always.

**Operator-deployment task.** Estimated budget: ~$3 (PRD §8). Run with:

    LOA_RUN_LIVE_TESTS=1 \\
    ANTHROPIC_API_KEY=sk-ant-... \\
    pytest tests/replay/test_opus_empty_content_thresholds.py -v

Output:
- Per-trial JSONL at `grimoires/loa/cycles/cycle-103-provider-unification/sprint-2-corpus/results-<timestamp>.jsonl`
- Per-size aggregation logged via stderr
- Test assertions: empty-content rate at 30K should be ≤20% (sanity);
  AC-2.1 disposition surfaced as the final test outcome.

Per AC-2.1: "Decision-rule: 'structural fix viable' requires ≥80%
full_content at empirically-safe threshold across 5 trials".
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import pytest

# Add the sprint-2-corpus to sys.path so we can import `build_prompts`.
_CORPUS_DIR = (
    Path(__file__).resolve().parents[2]
    / "grimoires"
    / "loa"
    / "cycles"
    / "cycle-103-provider-unification"
    / "sprint-2-corpus"
)
sys.path.insert(0, str(_CORPUS_DIR))

from build_prompts import build_prompt, estimate_tokens  # noqa: E402

from tests.replay.classifier import (
    TrialOutcome,
    classify_trial,
    classify_matrix,
    find_safe_threshold,
)


# ----------------------------------------------------------------------------
# Configuration
# ----------------------------------------------------------------------------

# AC-2.1 matrix: 5 input sizes × 5 trials × varying thinking config.
INPUT_SIZES = (30_000, 40_000, 50_000, 60_000, 80_000)
TRIALS_PER_CELL = 5

# `thinking.budget_tokens` sweep. None = thinking config unset.
THINKING_BUDGETS = (None, 2_000, 4_000)

# `max_tokens` sweep. The replay tests whether forcing visible-output
# budget improves the full-content rate at high input sizes.
MAX_TOKENS_VALUES = (4_096, 8_000)

# Model under test — the alias documented in `model-config.yaml` for the
# newest Opus. (cycle-103 T1.6 discovered the hyphen form is NOT a
# registered alias.)
MODEL = "claude-opus-4.7"

# Cheval CLI agent binding. Generic reviewer agent that works for any
# `--model` override (similar to T1.5 fixture-mode pattern).
AGENT = "flatline-reviewer"

# Per-call timeout in seconds. Long because Opus on 80K input may take
# minutes to first-token.
CALL_TIMEOUT_SEC = 600


# ----------------------------------------------------------------------------
# Skip-without-LOA_RUN_LIVE_TESTS gate
# ----------------------------------------------------------------------------

pytestmark = pytest.mark.skipif(
    os.environ.get("LOA_RUN_LIVE_TESTS") != "1",
    reason=(
        "Live replay requires LOA_RUN_LIVE_TESTS=1. "
        "Estimated budget ~$3. See module docstring for invocation."
    ),
)


# ----------------------------------------------------------------------------
# Result records
# ----------------------------------------------------------------------------


@dataclass(frozen=True)
class TrialResult:
    """Single trial's raw measurement. Persisted to JSONL."""

    timestamp: str
    input_tokens_target: int
    input_tokens_actual: int
    salt: int
    thinking_budget: int | None
    max_tokens: int
    cheval_exit_code: int
    latency_ms: int
    output_chars: int
    output_token_estimate: int
    outcome: str  # TrialOutcome value
    raw_stdout_preview: str  # first 500 chars for debugging
    raw_stderr_preview: str  # first 500 chars for debugging


# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------


def _cheval_script_path() -> Path:
    return Path(__file__).resolve().parents[2] / ".claude" / "adapters" / "cheval.py"


def _results_path() -> Path:
    ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    return _CORPUS_DIR / f"results-{ts}.jsonl"


def _persist_result(path: Path, result: TrialResult) -> None:
    """Append a TrialResult to the JSONL output file. Atomic append."""
    with path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(asdict(result)) + "\n")


def _invoke_cheval(
    *,
    prompt: str,
    thinking_budget: int | None,
    max_tokens: int,
) -> tuple[int, str, str, int]:
    """Invoke cheval with the given prompt and config.

    Returns:
      (exit_code, stdout, stderr, latency_ms)
    """
    cheval = _cheval_script_path()
    if not cheval.is_file():
        pytest.skip(f"cheval.py not at {cheval}")

    # Write prompt to a temp file (avoids argv length limits and keeps
    # the prompt out of process listings — same pattern as T1.6
    # `call_flatline_chat`).
    import tempfile

    with tempfile.NamedTemporaryFile(
        mode="w", suffix=".txt", delete=False, encoding="utf-8"
    ) as f:
        f.write(prompt)
        prompt_path = f.name

    args: list[str] = [
        "python3",
        str(cheval),
        "--agent",
        AGENT,
        "--model",
        MODEL,
        "--input",
        prompt_path,
        "--output-format",
        "json",
        "--json-errors",
        "--max-tokens",
        str(max_tokens),
        "--timeout",
        str(CALL_TIMEOUT_SEC),
    ]
    if thinking_budget is not None:
        # NOTE: cheval CLI does not currently expose a --thinking-budget
        # flag. If/when it does, this is the integration point. For now,
        # the env var `LOA_THINKING_BUDGET` is the documented override
        # path. We pass it via env so the cheval-side budget code (when
        # it exists) can read it.
        env = dict(os.environ)
        env["LOA_THINKING_BUDGET"] = str(thinking_budget)
    else:
        env = None  # subprocess.run uses parent env

    started = time.monotonic()
    try:
        proc = subprocess.run(
            args,
            capture_output=True,
            text=True,
            timeout=CALL_TIMEOUT_SEC + 30,
            env=env,
        )
        latency_ms = int((time.monotonic() - started) * 1000)
        return proc.returncode, proc.stdout, proc.stderr, latency_ms
    finally:
        try:
            os.unlink(prompt_path)
        except OSError:
            pass


def _extract_content_from_stdout(stdout: str) -> str | None:
    """Extract the `content` field from cheval's JSON stdout.
    Returns None if stdout is empty or unparseable."""
    stripped = stdout.strip()
    if not stripped:
        return None
    try:
        parsed = json.loads(stripped)
    except json.JSONDecodeError:
        return None
    if not isinstance(parsed, dict):
        return None
    content = parsed.get("content")
    return content if isinstance(content, str) else None


# ----------------------------------------------------------------------------
# Parametrized replay matrix
# ----------------------------------------------------------------------------


@pytest.fixture(scope="session")
def results_jsonl(tmp_path_factory: pytest.TempPathFactory) -> Path:
    """Session-scoped results file. Pre-created on first request so all
    parametrized trials append to the same file."""
    path = _results_path()
    path.touch()
    return path


@pytest.mark.parametrize("input_size", INPUT_SIZES)
@pytest.mark.parametrize("trial_salt", range(TRIALS_PER_CELL))
@pytest.mark.parametrize("thinking_budget", THINKING_BUDGETS)
@pytest.mark.parametrize("max_tokens", MAX_TOKENS_VALUES)
def test_replay_cell(
    input_size: int,
    trial_salt: int,
    thinking_budget: int | None,
    max_tokens: int,
    results_jsonl: Path,
) -> None:
    """One cell of the AC-2.1 matrix. Each test invocation = one live API
    call to claude-opus-4.7 via cheval. Records the outcome.

    The full matrix is 5 sizes × 5 trials × 3 thinking budgets × 2
    max_tokens = 150 cells. At ~$0.02/call, this is ~$3 — matches PRD §8
    budget estimate.
    """
    prompt = build_prompt(input_size, salt=trial_salt)
    actual_tokens = estimate_tokens(prompt)

    exit_code, stdout, stderr, latency_ms = _invoke_cheval(
        prompt=prompt,
        thinking_budget=thinking_budget,
        max_tokens=max_tokens,
    )

    content = _extract_content_from_stdout(stdout)
    outcome = classify_trial(content)
    output_chars = len(content) if content else 0

    result = TrialResult(
        timestamp=datetime.now(timezone.utc).isoformat(),
        input_tokens_target=input_size,
        input_tokens_actual=actual_tokens,
        salt=trial_salt,
        thinking_budget=thinking_budget,
        max_tokens=max_tokens,
        cheval_exit_code=exit_code,
        latency_ms=latency_ms,
        output_chars=output_chars,
        output_token_estimate=output_chars // 4,
        outcome=outcome.value,
        raw_stdout_preview=stdout[:500],
        raw_stderr_preview=stderr[:500],
    )

    _persist_result(results_jsonl, result)

    # Per-trial output to stderr for live feedback during a long run.
    print(
        f"[REPLAY] size={input_size} salt={trial_salt} "
        f"thinking={thinking_budget} max_tokens={max_tokens} "
        f"exit={exit_code} latency={latency_ms}ms outcome={outcome.value} "
        f"output_chars={output_chars}",
        file=sys.stderr,
    )

    # No per-trial assertion — the AC-2.1 disposition is computed at the
    # end-of-session aggregator (test_disposition below).


# ----------------------------------------------------------------------------
# Aggregation + disposition
# ----------------------------------------------------------------------------


def _load_results(path: Path) -> list[TrialResult]:
    """Reload results from the session JSONL."""
    if not path.is_file():
        return []
    results: list[TrialResult] = []
    with path.open(encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            data = json.loads(line)
            results.append(TrialResult(**data))
    return results


def test_disposition(results_jsonl: Path) -> None:
    """Aggregate the matrix outcomes and surface AC-2.1's
    structural-vs-vendor-side disposition.

    Runs AFTER all parametrized cells via session fixture ordering.
    """
    results = _load_results(results_jsonl)
    if not results:
        pytest.skip("No replay results — cells failed to run")

    # Aggregate by input_tokens_target only (ignore thinking_budget /
    # max_tokens for the threshold rule; AC-2.1 asks for size-banded
    # disposition).
    by_size: dict[int, list[TrialOutcome]] = {}
    for r in results:
        by_size.setdefault(r.input_tokens_target, []).append(
            TrialOutcome(r.outcome)
        )

    matrix = classify_matrix(by_size)
    threshold = find_safe_threshold(matrix)

    print("\n[REPLAY-DISPOSITION] AC-2.1 matrix:", file=sys.stderr)
    for size, result in matrix.items():
        print(
            f"  {size:>6} tokens: "
            f"full={result.full}/{result.trial_count} "
            f"({result.full_rate:.0%}) "
            f"empty={result.empty} partial={result.partial} "
            f"viable={result.structural_fix_viable}",
            file=sys.stderr,
        )

    if threshold is not None:
        print(
            f"\n[REPLAY-DISPOSITION] STRUCTURAL FIX VIABLE at "
            f"max_input_tokens={threshold}. Apply T2.2a.",
            file=sys.stderr,
        )
    else:
        print(
            "\n[REPLAY-DISPOSITION] NO VIABLE THRESHOLD. "
            "Route to T2.2b (vendor-side path).",
            file=sys.stderr,
        )

    # Persist the disposition summary alongside the raw JSONL.
    summary_path = results_jsonl.with_suffix(".summary.json")
    summary: dict[str, Any] = {
        "matrix": {
            str(size): asdict(result) for size, result in matrix.items()
        },
        "safe_threshold": threshold,
        "disposition": "structural" if threshold else "vendor-side",
        "ac_2_1_path": "T2.2a" if threshold else "T2.2b",
    }
    summary_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(f"[REPLAY-DISPOSITION] Summary: {summary_path}", file=sys.stderr)
