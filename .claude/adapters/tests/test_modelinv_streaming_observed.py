"""cycle-103 sprint-3 T3.2 — tests for observed-streaming audit field.

Pins the AC-3.2 contract:
  1. Adapter sets CompletionResult.metadata['streaming'] at completion
     time based on actual transport observed.
  2. emit_model_invoke_complete reads the caller-supplied `streaming`
     argument BEFORE falling back to env-derived `_streaming_active()`.
  3. The wire behavior (streaming=True for SSE transport, streaming=False
     for non-streaming POST) shows up in the audit envelope EVEN WHEN
     LOA_CHEVAL_DISABLE_STREAMING mid-session would have flipped the
     env-derived default.

Spec: sprint.md T3.2 + AC-3.2 + sdd.md §3.4.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from loa_cheval.audit.modelinv import (  # noqa: E402
    emit_model_invoke_complete,
)


# ----------------------------------------------------------------------------
# emit_model_invoke_complete: streaming arg precedence
# ----------------------------------------------------------------------------


def _capture_payload() -> dict:
    """Helper: patch audit_emit and capture the payload that would be
    written to the chain. Returns the captured dict (or empty if no
    emit happened)."""
    captured: dict = {}

    def _fake_emit(level, event, payload, *args, **kwargs) -> None:
        captured.update(payload)

    return captured, _fake_emit


class TestStreamingArgPrecedence:
    """AC-3.2: caller-supplied streaming MUST win over env-derived."""

    def test_streaming_true_from_adapter_overrides_env_false(
        self, monkeypatch
    ) -> None:
        """Adapter says streaming=True via metadata. Env says
        LOA_CHEVAL_DISABLE_STREAMING=1 → env-derived would be False.
        Result: payload['streaming'] = True (adapter wins)."""
        monkeypatch.setenv("LOA_CHEVAL_DISABLE_STREAMING", "1")

        captured, fake_emit = _capture_payload()
        with patch("loa_cheval.audit_envelope.audit_emit", fake_emit), \
             patch("loa_cheval.audit.modelinv.redact_payload_strings",
                   side_effect=lambda x: x), \
             patch(
                 "loa_cheval.audit.modelinv.assert_no_secret_shapes_remain"
             ):
            emit_model_invoke_complete(
                models_requested=["anthropic:claude-opus-4.7"],
                models_succeeded=["anthropic:claude-opus-4.7"],
                models_failed=[],
                operator_visible_warn=False,
                streaming=True,
            )

        assert captured.get("streaming") is True

    def test_streaming_false_from_adapter_overrides_env_true(
        self, monkeypatch
    ) -> None:
        """Adapter says streaming=False (non-streaming path ran). Env says
        LOA_CHEVAL_DISABLE_STREAMING unset → env-derived would be True.
        Result: payload['streaming'] = False (adapter wins)."""
        monkeypatch.delenv("LOA_CHEVAL_DISABLE_STREAMING", raising=False)

        captured, fake_emit = _capture_payload()
        with patch("loa_cheval.audit_envelope.audit_emit", fake_emit), \
             patch("loa_cheval.audit.modelinv.redact_payload_strings",
                   side_effect=lambda x: x), \
             patch(
                 "loa_cheval.audit.modelinv.assert_no_secret_shapes_remain"
             ):
            emit_model_invoke_complete(
                models_requested=["anthropic:claude-opus-4.7"],
                models_succeeded=["anthropic:claude-opus-4.7"],
                models_failed=[],
                operator_visible_warn=False,
                streaming=False,
            )

        assert captured.get("streaming") is False

    def test_streaming_none_falls_back_to_env_streaming_enabled(
        self, monkeypatch
    ) -> None:
        """Adapter didn't set metadata (legacy caller). Env says streaming
        enabled. Result: payload['streaming'] = True (env fallback)."""
        monkeypatch.delenv("LOA_CHEVAL_DISABLE_STREAMING", raising=False)

        captured, fake_emit = _capture_payload()
        with patch("loa_cheval.audit_envelope.audit_emit", fake_emit), \
             patch("loa_cheval.audit.modelinv.redact_payload_strings",
                   side_effect=lambda x: x), \
             patch(
                 "loa_cheval.audit.modelinv.assert_no_secret_shapes_remain"
             ):
            emit_model_invoke_complete(
                models_requested=["anthropic:claude-opus-4.7"],
                models_succeeded=["anthropic:claude-opus-4.7"],
                models_failed=[],
                operator_visible_warn=False,
                # streaming= NOT passed → falls back to env-derived
            )

        assert captured.get("streaming") is True

    def test_streaming_none_falls_back_to_env_streaming_disabled(
        self, monkeypatch
    ) -> None:
        """Adapter didn't set metadata. Env says streaming disabled.
        Result: payload['streaming'] = False (env fallback)."""
        monkeypatch.setenv("LOA_CHEVAL_DISABLE_STREAMING", "1")

        captured, fake_emit = _capture_payload()
        with patch("loa_cheval.audit_envelope.audit_emit", fake_emit), \
             patch("loa_cheval.audit.modelinv.redact_payload_strings",
                   side_effect=lambda x: x), \
             patch(
                 "loa_cheval.audit.modelinv.assert_no_secret_shapes_remain"
             ):
            emit_model_invoke_complete(
                models_requested=["anthropic:claude-opus-4.7"],
                models_succeeded=["anthropic:claude-opus-4.7"],
                models_failed=[],
                operator_visible_warn=False,
            )

        assert captured.get("streaming") is False


# ----------------------------------------------------------------------------
# Adapter-level: metadata['streaming'] is set on every CompletionResult
# ----------------------------------------------------------------------------


class TestAdapterSetsStreamingMetadata:
    """AC-3.2: every adapter must populate metadata['streaming'] so the
    cheval.py wiring at cmd_invoke can propagate it to emit."""

    def test_anthropic_adapter_streaming_metadata_present(self) -> None:
        """The anthropic_adapter source code MUST contain the
        streaming-flag-setting pattern in both transport branches."""
        path = (
            Path(__file__).resolve().parents[1]
            / "loa_cheval"
            / "providers"
            / "anthropic_adapter.py"
        )
        text = path.read_text(encoding="utf-8")
        # Streaming branch sets True via dict-merge pattern.
        assert '_meta["streaming"] = True' in text
        # Non-streaming branch returns metadata={"streaming": False}.
        assert '{"streaming": False}' in text

    def test_openai_adapter_streaming_metadata_present(self) -> None:
        path = (
            Path(__file__).resolve().parents[1]
            / "loa_cheval"
            / "providers"
            / "openai_adapter.py"
        )
        text = path.read_text(encoding="utf-8")
        assert '_meta["streaming"] = True' in text
        # Non-streaming path uses spread + override pattern.
        assert '"streaming": False' in text

    def test_google_adapter_streaming_metadata_present(self) -> None:
        path = (
            Path(__file__).resolve().parents[1]
            / "loa_cheval"
            / "providers"
            / "google_adapter.py"
        )
        text = path.read_text(encoding="utf-8")
        # Streaming path sets True.
        assert '_meta["streaming"] = True' in text
        # Non-streaming + Deep-Research paths both set False.
        assert '"streaming": False' in text


# ----------------------------------------------------------------------------
# cheval.py: cmd_invoke reads metadata['streaming'] and propagates to emit
# ----------------------------------------------------------------------------


class TestChevalPyPropagatesStreaming:
    """The cheval.py orchestration MUST capture result.metadata['streaming']
    and pass it to emit_model_invoke_complete(streaming=...)."""

    def test_cheval_py_propagates_streaming_flag(self) -> None:
        path = (
            Path(__file__).resolve().parents[1] / "cheval.py"
        )
        text = path.read_text(encoding="utf-8")
        # The metadata read at completion time.
        assert "_result_meta.get(\"streaming\")" in text
        # The flag in _modelinv_state.
        assert "_modelinv_state[\"streaming\"]" in text
        # Propagation to emit.
        assert "streaming=_modelinv_state[\"streaming\"]" in text
