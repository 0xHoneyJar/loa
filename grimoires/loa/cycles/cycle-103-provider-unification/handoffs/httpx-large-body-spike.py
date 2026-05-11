#!/usr/bin/env python3
"""
T1.0 — httpx large-body spike against Google generativelanguage API via cheval.

Reproduces the BB KF-008 scenario from a different client (Python httpx, not
Node fetch) at progressively larger request bodies. Outcome routes Sprint 1
per AC-1.0:

  (a) httpx handles 400KB without error → unification trivially closes KF-008
  (b) httpx hits the same threshold     → KF-008 is vendor-side, cycle-103
      ships unification + documented operator workaround

Invocation:
  cd <repo-root>
  python3 grimoires/loa/cycles/cycle-103-provider-unification/handoffs/httpx-large-body-spike.py

Output:
  - JSONL log at sibling path: httpx-large-body-spike-results.jsonl
  - Stdout: human-readable summary table
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[5]
CHEVAL = REPO_ROOT / ".claude" / "adapters" / "cheval.py"
RESULTS_PATH = Path(__file__).with_name("httpx-large-body-spike-results.jsonl")

# Body size targets (bytes). Chosen per cycle-103 PRD IMP-005 / AC-1.0:
#   172KB — verified failure size on 2026-05-11 BB run
#   250KB — between observed failure and the larger BB run (297KB)
#   318KB — slightly above the 297KB observed failure
#   400KB — stress test, beyond observed BB failures
TARGET_SIZES = [172_000, 250_000, 318_000, 400_000]

MODEL = "gemini-3.1-pro"
AGENT = "reviewing-code"
TIMEOUT_SECONDS = 180
MAX_OUTPUT_TOKENS = 64  # Minimize output so timing reflects upload + response shape, not generation


def make_filler_prompt(target_body_bytes: int) -> str:
    """
    Build a prompt of approximately target_body_bytes of meaningful-looking text.

    Uses a diff-like filler because BB review payloads are diffs — keeps shape
    similar to what KF-008 was observed against.
    """
    header = (
        "You are reviewing the following diff. Summarize in one sentence what "
        "the change does. Do not generate code; respond only with the summary.\n\n"
        "```diff\n"
    )
    footer = "\n```\nSummary:"

    # JSON envelope adds ~300 bytes (request structure for Gemini); leave 800
    # bytes of headroom so wall body size lands at or just above the target.
    envelope_overhead = 800
    content_budget = max(0, target_body_bytes - len(header) - len(footer) - envelope_overhead)

    line = "+ const newFlag = config.enabled ?? false; // adapter-{n:06d} cycle-103 hardening\n"
    lines_needed = (content_budget // len(line.format(n=0))) + 1
    body_lines = "".join(line.format(n=i) for i in range(lines_needed))

    return header + body_lines[:content_budget] + footer


def run_one(target_bytes: int, trial_idx: int) -> dict:
    import tempfile

    prompt = make_filler_prompt(target_bytes)
    prompt_bytes = len(prompt.encode("utf-8"))

    # Argv has ARG_MAX (~128KB on Linux); pass large prompts via --input file.
    tmp = tempfile.NamedTemporaryFile(
        mode="w", suffix=".txt", prefix="spike-prompt-", delete=False, encoding="utf-8"
    )
    try:
        tmp.write(prompt)
        tmp.flush()
        tmp_path = tmp.name
    finally:
        tmp.close()

    cmd = [
        "python3",
        str(CHEVAL),
        "--agent",
        AGENT,
        "--model",
        MODEL,
        "--input",
        tmp_path,
        "--max-tokens",
        str(MAX_OUTPUT_TOKENS),
        "--timeout",
        str(TIMEOUT_SECONDS),
        "--output-format",
        "json",
        "--json-errors",
    ]

    started = time.monotonic()
    try:
        proc = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=TIMEOUT_SECONDS + 30,
            check=False,
            env={**os.environ},
        )
        elapsed = time.monotonic() - started
        rc = proc.returncode
        stdout = proc.stdout
        stderr = proc.stderr
        timeout_outer = False
    except subprocess.TimeoutExpired as exc:
        elapsed = time.monotonic() - started
        rc = -1
        stdout = exc.stdout.decode() if isinstance(exc.stdout, bytes) else (exc.stdout or "")
        stderr = exc.stderr.decode() if isinstance(exc.stderr, bytes) else (exc.stderr or "")
        timeout_outer = True
    finally:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass

    parsed_stdout = None
    if stdout.strip():
        try:
            parsed_stdout = json.loads(stdout)
        except json.JSONDecodeError:
            parsed_stdout = {"_unparsed": stdout[:500]}

    parsed_err = None
    stderr_tail = stderr.strip().splitlines()[-1] if stderr.strip() else ""
    if stderr_tail.startswith("{"):
        try:
            parsed_err = json.loads(stderr_tail)
        except json.JSONDecodeError:
            parsed_err = None

    content = None
    finish_reason = None
    if isinstance(parsed_stdout, dict):
        content = parsed_stdout.get("content")
        finish_reason = parsed_stdout.get("finish_reason")

    outcome = "success" if rc == 0 and content else (
        "timeout" if timeout_outer else ("error" if rc != 0 else "empty_content")
    )

    return {
        "trial": trial_idx,
        "target_bytes": target_bytes,
        "actual_prompt_bytes": prompt_bytes,
        "model": MODEL,
        "exit_code": rc,
        "outcome": outcome,
        "elapsed_seconds": round(elapsed, 3),
        "content_len": len(content) if content else 0,
        "finish_reason": finish_reason,
        "error": parsed_err,
        "stderr_tail": stderr_tail[:500],
    }


def main() -> int:
    if not CHEVAL.exists():
        print(f"FATAL: cheval not found at {CHEVAL}", file=sys.stderr)
        return 2

    if not os.environ.get("GOOGLE_API_KEY"):
        print("FATAL: GOOGLE_API_KEY not set in environment", file=sys.stderr)
        return 2

    records = []
    print(f"# T1.0 httpx large-body spike — model={MODEL}")
    print(f"# Writing raw results to {RESULTS_PATH}")
    print()
    print(f"{'size_kb':>8}  {'prompt_b':>10}  {'rc':>3}  {'outcome':>14}  {'elapsed_s':>10}  {'content_len':>11}  {'finish_reason':>14}")
    print("-" * 95)

    with RESULTS_PATH.open("w") as fh:
        for idx, target in enumerate(TARGET_SIZES, start=1):
            result = run_one(target, idx)
            records.append(result)
            fh.write(json.dumps(result) + "\n")
            fh.flush()
            print(
                f"{target // 1000:>5}KB  "
                f"{result['actual_prompt_bytes']:>10}  "
                f"{result['exit_code']:>3}  "
                f"{result['outcome']:>14}  "
                f"{result['elapsed_seconds']:>10}  "
                f"{result['content_len']:>11}  "
                f"{str(result['finish_reason'])[:14]:>14}"
            )

    print()
    successes = sum(1 for r in records if r["outcome"] == "success")
    errors = [r for r in records if r["outcome"] != "success"]
    print(f"# Summary: {successes}/{len(records)} succeeded.")
    if errors:
        print("# Failures:")
        for r in errors:
            err_code = (r["error"] or {}).get("code", "n/a")
            err_msg = (r["error"] or {}).get("message", r["stderr_tail"])[:120]
            print(f"#   {r['target_bytes']//1000}KB: exit={r['exit_code']} code={err_code} msg={err_msg}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
