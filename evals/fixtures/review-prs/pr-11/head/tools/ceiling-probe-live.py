#!/usr/bin/env python3
"""ceiling-probe-live.py — binary-search the safe input size for an Anthropic model.

cycle-124 Sprint 1 Task 1.8 (SDD §2.5 / §6). The catalog ships
`effective_input_ceiling: 180000` as `kf_derived` (the streaming-probed
KF-002 ceiling). This probe measures it on a real account under the same
transport cheval uses (streaming) and emits a JSON record the operator pastes
into grimoires/loa/reports/2026-09-17-cycle-124-catalog-evidence.md and into
`ceiling_calibration` (source: empirical_probe, calibrated_at, sample_size).

Usage:
  ANTHROPIC_API_KEY=... tools/ceiling-probe-live.py --model claude-opus-5 \
      [--max-tokens-probe 200000] [--min-tokens-probe 32000] [--budget-usd 1.5] \
      [--output probe.json]

Exit codes: 0 probe completed · 1 a call failed for a non-size reason ·
2 usage · 3 the budget cap stopped the bisection (`partial: true` — the
record is still written but is NOT full evidence). A call is OK when the
stream reaches `message_stop`
without an error event — NOT when a text block arrives: default-on thinking
(Opus 5 / Fable) can spend a small `max_tokens` entirely on reasoning, which
is a budget outcome, not a size failure (review round-1 medium 7). Each call
asks for up to 1024 output tokens and records `stop_reason`; the cost is
still dominated by input: 200K tokens on Opus 5 ≈ $1.00 per call; the budget
cap stops the search (largest OK so far is still reported, `partial: true`,
exit 3).

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


_DEFAULT_CATALOG = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                                ".claude", "defaults", "model-config.yaml")
_TIERS = ("unverified", "1", "2", "3", "4", "custom")


def _indent(line: str) -> int:
    return len(line) - len(line.lstrip(" "))


def write_catalog(text: str, model: str, *, ceiling: int, calibrated_at: str, sample_size: int,
                  tier: str = "unverified", itpm: int | None = None) -> str:
    """cycle-126 FR-1.1 (SDD D-1.1): fold one probe result into the catalog
    TEXT — a line-level edit inside the model's block so every comment and
    every other entry stay byte-identical. Sets `effective_input_ceiling`,
    `ceiling_calibration` (source empirical_probe, calibrated_at, sample_size)
    and `account_limits` (tier, itpm). Raises ValueError when the block or a
    required field is missing (never guesses a location)."""
    if tier not in _TIERS:
        raise ValueError(f"tier must be one of {_TIERS}, got {tier!r}")
    lines = text.split("\n")
    start = next((i for i, l in enumerate(lines) if l.rstrip() == f"      {model}:"), None)
    if start is None:
        raise ValueError(f"{model}: no `      {model}:` block in the catalog")
    end = start + 1
    while end < len(lines) and (lines[end].strip() == "" or _indent(lines[end]) > 6):
        end += 1
    block = lines[start:end]

    def _find(prefix: str, indent: int) -> int:
        for i, l in enumerate(block):
            if _indent(l) == indent and l.strip().startswith(prefix):
                return i
        raise ValueError(f"{model}: `{prefix.rstrip(':')}` not found in the entry")

    def _set_scalar(i: int, key: str, value: str) -> None:
        # keep an inline comment when the line carries one
        comment = ""
        if "#" in block[i]:
            comment = "   #" + block[i].split("#", 1)[1]
        block[i] = f"{' ' * _indent(block[i])}{key}: {value}{comment}"

    _set_scalar(_find("effective_input_ceiling:", 8), "effective_input_ceiling", str(int(ceiling)))

    def _nested(head_prefix: str, wanted: dict) -> None:
        h = _find(head_prefix, 8)
        j = h + 1
        seen = set()
        while j < len(block) and (block[j].strip() == "" or _indent(block[j]) > 8):
            key = block[j].strip().split(":", 1)[0]
            if _indent(block[j]) == 10 and key in wanted:
                _set_scalar(j, key, wanted[key])
                seen.add(key)
            j += 1
        insert_at = j
        while insert_at > h + 1 and block[insert_at - 1].strip() == "":
            insert_at -= 1
        for key, value in wanted.items():
            if key not in seen:
                block.insert(insert_at, f"          {key}: {value}")
                insert_at += 1

    _nested("ceiling_calibration:", {"source": "empirical_probe", "calibrated_at": f'"{calibrated_at}"',
                                     "sample_size": str(int(sample_size))})
    try:
        _find("account_limits:", 8)
    except ValueError:
        cal = _find("ceiling_calibration:", 8)
        j = cal + 1
        while j < len(block) and (block[j].strip() == "" or _indent(block[j]) > 8):
            j += 1
        block.insert(j, "        account_limits:")
    _nested("account_limits:", {"tier": f'"{tier}"', "itpm": ("null" if itpm is None else str(int(itpm)))})
    return "\n".join(lines[:start] + block + lines[end:])


def _write_catalog_file(path: str, model: str, record: dict, tier: str, itpm: int | None) -> None:
    import tempfile
    with open(path, "r", encoding="utf-8") as fh:
        text = fh.read()
    new = write_catalog(text, model, ceiling=record["largest_ok_input_tokens"], calibrated_at=record["calibrated_at"],
                        sample_size=record["sample_size"], tier=tier, itpm=itpm)
    fd, tmp = tempfile.mkstemp(prefix=".model-config.", suffix=".tmp", dir=os.path.dirname(os.path.abspath(path)))
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(new)
    os.replace(tmp, path)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--model", required=True)
    ap.add_argument("--max-tokens-probe", type=int, default=200_000)
    ap.add_argument("--min-tokens-probe", type=int, default=32_000)
    ap.add_argument("--budget-usd", type=float, default=1.5)
    ap.add_argument("--output", default="-")
    # cycle-126 FR-1.1 (SDD D-1.1): one operator run sets calibrated_at, the
    # calibrated value and account_limits in the catalog (refused on a partial
    # bisection unless --allow-partial says the operator accepts it).
    ap.add_argument("--write-catalog", nargs="?", const=_DEFAULT_CATALOG, default=None, metavar="PATH")
    ap.add_argument("--tier", default="unverified", choices=_TIERS)
    ap.add_argument("--itpm", type=int, default=None)
    ap.add_argument("--allow-partial", action="store_true")
    args = ap.parse_args()

    key = os.environ.get("ANTHROPIC_API_KEY")
    if not key:
        print("ceiling-probe-live: ANTHROPIC_API_KEY is required", file=sys.stderr)
        return 2
    if args.min_tokens_probe >= args.max_tokens_probe:
        print("ceiling-probe-live: --min-tokens-probe must be below --max-tokens-probe", file=sys.stderr)
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
        print(f"ceiling-probe-live: {e}", file=sys.stderr)
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
        print(f"ceiling-probe-live: wrote {args.output} (largest_ok={largest_ok}, spent=${record['spent_usd']})", file=sys.stderr)
    if args.write_catalog:
        if partial and not args.allow_partial:
            print("ceiling-probe-live: partial record — not written to the catalog (pass --allow-partial to accept it)", file=sys.stderr)
            return 3
        if largest_ok <= 0:
            print("ceiling-probe-live: no successful probe — nothing to write", file=sys.stderr)
            return 1
        try:
            _write_catalog_file(args.write_catalog, args.model, record, args.tier, args.itpm)
        except (OSError, ValueError, KeyError) as e:
            print(f"ceiling-probe-live: catalog not written: {e}", file=sys.stderr)
            return 1
        print(f"ceiling-probe-live: {args.write_catalog}: {args.model} effective_input_ceiling={largest_ok} "
              f"calibrated_at={record['calibrated_at']} account_limits.tier={args.tier}; regenerate: "
              f"bash .claude/scripts/gen-adapter-maps.sh && npm --prefix .claude/skills/bridgebuilder-review run build",
              file=sys.stderr)
    if partial:
        print("ceiling-probe-live: budget cap stopped the bisection — partial record (exit 3)", file=sys.stderr)
        return 3
    return 0


if __name__ == "__main__":
    sys.exit(main())
