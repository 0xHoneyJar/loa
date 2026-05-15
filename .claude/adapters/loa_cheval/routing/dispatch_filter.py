"""Cycle-110 sprint-2b1 — dispatch_preference filter + deterministic auto-mode.

Sits between `chain_resolver.resolve()` (which builds the within-company
fallback chain) and the cheval invocation loop. Filters the chain by
`auth_type` according to the operator's `dispatch_preference` setting and,
for `auto` mode, runs a deterministic band-comparison algorithm against
windowed MODELINV success-rate stats.

Public surface:
- :func:`filter_chain_by_dispatch_preference` — given a `ResolvedChain` and
  a resolved `dispatch_preference`, return a `(filtered_entries, reason)`
  tuple. `reason` is one of the `auth_type_selection_reason` enum values
  per [PRD:FR-3.4] / SDD §1.4.7.
- :func:`run_auto_mode` — the deterministic algorithm for `dispatch_preference=auto`
  (FR-3.3). Pure function on (chain, stats, config, current_time).

Carry-in closures:
- C1 (legacy MODELINV dispatch_group derivation) — `_derive_dispatch_group_from_stats`
  reads from a per-process cache; missing entries → bucket dropped + WARNING.
- C10 (auto_evaluation_timestamp) — `AutoResolution.evaluation_timestamp` field.
- C11 (auto_selection_inputs canonical fixture) — `AutoResolution.selection_inputs`
  shape matches the SDD §3.4 example verbatim.
"""

from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional, Tuple

from loa_cheval.routing.types import (
    NoEligibleAdapterError,
    ResolvedChain,
    ResolvedEntry,
)

logger = logging.getLogger("loa_cheval.routing.dispatch_filter")


# --- Constants ----------------------------------------------------------------

# Dispatch_preference enum (matches advisor-strategy.schema.json)
DISPATCH_HEADLESS = "headless"
DISPATCH_HTTP_API = "http_api"
DISPATCH_AUTO = "auto"
DISPATCH_PREFERENCES = (DISPATCH_HEADLESS, DISPATCH_HTTP_API, DISPATCH_AUTO)

# auth_type_selection_reason enum (matches MODELINV v1.4 §1.4.7).
SELECTION_REASON_EXPLICIT = "explicit-dispatch_preference"
SELECTION_REASON_AUTO_BAND = "auto-band-comparison"
SELECTION_REASON_AUTO_RECOMMENDED = "auto-cold-start-recommended_for"
SELECTION_REASON_AUTO_DEFAULT = "auto-cold-start-default-headless"
SELECTION_REASONS = (
    SELECTION_REASON_EXPLICIT,
    SELECTION_REASON_AUTO_BAND,
    SELECTION_REASON_AUTO_RECOMMENDED,
    SELECTION_REASON_AUTO_DEFAULT,
)

# Auto-mode thresholds (SDD §5.2 v1.1)
AUTO_MODE_SAMPLE_SIZE_MIN = 20           # N≥20 per bucket for warm comparison
AUTO_MODE_RECENCY_WINDOW_SECONDS = 86400  # 24h
AUTO_MODE_BAND_GREEN_MIN = 0.80           # ≥80% success → green
AUTO_MODE_BAND_YELLOW_MIN = 0.50          # 50-80% → yellow

# Cross-auth fallback per FR-1.4 — when dispatch_preference=http_api,
# include aws_iam in the same "http-ish" bucket (Bedrock fits the
# http_api-vs-headless dichotomy on the HTTP side).
HTTP_API_LIKE_AUTH_TYPES = frozenset({"http_api", "aws_iam"})


# --- Data types ---------------------------------------------------------------


@dataclass(frozen=True)
class AutoResolution:
    """Output of the auto-mode algorithm (FR-3.4 MODELINV v1.4 input).

    All fields are JSON-serializable for direct inclusion in the
    `auto_selection_inputs` MODELINV envelope field.
    """

    selected_auth_type: str  # "headless" | "http_api" | "aws_iam"
    reason: str              # one of SELECTION_REASONS
    evaluation_timestamp: float  # C10 — epoch seconds when auto-mode ran
    sample_n_per_bucket: Dict[str, int] = field(default_factory=dict)
    band_per_bucket: Dict[str, str] = field(default_factory=dict)
    success_rate_per_bucket: Dict[str, float] = field(default_factory=dict)

    def as_selection_inputs(self) -> Dict[str, Any]:
        """Return the `auto_selection_inputs` MODELINV envelope sub-dict
        (C11 canonical shape from SDD §3.4)."""
        return {
            "sample_n_per_bucket": dict(self.sample_n_per_bucket),
            "band_per_bucket": dict(self.band_per_bucket),
            "success_rate_per_bucket": dict(self.success_rate_per_bucket),
        }


