"""Budget enforcement — pre/post call hooks (SDD §4.5.3).

Implements BudgetHook protocol from retry.py:
- Pre-call: Check daily spend vs budget, return ALLOW/WARN/DOWNGRADE/BLOCK
- Post-call: Record cost to ledger and update daily spend counter
- Atomic pre-call: flock-protected check+reserve (Sprint 3 Task 3.3)

cycle-095 Sprint 2 (Task 2.7 / SDD §1.4.4): per-session cost-cap primitive
with two-phase atomicity. check_session_cap_pre raises CostBudgetExceeded
BEFORE the API call when the prospective cost (current_session_total +
worst-case estimate) would exceed the cap. check_session_cap_post is
observability-only.
"""

from __future__ import annotations

import fcntl
import json
import logging
import os
import threading
from datetime import datetime, timezone
from typing import Any, Dict, Optional, Set

from loa_cheval.metering.ledger import (
    _daily_spend_path,
    create_ledger_entry,
    read_daily_spend,
    record_cost,
)
from loa_cheval.types import (
    BudgetExceededError,
    CompletionRequest,
    CompletionResult,
    CostBudgetExceeded,  # forward-compat alias for BudgetExceededError
)

logger = logging.getLogger("loa_cheval.metering.budget")

# cycle-095 Sprint 2 (SDD §1.4.4): single process-wide lock that serializes
# the read-then-check window of the session cap. Multi-process consistency
# is operator-action territory (documented soft-cap nature in CHANGELOG +
# loa-setup SKILL example).
_SESSION_CAP_LOCK = threading.Lock()

# cycle-095 Sprint 2 review-iter-2 (DISS-001 fix): in-process reservation
# tracking. Without this, two parallel pre_call invocations can both pass
# against the same ledger total before either post_call records cost,
# violating the hard-cap semantics. trace_id -> reserved_micro_usd.
# Caller MUST invoke release_session_reservation(trace_id, reserved_micro)
# after the API call resolves (on success OR failure) to free the slot.
_SESSION_RESERVATIONS: Dict[str, int] = {}


# Budget status values
ALLOW = "ALLOW"
WARN = "WARN"
DOWNGRADE = "DOWNGRADE"
BLOCK = "BLOCK"


