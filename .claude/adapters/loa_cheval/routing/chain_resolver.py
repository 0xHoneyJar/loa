"""Within-company chain resolver (cycle-104 Sprint 2, SDD §1.4.1, §5.1).

Single chokepoint that turns `(primary_alias, headless_mode)` into the
ordered list of `ResolvedEntry` tuples cheval.invoke() walks. The within-
company invariant is enforced here: every chain entry shares the primary's
provider. Mode transforms (`prefer-api`, `prefer-cli`, `api-only`, `cli-only`)
reorder/filter the chain WITHIN the company — they never substitute another
company's adapter.

Why this lives next to `chains.py` rather than replacing it: `chains.py`
implements the cycle-095 per-call walk used by `walk_fallback_chain` for
agent-binding-driven dispatch. The Sprint 2 design resolves the chain
UPFRONT before the first request so the MODELINV envelope can record the
full intended walk shape even when only the primary is invoked. The two
designs coexist; new code calls `chain_resolver.resolve()`.
"""

from __future__ import annotations

import logging
import os
from typing import Any, Dict, List, Optional, Tuple

from loa_cheval.routing.resolver import resolve_alias
from loa_cheval.routing.types import (
    HEADLESS_MODES,
    AdapterKind,
    HeadlessMode,
    HeadlessModeSource,
    NoEligibleAdapterError,
    ResolvedChain,
    ResolvedEntry,
)
from loa_cheval.types import ConfigError, ResolvedModel

logger = logging.getLogger("loa_cheval.routing.chain_resolver")


DEFAULT_HEADLESS_MODE: HeadlessMode = "prefer-api"


# --- Public entry point (SDD §5.1) ---


def resolve(
    primary_alias: str,
    *,
    model_config: Dict[str, Any],
    headless_mode: HeadlessMode = DEFAULT_HEADLESS_MODE,
    headless_mode_source: HeadlessModeSource = "default",
) -> ResolvedChain:
    """Resolve `primary_alias` into a within-company `ResolvedChain`.

    Args:
        primary_alias: caller-supplied alias (e.g. "gpt-5.5-pro" or
            "openai:gpt-5.5-pro"). Resolves via the merged `aliases:` map.
        model_config: parsed `model-config.yaml` with `providers:` and
            `aliases:` keys.
        headless_mode: operator-selected routing mode. Default `prefer-api`
            preserves today's behavior (HTTP first, CLI last).
        headless_mode_source: provenance of the mode value, recorded into
            MODELINV `config_observed.headless_mode_source` (audit-the-mode-
            source per PRD §1.3).

    Returns:
        ResolvedChain with `entries[0]` = primary, `entries[1:]` = within-
        company fallbacks reordered/filtered per `headless_mode`. Idempotent:
        same `(primary_alias, model_config, headless_mode)` ⇒ same chain.

    Raises:
        ConfigError: primary_alias unresolvable, or referenced fallback_chain
            entry references an unknown provider or model.
        NoEligibleAdapterError: mode transform leaves zero entries (e.g.
            `cli-only` for a primary with no CLI fallback declared).
        ValueError: `headless_mode` is not a known mode literal.
    """
    if headless_mode not in HEADLESS_MODES:
        raise ValueError(
            f"chain_resolver.resolve: headless_mode must be one of "
            f"{HEADLESS_MODES}, got {headless_mode!r}"
        )

    aliases = model_config.get("aliases", {})
    providers = model_config.get("providers", {})

    # Step 1: resolve the primary alias to (provider, model_id).
    primary_resolved = resolve_alias(primary_alias, aliases)

    # Step 2: build the unfiltered, unordered entry list — primary first,
    # then each fallback_chain entry verbatim.
    raw_entries: List[ResolvedEntry] = []
    raw_entries.append(_build_entry(primary_resolved, providers))

    primary_model_cfg = _lookup_model_cfg(primary_resolved, providers)
    chain_strings = list(primary_model_cfg.get("fallback_chain") or [])
    for spec in chain_strings:
        fallback_resolved = _parse_chain_spec(spec, aliases, primary_alias)
        raw_entries.append(_build_entry(fallback_resolved, providers))

    # Step 3: enforce the within-company invariant. This is the load-bearing
    # invariant of cycle-104 Sprint 2 — no chain entry may cross company
    # boundary, because the operator's intent is to absorb provider failures
    # within their own adapter rather than substitute another company's
    # voice (which would break BB 3-company consensus diversity).
    _validate_chain(primary_alias, raw_entries)

    # Step 4: apply mode transform within the company.
    transformed = _apply_mode_transform(raw_entries, headless_mode)
    if not transformed:
        # cli-only with no CLI entry is the canonical fail-loud case.
        raise NoEligibleAdapterError(
            primary_alias=primary_alias,
            headless_mode=headless_mode,
            reason=_no_eligible_reason(raw_entries, headless_mode),
        )

    return ResolvedChain(
        primary_alias=primary_alias,
        entries=tuple(transformed),
        headless_mode=headless_mode,
        headless_mode_source=headless_mode_source,
    )