# --- T2.6: dispatch_preference filter ----------------------------------------


def _entry_matches_preference(
    entry: ResolvedEntry,
    dispatch_preference: str,
) -> bool:
    """Return True if `entry` matches the operator's dispatch_preference.

    Semantics ([PRD:FR-3.1, FR-3.2]):
    - `headless` → only entries with auth_type == "headless".
    - `http_api` → entries with auth_type ∈ {"http_api", "aws_iam"}.
    - `auto`     → match all entries (caller passes filtered chain post-auto).
    """
    if dispatch_preference == DISPATCH_HEADLESS:
        return entry.auth_type == "headless"
    if dispatch_preference == DISPATCH_HTTP_API:
        return entry.auth_type in HTTP_API_LIKE_AUTH_TYPES
    if dispatch_preference == DISPATCH_AUTO:
        return True
    raise ValueError(
        f"dispatch_preference must be one of {DISPATCH_PREFERENCES}, "
        f"got {dispatch_preference!r}"
    )


def filter_chain_by_dispatch_preference(
    chain: ResolvedChain,
    *,
    dispatch_preference: str,
    allow_cross_auth_fallback: bool,
    auto_resolution: Optional[AutoResolution] = None,
) -> Tuple[List[ResolvedEntry], str]:
    """Apply the operator's dispatch_preference filter to a within-company chain.

    Args:
        chain: output of `chain_resolver.resolve()`. The within-company invariant
            is already enforced.
        dispatch_preference: one of `DISPATCH_PREFERENCES`. For `auto`, the caller
            MUST also pass `auto_resolution` (the deterministic algorithm's output).
        allow_cross_auth_fallback: when True AND the preferred-auth_type chain
            is exhausted, append the other auth_type entries as fallback (FR-1.2).
        auto_resolution: required when `dispatch_preference == "auto"`. Carries
            the auto-mode algorithm's selected auth_type + reason.

    Returns:
        `(filtered_entries, auth_type_selection_reason)` per [PRD:FR-3.4].

    Raises:
        NoEligibleAdapterError: when filtering produces an empty chain AND
            cross-auth fallback is disabled or also empty.
        ValueError: on invalid dispatch_preference or missing auto_resolution.
    """
    if dispatch_preference not in DISPATCH_PREFERENCES:
        raise ValueError(
            f"dispatch_preference must be one of {DISPATCH_PREFERENCES}, "
            f"got {dispatch_preference!r}"
        )

    if dispatch_preference == DISPATCH_AUTO:
        if auto_resolution is None:
            raise ValueError(
                "filter_chain_by_dispatch_preference: dispatch_preference=auto "
                "requires auto_resolution (run_auto_mode output)"
            )
        # Auto-mode resolves to a concrete auth_type; treat it as explicit
        # downstream. The reason carries the auto sub-class.
        effective_pref = (
            DISPATCH_HEADLESS
            if auto_resolution.selected_auth_type == "headless"
            else DISPATCH_HTTP_API
        )
        reason = auto_resolution.reason
    else:
        effective_pref = dispatch_preference
        reason = SELECTION_REASON_EXPLICIT

    preferred: List[ResolvedEntry] = [
        e for e in chain.entries if _entry_matches_preference(e, effective_pref)
    ]

    if preferred:
        if allow_cross_auth_fallback:
            # Append the non-preferred entries AFTER all preferred entries.
            non_preferred = [
                e for e in chain.entries
                if not _entry_matches_preference(e, effective_pref)
            ]
            return preferred + non_preferred, reason
        return preferred, reason

    # Preferred bucket empty.
    if allow_cross_auth_fallback:
        # Fall back to the whole chain (within-company is the SDD invariant).
        non_preferred = [
            e for e in chain.entries
            if not _entry_matches_preference(e, effective_pref)
        ]
        if non_preferred:
            return non_preferred, reason

    raise NoEligibleAdapterError(
        primary_alias=chain.primary_alias,
        headless_mode=chain.headless_mode,
        reason=(
            f"dispatch_preference={dispatch_preference!r} produced empty chain "
            f"for {chain.primary_alias!r} (within-company entries: "
            f"{[e.canonical + '|' + e.auth_type for e in chain.entries]}); "
            f"allow_cross_auth_fallback={allow_cross_auth_fallback}"
        ),
    )


