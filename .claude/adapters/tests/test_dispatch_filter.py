"""Cycle-110 sprint-2b1 T2.13 / T2.17 — dispatch_filter coverage.

Tests `loa_cheval.routing.dispatch_filter`:
- filter_chain_by_dispatch_preference (T2.6): 3 dispatch_preference × 3 chain
  shapes × 2 cross-auth-fallback settings = 18 cells (FR-8.1 cell count).
- run_auto_mode (T2.7): warm-path band comparison + cold-start branches +
  margin tie-breaker.
- AutoResolution.as_selection_inputs (C11 canonical shape).
- Deterministic-replica test (T2.17 / FR-8.7): identical input → identical
  AutoResolution.
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from loa_cheval.routing.dispatch_filter import (  # noqa: E402
    AUTO_MODE_SAMPLE_SIZE_MIN,
    AutoResolution,
    DISPATCH_AUTO,
    DISPATCH_HEADLESS,
    DISPATCH_HTTP_API,
    SELECTION_REASON_AUTO_BAND,
    SELECTION_REASON_AUTO_DEFAULT,
    SELECTION_REASON_AUTO_RECOMMENDED,
    SELECTION_REASON_EXPLICIT,
    filter_chain_by_dispatch_preference,
    run_auto_mode,
)
from loa_cheval.routing.types import (  # noqa: E402
    NoEligibleAdapterError,
    ResolvedChain,
    ResolvedEntry,
)


# --- Fixtures ----------------------------------------------------------------


def _entry(provider, model_id, auth_type, *, dispatch_group="anthropic-claude", adapter_kind="http"):
    return ResolvedEntry(
        provider=provider,
        model_id=model_id,
        adapter_kind=adapter_kind,
        capabilities=frozenset(["chat"]),
        auth_type=auth_type,
        dispatch_group=dispatch_group,
    )


def _chain(*entries, primary_alias=None):
    return ResolvedChain(
        primary_alias=primary_alias or entries[0].model_id,
        entries=tuple(entries),
        headless_mode="prefer-api",
        headless_mode_source="default",
    )


# Three canonical chain shapes for the 18-cell matrix.
MIXED_CHAIN = _chain(
    _entry("anthropic", "claude-headless", "headless", adapter_kind="cli"),
    _entry("anthropic", "claude-opus-4-7", "http_api"),
)
HEADLESS_ONLY_CHAIN = _chain(
    _entry("anthropic", "claude-headless", "headless", adapter_kind="cli"),
)
HTTP_API_ONLY_CHAIN = _chain(
    _entry("anthropic", "claude-opus-4-7", "http_api"),
    _entry("anthropic", "claude-opus-4-6", "http_api"),
)


# --- T2.6 coverage — 18 cells ------------------------------------------------


class TestDispatchPreferenceMatrix:
    """T2.13 / FR-8.1: 3 dispatch_preference × 3 chain shapes × 2 cross-auth
    fallback settings = 18 cells. Each test row pins (preference, chain, xfb)
    → expected outcome."""

    # ---- dispatch_preference=headless (6 cells) ----

    def test_headless_pref_mixed_chain_no_xfb(self):
        out, reason = filter_chain_by_dispatch_preference(
            MIXED_CHAIN, dispatch_preference=DISPATCH_HEADLESS,
            allow_cross_auth_fallback=False,
        )
        assert [e.canonical for e in out] == ["anthropic:claude-headless"]
        assert reason == SELECTION_REASON_EXPLICIT

    def test_headless_pref_mixed_chain_with_xfb(self):
        out, reason = filter_chain_by_dispatch_preference(
            MIXED_CHAIN, dispatch_preference=DISPATCH_HEADLESS,
            allow_cross_auth_fallback=True,
        )
        # Preferred (headless) first, then non-preferred (http_api) appended.
        assert [e.canonical for e in out] == [
            "anthropic:claude-headless", "anthropic:claude-opus-4-7",
        ]
        assert reason == SELECTION_REASON_EXPLICIT

    def test_headless_pref_headless_only_chain_no_xfb(self):
        out, _ = filter_chain_by_dispatch_preference(
            HEADLESS_ONLY_CHAIN, dispatch_preference=DISPATCH_HEADLESS,
            allow_cross_auth_fallback=False,
        )
        assert len(out) == 1 and out[0].auth_type == "headless"

    def test_headless_pref_headless_only_chain_with_xfb(self):
        out, _ = filter_chain_by_dispatch_preference(
            HEADLESS_ONLY_CHAIN, dispatch_preference=DISPATCH_HEADLESS,
            allow_cross_auth_fallback=True,
        )
        assert len(out) == 1 and out[0].auth_type == "headless"

    def test_headless_pref_http_only_chain_no_xfb_raises(self):
        with pytest.raises(NoEligibleAdapterError, match="dispatch_preference"):
            filter_chain_by_dispatch_preference(
                HTTP_API_ONLY_CHAIN, dispatch_preference=DISPATCH_HEADLESS,
                allow_cross_auth_fallback=False,
            )

    def test_headless_pref_http_only_chain_with_xfb_falls_back(self):
        out, _ = filter_chain_by_dispatch_preference(
            HTTP_API_ONLY_CHAIN, dispatch_preference=DISPATCH_HEADLESS,
            allow_cross_auth_fallback=True,
        )
        # Cross-auth fallback returns the http_api chain.
        assert [e.auth_type for e in out] == ["http_api", "http_api"]

    # ---- dispatch_preference=http_api (6 cells) ----

    def test_http_pref_mixed_chain_no_xfb(self):
        out, _ = filter_chain_by_dispatch_preference(
            MIXED_CHAIN, dispatch_preference=DISPATCH_HTTP_API,
            allow_cross_auth_fallback=False,
        )
        assert [e.auth_type for e in out] == ["http_api"]

    def test_http_pref_mixed_chain_with_xfb(self):
        out, _ = filter_chain_by_dispatch_preference(
            MIXED_CHAIN, dispatch_preference=DISPATCH_HTTP_API,
            allow_cross_auth_fallback=True,
        )
        # http_api first, headless fallback appended.
        assert [e.auth_type for e in out] == ["http_api", "headless"]

    def test_http_pref_headless_only_chain_no_xfb_raises(self):
        with pytest.raises(NoEligibleAdapterError):
            filter_chain_by_dispatch_preference(
                HEADLESS_ONLY_CHAIN, dispatch_preference=DISPATCH_HTTP_API,
                allow_cross_auth_fallback=False,
            )

    def test_http_pref_headless_only_chain_with_xfb_falls_back(self):
        out, _ = filter_chain_by_dispatch_preference(
            HEADLESS_ONLY_CHAIN, dispatch_preference=DISPATCH_HTTP_API,
            allow_cross_auth_fallback=True,
        )
        assert [e.auth_type for e in out] == ["headless"]

    def test_http_pref_http_only_chain_no_xfb(self):
        out, _ = filter_chain_by_dispatch_preference(
            HTTP_API_ONLY_CHAIN, dispatch_preference=DISPATCH_HTTP_API,
            allow_cross_auth_fallback=False,
        )
        assert len(out) == 2

    def test_http_pref_http_only_chain_with_xfb(self):
        out, _ = filter_chain_by_dispatch_preference(
            HTTP_API_ONLY_CHAIN, dispatch_preference=DISPATCH_HTTP_API,
            allow_cross_auth_fallback=True,
        )
        assert len(out) == 2  # no extra fallback since no other auth_type present

    # ---- dispatch_preference=auto (6 cells, requires AutoResolution) ----

    def test_auto_pref_requires_auto_resolution(self):
        with pytest.raises(ValueError, match="auto_resolution"):
            filter_chain_by_dispatch_preference(
                MIXED_CHAIN, dispatch_preference=DISPATCH_AUTO,
                allow_cross_auth_fallback=False,
            )

    def test_auto_pref_selects_headless_per_resolution(self):
        ar = AutoResolution(
            selected_auth_type="headless",
            reason=SELECTION_REASON_AUTO_BAND,
            evaluation_timestamp=1.0,
        )
        out, reason = filter_chain_by_dispatch_preference(
            MIXED_CHAIN, dispatch_preference=DISPATCH_AUTO,
            allow_cross_auth_fallback=False,
            auto_resolution=ar,
        )
        assert [e.auth_type for e in out] == ["headless"]
        # auto-mode reason flows through, NOT explicit.
        assert reason == SELECTION_REASON_AUTO_BAND

    def test_auto_pref_selects_http_per_resolution(self):
        ar = AutoResolution(
            selected_auth_type="http_api",
            reason=SELECTION_REASON_AUTO_BAND,
            evaluation_timestamp=1.0,
        )
        out, reason = filter_chain_by_dispatch_preference(
            MIXED_CHAIN, dispatch_preference=DISPATCH_AUTO,
            allow_cross_auth_fallback=False,
            auto_resolution=ar,
        )
        assert [e.auth_type for e in out] == ["http_api"]
        assert reason == SELECTION_REASON_AUTO_BAND

    def test_auto_pref_with_xfb_appends_other_auth(self):
        ar = AutoResolution(
            selected_auth_type="headless",
            reason=SELECTION_REASON_AUTO_BAND,
            evaluation_timestamp=1.0,
        )
        out, _ = filter_chain_by_dispatch_preference(
            MIXED_CHAIN, dispatch_preference=DISPATCH_AUTO,
            allow_cross_auth_fallback=True,
            auto_resolution=ar,
        )
        assert [e.auth_type for e in out] == ["headless", "http_api"]

    def test_auto_pref_cold_start_default_propagates(self):
        ar = AutoResolution(
            selected_auth_type="headless",
            reason=SELECTION_REASON_AUTO_DEFAULT,
            evaluation_timestamp=1.0,
        )
        out, reason = filter_chain_by_dispatch_preference(
            MIXED_CHAIN, dispatch_preference=DISPATCH_AUTO,
            allow_cross_auth_fallback=False,
            auto_resolution=ar,
        )
        assert reason == SELECTION_REASON_AUTO_DEFAULT
        assert [e.auth_type for e in out] == ["headless"]

    def test_auto_pref_recommended_for_reason_propagates(self):
        ar = AutoResolution(
            selected_auth_type="http_api",
            reason=SELECTION_REASON_AUTO_RECOMMENDED,
            evaluation_timestamp=1.0,
        )
        out, reason = filter_chain_by_dispatch_preference(
            MIXED_CHAIN, dispatch_preference=DISPATCH_AUTO,
            allow_cross_auth_fallback=False,
            auto_resolution=ar,
        )
        assert reason == SELECTION_REASON_AUTO_RECOMMENDED
        assert [e.auth_type for e in out] == ["http_api"]


class TestInvalidDispatchPreference:
    def test_unknown_value_raises(self):
        with pytest.raises(ValueError, match="dispatch_preference"):
            filter_chain_by_dispatch_preference(
                MIXED_CHAIN, dispatch_preference="bogus",
                allow_cross_auth_fallback=False,
            )


class TestAutoModeAwsIamPreservation:
    """BB iter-1 #905 F-002 closure: auto-mode selecting aws_iam must route
    through aws_iam buckets, NOT collapse to http_api."""

    def test_aws_iam_selected_uses_exact_aws_iam_filter(self):
        bedrock_chain = _chain(
            _entry("bedrock", "us.anthropic.claude-opus-4-7", "aws_iam",
                   dispatch_group="bedrock-anthropic"),
            _entry("bedrock", "us.anthropic.claude-sonnet-4-6", "aws_iam",
                   dispatch_group="bedrock-anthropic"),
        )
        ar = AutoResolution(
            selected_auth_type="aws_iam",
            reason=SELECTION_REASON_AUTO_BAND,
            evaluation_timestamp=1.0,
        )
        out, reason = filter_chain_by_dispatch_preference(
            bedrock_chain, dispatch_preference=DISPATCH_AUTO,
            allow_cross_auth_fallback=False, auto_resolution=ar,
        )
        assert all(e.auth_type == "aws_iam" for e in out)
        assert reason == SELECTION_REASON_AUTO_BAND

    def test_aws_iam_selected_does_NOT_pull_http_api_entries(self):
        # Mixed chain: aws_iam selection must NOT pick up http_api entries
        # (the pre-fix collapse would have).
        mixed = _chain(
            _entry("bedrock", "us.anthropic.claude-opus-4-7", "aws_iam",
                   dispatch_group="bedrock-anthropic"),
            _entry("bedrock", "us.anthropic.claude-sonnet-4-6", "http_api",
                   dispatch_group="bedrock-anthropic"),
        )
        ar = AutoResolution(
            selected_auth_type="aws_iam",
            reason=SELECTION_REASON_AUTO_BAND,
            evaluation_timestamp=1.0,
        )
        out, _ = filter_chain_by_dispatch_preference(
            mixed, dispatch_preference=DISPATCH_AUTO,
            allow_cross_auth_fallback=False, auto_resolution=ar,
        )
        # Only the aws_iam entry; http_api entry is NOT preferred under
        # auto-mode aws_iam selection.
        assert len(out) == 1
        assert out[0].auth_type == "aws_iam"


class TestAutoResolutionConstructionValidation:
    """BB iter-1 #905 F-002 closure: AutoResolution validates at construction."""

    def test_invalid_selected_auth_type_raises(self):
        with pytest.raises(ValueError, match="selected_auth_type"):
            AutoResolution(
                selected_auth_type="subscription",  # not in enum
                reason=SELECTION_REASON_AUTO_BAND,
                evaluation_timestamp=1.0,
            )

    def test_invalid_reason_raises(self):
        with pytest.raises(ValueError, match="reason"):
            AutoResolution(
                selected_auth_type="headless",
                reason="bogus-reason",
                evaluation_timestamp=1.0,
            )

    def test_all_three_valid_auth_types_construct(self):
        for at in ("headless", "http_api", "aws_iam"):
            ar = AutoResolution(
                selected_auth_type=at,
                reason=SELECTION_REASON_AUTO_BAND,
                evaluation_timestamp=1.0,
            )
            assert ar.selected_auth_type == at


