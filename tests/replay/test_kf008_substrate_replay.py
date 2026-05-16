"""Cycle-104 sprint-3 T3.4 — KF-008 substrate replay (live).

Tests whether the cheval Python substrate (`httpx` + streaming defaults)
reproduces KF-008's `SocketError: other side closed` at the observed
body sizes (297KB / 302KB / 317KB / 539KB) against Google's
`generativelanguage.googleapis.com`.

Two acceptable outcomes per SDD §1.4.5 (sprint-3-evidence.md §5):

  (a) Cheval substrate absorbs the body-size class — N/N trials succeed.
      KF-008 closes as `RESOLVED-architectural-complete`. T3.5 records
      the closing-evidence row.

  (b) Substrate still fails at ≥300KB. T3.5 files deeper upstream
      against #845 and leaves KF-008 as `MITIGATED-CONSUMER` (cycle-104
      voice-drop is the survival path; AC-3.3 (b) is valid).

The cycle-103 T1.0 spike (2026-05-11) already tested 172/250/318/400KB
via a one-off Python httpx probe and reported "did not reproduce". T3.4
re-tests via the actual cheval invocation path (not a one-off httpx
script) to confirm the closure under the production code path.

**Gated behind `LOA_RUN_LIVE_TESTS=1`.** Estimated budget ≤$2 (PRD §7.4).

Run with:

    LOA_RUN_LIVE_TESTS=1 \\
    GOOGLE_API_KEY=AIza... \\
    pytest tests/replay/test_kf008_substrate_replay.py -v

Output:
- `grimoires/loa/cycles/cycle-104-multi-model-stabilization/sprint-3-replay-corpus/kf008-results-<ts>.jsonl`
- Aggregate test reads the JSONL and prints the outcome (a)/(b).
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
from dataclasses import asdict, dataclass
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
    / "sprint-3-replay-corpus"
)

# ---- Gate ------------------------------------------------------------------

pytestmark = pytest.mark.skipif(
    os.environ.get("LOA_RUN_LIVE_TESTS") != "1",
    reason=(
        "Live KF-008 substrate replay requires LOA_RUN_LIVE_TESTS=1. "
        "Estimated budget ≤$2 across 4 trials. "
        "See module docstring for invocation."
    ),
)


# ---- Observed body sizes (from KF-008 attempts table) ---------------------
#
# The observation lineage:
#   297209B — 2026-05-11 05:33 first reproduction (PR #844 BB cycle-1)
#   302623B — 2026-05-11 05:55 second reproduction (PR #844, second-pass enrichment)
#   317766B — 2026-05-11 06:42 third reproduction → recurrence-3 gate
#   539089B — 2026-05-11 13:16 fourth reproduction (PR #846 BB cycle-3, 539KB)
#
# The T1.0 spike (2026-05-11 09:35) tested 172/250/318/400KB via one-off
# httpx probe and got 4-of-4 clean. T3.4 retests via the cheval invocation
# path (the production code path that BB now uses).

OBSERVED_SIZES_BYTES = [297_209, 302_623, 317_766, 539_089]


# ---- Per-trial record -----------------------------------------------------


@dataclass(frozen=True)
class TrialResult:
    timestamp: str
    target_body_bytes: int
    actual_body_bytes: int
    cheval_exit_code: int
    latency_ms: int
    final_model_id: str | None
    transport: str | None
    error_class: str | None
    error_message_preview: str
    chain_walked: bool


# ---- Session-scoped results file ------------------------------------------

_SESSION_TS = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def _results_path() -> Path:
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    return RESULTS_DIR / f"kf008-results-{_SESSION_TS}.jsonl"


# ---- Body construction ----------------------------------------------------


def _build_payload(target_bytes: int, seed: int) -> str:
    """Build a deterministic prompt of approximately `target_bytes` bytes.

    The content is text (ASCII), so UTF-8 byte length == char length.
    Seed varies the prefix to avoid provider-side cache hits.
    """
    preamble = (
        f"# KF-008 substrate replay (seed={seed:#x})\n"
        f"# Target body size: {target_bytes} bytes\n\n"
        "Analyze the following technical context and provide a "
        "single-sentence summary at the end. Each paragraph is "
        "independent; treat it as standalone reference text.\n\n"
    )
    body_unit = (
        "Paragraph: a sequence of facts about an arbitrary technical topic. "
        "The facts are nominally self-consistent but unrelated to any prior "
        "context. The summarization target is the final sentence of the "
        "paragraph, which restates the central claim in different words. "
        "This sentence is the only operative content; everything before is "
        "scaffolding.\n\n"
    )
    repeats = max(1, (target_bytes - len(preamble) - 50) // len(body_unit))
    body = preamble + (body_unit * repeats)
    closing = "\n\nFinal question: produce a one-sentence summary of the above."
    return body + closing


# ---- Cheval invocation ----------------------------------------------------


def _invoke_cheval_google(prompt: str) -> tuple[int, str, str, dict[str, Any]]:
    """Invoke cheval against the Google substrate for the given prompt.

    Returns (exit_code, stdout, stderr_preview, parsed_audit_record).

    The model is `gemini-3.1-pro-preview` — the exact model where KF-008
    reproduced. Prompt is passed via tempfile + --input to avoid ARG_MAX
    on 539K-byte bodies.
    """
    if not CHEVAL.is_file():
        pytest.skip(f"cheval.py not at {CHEVAL}")

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
            # Use the canonical provider:model form to bypass alias
            # resolution edge cases (cheval's aliases register the
            # tier-pin alias `gemini-3.1-pro` → `google:gemini-3.1-pro-preview`,
            # but the bare model_id is not registered as an alias).
            "--model",
            "google:gemini-3.1-pro-preview",
            "--input",
            prompt_file.name,
            "--output-format",
            "json",
            "--json-errors",
            "--timeout",
            "600",
        ]
        started = datetime.now(timezone.utc)
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=620, env=env)
        latency_ms = int((datetime.now(timezone.utc) - started).total_seconds() * 1000)

        audit: dict[str, Any] = {}
        try:
            with open(modelinv_log.name, "r", encoding="utf-8") as f:
                lines = [ln for ln in f if ln.strip()]
                if lines:
                    envelope = json.loads(lines[-1])
                    audit = envelope.get("payload") or envelope
        except (OSError, json.JSONDecodeError):
            pass
    finally:
        Path(prompt_file.name).unlink(missing_ok=True)
        Path(modelinv_log.name).unlink(missing_ok=True)

    return proc.returncode, proc.stdout, proc.stderr[:1000], audit | {"_latency_ms": latency_ms}


# ---- Per-trial test -------------------------------------------------------


@pytest.mark.parametrize("target_bytes", OBSERVED_SIZES_BYTES)
def test_kf008_cheval_substrate_at_observed_size(target_bytes: int) -> None:
    """Per-cell: invoke cheval with a `target_bytes`-sized payload to Google.

    The aggregate `test_kf008_substrate_absorption` reads the per-trial
    JSONL and computes the closure outcome.

    Per-trial pass condition: cheval either succeeds (exit 0) OR exhausts
    the chain gracefully (exit 12). A hard `SocketError: other side closed`
    surfaces as `RETRIES_EXHAUSTED` (exit 1) — that's the KF-008 signature
    and the test records it BUT does NOT fail the per-trial; the aggregate
    test makes the closure call.
    """
    seed = 0xC108 ^ (target_bytes & 0xFFFF)
    prompt = _build_payload(target_bytes, seed)
    actual_bytes = len(prompt.encode("utf-8"))

    exit_code, _stdout, stderr, audit = _invoke_cheval_google(prompt=prompt)

    final_model = audit.get("final_model_id")
    transport = audit.get("transport")
    models_failed = audit.get("models_failed") or []
    error_class = None
    error_msg = ""
    if models_failed:
        last = models_failed[-1]
        error_class = last.get("error_class")
        error_msg = (last.get("message_redacted") or "")[:300]
    elif exit_code != 0:
        error_class = "UNKNOWN_NON_ZERO_EXIT"
        error_msg = stderr[:300]

    models_req = audit.get("models_requested") or []
    chain_walked = bool(final_model and models_req and final_model != models_req[0])

    result = TrialResult(
        timestamp=datetime.now(timezone.utc).isoformat(),
        target_body_bytes=target_bytes,
        actual_body_bytes=actual_bytes,
        cheval_exit_code=exit_code,
        latency_ms=int(audit.get("_latency_ms") or 0),
        final_model_id=final_model,
        transport=transport,
        error_class=error_class,
        error_message_preview=error_msg,
        chain_walked=chain_walked,
    )
    with _results_path().open("a", encoding="utf-8") as f:
        f.write(json.dumps(asdict(result)) + "\n")

    print(
        f"\nKF-008 trial: target={target_bytes}B actual={actual_bytes}B "
        f"exit={exit_code} final_model={final_model} transport={transport} "
        f"error_class={error_class}",
        file=sys.stderr,
    )


# ---- Aggregate outcome decision ------------------------------------------


def test_kf008_substrate_outcome_decision() -> None:
    """Read the per-trial JSONL and emit the outcome decision per SDD §1.4.5.

    Decision rule:
      - ALL trials exit 0 → outcome (a) RESOLVED-architectural-complete
        (the cheval substrate absorbs the body-size class)
      - ANY trial fails with a SocketError-class error → outcome (b)
        MITIGATED-CONSUMER (substrate-layer bug persists; voice-drop is
        the survival path)
      - Any other combination → INCONCLUSIVE; document and re-run

    This test ALWAYS passes (records the outcome via stderr + the
    results file). The closure decision is informational; T3.5 records
    the final outcome in known-failures.md.
    """
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    candidates = sorted(
        RESULTS_DIR.glob("kf008-results-*.jsonl"),
        key=lambda p: p.stat().st_mtime,
        reverse=True,
    )
    if not candidates:
        pytest.skip(
            "No results file produced. Run the per-trial cells first "
            "(same pytest session)."
        )

    latest = candidates[0]
    trials: list[dict[str, Any]] = []
    with latest.open("r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                trials.append(json.loads(line))

    success = [t for t in trials if t["cheval_exit_code"] == 0]
    failures = [t for t in trials if t["cheval_exit_code"] != 0]

    if len(success) == len(trials):
        outcome = "(a) RESOLVED-architectural-complete"
    elif any(
        "SocketError" in (t.get("error_message_preview") or "")
        or "other side closed" in (t.get("error_message_preview") or "")
        for t in failures
    ):
        outcome = "(b) MITIGATED-CONSUMER (substrate-layer bug)"
    elif failures:
        outcome = "(?) INCONCLUSIVE — failures observed but not SocketError class"
    else:
        outcome = "(?) INCONCLUSIVE — no trials in latest file"

    print(
        f"\n\n=== KF-008 substrate outcome: {outcome} ===\n"
        f"Trials: {len(trials)} ({len(success)} success, {len(failures)} fail)\n"
        f"Results file: {latest.name}\n",
        file=sys.stderr,
    )

    # Always passes; the decision is informational. T3.5 makes the
    # known-failures.md update based on this outcome.
    assert outcome  # tautology — kept for clarity