class BudgetEnforcer:
    """Pre/post call budget enforcement hook.

    Wires into retry.py's BudgetHook protocol.

    Best-effort under concurrency: parallel invocations may pass the
    pre-call check simultaneously before either records cost. Expected
    overshoot bounded by MAX_TOTAL_ATTEMPTS * max_cost_per_call.
    """

    def __init__(
        self,
        config: Dict[str, Any],
        ledger_path: str,
        trace_id: Optional[str] = None,
    ) -> None:
        metering = config.get("metering", {})
        self._enabled = metering.get("enabled", True)
        self._ledger_path = ledger_path
        self._config = config
        self._trace_id = trace_id or "tr-unknown"
        self._attempt = 0
        self._seen_interactions: Set[str] = set()

        budget = metering.get("budget", {})
        self._daily_limit = budget.get("daily_micro_usd", 500_000_000)
        self._warn_pct = budget.get("warn_at_percent", 80)
        self._on_exceeded = budget.get("on_exceeded", "downgrade")

    def pre_call(self, request: CompletionRequest) -> str:
        """Pre-call budget check. Returns ALLOW, WARN, DOWNGRADE, or BLOCK.

        Uses daily spend counter (O(1) read) instead of scanning ledger.
        """
        if not self._enabled:
            return ALLOW

        self._attempt += 1
        spent = read_daily_spend(self._ledger_path)

        if spent >= self._daily_limit:
            if self._on_exceeded == "block":
                logger.warning(
                    "Budget BLOCK: spent %d >= limit %d micro-USD",
                    spent, self._daily_limit,
                )
                return BLOCK
            elif self._on_exceeded == "downgrade":
                logger.warning(
                    "Budget DOWNGRADE: spent %d >= limit %d micro-USD",
                    spent, self._daily_limit,
                )
                return DOWNGRADE
            else:
                logger.warning(
                    "Budget WARN: spent %d >= limit %d micro-USD",
                    spent, self._daily_limit,
                )
                return WARN

        warn_threshold = self._daily_limit * self._warn_pct // 100
        if spent >= warn_threshold:
            logger.info(
                "Budget WARN: spent %d >= %d%% of limit (%d micro-USD)",
                spent, self._warn_pct, self._daily_limit,
            )
            return WARN

        return ALLOW

    def pre_call_atomic(self, request: CompletionRequest, reservation_micro: int = 0) -> str:
        """Atomic budget check+reserve (Task 3.3, Flatline SKP-006).

        Locks daily-spend file, reads current spend, checks limit, and writes
        reservation — all under flock(LOCK_EX). Eliminates check-then-act race.

        Args:
            request: Completion request (for metadata).
            reservation_micro: Estimated cost to reserve (0 = check only).

        Returns ALLOW, WARN, DOWNGRADE, or BLOCK.
        """
        if not self._enabled:
            return ALLOW

        self._attempt += 1
        today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
        summary_path = _daily_spend_path(self._ledger_path, today)
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

            spent = data.get("total_micro_usd", 0)

            if spent >= self._daily_limit:
                if self._on_exceeded == "block":
                    logger.warning(
                        "Budget BLOCK (atomic): spent %d >= limit %d micro-USD",
                        spent, self._daily_limit,
                    )
                    return BLOCK
                elif self._on_exceeded == "downgrade":
                    logger.warning(
                        "Budget DOWNGRADE (atomic): spent %d >= limit %d micro-USD",
                        spent, self._daily_limit,
                    )
                    return DOWNGRADE
                else:
                    return WARN

            # Write reservation
            if reservation_micro > 0:
                data["date"] = today
                data["total_micro_usd"] = spent + reservation_micro
                data["entry_count"] = data.get("entry_count", 0) + 1

                os.lseek(fd, 0, os.SEEK_SET)
                os.ftruncate(fd, 0)
                os.write(fd, json.dumps(data).encode("utf-8"))

            warn_threshold = self._daily_limit * self._warn_pct // 100
            if spent >= warn_threshold:
                return WARN

            return ALLOW
        finally:
            fcntl.flock(fd, fcntl.LOCK_UN)
            os.close(fd)

    def post_call(self, result: CompletionResult) -> None:
        """Post-call cost reconciliation.

        Creates ledger entry and updates daily spend counter.
        Deduplicates by interaction_id for Deep Research (Flatline Beads SKP-002).
        """
        if not self._enabled:
            return

        # Deduplicate Deep Research entries by interaction_id
        interaction_id = getattr(result, "interaction_id", None)
        if interaction_id and interaction_id in self._seen_interactions:
            logger.info("Skipping duplicate cost for interaction %s", interaction_id)
            return
        if interaction_id:
            self._seen_interactions.add(interaction_id)

        agent = (result.model if hasattr(result, "model") else "unknown")
        if result.usage:
            entry = create_ledger_entry(
                trace_id=self._trace_id,
                agent=getattr(result, "_agent", agent),
                provider=result.provider,
                model=result.model,
                input_tokens=result.usage.input_tokens,
                output_tokens=result.usage.output_tokens,
                reasoning_tokens=result.usage.reasoning_tokens,
                latency_ms=result.latency_ms,
                config=self._config,
                usage_source=result.usage.source,
                attempt=self._attempt,
                interaction_id=interaction_id,
            )
            record_cost(entry, self._ledger_path)


def check_budget(
    config: Dict[str, Any],
    ledger_path: str,
) -> str:
    """Standalone budget check (not tied to a request).

    Returns ALLOW, WARN, DOWNGRADE, or BLOCK.
    """
    metering = config.get("metering", {})
    if not metering.get("enabled", True):
        return ALLOW

    budget = metering.get("budget", {})
    daily_limit = budget.get("daily_micro_usd", 500_000_000)
    warn_pct = budget.get("warn_at_percent", 80)
    on_exceeded = budget.get("on_exceeded", "downgrade")

    spent = read_daily_spend(ledger_path)

    if spent >= daily_limit:
        if on_exceeded == "block":
            return BLOCK
        elif on_exceeded == "downgrade":
            return DOWNGRADE
        return WARN

    warn_threshold = daily_limit * warn_pct // 100
    if spent >= warn_threshold:
        return WARN

    return ALLOW


# ─────────────────────────────────────────────────────────────────────────────
# cycle-095 Sprint 2 (Task 2.7 / SDD §1.4.4) — per-session cap primitive
# ─────────────────────────────────────────────────────────────────────────────


