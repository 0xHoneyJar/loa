"""JSONL cost ledger with atomic writes (SDD §4.5.1-§4.5.2).

Implements:
- JSONL append with fcntl.flock for concurrent append safety
- Atomic daily spend counter with flock-protected read-modify-write
- Corruption recovery: truncate to last valid JSONL line on read
- Ledger path resolution shared by writer and readers (cycle-124 FR-6)
"""

from __future__ import annotations

import fcntl
import json
import logging
import os
import uuid
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

from loa_cheval.metering.pricing import (
    PricingEntry,
    calculate_total_cost,
    find_pricing,
)
from loa_cheval.types import ConfigError

logger = logging.getLogger("loa_cheval.metering.ledger")


def _generate_request_id() -> str:
    """Generate a unique request ID."""
    return f"req-{uuid.uuid4().hex[:12]}"


# -----------------------------------------------------------------------------
# Ledger path resolution (cycle-124 FR-6).
#
# One resolver for the writer (cheval.py's BudgetEnforcer) and the readers
# (rollup.py, cost-report.sh) so a redirected ledger moves reads and writes
# together. Mirrors audit/modelinv.py::_resolve_log_path for the MODELINV log.
# -----------------------------------------------------------------------------

COST_LEDGER_ENV = "LOA_COST_LEDGER_PATH"
DEFAULT_COST_LEDGER_PATH = ".run/cost-ledger.jsonl"


def resolve_cost_ledger_path(metering_config: Optional[Dict[str, Any]] = None) -> str:
    """Return the canonical cost-ledger path.

    Precedence:
      1. ``LOA_COST_LEDGER_PATH`` env — test isolation / operator redirect
      2. ``metering.ledger_path`` from the merged config
      3. ``.run/cost-ledger.jsonl`` relative to the working directory (today's
         literal fallback; ``append_ledger`` still creates ``.run/`` on first
         write, so the default needs no existing parent)

    Path safety (sprint Flatline SKP-003): the result is canonicalized with
    ``os.path.realpath`` (``..``/``.`` segments collapse); a symlink at the
    target path is rejected for every source; an env- or config-supplied path
    must have an existing parent directory — a typo'd redirect is an error,
    not a ``mkdir``. Rejections raise ``ConfigError`` (``INVALID_CONFIG``).
    """
    override = os.environ.get(COST_LEDGER_ENV)
    if override:
        candidate, source = override, f"env {COST_LEDGER_ENV}"
    else:
        configured = (metering_config or {}).get("ledger_path")
        if configured:
            candidate, source = str(configured), "metering.ledger_path"
        else:
            candidate, source = DEFAULT_COST_LEDGER_PATH, "default"

    if os.path.islink(candidate):
        raise ConfigError(
            f"cost ledger path {candidate!r} ({source}) is a symlink; refusing to follow it"
        )
    resolved = os.path.realpath(candidate)
    parent = os.path.dirname(resolved)
    if source != "default" and not os.path.isdir(parent):
        raise ConfigError(
            f"cost ledger parent directory {parent!r} ({source}) does not exist"
        )
    return resolved


def create_ledger_entry(
    trace_id: str,
    agent: str,
    provider: str,
    model: str,
    input_tokens: int,
    output_tokens: int,
    reasoning_tokens: int,
    latency_ms: int,
    config: Dict[str, Any],
    phase_id: Optional[str] = None,
    sprint_id: Optional[str] = None,
    attempt: int = 1,
    usage_source: str = "actual",
    interaction_id: Optional[str] = None,
    reported_cost_micro_usd: Optional[int] = None,
    cache_read_tokens: int = 0,
    cache_creation_tokens: int = 0,
) -> Dict[str, Any]:
    """Create a ledger entry dict matching SDD §4.5.1 format.

    cycle-124 FR-4: `cache_read_tokens` / `cache_creation_tokens` (Anthropic
    usage fields, not part of input_tokens) are priced at the entry's cache
    rates and recorded as `tokens_cache_read` / `tokens_cache_creation` when
    non-zero (rows without cache traffic keep their pre-cycle shape).

    A normalized CLI-reported amount supersedes config pricing. Otherwise,
    calculates cost from config; absent pricing is 'unknown' with cost 0.

    For Deep Research (pricing_mode="task"), tokens are informational only —
    cost is the flat per_task_micro_usd.
    """
    pricing = find_pricing(provider, model, config)

    if reported_cost_micro_usd is not None:
        cost_micro_usd = reported_cost_micro_usd
        pricing_source = "cli_reported"
        pricing_mode = "token"
    elif pricing:
        breakdown = calculate_total_cost(
            input_tokens, output_tokens, reasoning_tokens, pricing,
            cache_read_tokens=cache_read_tokens,
            cache_creation_tokens=cache_creation_tokens,
        )
        cost_micro_usd = breakdown.total_cost_micro
        pricing_source = "config"
        pricing_mode = pricing.pricing_mode
    else:
        cost_micro_usd = 0
        pricing_source = "unknown"
        pricing_mode = "token"

    entry = {
        "ts": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z",
        "trace_id": trace_id,
        "request_id": _generate_request_id(),
        "agent": agent,
        "provider": provider,
        "model": model,
        "tokens_in": input_tokens,
        "tokens_out": output_tokens,
        "tokens_reasoning": reasoning_tokens,
        "latency_ms": latency_ms,
        "cost_micro_usd": cost_micro_usd,
        "usage_source": usage_source,
        "pricing_source": pricing_source,
        "pricing_mode": pricing_mode,
        "phase_id": phase_id,
        "sprint_id": sprint_id,
        "attempt": attempt,
    }

    if interaction_id:
        entry["interaction_id"] = interaction_id
    if cache_read_tokens:
        entry["tokens_cache_read"] = cache_read_tokens
    if cache_creation_tokens:
        entry["tokens_cache_creation"] = cache_creation_tokens

    return entry