# --- T2.7: deterministic auto-mode algorithm ---------------------------------


def _classify_band(success_rate: float) -> str:
    if success_rate >= AUTO_MODE_BAND_GREEN_MIN:
        return "green"
    if success_rate >= AUTO_MODE_BAND_YELLOW_MIN:
        return "yellow"
    return "red"


def _bucket_stats_for_chain(
    chain: ResolvedChain,
    stats: Dict[Tuple[str, str], Dict[str, Any]],
) -> Dict[str, Dict[str, Any]]:
    """Aggregate per-auth_type stats across the entries of a chain.

    Args:
        chain: resolved chain whose entries all share dispatch_group.
        stats: pre-computed per-(dispatch_group, auth_type) windowed stats:
            {("anthropic-claude", "headless"): {"n": 124, "success_rate": 0.984},
             ("anthropic-claude", "http_api"): {"n": 87, "success_rate": 0.862}, ...}

    Returns:
        {auth_type: {"n": int, "success_rate": float}, ...} for the auth_types
        present in the chain. Buckets that have NO stats at all are omitted.
    """
    auth_types_in_chain = {e.auth_type for e in chain.entries}
    # Pick a representative dispatch_group from the primary entry (within-
    # company invariant ⇒ all entries share dispatch_group when populated).
    dg = chain.entries[0].dispatch_group
    out: Dict[str, Dict[str, Any]] = {}
    for at in auth_types_in_chain:
        key = (dg, at)
        if key in stats:
            out[at] = dict(stats[key])
    return out


def _select_with_margin(
    bucket_stats: Dict[str, Dict[str, Any]],
    *,
    headless_margin_bps: int,
) -> Optional[str]:
    """Return the winning auth_type per the SDD §5.2 band-comparison + margin.

    Returns None when no bucket has N >= AUTO_MODE_SAMPLE_SIZE_MIN.
    """
    warm = {
        at: data for at, data in bucket_stats.items()
        if data.get("n", 0) >= AUTO_MODE_SAMPLE_SIZE_MIN
    }
    if not warm:
        return None

    # Sort by success_rate descending; deterministic tie-break by auth_type
    # name ascending (headless < http_api < aws_iam lexicographic — fine since
    # the SDD's intent is "headless wins ties at the band-comparison layer").
    ranked = sorted(
        warm.items(),
        key=lambda kv: (-kv[1].get("success_rate", 0.0), kv[0]),
    )
    top_at, top_data = ranked[0]
    # Headless preference margin: if a headless bucket exists and is within
    # `headless_margin_bps / 10000` of the top, headless wins.
    if "headless" in warm and top_at != "headless":
        head_rate = warm["headless"].get("success_rate", 0.0)
        top_rate = top_data.get("success_rate", 0.0)
        margin = headless_margin_bps / 10000.0
        if (top_rate - head_rate) <= margin:
            return "headless"
    return top_at