# --- T2.7 coverage — auto-mode algorithm -------------------------------------


class TestAutoModeWarmPath:
    """SDD §5.2 band-comparison with margin tie-breaker."""

    def _stats(self, **kv):
        return {("anthropic-claude", at): {"n": n, "success_rate": rate}
                for at, (n, rate) in kv.items()}

    def test_headless_wins_clear(self):
        stats = self._stats(headless=(100, 0.95), http_api=(100, 0.85))
        ar = run_auto_mode(MIXED_CHAIN, stats=stats, now=1.0)
        assert ar.selected_auth_type == "headless"
        assert ar.reason == SELECTION_REASON_AUTO_BAND

    def test_http_wins_clear_above_margin(self):
        # http_api ahead by 10pp >> 2pp default margin → http_api wins
        stats = self._stats(headless=(100, 0.70), http_api=(100, 0.90))
        ar = run_auto_mode(MIXED_CHAIN, stats=stats, now=1.0)
        assert ar.selected_auth_type == "http_api"
        assert ar.reason == SELECTION_REASON_AUTO_BAND

    def test_http_wins_but_within_margin_headless_takes_it(self):
        # http_api ahead by 1pp < 2pp margin → headless wins tie-zone
        stats = self._stats(headless=(100, 0.85), http_api=(100, 0.86))
        ar = run_auto_mode(MIXED_CHAIN, stats=stats, now=1.0)
        assert ar.selected_auth_type == "headless"
        assert ar.reason == SELECTION_REASON_AUTO_BAND

    def test_below_sample_size_min_falls_to_cold_start(self):
        # Both buckets below N=20.
        stats = self._stats(headless=(5, 0.99), http_api=(5, 0.99))
        ar = run_auto_mode(MIXED_CHAIN, stats=stats, now=1.0)
        # Cold-start branch — should NOT be auto-band-comparison.
        assert ar.reason != SELECTION_REASON_AUTO_BAND


