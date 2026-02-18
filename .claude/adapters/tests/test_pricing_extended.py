"""Tests for Sprint 3 metering extensions: per-task pricing, atomic budget,
rate limiting, feature flags, and Deep Research ledger entries (SDD §4.3-4.5)."""

import json
import os
import sys
import tempfile
import time
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from loa_cheval.metering.pricing import (
    CostBreakdown,
    PricingEntry,
    calculate_total_cost,
    find_pricing,
)
from loa_cheval.metering.ledger import (
    create_ledger_entry,
    record_cost,
    read_daily_spend,
    read_ledger,
)
from loa_cheval.metering.budget import (
    ALLOW,
    BLOCK,
    DOWNGRADE,
    WARN,
    BudgetEnforcer,
)
from loa_cheval.metering.rate_limiter import (
    TokenBucketLimiter,
    create_limiter,
)


# ── Per-Task Pricing Tests ───────────────────────────────────────────────────


class TestPerTaskPricing:
    """Deep Research per-task pricing mode."""

    TASK_PRICING = PricingEntry(
        provider="google",
        model="deep-research-pro",
        input_per_mtok=0,
        output_per_mtok=0,
        reasoning_per_mtok=0,
        per_task_micro_usd=2_000_000,  # $2.00
        pricing_mode="task",
    )

    def test_per_task_pricing(self):
        """Deep Research → per_task_micro_usd as total, tokens ignored."""
        breakdown = calculate_total_cost(
            input_tokens=10000,
            output_tokens=5000,
            reasoning_tokens=0,
            pricing=self.TASK_PRICING,
        )
        assert breakdown.total_cost_micro == 2_000_000
        assert breakdown.input_cost_micro == 0
        assert breakdown.output_cost_micro == 0
        assert breakdown.remainder_input == 0

    def test_per_task_zero_tokens(self):
        """Per-task pricing works even with zero tokens."""
        breakdown = calculate_total_cost(0, 0, 0, self.TASK_PRICING)
        assert breakdown.total_cost_micro == 2_000_000


class TestHybridPricing:
    """Hybrid pricing mode (token + per-task)."""

    HYBRID_PRICING = PricingEntry(
        provider="google",
        model="hybrid-model",
        input_per_mtok=1_000_000,  # $1/1M
        output_per_mtok=2_000_000,  # $2/1M
        reasoning_per_mtok=0,
        per_task_micro_usd=500_000,  # $0.50 flat
        pricing_mode="hybrid",
    )

    def test_hybrid_pricing(self):
        """Token cost + per-task cost summed."""
        breakdown = calculate_total_cost(
            input_tokens=1000,
            output_tokens=500,
            reasoning_tokens=0,
            pricing=self.HYBRID_PRICING,
        )
        # Token cost: 1000*$1/1M + 500*$2/1M = 1_000 + 1_000 = 2_000
        # Plus flat: 500_000
        assert breakdown.total_cost_micro == 502_000
        assert breakdown.input_cost_micro == 1_000
        assert breakdown.output_cost_micro == 1_000

    def test_hybrid_zero_tokens(self):
        """Hybrid with zero tokens still charges per-task."""
        breakdown = calculate_total_cost(0, 0, 0, self.HYBRID_PRICING)
        assert breakdown.total_cost_micro == 500_000


class TestPricingModeDetection:
    """Config parsing of pricing_mode field."""

    def test_pricing_mode_token(self):
        config = {
            "providers": {
                "openai": {
                    "models": {
                        "gpt-5.2": {
                            "pricing": {
                                "input_per_mtok": 10_000_000,
                                "output_per_mtok": 30_000_000,
                            }
                        }
                    }
                }
            }
        }
        pricing = find_pricing("openai", "gpt-5.2", config)
        assert pricing is not None
        assert pricing.pricing_mode == "token"

    def test_pricing_mode_task(self):
        config = {
            "providers": {
                "google": {
                    "models": {
                        "deep-research-pro": {
                            "pricing": {
                                "input_per_mtok": 0,
                                "output_per_mtok": 0,
                                "per_task_micro_usd": 2_000_000,
                                "pricing_mode": "task",
                            }
                        }
                    }
                }
            }
        }
        pricing = find_pricing("google", "deep-research-pro", config)
        assert pricing is not None
        assert pricing.pricing_mode == "task"
        assert pricing.per_task_micro_usd == 2_000_000

    def test_pricing_mode_hybrid(self):
        config = {
            "providers": {
                "google": {
                    "models": {
                        "hybrid-model": {
                            "pricing": {
                                "input_per_mtok": 1_000_000,
                                "output_per_mtok": 2_000_000,
                                "per_task_micro_usd": 500_000,
                                "pricing_mode": "hybrid",
                            }
                        }
                    }
                }
            }
        }
        pricing = find_pricing("google", "hybrid-model", config)
        assert pricing is not None
        assert pricing.pricing_mode == "hybrid"

    def test_existing_token_pricing_unchanged(self):
        """Backward compatibility: existing token-based pricing unaffected."""
        pricing = PricingEntry(
            provider="openai", model="gpt-5.2",
            input_per_mtok=10_000_000, output_per_mtok=30_000_000,
        )
        assert pricing.pricing_mode == "token"
        assert pricing.per_task_micro_usd == 0
        breakdown = calculate_total_cost(1000, 500, 0, pricing)
        assert breakdown.total_cost_micro == 25_000  # Same as before


