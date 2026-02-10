"""Fallback and downgrade chain walker (SDD §4.1.2 routing section).

Implements config-driven routing chains:
- Fallback: provider down → walk chain, skip entries missing required capabilities
- Downgrade: budget exceeded → walk chain to cheaper model
- Cycle detection to prevent infinite loops
- Routing decision trace logged to stderr
"""

from __future__ import annotations

import logging
from typing import Any, Dict, List, Optional, Set, Tuple

from loa_cheval.routing.resolver import resolve_alias
from loa_cheval.types import (
    AgentBinding,
    ConfigError,
    ProviderUnavailableError,
    ResolvedModel,
)

logger = logging.getLogger("loa_cheval.routing")


def walk_fallback_chain(
    original: ResolvedModel,
    agent: AgentBinding,
    config: Dict[str, Any],
    is_provider_healthy: Optional[callable] = None,
    visited: Optional[Set[str]] = None,
) -> ResolvedModel:
    """Walk fallback chain when a provider is unavailable.

    Checks capabilities and health for each candidate.
    Prevents cycles via visited set.

    Args:
        original: The originally resolved model that failed.
        agent: Agent binding with requirements.
        config: Merged hounfour config.
        is_provider_healthy: Optional health check callback(provider) -> bool.
        visited: Set of already-visited "provider:model" keys.

    Returns:
        ResolvedModel for the first valid fallback candidate.

    Raises:
        ProviderUnavailableError: If chain exhausted with no valid candidate.
    """
    if visited is None:
        visited = set()

    visited.add(f"{original.provider}:{original.model_id}")

    routing = config.get("routing", {})
    fallback_chains = routing.get("fallback", {})
    chain = fallback_chains.get(original.provider, [])

    if not chain:
        raise ProviderUnavailableError(
            original.provider,
            f"No fallback chain configured for provider '{original.provider}'",
        )

    aliases = config.get("aliases", {})
    providers = config.get("providers", {})
    requires = agent.requires or {}
    rejections: List[Dict[str, str]] = []

    for candidate in chain:
        try:
            resolved = resolve_alias(candidate, aliases)
        except ConfigError:
            rejections.append({"candidate": candidate, "reason": "cannot resolve alias"})
            continue

        canonical_key = f"{resolved.provider}:{resolved.model_id}"

        # Cycle prevention
        if canonical_key in visited:
            rejections.append(
                {"candidate": candidate, "reason": "already visited (cycle prevention)"}
            )
            continue

        # Capability check
        provider_config = providers.get(resolved.provider, {})
        model_config = provider_config.get("models", {}).get(resolved.model_id, {})
        capabilities = model_config.get("capabilities", [])

        cap_ok = True
        for req_key, req_value in requires.items():
            if req_key == "native_runtime":
                # Native runtime agents can't fall back to remote
                rejections.append(
                    {"candidate": candidate, "reason": "native_runtime required"}
                )
                cap_ok = False
                break
            if req_value is True and req_key not in capabilities:
                rejections.append(
                    {
                        "candidate": candidate,
                        "reason": f"missing capability: {req_key}",
                    }
                )
                cap_ok = False
                break

        if not cap_ok:
            continue

        # Health check
        if is_provider_healthy and not is_provider_healthy(resolved.provider):
            rejections.append(
                {"candidate": candidate, "reason": "provider unhealthy"}
            )
            continue

        visited.add(canonical_key)
        logger.info(
            "[routing] agent=%s → fallback %s:%s → %s:%s (reason: provider_unavailable)",
            agent.agent,
            original.provider,
            original.model_id,
            resolved.provider,
            resolved.model_id,
        )
        return resolved

    raise ProviderUnavailableError(
        original.provider,
        f"Fallback chain exhausted for agent '{agent.agent}' "
        f"(original: {original.provider}:{original.model_id}). "
        f"Rejections: {rejections}",
    )


