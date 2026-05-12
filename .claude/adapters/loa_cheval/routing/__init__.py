"""Routing — alias resolution, agent binding, chain walking, circuit breaker, context filtering."""

from loa_cheval.routing.resolver import (
    NATIVE_ALIAS,
    NATIVE_PROVIDER,
    NATIVE_MODEL,
    resolve_alias,
    resolve_agent_binding,
    resolve_execution,
    validate_bindings,
)
from loa_cheval.routing.chains import (
    validate_chains,
    walk_downgrade_chain,
    walk_fallback_chain,
)
from loa_cheval.routing.circuit_breaker import (
    CLOSED,
    HALF_OPEN,
    OPEN,
    check_state,
    cleanup_stale_files,
    record_failure,
    record_success,
)
from loa_cheval.routing.context_filter import (
    audit_filter_context,
    filter_context,
    filter_message_content,
    get_context_access,
    invalidate_permissions_cache,
    lookup_trust_scopes,
)

# cycle-104 Sprint 2 (SDD §1.4.1, §1.4.2, §3.1, §5.1, §5.2): within-company
# chain resolver + capability gate. Coexist with cycle-095 walk_fallback_chain;
# new call sites use resolve()/check() upfront.
from loa_cheval.routing.chain_resolver import (
    DEFAULT_HEADLESS_MODE,
    resolve,
    resolve_headless_mode,
)
from loa_cheval.routing.capability_gate import check as capability_check
from loa_cheval.routing.types import (
    ADAPTER_KINDS,
    HEADLESS_MODES,
    HEADLESS_MODE_SOURCES,
    AdapterKind,
    CapabilityCheckResult,
    ChainExhaustedError,
    EmptyContentError,
    HeadlessMode,
    HeadlessModeSource,
    NoEligibleAdapterError,
    ResolvedChain,
    ResolvedEntry,
)

__all__ = [
    "ADAPTER_KINDS",
    "AdapterKind",
    "CLOSED",
    "CapabilityCheckResult",
    "ChainExhaustedError",
    "DEFAULT_HEADLESS_MODE",
    "EmptyContentError",
    "HALF_OPEN",
    "HEADLESS_MODES",
    "HEADLESS_MODE_SOURCES",
    "HeadlessMode",
    "HeadlessModeSource",
    "NATIVE_ALIAS",
    "NATIVE_MODEL",
    "NATIVE_PROVIDER",
    "NoEligibleAdapterError",
    "OPEN",
    "ResolvedChain",
    "ResolvedEntry",
    "audit_filter_context",
    "capability_check",
    "check_state",
    "invalidate_permissions_cache",
    "cleanup_stale_files",
    "filter_context",
    "filter_message_content",
    "get_context_access",
    "lookup_trust_scopes",
    "record_failure",
    "record_success",
    "resolve",
    "resolve_alias",
    "resolve_agent_binding",
    "resolve_execution",
    "resolve_headless_mode",
    "validate_bindings",
    "validate_chains",
    "walk_downgrade_chain",
    "walk_fallback_chain",
]