def append_ledger(entry: Dict[str, Any], ledger_path: str) -> None:
    """Append a single JSONL line with concurrency safety (SDD §4.5.2).

    Uses fcntl.flock(LOCK_EX) for atomic append.
    """
    line = json.dumps(entry, separators=(",", ":")) + "\n"
    encoded = line.encode("utf-8")

    # Ensure parent directory exists
    os.makedirs(os.path.dirname(ledger_path) or ".", exist_ok=True)

    # O_NOFOLLOW: a symlink swapped in between resolve_cost_ledger_path's
    # check and this open fails (ELOOP) instead of being followed (FR-6).
    fd = os.open(
        ledger_path,
        os.O_WRONLY | os.O_APPEND | os.O_CREAT | os.O_NOFOLLOW,
        0o644,
    )
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        os.write(fd, encoded)
    finally:
        fcntl.flock(fd, fcntl.LOCK_UN)
        os.close(fd)


def read_ledger(ledger_path: str) -> List[Dict[str, Any]]:
    """Read JSONL ledger with corruption recovery.

    Skips corrupted lines, logs warning count.
    Returns list of valid entries.
    """
    if not os.path.exists(ledger_path):
        return []

    entries = []
    corrupt_count = 0

    with open(ledger_path, "r") as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                entries.append(json.loads(line))
            except json.JSONDecodeError:
                corrupt_count += 1

    if corrupt_count:
        logger.warning(
            "Ledger %s: skipped %d corrupted line(s)", ledger_path, corrupt_count
        )

    return entries


def read_daily_spend(ledger_path: str) -> int:
    """Read daily spend from summary file (O(1)).

    File: {ledger_dir}/.daily-spend-{YYYY-MM-DD}.json
    Format: {"date": "2026-02-10", "total_micro_usd": 1234567, "entry_count": 42}

    Returns total_micro_usd for today, 0 if file doesn't exist.
    """
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    summary_path = _daily_spend_path(ledger_path, today)

    if not os.path.exists(summary_path):
        return 0

    try:
        with open(summary_path, "r") as f:
            data = json.load(f)
        if data.get("date") != today:
            return 0
        return data.get("total_micro_usd", 0)
    except (json.JSONDecodeError, OSError):
        return 0


def update_daily_spend(entry_cost_micro: int, ledger_path: str) -> None:
    """Atomically update daily spend counter (SDD §4.5.3).

    Uses flock-protected read-modify-write on per-day summary file.
    """
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    summary_path = _daily_spend_path(ledger_path, today)

    os.makedirs(os.path.dirname(summary_path) or ".", exist_ok=True)

    fd = os.open(summary_path, os.O_RDWR | os.O_CREAT, 0o644)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)

        raw = os.read(fd, 4096)
        if raw:
            try:
                data = json.loads(raw.decode("utf-8"))
            except json.JSONDecodeError:
                data = {"total_micro_usd": 0, "entry_count": 0}
        else:
            data = {"total_micro_usd": 0, "entry_count": 0}

        data["date"] = today
        data["total_micro_usd"] = data.get("total_micro_usd", 0) + entry_cost_micro
        data["entry_count"] = data.get("entry_count", 0) + 1

        os.lseek(fd, 0, os.SEEK_SET)
        os.ftruncate(fd, 0)
        os.write(fd, json.dumps(data).encode("utf-8"))
    finally:
        fcntl.flock(fd, fcntl.LOCK_UN)
        os.close(fd)


def record_cost(
    entry: Dict[str, Any],
    ledger_path: str,
) -> None:
    """Append ledger entry and update daily spend counter.

    Convenience function combining append_ledger + update_daily_spend.
    """
    append_ledger(entry, ledger_path)
    update_daily_spend(entry.get("cost_micro_usd", 0), ledger_path)


def _daily_spend_path(ledger_path: str, date: str) -> str:
    """Compute daily spend summary file path."""
    ledger_dir = os.path.dirname(ledger_path) or "."
    return os.path.join(ledger_dir, f".daily-spend-{date}.json")
