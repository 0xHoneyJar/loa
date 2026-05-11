"""cycle-103 sprint-3 T3.4 — _lookup_max_input_tokens streaming/legacy split.

Pins AC-3.4: when `LOA_CHEVAL_DISABLE_STREAMING=1` is set, the gate auto-
reverts to the `legacy_max_input_tokens` value (24K openai / 36K
anthropic) instead of the streaming default (200K / 180K). Backward
compat: configs that only have `max_input_tokens` continue to work.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path
from typing import Any, Dict

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from cheval import _lookup_max_input_tokens  # noqa: E402


# ---------------------------------------------------------------------------
# Fixture builders
# ---------------------------------------------------------------------------


def _split_config(streaming_val: int, legacy_val: int) -> Dict[str, Any]:
    """Config with both split fields set (no backward-compat fallback)."""
    return {
        "providers": {
            "openai": {
                "models": {
                    "gpt-5.5": {
                        "streaming_max_input_tokens": streaming_val,
                        "legacy_max_input_tokens": legacy_val,
                    }
                }
            }
        }
    }


def _legacy_only_config(value: int) -> Dict[str, Any]:
    """Config with only the legacy single-field `max_input_tokens`."""
    return {
        "providers": {
            "openai": {
                "models": {"gpt-5.5": {"max_input_tokens": value}}
            }
        }
    }


def _mixed_config(
    streaming_val: int, legacy_val: int, fallback_val: int
) -> Dict[str, Any]:
    """Config with all three fields set — split fields take precedence."""
    return {
        "providers": {
            "openai": {
                "models": {
                    "gpt-5.5": {
                        "streaming_max_input_tokens": streaming_val,
                        "legacy_max_input_tokens": legacy_val,
                        "max_input_tokens": fallback_val,
                    }
                }
            }
        }
    }


# ---------------------------------------------------------------------------
# Fixture: scrub the kill-switch env between tests
# ---------------------------------------------------------------------------


@pytest.fixture(autouse=True)
def _scrub_streaming_killswitch(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("LOA_CHEVAL_DISABLE_STREAMING", raising=False)


# ---------------------------------------------------------------------------
# Core split behavior
# ---------------------------------------------------------------------------


class TestSplitBehavior:
    def test_streaming_default_uses_streaming_field(self) -> None:
        cfg = _split_config(streaming_val=200000, legacy_val=24000)
        assert _lookup_max_input_tokens("openai", "gpt-5.5", cfg) == 200000

    def test_kill_switch_uses_legacy_field(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setenv("LOA_CHEVAL_DISABLE_STREAMING", "1")
        cfg = _split_config(streaming_val=200000, legacy_val=24000)
        assert _lookup_max_input_tokens("openai", "gpt-5.5", cfg) == 24000

    def test_kill_switch_truthy_variants_each_revert(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        cfg = _split_config(streaming_val=200000, legacy_val=24000)
        for val in ("1", "true", "TRUE", "yes", "on", "On"):
            monkeypatch.setenv("LOA_CHEVAL_DISABLE_STREAMING", val)
            assert _lookup_max_input_tokens("openai", "gpt-5.5", cfg) == 24000

    def test_kill_switch_falsy_variants_stay_streaming(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        cfg = _split_config(streaming_val=200000, legacy_val=24000)
        for val in ("0", "false", "no", "off", ""):
            monkeypatch.setenv("LOA_CHEVAL_DISABLE_STREAMING", val)
            assert _lookup_max_input_tokens("openai", "gpt-5.5", cfg) == 200000


# ---------------------------------------------------------------------------
# Backward compatibility — legacy single-field configs
# ---------------------------------------------------------------------------


class TestBackwardCompat:
    def test_legacy_only_field_used_when_streaming_default(self) -> None:
        cfg = _legacy_only_config(50000)
        assert _lookup_max_input_tokens("openai", "gpt-5.5", cfg) == 50000

    def test_legacy_only_field_used_when_kill_switch_set(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setenv("LOA_CHEVAL_DISABLE_STREAMING", "1")
        # Legacy single-field config: same value used either way (operator
        # hasn't migrated to the split; backward-compat must not break).
        cfg = _legacy_only_config(50000)
        assert _lookup_max_input_tokens("openai", "gpt-5.5", cfg) == 50000

    def test_mixed_config_split_wins_over_fallback(self) -> None:
        # When all three fields are present, the split field for the
        # current transport wins.
        cfg = _mixed_config(
            streaming_val=200000, legacy_val=24000, fallback_val=99999
        )
        assert _lookup_max_input_tokens("openai", "gpt-5.5", cfg) == 200000

    def test_mixed_config_legacy_wins_with_killswitch(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setenv("LOA_CHEVAL_DISABLE_STREAMING", "1")
        cfg = _mixed_config(
            streaming_val=200000, legacy_val=24000, fallback_val=99999
        )
        assert _lookup_max_input_tokens("openai", "gpt-5.5", cfg) == 24000


# ---------------------------------------------------------------------------
# Partial-split fallback — only one of the split fields is set
# ---------------------------------------------------------------------------


class TestPartialSplit:
    def test_only_streaming_set_kill_switch_falls_back(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        # Operator added streaming_max_input_tokens but NOT
        # legacy_max_input_tokens. With kill switch on, preferred field
        # is legacy → absent → falls back to max_input_tokens. If that's
        # also absent → no gate.
        monkeypatch.setenv("LOA_CHEVAL_DISABLE_STREAMING", "1")
        cfg = {
            "providers": {
                "openai": {
                    "models": {
                        "gpt-5.5": {
                            "streaming_max_input_tokens": 200000,
                            "max_input_tokens": 24000,
                        }
                    }
                }
            }
        }
        assert _lookup_max_input_tokens("openai", "gpt-5.5", cfg) == 24000

    def test_only_legacy_set_streaming_falls_back(self) -> None:
        cfg = {
            "providers": {
                "openai": {
                    "models": {
                        "gpt-5.5": {
                            "legacy_max_input_tokens": 24000,
                            "max_input_tokens": 200000,
                        }
                    }
                }
            }
        }
        assert _lookup_max_input_tokens("openai", "gpt-5.5", cfg) == 200000


# ---------------------------------------------------------------------------
# CLI override — orthogonal to the split
# ---------------------------------------------------------------------------


class TestCliOverrideOrthogonal:
    def test_cli_override_wins_even_under_kill_switch(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setenv("LOA_CHEVAL_DISABLE_STREAMING", "1")
        cfg = _split_config(streaming_val=200000, legacy_val=24000)
        out = _lookup_max_input_tokens(
            "openai", "gpt-5.5", cfg, cli_override=50000
        )
        assert out == 50000

    def test_cli_override_zero_disables_gate(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setenv("LOA_CHEVAL_DISABLE_STREAMING", "1")
        cfg = _split_config(streaming_val=200000, legacy_val=24000)
        assert (
            _lookup_max_input_tokens(
                "openai", "gpt-5.5", cfg, cli_override=0
            )
            is None
        )


# ---------------------------------------------------------------------------
# Absent-config edge cases
# ---------------------------------------------------------------------------


class TestAbsentConfig:
    def test_unknown_provider_returns_none(self) -> None:
        cfg = _split_config(200000, 24000)
        assert _lookup_max_input_tokens("ghost", "gpt-5.5", cfg) is None

    def test_unknown_model_returns_none(self) -> None:
        cfg = _split_config(200000, 24000)
        assert _lookup_max_input_tokens("openai", "ghost", cfg) is None

    def test_no_fields_set_returns_none(self) -> None:
        cfg = {
            "providers": {
                "openai": {"models": {"gpt-5.5": {"context_window": 400000}}}
            }
        }
        assert _lookup_max_input_tokens("openai", "gpt-5.5", cfg) is None

    def test_invalid_type_returns_none(self) -> None:
        # String value where int expected — defensive against malformed config.
        cfg = {
            "providers": {
                "openai": {
                    "models": {
                        "gpt-5.5": {"streaming_max_input_tokens": "lots"}
                    }
                }
            }
        }
        assert _lookup_max_input_tokens("openai", "gpt-5.5", cfg) is None


# ---------------------------------------------------------------------------
# Integration: real model-config.yaml values via the loader
# ---------------------------------------------------------------------------


class TestLiveConfig:
    def test_live_gpt_5_5_streaming_value(self) -> None:
        # Live config (defaults/model-config.yaml) should have the split.
        import yaml
        path = Path(__file__).resolve().parents[2] / "defaults" / "model-config.yaml"
        if not path.exists():
            pytest.skip("model-config.yaml not present in this checkout")
        with open(path) as fh:
            cfg = yaml.safe_load(fh)
        # Streaming default should be 200000 for gpt-5.5.
        assert (
            _lookup_max_input_tokens("openai", "gpt-5.5", cfg) == 200000
        )

    def test_live_gpt_5_5_legacy_under_killswitch(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setenv("LOA_CHEVAL_DISABLE_STREAMING", "1")
        import yaml
        path = Path(__file__).resolve().parents[2] / "defaults" / "model-config.yaml"
        if not path.exists():
            pytest.skip("model-config.yaml not present in this checkout")
        with open(path) as fh:
            cfg = yaml.safe_load(fh)
        # Killing streaming should revert to 24000.
        assert (
            _lookup_max_input_tokens("openai", "gpt-5.5", cfg) == 24000
        )

    def test_live_claude_opus_4_7_legacy_under_killswitch(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setenv("LOA_CHEVAL_DISABLE_STREAMING", "1")
        import yaml
        path = Path(__file__).resolve().parents[2] / "defaults" / "model-config.yaml"
        if not path.exists():
            pytest.skip("model-config.yaml not present in this checkout")
        with open(path) as fh:
            cfg = yaml.safe_load(fh)
        assert (
            _lookup_max_input_tokens(
                "anthropic", "claude-opus-4-7", cfg
            )
            == 36000
        )
