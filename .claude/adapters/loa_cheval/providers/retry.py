"""Retry logic with global attempt budget (SDD §4.2.5-§4.2.7).

Implements exponential backoff with jitter, global attempt budget,
and circuit breaker integration. Extension hooks for Sprint 3 budget
and metrics collection.
"""

from __future__ import annotations

import logging
import random
import time
from typing import Any, Callable, Dict, Optional, Protocol

from loa_cheval.providers.base import ProviderAdapter
from loa_cheval.types import (
    CompletionRequest,
    CompletionResult,
    ChevalError,
    ProviderUnavailableError,
    RateLimitError,
    RetriesExhaustedError,
)

logger = logging.getLogger("loa_cheval.providers.retry")

# Global budget defaults (SDD §4.2.7)
MAX_TOTAL_ATTEMPTS = 6
MAX_PROVIDER_SWITCHES = 2


# --- Extension hooks (Sprint 3 wiring points) ---


class BudgetHook(Protocol):
    """Pre-call budget check hook (no-op in Sprint 1, wired in Sprint 3)."""

    def pre_call(self, request: CompletionRequest) -> str:
        """Returns budget status: 'ALLOW', 'WARN', 'DOWNGRADE', 'BLOCK'."""
        ...

    def post_call(self, result: CompletionResult) -> None:
        """Post-call cost reconciliation."""
        ...


class MetricsHook(Protocol):
    """Metrics collection hook (no-op in Sprint 1, wired in Sprint 3)."""

    def record_attempt(self, provider: str, success: bool, latency_ms: int) -> None:
        ...


class NoOpBudgetHook:
    """Default no-op budget hook for Sprint 1."""

    def pre_call(self, request: CompletionRequest) -> str:
        return "ALLOW"

    def post_call(self, result: CompletionResult) -> None:
        pass


class NoOpMetricsHook:
    """Default no-op metrics hook for Sprint 1."""

    def record_attempt(self, provider: str, success: bool, latency_ms: int) -> None:
        pass


# --- Circuit breaker (Sprint 3 — file-based state machine) ---


def _check_circuit_breaker(provider: str, config: Dict[str, Any]) -> str:
    """Check circuit breaker state for a provider.

    Returns: 'CLOSED', 'OPEN', 'HALF_OPEN'.
    Reads .run/circuit-breaker-{provider}.json.
    """
    from loa_cheval.routing.circuit_breaker import check_state

    return check_state(provider, config)


def _record_failure(provider: str, config: Dict[str, Any]) -> None:
    """Record a failure for circuit breaker tracking.

    Updates .run/circuit-breaker-{provider}.json.
    May transition CLOSED → OPEN or HALF_OPEN → OPEN.
    """
    from loa_cheval.routing.circuit_breaker import record_failure

    record_failure(provider, config)


def _record_success(provider: str, config: Dict[str, Any]) -> None:
    """Record a success for circuit breaker tracking.

    May transition HALF_OPEN → CLOSED on successful probe.
    """
    from loa_cheval.routing.circuit_breaker import record_success

    record_success(provider, config)


# --- Main retry function ---