# --- Mode resolution from env + config (SDD §3.3) ---


def resolve_headless_mode(
    config: Optional[Dict[str, Any]] = None,
    env: Optional[Dict[str, str]] = None,
) -> Tuple[HeadlessMode, HeadlessModeSource]:
    """Return the effective `(headless_mode, source)` pair.

    Precedence (SDD §3.3): env `LOA_HEADLESS_MODE` ⇒ config
    `hounfour.headless.mode` ⇒ default `prefer-api`. Env wins.

    Args:
        config: optional parsed `.loa.config.yaml` dict. If `None`, only env
            and default are considered. Test fixtures pass an explicit dict.
        env: optional env mapping for tests. Defaults to `os.environ`.

    Returns:
        `(mode, source)`. `source` is one of `"env"` / `"config"` / `"default"`.

    Raises:
        ValueError: if a set source produces a value that is not one of the
            four known modes. This is fail-loud — a typo in `.loa.config.yaml`
            should not silently fall through to `prefer-api`.
    """
    env_map = env if env is not None else os.environ
    env_value = env_map.get("LOA_HEADLESS_MODE")
    if env_value is not None and env_value != "":
        _assert_valid_mode(env_value, "env LOA_HEADLESS_MODE")
        return env_value, "env"  # type: ignore[return-value]

    if config is not None:
        cfg_value = (
            (config.get("hounfour") or {}).get("headless", {}).get("mode")
        )
        if cfg_value is not None:
            _assert_valid_mode(cfg_value, "hounfour.headless.mode")
            return cfg_value, "config"  # type: ignore[return-value]

    return DEFAULT_HEADLESS_MODE, "default"


# --- Internals ---


def _build_entry(
    model: ResolvedModel,
    providers: Dict[str, Any],
) -> ResolvedEntry:
    """Construct one ResolvedEntry from a provider:model pair."""
    model_cfg = _lookup_model_cfg(model, providers)

    kind_raw = model_cfg.get("kind", "http")
    if kind_raw not in ("http", "cli"):
        raise ConfigError(
            f"Provider '{model.provider}' model '{model.model_id}' has "
            f"unknown kind={kind_raw!r} (expected 'http' or 'cli')"
        )
    adapter_kind: AdapterKind = kind_raw  # type: ignore[assignment]

    capabilities = frozenset(model_cfg.get("capabilities") or ())
    # Cycle-110 sprint-2b1 (T2.6): propagate auth_type + dispatch_group from
    # model-config into the resolved entry so downstream callers (auto-mode
    # algorithm + envelope emitter + CB key derivation) read from one source.
    # The loader already validated both fields at process start; the empty-
    # string fallback is defensive for fixture/test paths that bypass loader.
    auth_type = model_cfg.get("auth_type", "http_api") or "http_api"
    dispatch_group = model_cfg.get("dispatch_group", "") or ""
    return ResolvedEntry(
        provider=model.provider,
        model_id=model.model_id,
        adapter_kind=adapter_kind,
        capabilities=capabilities,
        auth_type=auth_type,
        dispatch_group=dispatch_group,
    )


def _lookup_model_cfg(
    model: ResolvedModel,
    providers: Dict[str, Any],
) -> Dict[str, Any]:
    """Return the per-model config block, raising ConfigError if missing."""
    provider_cfg = providers.get(model.provider)
    if provider_cfg is None:
        raise ConfigError(
            f"Provider '{model.provider}' not declared in providers: "
            f"{sorted(providers.keys())}"
        )
    models = provider_cfg.get("models") or {}
    model_cfg = models.get(model.model_id)
    if model_cfg is None:
        raise ConfigError(
            f"Model '{model.provider}:{model.model_id}' not declared in "
            f"providers.{model.provider}.models (available: "
            f"{sorted(models.keys())})"
        )
    return model_cfg


