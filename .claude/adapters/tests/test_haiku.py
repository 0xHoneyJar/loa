"""cycle-095 Sprint 2 (Task 2.10 / SDD §7.3): Haiku 4.5 round-trip + frozen pricing snapshot."""

import json
import sys
from pathlib import Path
from unittest.mock import patch

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from loa_cheval.providers.anthropic_adapter import AnthropicAdapter
from loa_cheval.types import (
    CompletionRequest,
    ModelConfig,
    ProviderConfig,
)


def _make_haiku_provider() -> ProviderConfig:
    """Provider config mirroring the cycle-095 Sprint 2 model-config.yaml entry."""
    return ProviderConfig(
        name="anthropic",
        type="anthropic",
        endpoint="https://api.example.com/v1",
        auth="test-key",
        models={
            "claude-haiku-4-5-20251001": ModelConfig(
                capabilities=["chat", "tools", "function_calling"],
                context_window=200000,
                token_param="max_tokens",
                pricing={"input_per_mtok": 1000000, "output_per_mtok": 5000000},
            ),
        },
    )


class TestHaikuRoundTrip:
    """Sprint 2 G-3: Haiku 4.5 callable through cheval Anthropic adapter."""

    def test_haiku_routes_through_anthropic_messages_endpoint(self, monkeypatch):
        # Sprint 4A: AnthropicAdapter.complete() defaults to streaming. This
        # test only verifies routing (URL + headers + body shape + parsed
        # CompletionResult); it doesn't care about transport. Route through
        # the legacy non-streaming path so the existing http_post mock still
        # intercepts the call.
        monkeypatch.setenv("LOA_CHEVAL_DISABLE_STREAMING", "1")

        adapter = AnthropicAdapter(_make_haiku_provider())
        captured = []

        def fake(url, headers, body, **_kwargs):
            captured.append({"url": url, "body": body, "headers": headers})
            return 200, {
                "id": "msg_haiku_001",
                "model": "claude-haiku-4-5-20251001",
                "content": [{"type": "text", "text": "haiku response"}],
                "usage": {"input_tokens": 8, "output_tokens": 4},
                "stop_reason": "end_turn",
                "role": "assistant",
                "type": "message",
            }

        with patch("loa_cheval.providers.anthropic_adapter.http_post", side_effect=fake):
            result = adapter.complete(
                CompletionRequest(
                    messages=[{"role": "user", "content": "say hi"}],
                    model="claude-haiku-4-5-20251001",
                    max_tokens=64,
                )
            )

        assert captured[0]["url"].endswith("/messages")
        assert "x-api-key" in captured[0]["headers"]
        assert captured[0]["headers"]["anthropic-version"] == "2023-06-01"
        assert captured[0]["body"]["model"] == "claude-haiku-4-5-20251001"
        assert result.content == "haiku response"
        assert result.usage.input_tokens == 8
        assert result.usage.output_tokens == 4


class TestHaikuPricingFreezeSnapshot:
    """Sprint 2 FR-3 AC: live-fetch ONCE then freeze pricing in YAML.

    Pin the frozen 2026-04-29 values so accidental edits surface immediately.
    """

    FROZEN_INPUT = 1_000_000     # $1.00 / Mtok
    FROZEN_OUTPUT = 5_000_000    # $5.00 / Mtok

    def test_frozen_pricing_matches_snapshot(self):
        from loa_cheval.config.loader import load_config, clear_config_cache, _reset_warning_state_for_tests

        clear_config_cache()
        _reset_warning_state_for_tests()
        # Use the project's actual System Zone defaults for this assertion —
        # we want a regression sentinel that catches anyone editing the YAML.
        merged, _ = load_config(project_root=str(Path(__file__).resolve().parents[3]))
        haiku = merged["providers"]["anthropic"]["models"]["claude-haiku-4-5-20251001"]
        pricing = haiku["pricing"]
        assert pricing["input_per_mtok"] == self.FROZEN_INPUT, (
            "Haiku 4.5 input pricing changed from frozen 2026-04-29 value. "
            "If this is intentional, update the FROZEN_INPUT constant + CHANGELOG."
        )
        assert pricing["output_per_mtok"] == self.FROZEN_OUTPUT, (
            "Haiku 4.5 output pricing changed from frozen 2026-04-29 value."
        )