# ── Atomic Budget Tests ──────────────────────────────────────────────────────


class TestBudgetAtomicCheck:
    """pre_call_atomic() with flock serialization."""

    def _make_enforcer(self, tmp_path, daily_limit=100_000_000, on_exceeded="block"):
        config = {
            "metering": {
                "enabled": True,
                "budget": {
                    "daily_micro_usd": daily_limit,
                    "warn_at_percent": 80,
                    "on_exceeded": on_exceeded,
                },
            }
        }
        ledger_path = str(tmp_path / "ledger.jsonl")
        return BudgetEnforcer(config, ledger_path)

    def test_atomic_allow(self, tmp_path):
        """Under budget → ALLOW."""
        enforcer = self._make_enforcer(tmp_path)
        request = MagicMock()
        status = enforcer.pre_call_atomic(request, reservation_micro=1_000)
        assert status == ALLOW

    def test_atomic_block(self, tmp_path):
        """Over budget → BLOCK."""
        enforcer = self._make_enforcer(tmp_path, daily_limit=100)
        # Pre-seed spend file to exceed limit
        from loa_cheval.metering.ledger import update_daily_spend
        ledger_path = str(tmp_path / "ledger.jsonl")
        update_daily_spend(200, ledger_path)

        request = MagicMock()
        status = enforcer.pre_call_atomic(request)
        assert status == BLOCK

    def test_atomic_downgrade(self, tmp_path):
        """Over budget with downgrade policy → DOWNGRADE."""
        enforcer = self._make_enforcer(tmp_path, daily_limit=100, on_exceeded="downgrade")
        from loa_cheval.metering.ledger import update_daily_spend
        ledger_path = str(tmp_path / "ledger.jsonl")
        update_daily_spend(200, ledger_path)

        request = MagicMock()
        status = enforcer.pre_call_atomic(request)
        assert status == DOWNGRADE

    def test_atomic_reservation_written(self, tmp_path):
        """Reservation updates spend file atomically."""
        enforcer = self._make_enforcer(tmp_path)
        request = MagicMock()

        enforcer.pre_call_atomic(request, reservation_micro=50_000)
        ledger_path = str(tmp_path / "ledger.jsonl")
        spent = read_daily_spend(ledger_path)
        assert spent == 50_000


class TestBudgetReservationReconcile:
    """post_call adjusts over/under-estimated reservation."""

    def test_post_call_records_actual(self, tmp_path):
        config = {
            "metering": {"enabled": True, "budget": {"daily_micro_usd": 1_000_000_000}},
            "providers": {
                "openai": {
                    "models": {
                        "gpt-5.2": {
                            "pricing": {
                                "input_per_mtok": 10_000_000,
                                "output_per_mtok": 30_000_000,
                            }
                        }
                    }
                }
            },
        }
        ledger_path = str(tmp_path / "ledger.jsonl")
        enforcer = BudgetEnforcer(config, ledger_path)

        result = MagicMock()
        result.provider = "openai"
        result.model = "gpt-5.2"
        result.latency_ms = 1000
        result.usage = MagicMock()
        result.usage.input_tokens = 1000
        result.usage.output_tokens = 500
        result.usage.reasoning_tokens = 0
        result.usage.source = "actual"
        result.interaction_id = None
        result._agent = "reviewing-code"

        enforcer.post_call(result)

        entries = read_ledger(ledger_path)
        assert len(entries) == 1
        assert entries[0]["cost_micro_usd"] == 25_000


