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

cycle-127 FR-3 (SDD D-3.1/D-3.2, D-3.5…D-3.9): `--transport claude-headless`
measures the bound through the headless CLI instead (no API key; e.g. this
host's Bedrock route via CLAUDE_HEADLESS_BIN=$HOME/.local/bin/claude-bedrock):

  CLAUDE_HEADLESS_BIN=... tools/ceiling-probe-live.py --model claude-opus-5-5 \
      --transport claude-headless --cli-model opus [--host-route TEXT] \
      [--tolerance-tokens 16000] [--write-catalog]

Each attempt runs the headless adapter's own argv (claude_headless_adapter.
build_headless_argv) plus `--effort low --max-turns 1` — the probe bypasses
cheval, so FR-2's catalog effort default does NOT apply; low effort and one
turn keep the output side negligible. The prompt goes on stdin, the cwd is a
private empty directory, auto memory is off. The prompt ends with a random
12-hex needle; an attempt is ACCEPTED only when the completed JSON `result`
echoes it (a completed turn without it is `unverified`, never OK). The
accepted size is MEASURED from the CLI's JSON usage (input_tokens +
cache_creation_input_tokens + cache_read_input_tokens), not the filler size.
Every size is in MEASURED tokens (`size_unit: measured_tokens` in the
record): --max-tokens-probe / --min-tokens-probe / --tolerance-tokens, the
bisection targets, `largest_ok_input_tokens` and
`smallest_failed_input_tokens`; the filler actually sent per step is rescaled
by the latest measured/filler ratio and recorded beside it (`tokens`).