def _parse_chain_spec(
    spec: str,
    aliases: Dict[str, str],
    primary_alias: str,
) -> ResolvedModel:
    """Parse one fallback_chain entry into a ResolvedModel.

    Chain entries are normally `provider:model_id`, but plain aliases are
    accepted for forward-compat. Forbidden: empty / whitespace-only spec.
    """
    if not isinstance(spec, str) or not spec.strip():
        raise ConfigError(
            f"fallback_chain entry for primary='{primary_alias}' must be a "
            f"non-empty string, got {spec!r}"
        )
    try:
        return resolve_alias(spec, aliases)
    except ConfigError as exc:
        raise ConfigError(
            f"fallback_chain entry '{spec}' for primary='{primary_alias}' "
            f"could not be resolved: {exc}"
        ) from exc


def _validate_chain(
    primary_alias: str,
    entries: List[ResolvedEntry],
) -> None:
    """Enforce the within-company invariant + duplicate detection.

    Within-company: every entry shares the primary's provider. Cross-company
    fallback is a Sprint 2 cycle-exit goal (G1 — 3-company BB consensus
    diversity restored); a cross-company chain entry would silently undo
    that.

    Duplicate detection: a chain like `[A, B, A]` is a configuration error;
    the audit envelope's `models_failed[]` would record the same model twice
    and the operator could not distinguish the two failures.
    """
    if not entries:
        raise ConfigError(
            f"chain for primary='{primary_alias}' resolved to zero entries"
        )

    company = entries[0].provider
    seen: Dict[str, int] = {}
    for idx, entry in enumerate(entries):
        if entry.provider != company:
            raise ConfigError(
                f"fallback_chain for primary='{primary_alias}' crosses "
                f"company boundary at position {idx}: "
                f"{entry.canonical} (primary company={company!r}). "
                "Cross-company chains are forbidden — operator intent is "
                "within-company absorption (cycle-104 G1, SDD §1.4.1)."
            )
        if entry.canonical in seen:
            raise ConfigError(
                f"fallback_chain for primary='{primary_alias}' has duplicate "
                f"entry {entry.canonical} at positions "
                f"{seen[entry.canonical]} and {idx}"
            )
        seen[entry.canonical] = idx


def _apply_mode_transform(
    entries: List[ResolvedEntry],
    mode: HeadlessMode,
) -> List[ResolvedEntry]:
    """Reorder / filter entries within the company per `mode`.

    All transforms are stable (preserve relative order within each kind)
    so the operator-visible chain is predictable from the YAML order.
    """
    if mode == "prefer-api":
        http = [e for e in entries if e.adapter_kind == "http"]
        cli = [e for e in entries if e.adapter_kind == "cli"]
        return http + cli
    if mode == "prefer-cli":
        cli = [e for e in entries if e.adapter_kind == "cli"]
        http = [e for e in entries if e.adapter_kind == "http"]
        return cli + http
    if mode == "api-only":
        return [e for e in entries if e.adapter_kind == "http"]
    if mode == "cli-only":
        return [e for e in entries if e.adapter_kind == "cli"]
    # _assert_valid_mode in resolve() forbids this; defensive only.
    raise ValueError(f"Unknown headless_mode={mode!r}")


def _no_eligible_reason(
    raw_entries: List[ResolvedEntry],
    mode: HeadlessMode,
) -> str:
    """Compose a human-readable diagnostic for NoEligibleAdapterError."""
    canonicals = [e.canonical for e in raw_entries]
    if mode == "cli-only":
        return (
            "cli-only mode requires at least one CLI (kind: cli) entry; "
            f"chain has only HTTP adapters: {canonicals}. Either declare a "
            "headless alias in model-config.yaml or run in a mode that "
            "permits HTTP (prefer-api / prefer-cli / api-only)."
        )
    if mode == "api-only":
        return (
            "api-only mode requires at least one HTTP (kind: http) entry; "
            f"chain has only CLI adapters: {canonicals}. Either run in "
            "prefer-api / prefer-cli / cli-only mode or revise the chain."
        )
    return f"no entries survived mode transform; chain was {canonicals}"


def _assert_valid_mode(value: Any, source: str) -> None:
    """Fail-loud if a configured mode value is invalid."""
    if value not in HEADLESS_MODES:
        raise ValueError(
            f"{source} value {value!r} is not a valid headless mode; "
            f"expected one of {HEADLESS_MODES}"
        )