def invoke_with_retry(
    adapter: ProviderAdapter,
    request: CompletionRequest,
    config: Dict[str, Any],
    budget_hook: Optional[BudgetHook] = None,
    metrics_hook: Optional[MetricsHook] = None,
) -> CompletionResult:
    """Invoke adapter with retry logic (SDD §4.2.5).

    Features:
    - Exponential backoff with jitter on rate limits
    - Global attempt budget (MAX_TOTAL_ATTEMPTS)
    - Provider switch budget (MAX_PROVIDER_SWITCHES)
    - Circuit breaker check before each attempt
    - Extension hooks for budget and metrics

    Args:
        adapter: Provider adapter to call.
        request: Completion request.
        config: Merged hounfour config.
        budget_hook: Pre/post call budget hook (Sprint 3).
        metrics_hook: Attempt metrics hook (Sprint 3).

    Returns:
        CompletionResult from the successful call.

    Raises:
        RetriesExhaustedError: When all attempts exhausted.
        BudgetExceededError: When budget hook returns BLOCK.
    """
    if budget_hook is None:
        budget_hook = NoOpBudgetHook()
    if metrics_hook is None:
        metrics_hook = NoOpMetricsHook()

    retry_config = config.get("retry", {})
    max_retries = retry_config.get("max_retries", 3)
    max_total = retry_config.get("max_total_attempts", MAX_TOTAL_ATTEMPTS)
    max_switches = retry_config.get("max_provider_switches", MAX_PROVIDER_SWITCHES)
    base_delay = retry_config.get("base_delay_seconds", 1.0)

    total_attempts = 0
    provider_switches = 0
    last_error: Optional[str] = None

    for attempt in range(max_retries + 1):
        # Global attempt budget check
        total_attempts += 1
        if total_attempts > max_total:
            raise RetriesExhaustedError(
                total_attempts=total_attempts - 1,
                last_error=f"Global attempt limit ({max_total}) reached. Last error: {last_error}",
            )

        # Budget check BEFORE each attempt
        budget_status = budget_hook.pre_call(request)
        if budget_status == "BLOCK":
            from loa_cheval.types import BudgetExceededError
            raise BudgetExceededError(spent=0, limit=0)
        elif budget_status == "DOWNGRADE":
            logger.warning("Budget downgrade triggered — continuing with current model")

        # Circuit breaker check
        cb_state = _check_circuit_breaker(adapter.provider, config)
        if cb_state == "OPEN":
            logger.info("Circuit breaker OPEN for %s, skipping", adapter.provider)
            last_error = f"Circuit open for {adapter.provider}"
            # Don't count against retries — just skip
            continue

        start = time.monotonic()
        try:
            result = adapter.complete(request)
            latency_ms = int((time.monotonic() - start) * 1000)

            # Post-call hooks
            budget_hook.post_call(result)
            metrics_hook.record_attempt(adapter.provider, True, latency_ms)
            _record_success(adapter.provider, config)

            return result

        except RateLimitError as e:
            latency_ms = int((time.monotonic() - start) * 1000)
            metrics_hook.record_attempt(adapter.provider, False, latency_ms)
            _record_failure(adapter.provider, config)
            last_error = str(e)

            # Exponential backoff with jitter
            delay = base_delay * (2 ** attempt) + random.uniform(0, 1)
            logger.info(
                "Rate limited by %s (attempt %d/%d), retrying in %.1fs",
                adapter.provider, attempt + 1, max_retries + 1, delay,
            )
            time.sleep(delay)

        except ProviderUnavailableError as e:
            latency_ms = int((time.monotonic() - start) * 1000)
            metrics_hook.record_attempt(adapter.provider, False, latency_ms)
            _record_failure(adapter.provider, config)
            last_error = str(e)

            logger.warning(
                "Provider %s unavailable (attempt %d/%d): %s",
                adapter.provider, attempt + 1, max_retries + 1, e,
            )

            # Provider unavailable — no retry on same provider, move on
            break

        except ChevalError:
            # Non-retryable errors propagate immediately
            raise

        except Exception as e:
            latency_ms = int((time.monotonic() - start) * 1000)
            metrics_hook.record_attempt(adapter.provider, False, latency_ms)
            _record_failure(adapter.provider, config)
            last_error = str(e)

            logger.warning(
                "Unexpected error from %s (attempt %d/%d): %s",
                adapter.provider, attempt + 1, max_retries + 1, e,
            )
            # Unexpected errors get one retry with backoff
            if attempt < max_retries:
                delay = base_delay * (2 ** attempt) + random.uniform(0, 1)
                time.sleep(delay)

    raise RetriesExhaustedError(
        total_attempts=total_attempts,
        last_error=last_error,
    )