class TestBudgetDeduplication:
    """interaction_id dedupe (Flatline Beads SKP-002)."""

    def test_duplicate_interaction_skipped(self, tmp_path):
        config = {
            "metering": {"enabled": True, "budget": {"daily_micro_usd": 1_000_000_000}},
            "providers": {
                "google": {
                    "models": {
                        "deep-research-pro": {
                            "pricing": {
                                "per_task_micro_usd": 2_000_000,
                                "pricing_mode": "task",
                            }
                        }
                    }
                }
            },
        }
        ledger_path = str(tmp_path / "ledger.jsonl")
        enforcer = BudgetEnforcer(config, ledger_path)

        result = MagicMock()
        result.provider = "google"
        result.model = "deep-research-pro"
        result.latency_ms = 5000
        result.usage = MagicMock()
        result.usage.input_tokens = 0
        result.usage.output_tokens = 5000
        result.usage.reasoning_tokens = 0
        result.usage.source = "actual"
        result.interaction_id = "dr-abc123"
        result._agent = "deep-researcher"

        enforcer.post_call(result)
        enforcer.post_call(result)  # Duplicate — should be skipped

        entries = read_ledger(ledger_path)
        assert len(entries) == 1  # Only one entry


# ── Rate Limiter Tests ───────────────────────────────────────────────────────


class TestRateLimiterRPM:
    """RPM (requests per minute) enforcement."""

    def test_within_limit(self, tmp_path):
        limiter = TokenBucketLimiter(rpm=10, tpm=1_000_000, state_dir=str(tmp_path))
        assert limiter.check("google") is True

    def test_exceeding_limit(self, tmp_path):
        limiter = TokenBucketLimiter(rpm=2, tpm=1_000_000, state_dir=str(tmp_path))
        # Exhaust RPM
        limiter.record("google", 100)
        limiter.record("google", 100)
        assert limiter.check("google") is False


class TestRateLimiterTPM:
    """TPM (tokens per minute) enforcement."""

    def test_within_limit(self, tmp_path):
        limiter = TokenBucketLimiter(rpm=100, tpm=10_000, state_dir=str(tmp_path))
        assert limiter.check("google", estimated_tokens=5000) is True

    def test_exceeding_limit(self, tmp_path):
        limiter = TokenBucketLimiter(rpm=100, tpm=10_000, state_dir=str(tmp_path))
        limiter.record("google", 9000)
        assert limiter.check("google", estimated_tokens=5000) is False


class TestRateLimiterRefill:
    """Bucket refills after elapsed time."""

    def test_refill_over_time(self, tmp_path):
        limiter = TokenBucketLimiter(rpm=60, tpm=1_000_000, state_dir=str(tmp_path))
        # Exhaust most RPM
        for _ in range(58):
            limiter.record("google", 100)

        # Simulate time passing by manipulating state
        state_path = os.path.join(str(tmp_path), ".ratelimit-google.json")
        with open(state_path, "r") as f:
            state = json.load(f)
        # Set last_update to 30 seconds ago (half a minute → 30 RPM refill)
        state["last_update"] = time.time() - 30
        with open(state_path, "w") as f:
            json.dump(state, f)

        # Should be able to proceed after refill
        assert limiter.check("google") is True


class TestRateLimiterConfig:
    """create_limiter reads config or uses defaults."""

    def test_default_google(self, tmp_path):
        limiter = create_limiter("google", {}, state_dir=str(tmp_path))
        assert limiter._rpm == 60
        assert limiter._tpm == 1_000_000

    def test_config_override(self, tmp_path):
        config = {
            "routing": {
                "rate_limits": {
                    "google": {"rpm": 30, "tpm": 500_000},
                }
            }
        }
        limiter = create_limiter("google", config, state_dir=str(tmp_path))
        assert limiter._rpm == 30
        assert limiter._tpm == 500_000


# ── Feature Flag Tests ───────────────────────────────────────────────────────

# Import cheval internals for feature flag testing
sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent))


class TestFeatureFlagGoogleDisabled:
    """google_adapter: false → ConfigError."""

    def test_google_blocked(self):
        from cheval import _check_feature_flags
        hounfour = {"feature_flags": {"google_adapter": False}}
        err = _check_feature_flags(hounfour, "google", "gemini-2.5-pro")
        assert err is not None
        assert "disabled" in err

    def test_google_allowed_by_default(self):
        from cheval import _check_feature_flags
        err = _check_feature_flags({}, "google", "gemini-2.5-pro")
        assert err is None


class TestFeatureFlagDeepResearchDisabled:
    """deep_research: false → blocks DR models."""

    def test_deep_research_blocked(self):
        from cheval import _check_feature_flags
        hounfour = {"feature_flags": {"deep_research": False}}
        err = _check_feature_flags(hounfour, "google", "deep-research-pro")
        assert err is not None
        assert "disabled" in err

    def test_non_dr_model_unaffected(self):
        from cheval import _check_feature_flags
        hounfour = {"feature_flags": {"deep_research": False}}
        err = _check_feature_flags(hounfour, "google", "gemini-2.5-pro")
        assert err is None


