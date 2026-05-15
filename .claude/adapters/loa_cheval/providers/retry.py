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
from loa_cheval.redaction import sanitize_provider_error_message
from loa_cheval.types import (
    CompletionRequest,
    CompletionResult,
    ChevalError,
    ConnectionLostError,
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


# --- Circuit breaker (cycle-110: keyed on (provider, auth_type) — FR-0) ---


def _adapter_auth_type(adapter: "ProviderAdapter") -> str:
    """Resolve the auth_type bucket for an adapter.

    Cycle-110 FR-2.3 (sprint-2b2a): every adapter class declares `auth_type`
    explicitly via ProviderAdapter base + per-class overrides. The sprint-1
    `getattr(..., default="http_api")` fallback is RETIRED — adapters MUST
    label themselves, and a missing label is a programming error (the base
    class always defines `auth_type: str = "http_api"`, so the only way this
    helper sees no attribute is if an out-of-tree adapter forgot to inherit
    from ProviderAdapter).

    Closes BB #903 iter-1 F7 + iter-2 F-001 (REFRAME) fail-loud per
    `feedback_bb_plateau_via_reframe.md` — the sprint-2 PRs are the
    structural fix; this helper now reads the declared attribute directly.
    """
    auth_type = getattr(adapter, "auth_type", None)
    # Accept only declared-string auth_type values. MagicMock and other
    # synthetic attributes (auto-generated test doubles) read as non-str —
    # treat as "not declared" and fall back to http_api conservatively
    # without raising, since the test surface is well-controlled. Real
    # adapters inheriting from ProviderAdapter ALWAYS get the base
    # `auth_type: str = "http_api"` class default, then headless/bedrock
    # subclasses override.
    if not isinstance(auth_type, str):
        return "http_api"
    if auth_type not in ("headless", "http_api", "aws_iam"):
        raise ValueError(
            f"adapter {type(adapter).__name__} declares "
            f"auth_type={auth_type!r}; allowed: headless, http_api, aws_iam"
        )
    return auth_type


# Cycle-110 SDD §5.3 starvation guard: exponential-backoff retry envelope
# wrapping the migration timeout. Per SDD: "bash callers wrap migration in a
# 3-retry exponential backoff (1s/2s/4s) before treating MigrationTimeout as
# fatal." Implemented Python-side because retry.py is the canonical caller.
_CB_MIGRATION_RETRY_DELAYS = (1.0, 2.0, 4.0)


def _check_circuit_breaker(
    provider: str, auth_type: str, config: Dict[str, Any]
) -> str:
    """Check circuit breaker state for a (provider, auth_type) bucket.

    Returns: 'CLOSED', 'OPEN', 'HALF_OPEN'.
    Reads .run/circuit-breaker-{provider}-{auth_type}.json.

    Wraps the underlying call in an SDD §5.3 starvation guard: if the
    legacy-migration flock cannot be acquired within its 10s timeout, retry
    with exponential backoff (1s / 2s / 4s). After exhausting retries,
    degrade fail-CLOSED-but-treated-as-OPEN: we cannot read the bucket
    state safely, so we refuse the dispatch rather than crash with an
    unhandled typed exception.
    """
    from loa_cheval.routing.circuit_breaker import (
        CircuitBreakerMigrationTimeout, check_state,
    )

    last_exc: Optional[CircuitBreakerMigrationTimeout] = None
    for attempt in range(len(_CB_MIGRATION_RETRY_DELAYS) + 1):
        try:
            return check_state(provider, auth_type, config)
        except CircuitBreakerMigrationTimeout as exc:
            last_exc = exc
            if attempt >= len(_CB_MIGRATION_RETRY_DELAYS):
                break
            delay = _CB_MIGRATION_RETRY_DELAYS[attempt]
            logger.warning(
                "CB migration lock contended for %s/%s "
                "(attempt %d/%d, holder_pid=%d) — backing off %ss",
                provider, auth_type,
                attempt + 1, len(_CB_MIGRATION_RETRY_DELAYS) + 1,
                exc.holder_pid, delay,
            )
            time.sleep(delay)
    # Starvation: cannot read bucket state. Treat as OPEN (fail-closed) so the
    # caller skips this adapter rather than blowing up.
    holder_pid = last_exc.holder_pid if last_exc else 0
    logger.error(
        "CB migration starvation for %s/%s after %d retries (holder_pid=%d) "
        "— degrading to OPEN",
        provider, auth_type,
        len(_CB_MIGRATION_RETRY_DELAYS) + 1,
        holder_pid,
    )
    # BB iter-1 F4 closure: emit a distinct [L4-CB-STARVATION] marker to the
    # substrate-health journal so operators can distinguish 'circuit tripped
    # from failures' from 'circuit unreadable due to flock contention'. The
    # write is best-effort — if it fails, the caller has already logged the
    # ERROR-level diagnostic above.
    _emit_cb_starvation_marker(provider, auth_type, holder_pid, "degraded-to-OPEN")
    return "OPEN"


def _emit_cb_starvation_marker(
    provider: str, auth_type: str, holder_pid: int, action: str,
) -> None:
    """Emit `[L4-CB-STARVATION]` to substrate-health journal. Best-effort."""
    try:
        from loa_cheval.routing.circuit_breaker import _emit_journal_marker
        _emit_journal_marker(
            ".run",
            "L4-CB-STARVATION",
            {
                "provider": provider,
                "auth_type": auth_type,
                "holder_pid": holder_pid,
                "retries": len(_CB_MIGRATION_RETRY_DELAYS) + 1,
                "action": action,
            },
        )
    except Exception:  # noqa: BLE001 — observability is best-effort
        pass


def _with_cb_migration_retry(
    fn: Callable[..., Any],
    *args: Any,
    on_starvation_value: Optional[Any] = None,
    starvation_action: str = "degraded-to-noop",
    provider_for_log: str = "<unknown>",
    auth_type_for_log: str = "<unknown>",
) -> Any:
    """BB iter-2 F5 closure: shared SDD §5.3 starvation-retry envelope.

    Wraps any callable that may raise `CircuitBreakerMigrationTimeout` in the
    canonical (1s, 2s, 4s) exponential-backoff retry envelope. On exhaustion,
    logs ERROR + emits [L4-CB-STARVATION] journal marker + returns the
    caller-provided `on_starvation_value` (None for record_* paths which are
    fire-and-forget; "OPEN" for check_state).

    Symmetric application across check / record_failure / record_success
    closes BB iter-2 F5: asymmetric envelopes were a known source of
    intermittent crashes under migration-lock contention.
    """
    from loa_cheval.routing.circuit_breaker import CircuitBreakerMigrationTimeout

    last_exc: Optional[CircuitBreakerMigrationTimeout] = None
    for attempt in range(len(_CB_MIGRATION_RETRY_DELAYS) + 1):
        try:
            return fn(*args)
        except CircuitBreakerMigrationTimeout as exc:
            last_exc = exc
            if attempt >= len(_CB_MIGRATION_RETRY_DELAYS):
                break
            delay = _CB_MIGRATION_RETRY_DELAYS[attempt]
            logger.warning(
                "CB migration lock contended for %s/%s "
                "(attempt %d/%d, holder_pid=%d) — backing off %ss",
                provider_for_log, auth_type_for_log,
                attempt + 1, len(_CB_MIGRATION_RETRY_DELAYS) + 1,
                exc.holder_pid, delay,
            )
            time.sleep(delay)
    holder_pid = last_exc.holder_pid if last_exc else 0
    logger.error(
        "CB migration starvation for %s/%s on %s after %d retries "
        "(holder_pid=%d) — %s",
        provider_for_log, auth_type_for_log,
        fn.__name__, len(_CB_MIGRATION_RETRY_DELAYS) + 1,
        holder_pid, starvation_action,
    )
    _emit_cb_starvation_marker(
        provider_for_log, auth_type_for_log, holder_pid, starvation_action,
    )
    return on_starvation_value


def _record_failure(
    provider: str, auth_type: str, config: Dict[str, Any]
) -> None:
    """Record a failure for the (provider, auth_type) bucket.

    BB iter-2 F5 closure: wrapped in the SDD §5.3 starvation envelope so
    a long-held migration lock cannot crash the record path. record_*
    is fire-and-forget; on starvation we degrade to no-op (the next
    invocation's check_state will re-evaluate).
    """
    from loa_cheval.routing.circuit_breaker import record_failure

    _with_cb_migration_retry(
        record_failure, provider, auth_type, config,
        on_starvation_value=None,
        starvation_action="degraded-record-failure-to-noop",
        provider_for_log=provider, auth_type_for_log=auth_type,
    )


def _record_success(
    provider: str, auth_type: str, config: Dict[str, Any]
) -> None:
    """Record a success for the (provider, auth_type) bucket.

    BB iter-2 F5 closure: same symmetric starvation envelope as
    _record_failure. On starvation, no-op (lose this success-credit;
    the circuit breaker's worst case is staying OPEN slightly longer).
    """
    from loa_cheval.routing.circuit_breaker import record_success

    _with_cb_migration_retry(
        record_success, provider, auth_type, config,
        on_starvation_value=None,
        starvation_action="degraded-record-success-to-noop",
        provider_for_log=provider, auth_type_for_log=auth_type,
    )


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
    # Issue #774: track the typed exception alongside the string so the
    # final RetriesExhaustedError can carry structured failure metadata
    # (used by cheval.py to emit `failure_class: PROVIDER_DISCONNECT`).
    last_typed_error: Optional[ChevalError] = None

    for attempt in range(max_retries + 1):
        # Global attempt budget check
        total_attempts += 1
        if total_attempts > max_total:
            # T3.3 / AC-3.3: sanitize the upstream-bytes-derived final-cause
            # chain so secret shapes (AKIA / PEM / Bearer / provider keys)
            # don't reach RetriesExhaustedError.last_error.
            raise RetriesExhaustedError(
                total_attempts=total_attempts - 1,
                last_error=sanitize_provider_error_message(
                    f"Global attempt limit ({max_total}) reached. "
                    f"Last error: {last_error}"
                ),
            )

        # Budget check BEFORE each attempt
        budget_status = budget_hook.pre_call(request)
        if budget_status == "BLOCK":
            from loa_cheval.types import BudgetExceededError
            raise BudgetExceededError(spent=0, limit=0)
        elif budget_status == "DOWNGRADE":
            logger.warning("Budget downgrade triggered — continuing with current model")

        # Circuit breaker check (cycle-110 FR-0: keyed on (provider, auth_type))
        auth_type = _adapter_auth_type(adapter)
        cb_state = _check_circuit_breaker(adapter.provider, auth_type, config)
        if cb_state == "OPEN":
            logger.info(
                "Circuit breaker OPEN for %s/%s, skipping",
                adapter.provider, auth_type,
            )
            last_error = f"Circuit open for {adapter.provider}/{auth_type}"
            # Don't count against retries — just skip
            continue

        start = time.monotonic()
        try:
            result = adapter.complete(request)
            latency_ms = int((time.monotonic() - start) * 1000)

            # Post-call hooks
            budget_hook.post_call(result)
            metrics_hook.record_attempt(adapter.provider, True, latency_ms)
            _record_success(adapter.provider, auth_type, config)

            return result

        except RateLimitError as e:
            latency_ms = int((time.monotonic() - start) * 1000)
            metrics_hook.record_attempt(adapter.provider, False, latency_ms)
            _record_failure(adapter.provider, auth_type, config)
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
            _record_failure(adapter.provider, auth_type, config)
            last_error = str(e)

            logger.warning(
                "Provider %s unavailable (attempt %d/%d): %s",
                adapter.provider, attempt + 1, max_retries + 1, e,
            )

            # Provider unavailable — no retry on same provider, move on
            break

        except ConnectionLostError as e:
            # Issue #774: classify httpx connection-loss as a typed transient.
            # Pre-fix, the underlying httpx.RemoteProtocolError landed in the
            # bare `except Exception:` arm below and produced the misleading
            # "Unexpected error from %s" log line plus an operator pointer to
            # `--per-call-max-tokens 4096` — a remedy that is a no-op against
            # the cheval.py default of 4096 (issue body, sub-issue 3).
            #
            # The remediation hint here MUST NOT recommend that flag.
            latency_ms = int((time.monotonic() - start) * 1000)
            metrics_hook.record_attempt(adapter.provider, False, latency_ms)
            _record_failure(adapter.provider, auth_type, config)
            last_error = str(e)
            last_typed_error = e

            logger.warning(
                "Connection lost from %s after %dB request "
                "(transport=%s, attempt %d/%d) — likely server-side disconnect "
                "on long prompt. Tip: --per-call-max-tokens has no effect on "
                "this failure mode (cheval default=4096). See issue #774.",
                adapter.provider,
                e.request_size_bytes or 0,
                e.transport_class or "unknown",
                attempt + 1,
                max_retries + 1,
            )

            # Transient: retry with exponential backoff (counts against budget)
            if attempt < max_retries:
                delay = base_delay * (2 ** attempt) + random.uniform(0, 1)
                time.sleep(delay)

        except ChevalError:
            # Non-retryable errors propagate immediately
            raise

        except Exception as e:
            latency_ms = int((time.monotonic() - start) * 1000)
            metrics_hook.record_attempt(adapter.provider, False, latency_ms)
            _record_failure(adapter.provider, auth_type, config)
            last_error = str(e)

            logger.warning(
                "Unexpected error from %s (attempt %d/%d): %s",
                adapter.provider, attempt + 1, max_retries + 1, e,
            )
            # Unexpected errors get one retry with backoff
            if attempt < max_retries:
                delay = base_delay * (2 ** attempt) + random.uniform(0, 1)
                time.sleep(delay)

    # Issue #774: surface typed metadata when the last error was a typed
    # ConnectionLostError so cheval.py can emit failure_class on stderr.
    last_error_class: Optional[str] = None
    last_error_context: Optional[Dict[str, Any]] = None
    if isinstance(last_typed_error, ConnectionLostError):
        last_error_class = "ConnectionLostError"
        last_error_context = {
            "provider": last_typed_error.provider or adapter.provider,
            "transport_class": last_typed_error.transport_class,
            "request_size_bytes": last_typed_error.request_size_bytes,
        }

    # T3.3 / AC-3.3: sanitize the final-cause chain.
    raise RetriesExhaustedError(
        total_attempts=total_attempts,
        last_error=sanitize_provider_error_message(last_error),
        last_error_class=last_error_class,
        last_error_context=last_error_context,
    )