class TestAutoModeColdStart:
    def test_default_headless_with_headless_in_chain(self):
        ar = run_auto_mode(MIXED_CHAIN, stats={}, now=1.0)
        assert ar.selected_auth_type == "headless"
        assert ar.reason == SELECTION_REASON_AUTO_DEFAULT

    def test_default_first_auth_type_when_no_headless(self):
        ar = run_auto_mode(HTTP_API_ONLY_CHAIN, stats={}, now=1.0)
        assert ar.selected_auth_type == "http_api"
        assert ar.reason == SELECTION_REASON_AUTO_DEFAULT

    def test_recommended_for_hint_wins_over_default(self):
        capability = {"recommended_for": ["http_api"]}
        ar = run_auto_mode(
            MIXED_CHAIN, stats={}, capability_evaluation=capability, now=1.0,
        )
        assert ar.selected_auth_type == "http_api"
        assert ar.reason == SELECTION_REASON_AUTO_RECOMMENDED

    def test_recommended_for_unknown_auth_type_falls_to_default(self):
        capability = {"recommended_for": ["nonsense"]}
        ar = run_auto_mode(
            MIXED_CHAIN, stats={}, capability_evaluation=capability, now=1.0,
        )
        assert ar.reason == SELECTION_REASON_AUTO_DEFAULT