The classifier reads the FULL diagnostic (at most the 1 MB capture; only
the record's `detail` is truncated to 300 chars). A context-limit message
(the provider's, or the CLI's own pre-flight check) is a size rejection.
Throttling / 429 / 5xx (a status in context: `API Error: 5xx`, `HTTP 5xx`,
`status 5xx`, `api_status=5xx`) / network is retried up to 3 attempts after
5 s / 15 s; a token-budget 429 (tokens per minute) up to 4 attempts after
20 s / 45 s / 75 s so the 60 s window clears, a `retry-after` hint honoured
when longer, the total wait per step capped at 180 s. A token-budget 429 that
persists over every attempt once the window was waited out is a size
rejection (`failure_class: token_limit`); any other persisting transient,
and anything else, is `other`. An exception inside the classifier is
`other` with its text — never a traceback that loses the record; a ^C or
an unexpected exception during the bisection still writes the record
(`stop: interrupted`, `interrupted`: the exception, outcome `partial`, exit
130 / 1, never a catalog write). A throttle marker (`throttl`, `please wait`,
a 429 status, `rate limit`, `tokens per min`) on a message that also names
tokens or a context limit — Bedrock's "Too many tokens, please wait before
trying again" — is a token-budget transient, never a size rejection; a bound
bracketed by anything but a context-limit rejection is `partial`. A
timeout kills the CLI's whole process group (the route is a wrapper around
`claude`; loa_cheval's run_subprocess_pgkill), and output past the 1 MB cap
is `other`, never truncated into a classification. --allow-partial / --tier
/ --itpm are api-transport flags: a usage error here (exit 2, no call).

Spend (`spent_usd`, per sample `charged_usd` + `charge_basis`) is what each
attempt plausibly cost, at the catalog input price × 1.25 — the cache-write
rate the CLI is billed at for the prompt (`pricing_basis: catalog_estimate`,
`estimate_rate`; Bedrock bills separately):
  completion (ok / unverified)      max(CLI total_cost_usd, measured × price)
  cli_local_rejection               0 (the CLI's own pre-flight; never sent)
  provider rejection / transient    the CLI-reported cost if > 0, else 0
                                    (`cli_reported` / `provider_rejection_unbilled`)
  a failure carrying usage          max(CLI cost, measured × price) (`usage_reported`)
  timeout / classifier error /      the estimate (the request may have run)
  output past the cap / interrupted
  not sent (spawn failed)           0
The budget cap is checked BEFORE every attempt against the estimate
(target × price): what an attempt will cost is unknown until it returns.

Outcome `clean` = the largest accepted step is verified, a size rejection
sits within --tolerance-tokens above it, and nothing was `other`,
unverified, budget-capped or inconsistent; anything else is `partial`
(exit 3; exit 1 when an `other` failure stopped it). The record is always
written; only `clean` with `--write-catalog` touches the catalog — unless --write-partial-as-operator-set says the
operator vouches for the last verified accept (the entry then carries
`probe_outcome: partial`; the exit code still reports the partial probe).
Every write records `ceiling_calibration.probe_outcome` (clean | partial) and
`sample_size` = the record's sample count (accepted + rejected). With --write-catalog the entry's write
prerequisites (the block, a positive `context_window`, `probed_ceiling`,
`effective_input_ceiling`, `ceiling_calibration`) are checked before the
first call — exit 2, no spend, when one is missing. The write is the I2
clamp of the measured accept:
  written = min(measured, context_window − default_max_tokens)
(cheval's invariant `effective_input_ceiling + default max_tokens ≤
context_window`, default_max_tokens from the entry's max_output_tokens, the
streaming default regardless of the operator's switches; no other margin; a
bound below 180K is written as measured, never kept) into `probed_ceiling`
and `effective_input_ceiling` — the record's `written_ceiling` — with the raw
accept kept in `ceiling_calibration.measured_input_tokens` and
`ceiling_calibration` {source: operator_set, method: probed_headless,
transport, cli_version, cli_model, measured_input_tokens, …}.

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
import re
import shutil
import subprocess
import sys
import tempfile
import traceback
import urllib.error
import urllib.request

API = "https://api.anthropic.com/v1/messages"
# micro-USD per input MTok (the catalog's pricing.input_per_mtok). Bedrock bills
# separately; the CLI transport records `pricing_basis: catalog_estimate`.
_PRICE_IN = {"claude-opus-5-5": 4_000_000, "claude-opus-5": 5_000_000, "claude-fable-5-1": 10_000_000, "claude-sonnet-5": 2_000_000,
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


_ADAPTERS_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), ".claude", "adapters")
_CAPTURE_CAP = 1 << 20          # bytes kept of a CLI's stdout / stderr
_ATTEMPTS = 3                   # per step, for transient classes only
_BACKOFF_S = (5, 15)            # 5xx / network / throttling: sleep before attempt 2, 3
# A token-budget 429 (tokens per minute) cannot clear in 5 s / 15 s: wait the
# 60 s window out (r251-1 P2), honour a longer retry-after hint, cap the total.
_TPM_ATTEMPTS = 4
_TPM_BACKOFF_S = (20, 45, 75)   # sleep before attempt 2, 3, 4 (cumulative 140 s)
_TPM_WINDOW_S = 60
if sum(_TPM_BACKOFF_S) < _TPM_WINDOW_S:  # r251-2 Q7: the schedule alone clears the window
    raise RuntimeError("ceiling-probe-live: _TPM_BACKOFF_S must sum to at least _TPM_WINDOW_S")
_RETRY_WAIT_CAP_S = 180         # total sleep per step, every class
_RETRY_AFTER = re.compile(r"retry[-_ ]after\W{0,4}(\d+(?:\.\d+)?)", re.I)
# A throttle marker (verifier r251-1): Bedrock's token throttle reads "Too many
# tokens, please wait before trying again" — it carries the context marker
# `too many tokens`, so a throttle marker must win or the first throttle is a
# size rejection with no retry. `429` is matched as a status, never inside a
# token count ("429,000 tokens", "1,429.5k"); a status followed by punctuation
# ("API Error: 429. Too many tokens") is still a status (r251-2 Q1).
_THROTTLE = re.compile(r"throttl|please wait|(?<![\d,.])429(?!\d|[,.]\d)|rate limit|tokens per min", re.I)
_SLEEP = __import__("time").sleep
# `opus` / `sonnet` / `haiku` are resolved by the claude CLI itself from these
# pins (the claude-bedrock wrapper exports them); recorded when visible.
_CLI_ALIAS_ENV = {"opus": "ANTHROPIC_DEFAULT_OPUS_MODEL", "sonnet": "ANTHROPIC_DEFAULT_SONNET_MODEL",
                  "haiku": "ANTHROPIC_DEFAULT_HAIKU_MODEL"}
# Beyond the adapter's own RateLimitError class: ProviderUnavailableError is the
# adapter's catch-all, transient only when the diagnostic names one of these.
_TRANSIENT_MARKERS = ("throttl", "timeout", "timed out", "connection", "network", "econnreset", "socket",
                      "service unavailable", "internal server error", "bad gateway", "overloaded")
# A 5xx only in a status context (r251-1 P8): a bare 3-digit number ("took 503 ms") is not one.
_STATUS_5XX = re.compile(r"(?:\bapi error\b|\bhttp(?:/[\d.]+)?|\bstatus(?:[ _]code)?|api_status=|"
                         r"api_error_status[\"']?)[\s:=]*5\d\d\b", re.I)
# Explicit provider markers only: a bare 4xx pattern matched the CLI's own token
# counts ("Prompt is too long: 403,000 tokens > …") as provider-origin.
_PROVIDER_ORIGIN = __import__("re").compile(r"api error|api_status=|api_error_status|invalid_request_error|"
                                            r"validationexception|\b(?:http|status)[ :]+4\d\d\b", __import__("re").I)


def _adapters():
    """The one import seam into cheval (tools/ is not a package): the adapters
    directory is located from THIS file and put on sys.path explicitly, so the
    probe works from any cwd and under `python3 -I` (never via cwd)."""
    if _ADAPTERS_DIR not in sys.path:
        sys.path.insert(0, _ADAPTERS_DIR)
    from loa_cheval.providers import claude_headless_adapter
    from loa_cheval.routing import ceiling
    from loa_cheval import types as cheval_types
    return claude_headless_adapter, ceiling, cheval_types


def _cli_bin() -> str:
    return os.environ.get("CLAUDE_HEADLESS_BIN") or "claude"


def _cli_command(cli_bin: str, cli_model: str) -> list[str]:
    """The adapter's argv (prompt on stdin) + the probe's pins: --effort low --max-turns 1."""
    cha, _, _ = _adapters()
    return cha.build_headless_argv(cli_bin, cli_model, effort="low", max_turns=1)


def _resolved_cli_model(cli_model: str) -> str:
    env = _CLI_ALIAS_ENV.get(cli_model)
    return (os.environ.get(env) or cli_model) if env else cli_model


def _default_host_route(cli_bin: str) -> str:
    base = os.path.basename(cli_bin)
    if "bedrock" in base.lower() or os.environ.get("CLAUDE_CODE_USE_BEDROCK", "").strip() in ("1", "true"):
        return f"bedrock (via {base})"
    return f"claude CLI default auth (via {base})"


def _route_env() -> dict:
    """Route context for the record: region/prefix values, the Bedrock switch's presence only."""
    return {"AWS_REGION": os.environ.get("AWS_REGION"),
            "ANTHROPIC_BEDROCK_REGION_PREFIX": os.environ.get("ANTHROPIC_BEDROCK_REGION_PREFIX"),
            "CLAUDE_CODE_USE_BEDROCK": "CLAUDE_CODE_USE_BEDROCK" in os.environ}


def _cli_version(cli_bin: str) -> str | None:
    try:
        out = subprocess.run([cli_bin, "--version"], capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.TimeoutExpired):
        return None
    line = (out.stdout or "").strip().splitlines()
    return line[0][:120] if out.returncode == 0 and line else None


def _attempt_timeout(tokens: int) -> int:
    return min(1800, 120 + tokens // 2000)


def _measured(usage) -> int | None:
    if not isinstance(usage, dict):
        return None
    total = sum(v for k, v in usage.items()
                if k in ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens")
                and isinstance(v, int) and not isinstance(v, bool))
    return total or None


def _run_capped(cmd: list[str], prompt: str, timeout: int) -> tuple[int, str, str]:
    """Run through loa_cheval's run_subprocess_pgkill (r251-1 P7): the child
    leads its own process group and a timeout (or any exception, ^C included)
    SIGKILLs the GROUP — the route is usually a wrapper (claude-bedrock) around
    `claude`, and subprocess.run(timeout=) kills only the direct child. Output
    past the 1 MB per-stream cap raises SubprocessOutputCapExceeded (the group
    killed first) instead of truncating: a truncated answer never classifies;
    the step maps it to `other`."""
    _adapters()
    from loa_cheval.providers.base import run_subprocess_pgkill
    workspace = tempfile.mkdtemp(prefix="loa-ceiling-probe-")
    env = {**os.environ, "CLAUDE_CODE_DISABLE_AUTO_MEMORY": "1"}
    try:
        proc = run_subprocess_pgkill(cmd, input=prompt, timeout=timeout, env=env, max_bytes=_CAPTURE_CAP,
                                     cwd=workspace)
        return proc.returncode, proc.stdout, proc.stderr
    finally:
        shutil.rmtree(workspace, ignore_errors=True)


_DETAIL_CHARS = 300             # the record's `detail`; classification reads the full text


def _classify(rc: int, stdout: str, stderr: str, needle: str) -> dict:
    """One attempt → {kind: ok|unverified|size|transient|other, …}. Never raises
    (r251-1 P5): an exception inside classification is `other` with its text."""
    try:
        return _classify_unguarded(rc, stdout, stderr, needle)
    except Exception as e:  # noqa: BLE001 — the record must survive any classifier defect
        return {"kind": "other", "classifier_error": True, "measured_input_tokens": None,
                "cli_reported_cost_usd": None, "stop_reason": None,
                "detail": f"classifier error: {type(e).__name__}: {e}"[:_DETAIL_CHARS]}


def _classify_unguarded(rc: int, stdout: str, stderr: str, needle: str) -> dict:
    cha, ceiling, t = _adapters()
    stdout, stderr = stdout[:_CAPTURE_CAP], stderr[:_CAPTURE_CAP]
    try:
        parsed = json.loads(stdout) if stdout.strip() else None
    except json.JSONDecodeError:
        parsed = None
    usage = parsed.get("usage") if isinstance(parsed, dict) else None
    base = {"measured_input_tokens": _measured(usage),
            "cli_reported_cost_usd": parsed.get("total_cost_usd") if isinstance(parsed, dict) else None,
            "stop_reason": parsed.get("stop_reason") if isinstance(parsed, dict) else None}
    if rc == 0 and isinstance(parsed, dict) and not parsed.get("is_error"):
        result = str(parsed.get("result") or "")
        if needle in result:
            return {**base, "kind": "ok", "detail": ""}
        return {**base, "kind": "unverified", "detail": f"completed without the needle: {result[:120]!r}"}
    if not isinstance(parsed, dict):
        if rc == 0:
            return {**base, "kind": "other", "detail": f"non-JSON output: {stdout.strip()[:200]!r}"}
    result = str(parsed.get("result") or "") if isinstance(parsed, dict) and parsed.get("is_error") else ""
    api_status = parsed.get("api_error_status") if isinstance(parsed, dict) else None
    full = " ".join(x for x in (result, f"(api_status={api_status})" if api_status else "", stderr.strip()) if x)
    full = (full or stdout.strip() or f"exit code {rc}, no diagnostic")[:_CAPTURE_CAP]
    diag = full[:_DETAIL_CHARS]          # for the record only (r251-1 P4)
    hint = _RETRY_AFTER.search(full)
    if hint:
        base["retry_after_s"] = float(hint.group(1))
    # r251-2 Q1: the throttle verdict reads the CLI's own answer (result + api_status);
    # stderr decides only when there is no result, so a stale "rate limit … please
    # wait" line on stderr cannot turn a genuine context-limit result into a transient
    throttle_text = " ".join(x for x in (result, f"(api_status={api_status})" if api_status else "") if x) \
        if result else full
    if _THROTTLE.search(throttle_text) and (ceiling.is_context_limit_message(full)
                                            or ceiling.is_token_limit_message(full)):
        # a token throttle, even when it also reads like a context limit: retried on the TPM schedule
        return {**base, "kind": "transient", "token_limit": True, "detail": diag}
    if ceiling.is_context_limit_message(full):
        origin = "provider" if (api_status or _PROVIDER_ORIGIN.search(full)) else "cli_local"
        return {**base, "kind": "size", "failure_class": "context_limit", "size_origin": origin, "detail": diag,
                "rejected_input_tokens": ceiling.parse_context_limit(full).get("input_tokens")}
    if ceiling.is_token_limit_message(full):
        # a token-budget 429: retried as transient; persisting at this size it is a size rejection
        return {**base, "kind": "transient", "token_limit": True, "detail": diag}
    try:
        cha.ClaudeHeadlessAdapter._raise_for_error(__import__("types").SimpleNamespace(provider="claude-headless"),
                                                   returncode=rc, stderr=stderr, parsed=parsed)
    except t.RateLimitError:
        return {**base, "kind": "transient", "detail": diag}
    except t.ProviderUnavailableError:
        low = full.lower()
        if any(m in low for m in _TRANSIENT_MARKERS) or _STATUS_5XX.search(full):
            return {**base, "kind": "transient", "detail": diag}
        return {**base, "kind": "other", "detail": diag}
    except Exception:  # noqa: BLE001 — auth / config classes: not transient, not size
        return {**base, "kind": "other", "detail": diag}
    return {**base, "kind": "other", "detail": diag}


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


def _catalog_default_output(max_output) -> int:
    """The default output budget the catalog invariant is checked against:
    cheval's own default_max_tokens (providers/base.py — the rule
    test_anthropic_catalog_floor._default_max_tokens mirrors) with the
    streaming/legacy switches cleared, so an operator running the probe with
    streaming disabled does not loosen the bound (the env is restored)."""
    _adapters()
    from loa_cheval.providers.base import default_max_tokens
    saved = {k: os.environ.pop(k) for k in ("LOA_CHEVAL_DISABLE_STREAMING", "LOA_CHEVAL_LEGACY_WIRE") if k in os.environ}
    try:
        return default_max_tokens(provider="anthropic", model_max_output=max_output)
    finally:
        os.environ.update(saved)


def i2_clamped(text: str, model: str, measured: int) -> tuple[int, int, int]:
    """(written, context_window, default_output): the bound a probe may write,
    min(measured, context_window − default_max_tokens(entry)) — I2, the
    catalog invariant `effective_input_ceiling + default max_tokens ≤
    context_window` (cycle-127 fr23b; the live probe measured 972,887 on a 1M
    window). ValueError when the entry has no context_window."""
    lines = text.split("\n")
    start = next((i for i, l in enumerate(lines) if l.rstrip() == f"      {model}:"), None)
    if start is None:
        raise ValueError(f"{model}: no `      {model}:` block in the catalog")
    fields: dict = {}
    for l in lines[start + 1:]:
        if l.strip() and _indent(l) <= 6:
            break
        if _indent(l) == 8 and ":" in l and not l.strip().startswith("#"):
            k, v = l.strip().split(":", 1)
            fields[k] = v.split("#", 1)[0].strip()
    cw = fields.get("context_window", "")
    if not cw.isdigit() or int(cw) <= 0:
        raise ValueError(f"{model}: no positive context_window in the entry — cannot apply the I2 clamp")
    mo = fields.get("max_output_tokens", "")
    default_out = _catalog_default_output(int(mo) if mo.isdigit() else None)
    return min(int(measured), int(cw) - default_out), int(cw), default_out


def write_catalog_operator_set(text: str, model: str, *, ceiling: int, calibrated_at: str, cli_model: str,
                               host_route: str, probe_outcome: str, sample_size: int,
                               cli_version: str | None = None, transport: str = "claude-headless",
                               force_partial: bool = False) -> str:
    """cycle-127 FR-3.2 (SDD D-3.2, D-3.8): fold a CLI-transport bound into the
    catalog TEXT as `operator_set` — `probed_ceiling` and
    `effective_input_ceiling` (a calibrated entry is bounded by the latter,
    routing/ceiling.input_bound) = min(`ceiling` — the measured accepted size,
    no margin, as the api transport — , context_window − default max_tokens)
    (the I2 clamp, i2_clamped; a value below the old bound is written, never
    max()-ed); `measured_input_tokens` keeps the raw measurement; `ceiling_calibration {source, method: probed_headless,
    transport, cli_version, cli_model, measured_input_tokens, calibrated_at,
    sample_size, probe_outcome, stale_after_days (kept, else 90), reprobe_trigger}`;
    the entry's `loa:shortcut` ceiling comment becomes one provenance comment.
    Line-level, inside the model's block only; ValueError when a field is missing.

    r251-1 P12: `probe_outcome` (clean | partial) and `sample_size` (the record's
    sample count, accepted + rejected) are REQUIRED — no caller can claim a clean
    probe by default. A `partial` record is refused unless `force_partial=True`
    (--write-partial-as-operator-set: the operator vouches for the last verified
    accept, and the entry says `probe_outcome: partial`)."""
    if probe_outcome not in ("clean", "partial"):
        raise ValueError(f"{model}: probe_outcome must be 'clean' or 'partial', got {probe_outcome!r}")
    if probe_outcome == "partial" and not force_partial:
        raise ValueError(f"{model}: a partial probe record is not written as operator_set without "
                         f"force_partial=True (--write-partial-as-operator-set)")
    if isinstance(sample_size, bool) or not isinstance(sample_size, int) or sample_size < 0:
        raise ValueError(f"{model}: sample_size must be a non-negative integer, got {sample_size!r}")
    lines = text.split("\n")
    start = next((i for i, l in enumerate(lines) if l.rstrip() == f"      {model}:"), None)
    if start is None:
        raise ValueError(f"{model}: no `      {model}:` block in the catalog")
    if isinstance(ceiling, bool) or not isinstance(ceiling, int) or ceiling <= 0:
        raise ValueError(f"{model}: ceiling must be a positive integer, got {ceiling!r}")
    end = start + 1
    while end < len(lines) and (lines[end].strip() == "" or _indent(lines[end]) > 6):
        end += 1
    block = lines[start:end]

    def _find(prefix: str, indent: int, lo: int = 0, hi: int | None = None) -> int:
        for i in range(lo, len(block) if hi is None else hi):
            if _indent(block[i]) == indent and block[i].strip().startswith(prefix):
                return i
        raise ValueError(f"{model}: `{prefix.rstrip(':')}` not found in the entry")

    def _set_scalar(i: int, key: str, value: str) -> None:
        comment = "   #" + block[i].split("#", 1)[1] if "#" in block[i] else ""
        block[i] = f"{' ' * _indent(block[i])}{key}: {value}{comment}"

    day = calibrated_at[:10]
    route = "Bedrock" if "bedrock" in host_route.lower() else host_route
    trigger = (f"API-transport probe (tools/ceiling-probe-live.py --transport api) from a host with "
               f"ANTHROPIC_API_KEY; this bound was measured through claude-headless on {route} ({cli_model}) on {day}")
    measured = ceiling
    written, cw, default_out = i2_clamped(text, model, measured)
    _set_scalar(_find("effective_input_ceiling:", 8), "effective_input_ceiling", str(written))
    _set_scalar(_find("probed_ceiling:", 8), "probed_ceiling", str(written))
    h = _find("ceiling_calibration:", 8)
    j = h + 1
    while j < len(block) and (block[j].strip() == "" or _indent(block[j]) > 8):
        j += 1
    stale = 90
    try:
        raw = block[_find("stale_after_days:", 10, h + 1, j)].split(":", 1)[1].split("#", 1)[0].strip()
        stale = int(raw) if raw.isdigit() and int(raw) > 0 else 90
    except ValueError:
        pass
    new_cal = ["        ceiling_calibration:", "          source: operator_set",
               f'          calibrated_at: "{calibrated_at}"', f"          sample_size: {sample_size}",
               f"          stale_after_days: {stale}", f"          reprobe_trigger: {json.dumps(trigger)}",
               "          method: probed_headless", f"          transport: {transport}",
               f"          cli_version: {json.dumps(cli_version) if cli_version else 'null'}",
               f"          cli_model: {json.dumps(cli_model)}", f"          measured_input_tokens: {measured}",
               f"          probe_outcome: {probe_outcome}"]
    block[h:j] = new_cal
    # the shortcut marker: a `# loa:shortcut:` comment line plus its comment continuation lines
    k = next((i for i, l in enumerate(block) if _indent(l) == 8 and l.strip().startswith("# loa:shortcut:")
              and "ceiling-probe-live" in " ".join(block[i:i + 3])), None)
    clamp_note = (f"; written clamped to {written} (I2: context_window {cw} − default max_tokens {default_out}) "
                  f"from the measured {measured}") if written < measured else ""
    partial_note = ("; probe outcome partial — the operator vouches for the last verified accept"
                    if probe_outcome == "partial" else "")
    provenance = (f"        # cycle-127 FR-3: bound measured {day} by tools/ceiling-probe-live.py --transport "
                  f"claude-headless ({route}, {cli_model}){clamp_note}{partial_note}; "
                  f"see ceiling_calibration.reprobe_trigger.")
    old_prov = next((i for i, l in enumerate(block) if l.startswith("        # cycle-127 FR-3: bound measured ")), None)
    if k is not None:
        e = k + 1
        while e < len(block) and _indent(block[e]) == 8 and block[e].strip().startswith("#") \
                and not block[e].strip().startswith("# loa:"):
            e += 1
        block[k:e] = [provenance]
    elif old_prov is not None:
        block[old_prov] = provenance
    else:
        block.insert(_find("probed_ceiling:", 8), provenance)
    return "\n".join(lines[:start] + block + lines[end:])


def _write_text_atomic(path: str, new: str) -> None:
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
    ap.add_argument("--tier", default=None, choices=_TIERS, help="api transport (default unverified)")
    ap.add_argument("--itpm", type=int, default=None)
    ap.add_argument("--allow-partial", action="store_true",
                    help="api transport: write a budget-capped partial bisection to the catalog "
                         "(a usage error with --transport claude-headless: see --write-partial-as-operator-set)")
    ap.add_argument("--write-partial-as-operator-set", action="store_true",
                    help="claude-headless, with --write-catalog: write a PARTIAL record anyway — the operator "
                         "vouches for the last verified accept; the entry carries probe_outcome: partial "
                         "(the exit code still reports the partial probe)")
    # cycle-127 FR-3 (SDD D-3.1): the headless-CLI transport (default api, unchanged).
    ap.add_argument("--transport", choices=("api", "claude-headless"), default="api")
    ap.add_argument("--cli-model", default=None, help="model passed to the CLI (default: --model)")
    ap.add_argument("--host-route", default=None, help="free-text route note for the record")
    ap.add_argument("--tolerance-tokens", type=int, default=16_000,
                    help="claude-headless: stop when the accept/reject bracket is this narrow (default 16000)")
    args = ap.parse_args()

    if args.transport == "claude-headless":
        # verifier r251-1: the api-only flags are refused, never silently ignored
        for flag, used in (("--allow-partial", args.allow_partial), ("--tier", args.tier is not None),
                           ("--itpm", args.itpm is not None)):
            if used:
                print(f"ceiling-probe-live: {flag} is an api-transport flag — --transport claude-headless does not "
                      f"read it (a partial record is written only with --write-partial-as-operator-set; "
                      f"account_limits are left alone); no call made", file=sys.stderr)
                return 2
        return _main_cli(args)
    if args.write_partial_as_operator_set:
        print("ceiling-probe-live: --write-partial-as-operator-set applies to --transport claude-headless only",
              file=sys.stderr)
        return 2
    args.tier = args.tier or "unverified"

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



def _outcome_reasons(samples: list[dict], *, stop: str | None, largest_ok: int, measured: int | None,
                     smallest_fail: int | None, hi: int, tol: int) -> list[str]:
    """Why a bisection is NOT clean ([] ⇒ clean; sprint.md § Flatline review integration (a)):
    clean = the largest accepted step verified by the echoed needle and measured, a size
    rejection within `tol` above it, no `other` / unverified / budget stop, no accept
    above a rejection."""
    reasons: list[str] = []
    if stop == "budget":
        reasons.append("budget cap stopped the bisection")
    if stop == "other" or any(s.get("kind") == "other" for s in samples):
        reasons.append("an attempt failed for a non-size reason (other)")
    if stop == "unverified" or any(s.get("kind") == "unverified" for s in samples):
        reasons.append("a completed response did not echo the needle (unverified)")
    oks = [s.get("size_measured", s["tokens"]) for s in samples if s.get("kind") == "ok"]
    fails = [s.get("size_measured", s["tokens"]) for s in samples if s.get("kind") == "size"]
    if oks and fails and max(oks) > min(fails):
        reasons.append("inconsistent: an accept above a size rejection")
    elif fails:
        bracket = min((s for s in samples if s.get("kind") == "size"), key=lambda s: s.get("size_measured", s["tokens"]))
        fc = bracket.get("failure_class")
        if fc != "context_limit":
            # verifier r251-1: a token-budget / throttle rejection bounds the account's rate, not the window
            reasons.append(f"the bracketing rejection is {fc or 'unclassified'}, not context_limit — "
                           f"a throttle or token budget, not the context window")
    if reasons:
        return reasons
    if largest_ok <= 0:
        reasons.append("no accepted size in the probed range")
    elif smallest_fail is None or (largest_ok >= hi - tol and smallest_fail - largest_ok > tol):
        reasons.append(f"no size rejection up to {hi} tokens — the bound is not bracketed")
    elif smallest_fail - largest_ok > tol:
        reasons.append("the accept/reject bracket is wider than --tolerance-tokens")
    elif not measured:
        reasons.append("the accepted step reported no usage — nothing measured")
    return reasons


def _charge(res: dict, *, est_micro: int, price_in: int) -> tuple[int, str]:
    """(micro-USD, basis) one attempt is charged (r251-1 P1; the table in the module docstring)."""
    measured = res.get("measured_input_tokens")
    reported = res.get("cli_reported_cost_usd")
    rep = int(reported * 1_000_000) if isinstance(reported, (int, float)) and not isinstance(reported, bool) \
        and reported > 0 else 0
    if res.get("not_sent"):
        return 0, "not_sent"
    if res.get("timed_out"):
        return est_micro, "timeout_estimate"
    if res.get("classifier_error"):
        return est_micro, "classifier_error_estimate"
    if res.get("output_cap"):
        return est_micro, "output_cap_estimate"
    usage_micro = measured * price_in // 1_000_000 if measured else None
    if res["kind"] in ("ok", "unverified"):
        return max(usage_micro if usage_micro is not None else est_micro, rep), "completion"
    if res["kind"] == "size" and res.get("size_origin") == "cli_local":
        return 0, "cli_local_rejection"
    if usage_micro is not None:
        return max(usage_micro, rep), "usage_reported"
    if rep:
        return rep, "cli_reported"
    return 0, ("provider_rejection_unbilled" if res["kind"] in ("size", "transient") else "failed_unbilled")


def _retry_wait(res: dict, attempt: int, waited: float) -> float:
    """Seconds to sleep before attempt `attempt + 1` (0 ⇒ the retry budget is spent)."""
    schedule = _TPM_BACKOFF_S if res.get("token_limit") else _BACKOFF_S
    wait = float(schedule[min(attempt - 1, len(schedule) - 1)])
    hint = res.get("retry_after_s")
    if isinstance(hint, (int, float)) and hint > wait:
        wait = float(hint)
    return max(0.0, min(wait, _RETRY_WAIT_CAP_S - waited))


def _persisted_transient(res: dict, *, attempt_kinds: list[str], waited: float) -> dict:
    """The final classification of a step whose transient class outlived its
    retries (r251-1 P3): a token-budget 429 on EVERY attempt, once the 60 s
    window was waited out, says this size does not fit the budget — a size
    rejection (`token_limit`), and the bisection continues downward; anything
    else is `other`."""
    out = {k: v for k, v in res.items() if k not in ("token_limit", "retry_after_s")}
    n = len(attempt_kinds)
    if res.get("token_limit") and attempt_kinds and all(k == "token_limit" for k in attempt_kinds):
        if waited >= _TPM_WINDOW_S:
            out.update(kind="size", failure_class="token_limit", size_origin="provider")
            return out
        out.update(kind="other", detail=(f"token-limit 429 persisted over {n} attempts but only {waited:g}s were "
                                         f"waited — the {_TPM_WINDOW_S}s tokens-per-minute window was not cleared: "
                                         f"{res.get('detail', '')}")[:_DETAIL_CHARS * 2])
        return out
    out.update(kind="other", detail=f"transient class persisted over {n} attempts: {res.get('detail', '')}")
    return out


def _main_cli(args) -> int:
    """The bisection, through the headless CLI (cycle-127 FR-3.1, D-3.5…D-3.9)."""
    import secrets

    if args.min_tokens_probe >= args.max_tokens_probe or args.tolerance_tokens <= 0:
        print("ceiling-probe-live: need --min-tokens-probe < --max-tokens-probe and --tolerance-tokens > 0",
              file=sys.stderr)
        return 2
    if args.write_partial_as_operator_set and not args.write_catalog:
        print("ceiling-probe-live: --write-partial-as-operator-set needs --write-catalog", file=sys.stderr)
        return 2
    started_at = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    cli_bin = _cli_bin()
    cli_arg = args.cli_model or args.model
    host_route = args.host_route or _default_host_route(cli_bin)
    if args.write_catalog:
        # r251-1 P6: a write that cannot land must fail before any spend — dry-run
        # the writer (block, positive context_window for the I2 clamp, fields).
        try:
            with open(args.write_catalog, "r", encoding="utf-8") as fh:
                write_catalog_operator_set(fh.read(), args.model, ceiling=1, calibrated_at=started_at,
                                           cli_model=cli_arg, host_route=host_route, probe_outcome="clean",
                                           sample_size=0)
            # r251-2 Q2: the atomic write needs the directory (mkstemp + replace) and an
            # operator-writable file; a read-only catalog must fail here, not after spend
            cat_dir = os.path.dirname(os.path.abspath(args.write_catalog))
            for what, path in (("directory", cat_dir), ("file", args.write_catalog)):
                if not os.access(path, os.W_OK):
                    raise OSError(f"catalog {what} {path} is not writable")
        except (OSError, ValueError) as e:
            print(f"ceiling-probe-live: --write-catalog {args.write_catalog}: {e} — no call made, nothing spent",
                  file=sys.stderr)
            return 2
    argv = _cli_command(cli_bin, cli_arg)
    _adapters()
    from loa_cheval.providers.base import SubprocessOutputCapExceeded
    # The CLI writes the whole prompt to the prompt cache: the live record shows
    # $4.99/MTok billed for 972,887 tokens on a $4 input price — 1.25×, the
    # cache-write rate. Estimates (the pre-check, the worst-case line, the floor
    # of an accepted step's charge) use it.
    price_in = _PRICE_IN.get(args.model, 10_000_000) * 5 // 4
    lo, hi, tol = args.min_tokens_probe, args.max_tokens_probe, args.tolerance_tokens
    budget_micro = int(args.budget_usd * 1_000_000)
    worst_micro = hi * price_in // 1_000_000
    print(f"ceiling-probe-live: worst-case step ≈ ${worst_micro / 1e6:.2f} at the catalog price "
          f"(${price_in * 4 / 5 / 1e6:.2f}/MTok input × 1.25 cache-write rate = ${price_in / 1e6:.2f}/MTok, "
          f"catalog estimate × {hi} tokens; Bedrock bills separately); "
          f"{budget_micro // worst_micro if worst_micro else 0} such steps fit in ${args.budget_usd:g} (the cap "
          f"is checked against this estimate before every attempt; a size rejection is charged $0 unless the "
          f"CLI reports a cost)", file=sys.stderr)
    cli_version = _cli_version(cli_bin)

    # Sizes are MEASURED tokens (the CLI's usage, or the count a rejection states):
    # --max-tokens-probe / --min-tokens-probe / --tolerance-tokens mean measured
    # tokens, and the filler sent for a target is target / ratio, ratio being the
    # latest measured/filler (1.0 until a step measures something — the Opus 4.7+
    # tokenizer counts this filler ≈1.8× heavier than its 10-tokens-per-sentence).
    spent_micro = 0
    samples: list[dict] = []
    stop = None  # "budget" | "other" | "unverified"
    ratio: float | None = None

    def _m(sample: dict) -> int | None:
        return sample.get("measured_input_tokens") if sample.get("kind") == "ok" else sample.get("rejected_input_tokens")

    def _size(sample: dict) -> tuple[int, str]:
        m = _m(sample)
        return (m, "usage" if sample.get("kind") == "ok" else "parsed") if m else \
            (int(sample["tokens"] * (ratio or 1.0)), "scaled")

    def current_ok() -> int | None:
        vals = [_size(x)[0] for x in samples if x.get("kind") == "ok"]
        return max(vals) if vals else None

    def current_fail() -> tuple[int | None, str | None]:
        vals = [_size(x) for x in samples if x.get("kind") == "size"]
        return min(vals) if vals else (None, None)

    def step(target: int) -> str:
        """Probe one MEASURED target, retrying transient classes. Returns the final kind."""
        nonlocal spent_micro, ratio
        tokens = max(1, int(target / (ratio or 1.0)))
        sample = {"tokens": tokens, "target_measured": target, "ratio_at_send": ratio, "attempts": 0,
                  "ok": False, "verified": False, "charged_usd": 0.0, "charge_basis": None, "retry_wait_s": 0,
                  "attempt_log": []}
        samples.append(sample)
        est_measured = int(tokens * (ratio or 1.0))
        est_micro = est_measured * price_in // 1_000_000
        charged_micro, waited, wait, kinds = 0, 0.0, 0.0, []
        attempt = 0
        while True:
            attempt += 1
            # The cap is checked against the ESTIMATE before every attempt — what an
            # attempt will cost is unknown until it returns (a rejection is charged $0
            # after the fact, an accept its usage); this is the cap's whole purpose.
            if spent_micro + est_micro > budget_micro:
                if attempt == 1:
                    samples.pop()          # a step never attempted is not a sample
                    return "budget"
                sample.update(kind="budget", detail="budget cap before a retry")
                return "budget"
            if attempt > 1:
                _SLEEP(wait)
                waited += wait
            needle = secrets.token_hex(6)
            prompt = _FILLER * (tokens // 10) + f"\n\nReply with exactly this code and nothing else: {needle}"
            print(f"ceiling-probe-live: target {target} measured tokens → filler {tokens} tokens (attempt {attempt}) "
                  f"via {os.path.basename(cli_bin)} ...", file=sys.stderr)
            try:
                rc, out, err = _run_capped(argv, prompt, _attempt_timeout(est_measured))
                res = _classify(rc, out, err, needle)
            except SubprocessOutputCapExceeded as e:
                res = {"kind": "other", "output_cap": True,
                       "detail": f"the CLI's output passed the 1 MB capture cap (process group killed): {e}"[:300],
                       "measured_input_tokens": None, "cli_reported_cost_usd": None, "stop_reason": None}
            except subprocess.TimeoutExpired:
                res = {"kind": "transient", "timed_out": True,
                       "detail": f"no answer within {_attempt_timeout(est_measured)}s (process group killed)",
                       "measured_input_tokens": None, "cli_reported_cost_usd": None, "stop_reason": None}
            except OSError as e:
                res = {"kind": "other", "not_sent": True, "detail": f"cannot run {cli_bin}: {e}",
                       "measured_input_tokens": None, "cli_reported_cost_usd": None, "stop_reason": None}
            except BaseException as e:
                # ^C or an unexpected defect mid-attempt: the request may have run — charge the
                # estimate, mark the sample, and let the bisection's handler write the record
                spent_micro += est_micro
                charged_micro += est_micro
                sample["attempt_log"].append({"attempt": attempt, "kind": "interrupted",
                                              "wait_before_s": wait if attempt > 1 else 0,
                                              "charged_usd": round(est_micro / 1e6, 6),
                                              "charge_basis": "interrupted_estimate"})
                sample.update(kind="interrupted", attempts=attempt, charged_usd=round(charged_micro / 1e6, 6),
                              charge_basis="interrupted_estimate", retry_wait_s=waited,
                              detail=f"{type(e).__name__}: {e}"[:300])
                raise
            cost, basis = _charge(res, est_micro=est_micro, price_in=price_in)
            spent_micro += cost
            charged_micro += cost
            kinds.append("token_limit" if res.get("token_limit") else res["kind"])
            sample["attempt_log"].append({"attempt": attempt, "kind": kinds[-1], "wait_before_s": wait if attempt > 1 else 0,
                                          "charged_usd": round(cost / 1e6, 6), "charge_basis": basis})
            sample["attempts"] = attempt
            sample["charged_usd"] = round(charged_micro / 1e6, 6)
            sample["charge_basis"] = basis
            sample["retry_wait_s"] = waited
            sample.update({k: v for k, v in res.items()
                           if k not in ("token_limit", "retry_after_s", "timed_out", "not_sent", "classifier_error",
                                        "output_cap")})
            if res["kind"] == "transient":
                limit = _TPM_ATTEMPTS if res.get("token_limit") else _ATTEMPTS
                wait = _retry_wait(res, attempt, waited) if attempt < limit else 0.0
                if wait > 0:
                    continue
                sample.update(_persisted_transient(res, attempt_kinds=kinds, waited=waited))
                for k in ("timed_out", "not_sent", "classifier_error", "output_cap"):
                    sample.pop(k, None)
            break
        if sample["kind"] == "ok":
            sample.update(ok=True, verified=True)
        m = _m(sample) or (sample.get("measured_input_tokens") if sample["kind"] == "unverified" else None)
        if m:
            ratio = m / tokens
        return sample["kind"]

    def next_target() -> int | None:
        first = samples[0]
        if first["ratio_at_send"] is None and _m(first) and abs(_m(first) - hi) > tol \
                and not any(x["target_measured"] == hi for x in samples[1:]):
            return hi          # the top was sent blind and missed: re-anchor it in measured tokens, once
        ok_m, (fail_m, _) = current_ok(), current_fail()
        if ok_m is not None and ok_m >= hi - tol:
            return None        # accepted at the top of the range
        if fail_m is None:
            return None
        lower = max(ok_m or 0, lo)
        if fail_m - lower <= tol:
            return None
        return (lower + fail_m) // 2

    interrupted: BaseException | None = None
    try:
        kind = step(hi)
        if kind in ("budget", "other", "unverified"):
            stop = kind
        tried: set = set()
        while stop is None and len(samples) < 40:
            target = next_target()
            if target is None or (target, int(target / (ratio or 1.0))) in tried:
                break
            tried.add((target, int(target / (ratio or 1.0))))
            kind = step(target)
            if kind in ("budget", "other", "unverified"):
                stop = kind
    except BaseException as e:  # noqa: BLE001 — ^C / a defect after paid steps must not lose the record
        stop, interrupted = "interrupted", e
        if not isinstance(e, KeyboardInterrupt):
            traceback.print_exc()           # r251-2 Q5: a defect keeps its traceback
    interrupted_text = f"{type(interrupted).__name__}: {interrupted}" if interrupted is not None else None

    for x in samples:
        if x.get("kind") in ("ok", "size"):
            x["size_measured"], x["size_basis"] = _size(x)
    largest_ok = current_ok() or 0
    smallest_fail, fail_basis = current_fail()
    best = max((x for x in samples if x.get("kind") == "ok"), key=lambda x: x["size_measured"], default=None)
    largest_ok_measured = best.get("measured_input_tokens") if best else None
    reasons = _outcome_reasons(samples, stop=stop, largest_ok=largest_ok, measured=largest_ok_measured,
                               smallest_fail=smallest_fail, hi=hi, tol=tol)
    if interrupted is not None:
        reasons.insert(0, f"the bisection was interrupted ({interrupted_text})")
    outcome = "partial" if reasons else "clean"

    record = {
        "model": args.model,
        "transport": "claude-headless",
        "source": "operator_set",
        "method": "probed_headless",
        "outcome": outcome,
        "reasons": reasons,
        "calibrated_at": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "started_at": started_at,
        "sample_size": len(samples),
        "largest_ok_input_tokens": largest_ok,
        "largest_ok_filler_tokens": best["tokens"] if best else None,
        "measured_input_tokens": largest_ok_measured,
        "smallest_failed_input_tokens": smallest_fail,
        "smallest_failed_basis": fail_basis,
        "tokenizer_ratio": round(ratio, 4) if ratio else None,
        "size_unit": "measured_tokens",
        "tolerance_tokens": tol,
        "bounds_tested": {"min": lo, "max": hi},
        "partial": outcome != "clean",
        "unverified": any(s.get("kind") == "unverified" for s in samples),
        "budget_usd": args.budget_usd,
        "spent_usd": round(spent_micro / 1_000_000, 4),
        "pricing_basis": "catalog_estimate",
        "estimate_rate": "input × 1.25 (cache-write rate)",
        "estimate_usd_per_mtok": price_in / 1e6,
        "stop": stop,
        "interrupted": interrupted_text,
        "cli_bin": cli_bin,
        "cli_version": cli_version,
        "cli_model": _resolved_cli_model(cli_arg),
        "argv": argv,
        "host_route": host_route,
        "route_env": _route_env(),
        "samples": samples,
    }
    errors = [s["detail"] for s in samples if s.get("kind") == "other"]
    if errors:
        record["error"] = errors[0]
    new_catalog = None
    forced = outcome != "clean" and args.write_partial_as_operator_set and interrupted is None
    if args.write_catalog and (outcome == "clean" or forced):
        if forced and not (best and largest_ok_measured):
            # nothing to vouch for: not an `other` failure of the probe, the exit stays 3
            # r251-2 Q4: a separate key — the probe's own first error (errors[0]) stays in `error`
            record["write_skipped"] = ("catalog not written: --write-partial-as-operator-set but no verified "
                                       "accept to vouch for")
            record.setdefault("error", record["write_skipped"])
        else:
            try:
                with open(args.write_catalog, "r", encoding="utf-8") as fh:
                    current = fh.read()
                written = i2_clamped(current, args.model, int(largest_ok_measured))[0]
                new_catalog = write_catalog_operator_set(
                    current, args.model, ceiling=int(largest_ok_measured), calibrated_at=record["calibrated_at"],
                    cli_model=record["cli_model"], host_route=host_route, cli_version=cli_version,
                    probe_outcome=outcome, sample_size=len(samples), force_partial=bool(forced))
                # r251-2 Q3: the catalog lands BEFORE the record is serialized, and the
                # record claims a write only once it has landed
                _write_text_atomic(args.write_catalog, new_catalog)
                record["written_ceiling"] = written
                record["written_probe_outcome"] = outcome
            except (OSError, ValueError) as e:
                new_catalog = None
                record["write_failed"] = True
                record["error"] = f"catalog not written: {e}"
                errors.append(record["error"])
    text = json.dumps(record, indent=2)
    if args.output == "-":
        print(text)
    else:
        with open(args.output, "w") as fh:
            fh.write(text + "\n")
        print(f"ceiling-probe-live: wrote {args.output} (outcome={outcome}, measured={largest_ok_measured}, "
              f"spent≈${record['spent_usd']} catalog estimate)", file=sys.stderr)
    if interrupted is not None:
        print(f"ceiling-probe-live: interrupted ({interrupted_text}) — record kept, nothing written to the "
              f"catalog", file=sys.stderr)
        return 130 if isinstance(interrupted, KeyboardInterrupt) else 1
    if outcome != "clean":
        if record.get("write_failed"):
            print(f"ceiling-probe-live: {record['error']}", file=sys.stderr)
            return 1
        if forced and new_catalog is not None:
            print(f"ceiling-probe-live: partial ({'; '.join(reasons)}) — written anyway as operator_set "
                  f"(--write-partial-as-operator-set: the operator vouches for the last verified accept): "
                  f"{args.model} effective_input_ceiling={record['written_ceiling']} (measured {largest_ok_measured}), "
                  f"probe_outcome: partial, sample_size {len(samples)}", file=sys.stderr)
        else:
            why = f" ({record['write_skipped']})" if record.get("write_skipped") else ""
            print(f"ceiling-probe-live: partial ({'; '.join(reasons)}) — nothing written to the catalog{why}",
                  file=sys.stderr)
        return 1 if errors else 3
    if args.write_catalog:
        if new_catalog is None:
            print(f"ceiling-probe-live: {record['error']}", file=sys.stderr)
            return 1
        print(f"ceiling-probe-live: {args.write_catalog}: {args.model} probed_ceiling=effective_input_ceiling="
              f"{record['written_ceiling']} (measured {largest_ok_measured}; operator_set, probed_headless, "
              f"calibrated_at={record['calibrated_at']}); "
              f"regenerate: bash .claude/scripts/gen-adapter-maps.sh && "
              f"npm --prefix .claude/skills/bridgebuilder-review run build", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
