#!/usr/bin/env python3
"""ceiling-probe.py — binary-search the safe input size for an Anthropic model.

cycle-124 Sprint 1 Task 1.8 (SDD §2.5 / §6). The catalog ships
`effective_input_ceiling: 180000` as `kf_derived` (the streaming-probed
KF-002 ceiling). This probe measures it on a real account under the same
transport cheval uses (streaming) and emits a JSON record the operator pastes
into grimoires/loa/reports/2026-09-17-cycle-124-catalog-evidence.md and into
`ceiling_calibration` (source: empirical_probe, calibrated_at, sample_size).

Usage:
  ANTHROPIC_API_KEY=... tools/ceiling-probe.py --model claude-opus-5 \
      [--max-tokens-probe 200000] [--min-tokens-probe 32000] [--budget-usd 1.5] \
      [--output probe.json]

Exit codes: 0 probe completed · 1 a call failed for a non-size reason ·
2 usage / budget exceeded. A call is OK when the stream reaches `message_stop`
without an error event — NOT when a text block arrives: default-on thinking
(Opus 5 / Fable) can spend a small `max_tokens` entirely on reasoning, which
is a budget outcome, not a size failure (review round-1 medium 7). Each call
asks for up to 1024 output tokens and records `stop_reason`; the cost is
still dominated by input: 200K tokens on Opus 5 ≈ $1.00 per call; the budget
cap stops the search (largest OK so far is still reported, `partial: true`).

Never run this from a test without LOA_RUN_LIVE_TESTS=1 — it spends money.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import sys
import urllib.error
import urllib.request

API = "https://api.anthropic.com/v1/messages"
_PRICE_IN = {"claude-opus-5": 5_000_000, "claude-fable-5-1": 10_000_000, "claude-sonnet-5": 2_000_000,
             "claude-opus-4-8": 5_000_000, "claude-haiku-4-5-20251001": 1_000_000}
_FILLER = "The quick brown fox jumps over the lazy dog. "  # ≈ 10 tokens


def _probe_once(model: str, tokens: int, key: str) -> tuple[bool, str, str | None]:
    """Stream one request with ≈`tokens` input tokens.

    Returns (ok, detail, stop_reason): ok iff the stream reached `message_stop`
    with no error event — the request was accepted at this size whatever the
    model chose to do with its output budget."""
    body = {
        "model": model, "max_tokens": 1024, "stream": True,
        "messages": [{"role": "user", "content": _FILLER * (tokens // 10) + "\n\nReply: ok."}],
    }
    req = urllib.request.Request(
        API, data=json.dumps(body).encode(), method="POST",
        headers={"x-api-key": key, "anthropic-version": "2023-06-01", "content-type": "application/json",
                 "accept": "text/event-stream"},
    )
    try:
        with urllib.request.urlopen(req, timeout=300) as resp:
            saw_stop, stop_reason = False, None
            for raw in resp:
                line = raw.decode("utf-8", errors="replace").strip()
                if not line.startswith("data: "):
                    continue
                try:
                    event = json.loads(line[6:])
                except json.JSONDecodeError:
                    continue
                kind = event.get("type")
                if kind == "error":
                    return False, line[:300], None
                if kind == "message_delta":
                    stop_reason = (event.get("delta") or {}).get("stop_reason") or stop_reason
                if kind == "message_stop":
                    saw_stop = True
            if saw_stop:
                return True, "", stop_reason
            return False, "stream ended before message_stop (transport / truncation class)", stop_reason
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")[:300]
        if e.code in (400, 413) and ("too long" in detail or "exceed" in detail or "maximum" in detail):
            return False, f"HTTP {e.code}: {detail}", None
        raise RuntimeError(f"HTTP {e.code} (non-size failure): {detail}")
    except (urllib.error.URLError, TimeoutError, ConnectionError) as e:
        return False, f"transport: {e}", None


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--model", required=True)
    ap.add_argument("--max-tokens-probe", type=int, default=200_000)
    ap.add_argument("--min-tokens-probe", type=int, default=32_000)
    ap.add_argument("--budget-usd", type=float, default=1.5)
    ap.add_argument("--output", default="-")
    args = ap.parse_args()

    key = os.environ.get("ANTHROPIC_API_KEY")
    if not key:
        print("ceiling-probe: ANTHROPIC_API_KEY is required", file=sys.stderr)
        return 2
    if args.min_tokens_probe >= args.max_tokens_probe:
        print("ceiling-probe: --min-tokens-probe must be below --max-tokens-probe", file=sys.stderr)
        return 2

    price_in = _PRICE_IN.get(args.model, 10_000_000)
    spent_micro = 0
    lo, hi = args.min_tokens_probe, args.max_tokens_probe
    largest_ok, smallest_fail, samples, partial = 0, None, [], False

    def within_budget(tokens: int) -> bool:
        return spent_micro + tokens * price_in // 1_000_000 <= args.budget_usd * 1_000_000

    try:
        # Anchor the top first: if the max works, the ceiling is at least that.
        for tokens in (hi,):
            if not within_budget(tokens):
                partial = True
                break
            ok, why, stop_reason = _probe_once(args.model, tokens, key)
            spent_micro += tokens * price_in // 1_000_000
            samples.append({"tokens": tokens, "ok": ok, "stop_reason": stop_reason, "detail": why})
            if ok:
                largest_ok = tokens
            else:
                smallest_fail = tokens
        while largest_ok < hi and smallest_fail is not None and smallest_fail - max(largest_ok, lo) > 8_000:
            mid = (max(largest_ok, lo) + smallest_fail) // 2
            if not within_budget(mid):
                partial = True
                break
            ok, why, stop_reason = _probe_once(args.model, mid, key)
            spent_micro += mid * price_in // 1_000_000
            samples.append({"tokens": mid, "ok": ok, "stop_reason": stop_reason, "detail": why})
            if ok:
                largest_ok = mid
            else:
                smallest_fail = mid
    except RuntimeError as e:
        print(f"ceiling-probe: {e}", file=sys.stderr)
        return 1

    record = {
        "model": args.model,
        "transport": "streaming",
        "source": "empirical_probe",
        "calibrated_at": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "sample_size": len(samples),
        "largest_ok_input_tokens": largest_ok,
        "smallest_failed_input_tokens": smallest_fail,
        "partial": partial,
        "spent_usd": round(spent_micro / 1_000_000, 4),
        "samples": samples,
    }
    text = json.dumps(record, indent=2)
    if args.output == "-":
        print(text)
    else:
        with open(args.output, "w") as fh:
            fh.write(text + "\n")
        print(f"ceiling-probe: wrote {args.output} (largest_ok={largest_ok}, spent=${record['spent_usd']})", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