class TestAutoModeMarginTunable:
    def test_zero_margin_strict_equality_required(self):
        stats = {("anthropic-claude", "headless"): {"n": 100, "success_rate": 0.85},
                 ("anthropic-claude", "http_api"): {"n": 100, "success_rate": 0.86}}
        config = {"auto_mode": {"headless_margin_bps": 0}}
        ar = run_auto_mode(MIXED_CHAIN, stats=stats, advisor_config=config, now=1.0)
        # http_api strictly higher → http_api wins.
        assert ar.selected_auth_type == "http_api"

    def test_huge_margin_headless_always_wins(self):
        stats = {("anthropic-claude", "headless"): {"n": 100, "success_rate": 0.50},
                 ("anthropic-claude", "http_api"): {"n": 100, "success_rate": 0.99}}
        config = {"auto_mode": {"headless_margin_bps": 10000}}  # 100pp margin
        ar = run_auto_mode(MIXED_CHAIN, stats=stats, advisor_config=config, now=1.0)
        assert ar.selected_auth_type == "headless"


# --- C10 + C11 canonical fixture / envelope shape ---------------------------


class TestAutoResolutionEnvelopeShape:
    """C11 closure — auto_selection_inputs canonical shape matches SDD §3.4."""

    def test_as_selection_inputs_has_three_required_keys(self):
        ar = AutoResolution(
            selected_auth_type="headless",
            reason=SELECTION_REASON_AUTO_BAND,
            evaluation_timestamp=1715789012.345,
            sample_n_per_bucket={"headless": 124, "http_api": 87},
            band_per_bucket={"headless": "green", "http_api": "yellow"},
            success_rate_per_bucket={"headless": 0.984, "http_api": 0.862},
        )
        inputs = ar.as_selection_inputs()
        assert set(inputs.keys()) == {
            "sample_n_per_bucket", "band_per_bucket", "success_rate_per_bucket",
        }
        # Defensive-copy verification.
        inputs["sample_n_per_bucket"]["headless"] = 999
        assert ar.sample_n_per_bucket["headless"] == 124  # original unchanged

    def test_evaluation_timestamp_field_carries(self):
        ar = AutoResolution(
            selected_auth_type="headless",
            reason=SELECTION_REASON_AUTO_DEFAULT,
            evaluation_timestamp=1715789012.345,
        )
        assert ar.evaluation_timestamp == 1715789012.345