def walk_downgrade_chain(
    original: ResolvedModel,
    agent: AgentBinding,
    config: Dict[str, Any],
    visited: Optional[Set[str]] = None,
) -> ResolvedModel:
    """Walk downgrade chain when budget exceeded.

    Uses the 'downgrade' routing config to find a cheaper alternative.
    Checks capabilities for each candidate.

    Args:
        original: The originally resolved model (too expensive).
        agent: Agent binding with requirements.
        config: Merged hounfour config.
        visited: Set of already-visited "provider:model" keys.

    Returns:
        ResolvedModel for the first valid downgrade candidate.

    Raises:
        ProviderUnavailableError: If chain exhausted with no valid candidate.
    """
    if visited is None:
        visited = set()

    # Track the original model's alias to find its downgrade chain
    # The downgrade config maps alias → [cheaper_alias, ...]
    routing = config.get("routing", {})
    downgrade_chains = routing.get("downgrade", {})
    aliases = config.get("aliases", {})
    providers = config.get("providers", {})
    requires = agent.requires or {}

    visited.add(f"{original.provider}:{original.model_id}")

    # Find which alias maps to this model
    # Walk downgrade chains for any alias that resolves to our provider:model
    chain = _find_downgrade_chain(original, aliases, downgrade_chains)

    if not chain:
        raise ProviderUnavailableError(
            original.provider,
            f"No downgrade chain found for {original.provider}:{original.model_id}",
        )

    rejections: List[Dict[str, str]] = []

    for candidate in chain:
        try:
            resolved = resolve_alias(candidate, aliases)
        except ConfigError:
            rejections.append({"candidate": candidate, "reason": "cannot resolve alias"})
            continue

        canonical_key = f"{resolved.provider}:{resolved.model_id}"

        if canonical_key in visited:
            rejections.append(
                {"candidate": candidate, "reason": "already visited (cycle prevention)"}
            )
            continue

        # Capability check
        provider_config = providers.get(resolved.provider, {})
        model_config = provider_config.get("models", {}).get(resolved.model_id, {})
        capabilities = model_config.get("capabilities", [])

        cap_ok = True
        for req_key, req_value in requires.items():
            if req_key == "native_runtime":
                rejections.append(
                    {"candidate": candidate, "reason": "native_runtime required"}
                )
                cap_ok = False
                break
            if req_value is True and req_key not in capabilities:
                rejections.append(
                    {
                        "candidate": candidate,
                        "reason": f"missing capability: {req_key}",
                    }
                )
                cap_ok = False
                break

        if not cap_ok:
            continue

        visited.add(canonical_key)
        logger.info(
            "[routing] agent=%s → downgrade %s:%s → %s:%s (reason: budget_exceeded)",
            agent.agent,
            original.provider,
            original.model_id,
            resolved.provider,
            resolved.model_id,
        )
        return resolved

    raise ProviderUnavailableError(
        original.provider,
        f"Downgrade chain exhausted for agent '{agent.agent}' "
        f"(original: {original.provider}:{original.model_id}). "
        f"Rejections: {rejections}",
    )


def validate_chains(config: Dict[str, Any]) -> List[str]:
    """Validate routing chains for cycles and resolvability.

    Detects circular chains at config validation time (not runtime).
    Returns list of error strings (empty = valid).
    """
    errors = []
    routing = config.get("routing", {})
    aliases = config.get("aliases", {})

    # Check fallback chains
    for provider, chain in routing.get("fallback", {}).items():
        visited: Set[str] = set()
        for candidate in chain:
            try:
                resolved = resolve_alias(candidate, aliases)
                key = f"{resolved.provider}:{resolved.model_id}"
                if key in visited:
                    errors.append(
                        f"Fallback chain for '{provider}' has cycle at '{candidate}'"
                    )
                visited.add(key)
            except ConfigError as e:
                errors.append(
                    f"Fallback chain for '{provider}': cannot resolve '{candidate}': {e}"
                )

    # Check downgrade chains
    for alias, chain in routing.get("downgrade", {}).items():
        visited = set()
        for candidate in chain:
            try:
                resolved = resolve_alias(candidate, aliases)
                key = f"{resolved.provider}:{resolved.model_id}"
                if key in visited:
                    errors.append(
                        f"Downgrade chain for '{alias}' has cycle at '{candidate}'"
                    )
                visited.add(key)
            except ConfigError as e:
                errors.append(
                    f"Downgrade chain for '{alias}': cannot resolve '{candidate}': {e}"
                )

    return errors


def _find_downgrade_chain(
    original: ResolvedModel,
    aliases: Dict[str, str],
    downgrade_chains: Dict[str, List[str]],
) -> List[str]:
    """Find the downgrade chain applicable to a resolved model.

    Matches by checking which alias in the downgrade config resolves
    to the original's provider:model.
    """
    for alias, chain in downgrade_chains.items():
        try:
            resolved = resolve_alias(alias, aliases)
            if (
                resolved.provider == original.provider
                and resolved.model_id == original.model_id
            ):
                return chain
        except ConfigError:
            continue

    return []
