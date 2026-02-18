"""Budget enforcement — pre/post call hooks (SDD §4.5.3).

Implements BudgetHook protocol from retry.py:
- Pre-call: Check daily spend vs budget, return ALLOW/WARN/DOWNGRADE/BLOCK
- Post-call: Record cost to ledger and update daily spend counter
- Atomic pre-call: flock-protected check+reserve (Sprint 3 Task 3.3)
"""

from __future__ import annotations

import fcntl
import json
import logging
import os
from datetime import datetime, timezone
from typing import Any, Dict, Optional, Set

from loa_cheval.metering.ledger import (
    _daily_spend_path,
    create_ledger_entry,
    read_daily_spend,
    record_cost,
)
from loa_cheval.types import BudgetExceededError, CompletionRequest, CompletionResult

logger = logging.getLogger("loa_cheval.metering.budget")


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