def _read_session_total(ledger_path: str, trace_id: str) -> int:
    """Sum cost_micro_usd across all entries with the given trace_id.

    Naive ledger scan; acceptable for cycle-095 because session ledgers
    are bounded (1 process, hours of runtime, ~thousands of entries max).
    Sprint 3 may add a session-spend counter analogous to daily-spend.
    """
    if not os.path.exists(ledger_path):
        return 0
    total = 0
    try:
        with open(ledger_path) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    entry = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if entry.get("trace_id") != trace_id:
                    continue
                total += int(entry.get("cost_micro_usd", 0) or 0)
    except OSError:
        return 0
    return total


def check_session_cap_pre(
    trace_id: str,
    ledger_path: str,
    cap_micro: Optional[int],
    request_estimate_micro: int,
) -> None:
    """Pre-call session cap check (SDD §1.4.4 hard-guard) with reservation.

    Raises CostBudgetExceeded if (ledger session total + pending reservations
    + worst-case estimate) would exceed `cap_micro`. On pass, ATOMICALLY
    increments the in-process reservation tracker so a concurrent pre_call
    sees the slot taken.

    cap_micro=None or <= 0 → no enforcement (no-op).

    Concurrency: a single threading.Lock serializes the read+check+reserve
    window. The caller MUST invoke release_session_reservation(trace_id,
    request_estimate_micro) after the API call resolves (success OR failure)
    to free the slot — otherwise reservations accumulate and eventually
    block legitimate calls.

    Multi-process consistency: each process tracks its own reservations
    independently — operators wanting cross-process consistency must use
    a shared ledger file via flock AND coordinate trace_id manually
    (documented in CHANGELOG cycle-095 multi-process section).
    """
    if cap_micro is None or cap_micro <= 0:
        return
    if request_estimate_micro < 0:
        request_estimate_micro = 0

    with _SESSION_CAP_LOCK:
        current_total = _read_session_total(ledger_path, trace_id)
        pending = _SESSION_RESERVATIONS.get(trace_id, 0)
        prospective = current_total + pending + request_estimate_micro
        if prospective > cap_micro:
            raise CostBudgetExceeded(
                spent=current_total + pending,
                limit=cap_micro,
            )
        # Reserve the slot — atomic with the check above.
        _SESSION_RESERVATIONS[trace_id] = pending + request_estimate_micro


def release_session_reservation(trace_id: str, reservation_micro: int) -> None:
    """Release an in-process reservation taken by check_session_cap_pre.

    Idempotent and safe to call when no reservation exists (releases 0).
    Caller MUST call this on the success AND failure path of the API call —
    otherwise reservations accumulate and eventually block legitimate calls.
    Recommended pattern: try/finally around the API call.
    """
    if reservation_micro <= 0:
        return
    with _SESSION_CAP_LOCK:
        current = _SESSION_RESERVATIONS.get(trace_id, 0)
        new = max(0, current - reservation_micro)
        if new == 0:
            _SESSION_RESERVATIONS.pop(trace_id, None)
        else:
            _SESSION_RESERVATIONS[trace_id] = new


def _reset_session_reservations_for_tests() -> None:
    """Test fixture hook — clears the in-process reservation tracker."""
    with _SESSION_CAP_LOCK:
        _SESSION_RESERVATIONS.clear()


def check_session_cap_post(
    trace_id: str,
    ledger_path: str,
    cap_micro: Optional[int],
) -> None:
    """Post-call session cap reconciliation (SDD §1.4.4 observability).

    Logs WARN if actual session total exceeds cap. Should not fire in
    practice — the pre-call estimate is a worst-case upper bound, so the
    actual cost is always ≤ prospective. If this WARN fires, it means
    either (a) the pre-call estimate was wrong, or (b) the multi-process
    soft-cap nature manifested. Both are operator-investigation signals.
    """
    if cap_micro is None or cap_micro <= 0:
        return
    actual_total = _read_session_total(ledger_path, trace_id)
    if actual_total > cap_micro:
        logger.warning(
            "Session cap reconciliation: trace_id=%s actual=%d > cap=%d. "
            "If single-process: investigate pre-call estimate accuracy. "
            "If multi-process: per-process caps don't share — coordinate trace_id "
            "manually for shared-budget workflows.",
            trace_id, actual_total, cap_micro,
        )