class TestFeatureFlagMeteringDisabled:
    """metering: false → no BudgetEnforcer created."""

    def test_metering_disabled(self, tmp_path):
        config = {
            "metering": {"enabled": False, "budget": {"daily_micro_usd": 100}},
        }
        ledger_path = str(tmp_path / "ledger.jsonl")
        enforcer = BudgetEnforcer(config, ledger_path)

        request = MagicMock()
        assert enforcer.pre_call(request) == ALLOW
        # post_call should be no-op
        result = MagicMock()
        enforcer.post_call(result)
        # No ledger entry written
        assert not os.path.exists(ledger_path)


# ── Budget Edge Cases (Flatline SKP-007) ─────────────────────────────────────


class TestBudgetWithMissingUsage:
    """partial/missing usage metadata."""

    def test_missing_usage_no_crash(self, tmp_path):
        """post_call with None usage doesn't record."""
        config = {
            "metering": {"enabled": True, "budget": {"daily_micro_usd": 1_000_000_000}},
        }
        ledger_path = str(tmp_path / "ledger.jsonl")
        enforcer = BudgetEnforcer(config, ledger_path)

        result = MagicMock()
        result.usage = None
        result.interaction_id = None
        enforcer.post_call(result)

        entries = read_ledger(ledger_path)
        assert len(entries) == 0


class TestBudgetWithTaskPricing:
    """Deep Research per-task cost correctly deducted from daily budget."""

    def test_task_cost_deducted(self, tmp_path):
        config = {
            "metering": {"enabled": True, "budget": {"daily_micro_usd": 5_000_000}},
            "providers": {
                "google": {
                    "models": {
                        "deep-research-pro": {
                            "pricing": {
                                "per_task_micro_usd": 2_000_000,
                                "pricing_mode": "task",
                            }
                        }
                    }
                }
            },
        }
        ledger_path = str(tmp_path / "ledger.jsonl")
        enforcer = BudgetEnforcer(config, ledger_path)

        result = MagicMock()
        result.provider = "google"
        result.model = "deep-research-pro"
        result.latency_ms = 30000
        result.usage = MagicMock()
        result.usage.input_tokens = 0
        result.usage.output_tokens = 10000
        result.usage.reasoning_tokens = 0
        result.usage.source = "actual"
        result.interaction_id = "dr-task-001"
        result._agent = "deep-researcher"

        enforcer.post_call(result)

        spent = read_daily_spend(ledger_path)
        assert spent == 2_000_000  # Exactly the per-task cost


# ── Ledger Extension Tests ───────────────────────────────────────────────────


class TestLedgerPricingMode:
    """Ledger entries include pricing_mode and interaction_id."""

    CONFIG = {
        "providers": {
            "google": {
                "models": {
                    "deep-research-pro": {
                        "pricing": {
                            "per_task_micro_usd": 2_000_000,
                            "pricing_mode": "task",
                        }
                    }
                }
            }
        }
    }

    def test_task_pricing_mode_in_entry(self):
        entry = create_ledger_entry(
            trace_id="tr-test",
            agent="deep-researcher",
            provider="google",
            model="deep-research-pro",
            input_tokens=0,
            output_tokens=5000,
            reasoning_tokens=0,
            latency_ms=30000,
            config=self.CONFIG,
            interaction_id="dr-abc123",
        )
        assert entry["pricing_mode"] == "task"
        assert entry["interaction_id"] == "dr-abc123"
        assert entry["cost_micro_usd"] == 2_000_000

    def test_token_pricing_mode_default(self):
        config = {
            "providers": {
                "openai": {
                    "models": {
                        "gpt-5.2": {
                            "pricing": {
                                "input_per_mtok": 10_000_000,
                                "output_per_mtok": 30_000_000,
                            }
                        }
                    }
                }
            }
        }
        entry = create_ledger_entry(
            trace_id="tr-test",
            agent="reviewer",
            provider="openai",
            model="gpt-5.2",
            input_tokens=1000,
            output_tokens=500,
            reasoning_tokens=0,
            latency_ms=2000,
            config=config,
        )
        assert entry["pricing_mode"] == "token"
        assert "interaction_id" not in entry  # Not set for token-based

    def test_backward_compatible_fields(self):
        """Existing required fields still present."""
        entry = create_ledger_entry(
            trace_id="tr-test",
            agent="test",
            provider="google",
            model="deep-research-pro",
            input_tokens=0,
            output_tokens=5000,
            reasoning_tokens=0,
            latency_ms=30000,
            config=self.CONFIG,
        )
        required = [
            "ts", "trace_id", "request_id", "agent", "provider", "model",
            "tokens_in", "tokens_out", "tokens_reasoning", "latency_ms",
            "cost_micro_usd", "usage_source", "pricing_source",
            "pricing_mode", "attempt",
        ]
        for field in required:
            assert field in entry, f"Missing field: {field}"