# --- T2.17: deterministic-replica test (FR-8.7) ------------------------------


class TestDeterministicReplica:
    """FR-8.7 / AC2.4: identical inputs → byte-identical AutoResolution output.

    Replays the same (chain, stats, config, now) twice and asserts the two
    AutoResolution instances compare equal. Pins the auto-mode algorithm as
    a pure function — no env/time-of-day inputs allowed to leak in.
    """

    def test_identical_inputs_identical_output(self):
        stats = {("anthropic-claude", "headless"): {"n": 100, "success_rate": 0.95},
                 ("anthropic-claude", "http_api"): {"n": 100, "success_rate": 0.85}}
        config = {"auto_mode": {"headless_margin_bps": 200}}
        # Two identical replays — same now.
        ar1 = run_auto_mode(MIXED_CHAIN, stats=stats, advisor_config=config, now=1715789012.345)
        ar2 = run_auto_mode(MIXED_CHAIN, stats=stats, advisor_config=config, now=1715789012.345)
        assert ar1 == ar2
        assert ar1.as_selection_inputs() == ar2.as_selection_inputs()

    def test_different_now_produces_different_timestamp_only(self):
        """Sanity check: the only field that varies with `now` is the timestamp.
        Selection itself is deterministic per the algorithm spec."""
        stats = {("anthropic-claude", "headless"): {"n": 100, "success_rate": 0.95},
                 ("anthropic-claude", "http_api"): {"n": 100, "success_rate": 0.85}}
        ar1 = run_auto_mode(MIXED_CHAIN, stats=stats, now=1.0)
        ar2 = run_auto_mode(MIXED_CHAIN, stats=stats, now=2.0)
        assert ar1.evaluation_timestamp != ar2.evaluation_timestamp
        assert ar1.selected_auth_type == ar2.selected_auth_type
        assert ar1.reason == ar2.reason
        assert ar1.sample_n_per_bucket == ar2.sample_n_per_bucket