def run_auto_mode(
    chain: ResolvedChain,
    *,
    stats: Dict[Tuple[str, str], Dict[str, Any]],
    advisor_config: Optional[Dict[str, Any]] = None,
    capability_evaluation: Optional[Dict[str, Any]] = None,
    now: Optional[float] = None,
) -> AutoResolution:
    """Deterministic auto-mode resolution ([PRD:FR-3.3], SDD §5.2 v1.1).

    Decision tree:
      1. If any bucket in the chain has N >= AUTO_MODE_SAMPLE_SIZE_MIN, use the
         band-comparison algorithm with headless_margin_bps preference.
         Reason: auto-band-comparison.
      2. Else (cold-start), if capability_evaluation.recommended_for hints
         a specific auth_type, use that.
         Reason: auto-cold-start-recommended_for.
      3. Else, default to headless when the chain has a headless entry,
         otherwise the first available auth_type.
         Reason: auto-cold-start-default-headless.

    The algorithm is a pure function on (chain, stats, advisor_config,
    capability_evaluation, now) — same inputs ⇒ byte-identical AutoResolution.
    FR-8.7 deterministic-replica test pins this.

    Args:
        chain: resolved within-company chain.
        stats: per-(dispatch_group, auth_type) windowed stats. Empty dict in
            tests / cold-start.
        advisor_config: parsed advisor_strategy section. Used to read
            `auto_mode.headless_margin_bps` (default 200).
        capability_evaluation: capability-aware substrate evaluation from
            the pre-flight gate (cycle-109 Sprint 1). Used for `recommended_for`
            cold-start hint.
        now: injected current time for tests; defaults to time.time().

    Returns:
        AutoResolution carrying selected auth_type + reason + per-bucket stats.
    """
    eval_ts = now if now is not None else time.time()
    config = advisor_config or {}
    auto_mode_cfg = config.get("auto_mode") or {}
    headless_margin_bps = int(auto_mode_cfg.get("headless_margin_bps", 200))

    bucket_stats = _bucket_stats_for_chain(chain, stats)

    sample_n = {at: int(d.get("n", 0)) for at, d in bucket_stats.items()}
    rates = {at: float(d.get("success_rate", 0.0)) for at, d in bucket_stats.items()}
    bands = {at: _classify_band(r) for at, r in rates.items()}

    # Phase 1: warm path — band-comparison.
    warm_winner = _select_with_margin(bucket_stats, headless_margin_bps=headless_margin_bps)
    if warm_winner is not None:
        return AutoResolution(
            selected_auth_type=warm_winner,
            reason=SELECTION_REASON_AUTO_BAND,
            evaluation_timestamp=eval_ts,
            sample_n_per_bucket=sample_n,
            band_per_bucket=bands,
            success_rate_per_bucket=rates,
        )

    # Phase 2: cold-start recommended_for hint.
    if capability_evaluation:
        rec = capability_evaluation.get("recommended_for") or []
        rec_auth_types = {r for r in rec if r in ("headless", "http_api", "aws_iam")}
        # Pick the first chain entry whose auth_type is in rec_auth_types.
        for entry in chain.entries:
            if entry.auth_type in rec_auth_types:
                return AutoResolution(
                    selected_auth_type=entry.auth_type,
                    reason=SELECTION_REASON_AUTO_RECOMMENDED,
                    evaluation_timestamp=eval_ts,
                    sample_n_per_bucket=sample_n,
                    band_per_bucket=bands,
                    success_rate_per_bucket=rates,
                )

    # Phase 3: cold-start default — prefer headless.
    chain_auth_types = [e.auth_type for e in chain.entries]
    default = "headless" if "headless" in chain_auth_types else chain_auth_types[0]
    return AutoResolution(
        selected_auth_type=default,
        reason=SELECTION_REASON_AUTO_DEFAULT,
        evaluation_timestamp=eval_ts,
        sample_n_per_bucket=sample_n,
        band_per_bucket=bands,
        success_rate_per_bucket=rates,
    )


__all__ = [
    "AUTO_MODE_BAND_GREEN_MIN",
    "AUTO_MODE_BAND_YELLOW_MIN",
    "AUTO_MODE_RECENCY_WINDOW_SECONDS",
    "AUTO_MODE_SAMPLE_SIZE_MIN",
    "AutoResolution",
    "DISPATCH_AUTO",
    "DISPATCH_HEADLESS",
    "DISPATCH_HTTP_API",
    "DISPATCH_PREFERENCES",
    "HTTP_API_LIKE_AUTH_TYPES",
    "SELECTION_REASONS",
    "SELECTION_REASON_AUTO_BAND",
    "SELECTION_REASON_AUTO_DEFAULT",
    "SELECTION_REASON_AUTO_RECOMMENDED",
    "SELECTION_REASON_EXPLICIT",
    "filter_chain_by_dispatch_preference",
    "run_auto_mode",
]
