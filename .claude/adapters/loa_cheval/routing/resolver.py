"""Alias resolution and agent binding lookup (SDD §4.1.2, §2.3)."""

from __future__ import annotations

import logging
from typing import Any, Dict, List, Optional, Set

from loa_cheval.types import (
    AgentBinding,
    ConfigError,
    InvalidInputError,
    NativeRuntimeRequired,
    ResolvedModel,
)

logger = logging.getLogger("loa_cheval.routing")

# Reserved alias — always resolves to Claude Code session, cannot be reassigned (SDD §2.3)
NATIVE_ALIAS = "native"
NATIVE_PROVIDER = "claude-code"
NATIVE_MODEL = "session"


def resolve_alias(
    alias: str,
    aliases: Dict[str, str],
    max_depth: int = 10,
) -> ResolvedModel:
    """Resolve an alias to a provider:model-id pair.

    Handles chained aliases (alias → alias → provider:model).
    Detects circular references.

    Args:
        alias: The alias name to resolve.
        aliases: Mapping of alias → target (either another alias or "provider:model-id").
        max_depth: Maximum resolution depth for chained aliases.

    Returns:
        ResolvedModel with provider and model_id.

    Raises:
        ConfigError: On circular references or unknown aliases.
    """
    # Reserved alias — always native
    if alias == NATIVE_ALIAS:
        return ResolvedModel(provider=NATIVE_PROVIDER, model_id=NATIVE_MODEL)

    # Direct provider:model format (not an alias)
    if ":" in alias:
        parts = alias.split(":", 1)
        return ResolvedModel(provider=parts[0], model_id=parts[1])

    visited: Set[str] = set()
    current = alias

    for _ in range(max_depth):
        if current in visited:
            chain = " → ".join(list(visited) + [current])
            raise ConfigError(f"Circular alias reference detected: {chain}")

        visited.add(current)

        if current not in aliases:
            raise ConfigError(f"Unknown alias: '{current}'. Available aliases: {sorted(aliases.keys())}")

        target = aliases[current]

        # If target is provider:model format, we're done
        if ":" in target:
            parts = target.split(":", 1)
            return ResolvedModel(provider=parts[0], model_id=parts[1])

        # Otherwise it's another alias — keep resolving
        current = target

    raise ConfigError(f"Alias resolution exceeded max depth ({max_depth}): {alias}")


def resolve_agent_binding(
    agent_name: str,
    config: Dict[str, Any],
) -> AgentBinding:
    """Look up agent binding from config.

    Args:
        agent_name: The agent name (e.g., "reviewing-code").
        config: Merged hounfour config dict.

    Returns:
        AgentBinding for the agent.

    Raises:
        InvalidInputError: If agent not found in config.
    """
    agents = config.get("agents", {})

    if agent_name not in agents:
        available = sorted(agents.keys())
        raise InvalidInputError(
            f"Unknown agent: '{agent_name}'. Available agents: {available}"
        )

    agent_config = agents[agent_name]
    return AgentBinding(
        agent=agent_name,
        model=agent_config.get("model", NATIVE_ALIAS),
        temperature=agent_config.get("temperature"),
        persona=agent_config.get("persona"),
        requires=agent_config.get("requires", {}),
    )


def resolve_execution(
    agent_name: str,
    config: Dict[str, Any],
    model_override: Optional[str] = None,
) -> tuple:
    """Full resolution pipeline: agent → binding → alias → provider:model.

    Returns (AgentBinding, ResolvedModel).

    Raises:
        NativeRuntimeRequired: If agent requires native_runtime.
        ConfigError: On invalid config.
        InvalidInputError: On unknown agent.
    """
    binding = resolve_agent_binding(agent_name, config)
    model_ref = model_override or binding.model

    # Native runtime guard (SDD §2.3)
    if binding.requires and binding.requires.get("native_runtime"):
        if model_ref == NATIVE_ALIAS or (model_ref == f"{NATIVE_PROVIDER}:{NATIVE_MODEL}"):
            # Technically valid — agent is bound to native, just return
            resolved = ResolvedModel(provider=NATIVE_PROVIDER, model_id=NATIVE_MODEL)
            return binding, resolved
        # Agent requires native but was requested on a remote model
        raise NativeRuntimeRequired(agent_name)

    # Resolve alias → provider:model
    aliases = config.get("aliases", {})
    resolved = resolve_alias(model_ref, aliases)

    # If resolved to native after alias resolution, check native_runtime guard
    if resolved.provider == NATIVE_PROVIDER:
        return binding, resolved

    return binding, resolved


def validate_bindings(config: Dict[str, Any]) -> List[str]:
    """Validate all agent bindings resolve correctly.

    Used by `model-invoke --validate-bindings`.

    Returns list of error strings (empty = valid).
    """
    errors = []
    agents = config.get("agents", {})
    aliases = config.get("aliases", {})
    providers = config.get("providers", {})

    for agent_name, agent_config in agents.items():
        model_ref = agent_config.get("model", NATIVE_ALIAS)

        try:
            # Check alias resolves
            resolved = resolve_alias(model_ref, aliases)

            # Check provider exists (unless native)
            if resolved.provider != NATIVE_PROVIDER:
                if resolved.provider not in providers:
                    errors.append(
                        f"Agent '{agent_name}': model '{model_ref}' resolves to provider "
                        f"'{resolved.provider}' which is not configured"
                    )

                # Check model exists in provider
                provider_config = providers.get(resolved.provider, {})
                provider_models = provider_config.get("models", {})
                if resolved.model_id not in provider_models:
                    errors.append(
                        f"Agent '{agent_name}': model '{resolved.model_id}' not found in "
                        f"provider '{resolved.provider}' models"
                    )

            # Check capabilities if requirements specified
            requires = agent_config.get("requires", {})
            if requires and resolved.provider != NATIVE_PROVIDER:
                provider_config = providers.get(resolved.provider, {})
                model_config = provider_config.get("models", {}).get(resolved.model_id, {})
                capabilities = model_config.get("capabilities", [])

                for req_key, req_value in requires.items():
                    if req_key == "native_runtime":
                        continue  # Handled separately
                    if req_value is True and req_key not in capabilities:
                        errors.append(
                            f"Agent '{agent_name}': requires '{req_key}' but model "
                            f"'{resolved.model_id}' does not list it in capabilities"
                        )
                    elif req_value == "preferred" and req_key not in capabilities:
                        # Preferred is a soft requirement — log warning, not error
                        logger.warning(
                            "Agent '%s' prefers '%s' but model '%s' does not support it",
                            agent_name, req_key, resolved.model_id,
                        )

        except ConfigError as e:
            errors.append(f"Agent '{agent_name}': {e}")

    # Check for alias cycles
    try:
        _detect_alias_cycles(aliases)
    except ConfigError as e:
        errors.append(str(e))

    return errors


def _detect_alias_cycles(aliases: Dict[str, str]) -> None:
    """DFS-based cycle detection for alias graph."""
    for alias in aliases:
        if alias == NATIVE_ALIAS:
            continue
        visited: Set[str] = set()
        current = alias
        while current in aliases and ":" not in aliases.get(current, ":"):
            if current in visited:
                raise ConfigError(f"Circular alias chain detected starting from '{alias}'")
            visited.add(current)
            current = aliases[current]