# --- BB-406: RemainderAccumulator and overflow guard tests ---


class TestRemainderAccumulator:
    """Test RemainderAccumulator carry behavior (BB-406)."""

    def test_carry_accumulates_across_calls(self):
        """Remainders carry over and produce extra micro-USD when they reach 1M."""
        from loa_cheval.metering.pricing import RemainderAccumulator

        acc = RemainderAccumulator()
        # Each call accumulates 500_000 remainder (half a micro-USD)
        extra1 = acc.carry("input", 500_000)
        assert extra1 == 0
        assert acc.get("input") == 500_000

        # Second call: 500_000 + 500_000 = 1_000_000 → carry 1 micro-USD
        extra2 = acc.carry("input", 500_000)
        assert extra2 == 1
        assert acc.get("input") == 0  # Reset after carry

    def test_carry_with_large_remainder(self):
        """Large remainder carries multiple micro-USD."""
        from loa_cheval.metering.pricing import RemainderAccumulator

        acc = RemainderAccumulator()
        extra = acc.carry("output", 2_500_000)
        assert extra == 2
        assert acc.get("output") == 500_000

    def test_carry_zero_remainder(self):
        """Zero remainder produces no carry and no accumulation."""
        from loa_cheval.metering.pricing import RemainderAccumulator

        acc = RemainderAccumulator()
        extra = acc.carry("input", 0)
        assert extra == 0
        assert acc.get("input") == 0

    def test_independent_scope_keys(self):
        """Different scope keys accumulate independently."""
        from loa_cheval.metering.pricing import RemainderAccumulator

        acc = RemainderAccumulator()
        acc.carry("input", 700_000)
        acc.carry("output", 300_000)
        assert acc.get("input") == 700_000
        assert acc.get("output") == 300_000

    def test_clear_resets_all(self):
        """Clear removes all accumulated remainders."""
        from loa_cheval.metering.pricing import RemainderAccumulator

        acc = RemainderAccumulator()
        acc.carry("input", 500_000)
        acc.carry("output", 300_000)
        acc.clear()
        assert acc.get("input") == 0
        assert acc.get("output") == 0


class TestOverflowGuard:
    """Test MAX_SAFE_PRODUCT overflow guard in calculate_cost_micro (BB-406)."""

    def test_normal_calculation(self):
        """Normal values produce correct cost and remainder."""
        from loa_cheval.metering.pricing import calculate_cost_micro

        # 1000 tokens at 3_000_000 micro-USD per million
        # = 1000 * 3_000_000 / 1_000_000 = 3000 micro-USD ($0.003)
        cost, remainder = calculate_cost_micro(1000, 3_000_000)
        assert cost == 3000
        assert remainder == 0

    def test_remainder_from_division(self):
        """Non-even division produces remainder."""
        from loa_cheval.metering.pricing import calculate_cost_micro

        # 7 tokens at 1_500_000 micro-USD per million = 0.0105 USD = 10 micro + 500000 rem
        cost, remainder = calculate_cost_micro(7, 1_500_000)
        assert cost == 10
        assert remainder == 500_000

    def test_near_max_safe_product(self):
        """Values just below MAX_SAFE_PRODUCT succeed."""
        from loa_cheval.metering.pricing import calculate_cost_micro, MAX_SAFE_PRODUCT

        # tokens * price = MAX_SAFE_PRODUCT exactly
        tokens = 9007199254740991  # 2^53 - 1
        cost, remainder = calculate_cost_micro(tokens, 1)
        assert cost == tokens // 1_000_000
        assert remainder == tokens % 1_000_000

    def test_overflow_raises(self):
        """Values exceeding MAX_SAFE_PRODUCT raise ValueError."""
        import pytest
        from loa_cheval.metering.pricing import calculate_cost_micro

        # tokens * price > 2^53 - 1
        with pytest.raises(ValueError, match="BUDGET_OVERFLOW"):
            calculate_cost_micro(10_000_000_000, 1_000_000_000)

    def test_zero_tokens_zero_cost(self):
        """Zero tokens always produce zero cost."""
        from loa_cheval.metering.pricing import calculate_cost_micro

        cost, remainder = calculate_cost_micro(0, 15_000_000)
        assert cost == 0
        assert remainder == 0
