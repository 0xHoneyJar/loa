"""Cycle-110 sprint-2b2a T2.9 — `loa substrate doctor` CLI implementation.

Operator-facing OAuth pre-flight probe per [PRD:FR-4]. For each of the three
headless CLIs (`claude`, `codex`, `gemini`), probes auth state via:

- **status-command** for CLIs that expose a clean status subcommand
  (`codex login status` per `spike-cli-status.md` T2.0 findings)
- **no-op-dispatch** fallback (FR-4.5) for CLIs that lack a status
  subcommand (`claude` + `gemini` per spike findings)

Hardening per NFR-Sec-3 + cycle-110 C2/C6 carry-ins:
- `timeout 10s` per probe
- stdin redirected from `/dev/null` (no inherited TTY)
- streaming-read with byte cap (NOT `proc.communicate()` — C2 closure)
- process-group `kill -9` on timeout with `ProcessLookupError` handler (C6)
- `hint` field is a fixed-template string (no user-content interpolation —
  closes SKP-003 v1.3 HIGH-750 from cycle-110 SDD §5.4)

Output schema ([PRD:FR-4.2]):

```json
{
  "schema_version": 1,
  "ts_iso": "2026-05-15T12:34:56Z",
  "probes": [
    {
      "provider": "anthropic",
      "cli": "claude-headless",
      "auth_state": "ok" | "needs-login" | "unreachable" | "unknown",
      "last_verified": "ISO-8601",
      "hint": "fixed-template string",
      "probe_method": "status-command" | "no-op-dispatch"
    }
  ],
  "verdict": "N/M ready for dispatch_preference: headless rollout"
}
```
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import shutil
import signal
import subprocess
import sys
import time
from dataclasses import dataclass, asdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

logger = logging.getLogger("loa_cheval.doctor")


# --- Constants ---------------------------------------------------------------

# Per-CLI probe configuration. Sourced from spike-cli-status.md (T2.0):
# - codex: clean `codex login status` exit-0 path
# - claude: no status subcommand; FR-4.5 fallback via `claude -p "ping" < /dev/null`
# - gemini: no status subcommand; FR-4.5 fallback via `gemini -p "ping" < /dev/null`
_PROBE_TABLE: Dict[str, Dict[str, Any]] = {
    "claude": {
        "provider": "anthropic",
        "cli_name": "claude-headless",
        "method": "no-op-dispatch",
        # The ping command. NEVER interpolate user content. The literal "ping"
        # prompt is the FR-4.5 fixed-template per C110.OP-SPLAN SKP-002 closure.
        "cmd": ["claude", "-p", "ping", "--max-budget-usd", "0.001",
                "--strict-mcp-config", "--disable-slash-commands",
                "--output-format", "text"],
    },
    "codex": {
        "provider": "openai",
        "cli_name": "codex-headless",
        "method": "status-command",
        "cmd": ["codex", "login", "status"],
    },
    "gemini": {
        "provider": "google",
        "cli_name": "gemini-headless",
        "method": "no-op-dispatch",
        "cmd": ["gemini", "-p", "ping", "-o", "text", "--skip-trust"],
    },
}

DEFAULT_TIMEOUT_SECONDS = 10
DEFAULT_MAX_BYTES = 1_048_576  # 1 MiB per stream cap
SCHEMA_VERSION = 1


# --- Data types --------------------------------------------------------------


@dataclass(frozen=True)
class ProbeResult:
    """One CLI's probe outcome.

    `hint` is ALWAYS a fixed-template string per SKP-003 v1.3 HIGH-750 — no
    user-content (stderr/stdout) interpolation. Captures of the actual
    subprocess output stay LOCAL to `_run_probe` and never leak through the
    schema boundary.
    """
    provider: str
    cli: str
    auth_state: str       # "ok" | "needs-login" | "unreachable" | "unknown"
    last_verified: str    # ISO-8601 UTC
    hint: str             # fixed-template
    probe_method: str     # "status-command" | "no-op-dispatch"


# --- Streaming capture (C2 closure) ------------------------------------------


def _capture_with_byte_cap(
    proc: subprocess.Popen,
    *,
    max_bytes: int = DEFAULT_MAX_BYTES,
    timeout_s: int = DEFAULT_TIMEOUT_SECONDS,
) -> Tuple[bytes, bytes, int]:
    """Read stdout + stderr with byte-cap and timeout — NEVER proc.communicate().

    Cycle-110 C2 closure: proc.communicate() buffers unbounded output in
    memory, which breaks on a malicious / runaway CLI that floods stdout.
    Streaming-read enforces an upper bound per stream + an overall timeout.

    Returns:
        (stdout_bytes_capped, stderr_bytes_capped, returncode).

    Raises:
        subprocess.TimeoutExpired: on overall deadline exceed.
    """
    import select

    deadline = time.monotonic() + timeout_s
    stdout_buf = bytearray()
    stderr_buf = bytearray()
    stdout_fd = proc.stdout.fileno() if proc.stdout else -1
    stderr_fd = proc.stderr.fileno() if proc.stderr else -1
    open_fds = [fd for fd in (stdout_fd, stderr_fd) if fd >= 0]

    while open_fds:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise subprocess.TimeoutExpired(proc.args, timeout_s)
        readable, _, _ = select.select(open_fds, [], [], remaining)
        if not readable:
            raise subprocess.TimeoutExpired(proc.args, timeout_s)
        for fd in readable:
            try:
                chunk = os.read(fd, 4096)
            except OSError:
                chunk = b""
            if not chunk:
                open_fds.remove(fd)
                continue
            if fd == stdout_fd:
                if len(stdout_buf) < max_bytes:
                    stdout_buf.extend(chunk[: max_bytes - len(stdout_buf)])
            elif fd == stderr_fd:
                if len(stderr_buf) < max_bytes:
                    stderr_buf.extend(chunk[: max_bytes - len(stderr_buf)])
        # Check whether the process has exited even if both streams still
        # appear open — the kernel sometimes leaves the FDs readable until
        # the next select call.
        if proc.poll() is not None and not open_fds:
            break
    # Final wait — bounded.
    try:
        proc.wait(timeout=max(0.5, deadline - time.monotonic()))
    except subprocess.TimeoutExpired:
        pass
    # `proc.returncode or -1` is a Python falsiness bug — returncode 0 is
    # falsy, so it would collapse "success" to -1. Use explicit `is None`.
    rc = proc.returncode
    if rc is None:
        rc = -1
    return bytes(stdout_buf), bytes(stderr_buf), rc


# --- Probe driver -------------------------------------------------------------


def _run_probe(
    cli: str,
    spec: Dict[str, Any],
    *,
    timeout_s: int = DEFAULT_TIMEOUT_SECONDS,
    now: Optional[datetime] = None,
) -> ProbeResult:
    """Invoke one CLI's probe command with full NFR-Sec-3 hardening.

    Returns ProbeResult — never raises (every failure mode maps to an
    `auth_state` value). The `hint` is a fixed-template lookup.
    """
    ts = (now or datetime.now(timezone.utc)).isoformat(timespec="seconds")
    provider = spec["provider"]
    cli_name = spec["cli_name"]
    method = spec["method"]
    cmd = spec["cmd"]

    # Resolve the CLI binary path. shutil.which scans PATH; absent CLI is
    # an explicit `unreachable` state, NOT a probe failure.
    cli_bin = shutil.which(cmd[0])
    if cli_bin is None:
        return ProbeResult(
            provider=provider, cli=cli_name,
            auth_state="unreachable",
            last_verified=ts,
            hint=_hint_for(method, "binary-not-on-path", cmd[0]),
            probe_method=method,
        )

    # Hardened subprocess invocation:
    # - stdin=DEVNULL (no inherited TTY / no operator paste)
    # - start_new_session=True (process-group isolation for kill -9)
    # - bufsize=0 (unbuffered, line-by-line read)
    # - close_fds=True (default on POSIX; preserved explicitly for clarity)
    try:
        proc = subprocess.Popen(
            [cli_bin, *cmd[1:]],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            start_new_session=True,
            bufsize=0,
            close_fds=True,
        )
    except OSError as exc:
        return ProbeResult(
            provider=provider, cli=cli_name,
            auth_state="unreachable",
            last_verified=ts,
            hint=_hint_for(method, "spawn-failed", cli_bin),
            probe_method=method,
        )

    try:
        stdout_bytes, stderr_bytes, returncode = _capture_with_byte_cap(
            proc, timeout_s=timeout_s,
        )
    except subprocess.TimeoutExpired:
        # C6 closure: ProcessLookupError-safe process-group kill.
        try:
            os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
        except ProcessLookupError:
            pass  # process exited between poll + kill — idempotent
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            pass
        return ProbeResult(
            provider=provider, cli=cli_name,
            auth_state="unreachable",
            last_verified=ts,
            hint=_hint_for(method, "timeout", cli_name),
            probe_method=method,
        )

    return _classify(provider, cli_name, method, returncode, stdout_bytes, ts)


def _classify(
    provider: str,
    cli_name: str,
    method: str,
    returncode: int,
    stdout_bytes: bytes,
    ts: str,
) -> ProbeResult:
    """Map (returncode, stdout) to (auth_state, hint).

    Fixed-template hints only. No stdout/stderr interpolation per SKP-003.
    """
    if returncode == 0:
        # status-command: 0 means logged in.
        # no-op-dispatch: 0 means the dispatch round-tripped — implies auth.
        return ProbeResult(
            provider=provider, cli=cli_name,
            auth_state="ok",
            last_verified=ts,
            hint=_hint_for(method, "ok", cli_name),
            probe_method=method,
        )

    # Non-zero exit. Classify by method:
    # status-command: non-zero generally means not-logged-in (codex prints
    #   that explicitly to stderr but we don't interpolate).
    # no-op-dispatch: non-zero could be auth failure OR rate-limit OR
    #   provider-side error; without interpolation we cannot distinguish.
    if method == "status-command":
        return ProbeResult(
            provider=provider, cli=cli_name,
            auth_state="needs-login",
            last_verified=ts,
            hint=_hint_for(method, "needs-login", cli_name),
            probe_method=method,
        )
    return ProbeResult(
        provider=provider, cli=cli_name,
        auth_state="unknown",
        last_verified=ts,
        hint=_hint_for(method, "non-zero-exit", cli_name),
        probe_method=method,
    )


_HINT_TEMPLATES: Dict[Tuple[str, str], str] = {
    # (method, state) → fixed template
    ("status-command", "ok"): "{cli} reports authenticated and reachable",
    ("status-command", "needs-login"): "{cli} not authenticated; run the CLI's login subcommand",
    ("status-command", "binary-not-on-path"): "{cli} binary not found on PATH; install the headless CLI",
    ("status-command", "spawn-failed"): "{cli} could not be spawned",
    ("status-command", "timeout"): "{cli} status-command timed out",
    ("no-op-dispatch", "ok"): "{cli} no-op-dispatch round-tripped (auth + reachability OK)",
    ("no-op-dispatch", "non-zero-exit"): "{cli} no-op-dispatch failed (auth / quota / provider error)",
    ("no-op-dispatch", "binary-not-on-path"): "{cli} binary not found on PATH; install the headless CLI",
    ("no-op-dispatch", "spawn-failed"): "{cli} could not be spawned",
    ("no-op-dispatch", "timeout"): "{cli} no-op-dispatch timed out",
}


def _hint_for(method: str, state: str, cli: str) -> str:
    """Return a fixed-template hint string for (method, state).

    The {cli} interpolation is the CLI's canonical name (e.g., "codex" /
    "claude" / "gemini") — operator-controlled config, NOT user content.
    """
    template = _HINT_TEMPLATES.get((method, state))
    if template is None:
        return f"{cli}: state={state}"
    return template.format(cli=cli)


# --- CLI entrypoint -----------------------------------------------------------


def aggregate(
    *,
    provider_filter: Optional[str] = None,
    timeout_s: int = DEFAULT_TIMEOUT_SECONDS,
    now: Optional[datetime] = None,
) -> Dict[str, Any]:
    """Run probes per `_PROBE_TABLE` and return a JSON-serializable dict.

    Filter via `provider_filter` (e.g., "anthropic" probes only claude).
    """
    probes: List[ProbeResult] = []
    for cli, spec in _PROBE_TABLE.items():
        if provider_filter and spec["provider"] != provider_filter:
            continue
        probes.append(_run_probe(cli, spec, timeout_s=timeout_s, now=now))

    ts_iso = (now or datetime.now(timezone.utc)).isoformat(timespec="seconds")
    ready = sum(1 for p in probes if p.auth_state == "ok")
    total = len(probes)
    verdict = f"{ready}/{total} ready for dispatch_preference: headless rollout"

    return {
        "schema_version": SCHEMA_VERSION,
        "ts_iso": ts_iso,
        "probes": [asdict(p) for p in probes],
        "verdict": verdict,
    }


def render_text(report: Dict[str, Any]) -> str:
    """Operator-readable text rendering of the doctor report."""
    lines = ["Headless CLI authentication status:", ""]
    for probe in report["probes"]:
        marker = {"ok": "✓", "needs-login": "⚠", "unreachable": "❌"}.get(
            probe["auth_state"], "?",
        )
        lines.append(f"  {marker} [{probe['provider']}] {probe['cli']}")
        lines.append(f"      auth_state: {probe['auth_state']}")
        lines.append(f"      last_verified: {probe['last_verified']}")
        lines.append(f"      probe_method: {probe['probe_method']}")
        lines.append(f"      hint: {probe['hint']}")
        lines.append("")
    lines.append(f"Verdict: {report['verdict']}")
    return "\n".join(lines)


def _cli_main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        prog="loa-substrate-doctor",
        description="Cycle-110 FR-4.1 / FR-4.5: probe headless CLI OAuth state.",
    )
    parser.add_argument(
        "--json", action="store_true",
        help="Emit JSON instead of human-readable text",
    )
    parser.add_argument(
        "--provider", default=None,
        choices=("anthropic", "openai", "google"),
        help="Probe only one provider (default: all 3)",
    )
    parser.add_argument(
        "--timeout", type=int, default=DEFAULT_TIMEOUT_SECONDS,
        help=f"Per-probe timeout in seconds (default {DEFAULT_TIMEOUT_SECONDS})",
    )
    args = parser.parse_args(argv)

    report = aggregate(provider_filter=args.provider, timeout_s=args.timeout)
    if args.json:
        print(json.dumps(report, indent=2))
    else:
        print(render_text(report))

    # Exit code: 0 if ALL probes report "ok"; 2 otherwise (operator-actionable).
    bad = sum(1 for p in report["probes"] if p["auth_state"] != "ok")
    return 0 if bad == 0 else 2


if __name__ == "__main__":  # pragma: no cover
    sys.exit(_cli_main())
