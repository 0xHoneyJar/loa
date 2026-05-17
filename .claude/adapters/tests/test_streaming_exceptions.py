"""cycle-113 Sprint 1 T1.1 — StreamingRecoveryAbort exception unit tests.

Pins the SDD §2.2 contract:
  * exception is importable from both ``loa_cheval.streaming.exceptions``
    and the package-level ``loa_cheval.streaming``
  * carries reason / tokens_before_abort / config_applied verbatim
  * partial_content defaults to None and is preserved when supplied
  * __str__ contains the reason and token count (for log/trace utility)
  * subclasses Exception (so existing `except Exception` arms still catch)
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))


# ---------------------------------------------------------------------------
# Import-surface contract
# ---------------------------------------------------------------------------


def test_importable_from_exceptions_module():
    from loa_cheval.streaming.exceptions import StreamingRecoveryAbort

    assert StreamingRecoveryAbort is not None


def test_importable_from_package_root():
    from loa_cheval.streaming import StreamingRecoveryAbort

    assert StreamingRecoveryAbort is not None


def test_package_root_and_module_export_same_class():
    from loa_cheval.streaming import StreamingRecoveryAbort as A
    from loa_cheval.streaming.exceptions import StreamingRecoveryAbort as B

    assert A is B


def test_exported_in_package_all():
    from loa_cheval.streaming import __all__

    assert "StreamingRecoveryAbort" in __all__


# ---------------------------------------------------------------------------
# Inheritance contract (I-2: typed exception, must still be `Exception`)
# ---------------------------------------------------------------------------


def test_subclasses_exception():
    from loa_cheval.streaming import StreamingRecoveryAbort

    assert issubclass(StreamingRecoveryAbort, Exception)


def test_caught_by_bare_except_exception_arm():
    """I-2: existing adapter ``except Exception`` arms still catch the abort
    (the typed translation arm is an ENHANCEMENT, not a replacement)."""
    from loa_cheval.streaming import StreamingRecoveryAbort

    caught = None
    try:
        raise StreamingRecoveryAbort(
            reason="first_token_deadline",
            tokens_before_abort=0,
            config_applied={"first_token_deadline_s": 30.0},
        )
    except Exception as exc:  # noqa: BLE001 — intentional bare-Exception
        caught = exc

    assert isinstance(caught, StreamingRecoveryAbort)


# ---------------------------------------------------------------------------
# Field-preservation contract
# ---------------------------------------------------------------------------


def test_carries_reason_field():
    from loa_cheval.streaming import StreamingRecoveryAbort

    exc = StreamingRecoveryAbort(
        reason="empty_content_window",
        tokens_before_abort=200,
        config_applied={},
    )
    assert exc.reason == "empty_content_window"


def test_carries_tokens_before_abort_field():
    from loa_cheval.streaming import StreamingRecoveryAbort

    exc = StreamingRecoveryAbort(
        reason="empty_content_window",
        tokens_before_abort=200,
        config_applied={},
    )
    assert exc.tokens_before_abort == 200


def test_carries_config_applied_field_verbatim():
    """I-3 + audit: config_applied is the operator-visible threshold-config
    record. The exception MUST NOT mutate it; the adapter copies it into
    MODELINV verbatim."""
    from loa_cheval.streaming import StreamingRecoveryAbort

    original = {
        "first_token_deadline_s": 60.0,
        "empty_content_window_tokens": 200,
        "cot_budget_tokens": 500,
        "reasoning_class": True,
    }
    exc = StreamingRecoveryAbort(
        reason="cot_budget_exhausted",
        tokens_before_abort=523,
        config_applied=original,
    )

    assert exc.config_applied == original
    assert exc.config_applied is original  # identity preserved, no defensive copy


def test_partial_content_defaults_to_none():
    from loa_cheval.streaming import StreamingRecoveryAbort

    exc = StreamingRecoveryAbort(
        reason="first_token_deadline",
        tokens_before_abort=0,
        config_applied={},
    )
    assert exc.partial_content is None


def test_partial_content_preserved_when_supplied():
    from loa_cheval.streaming import StreamingRecoveryAbort

    exc = StreamingRecoveryAbort(
        reason="empty_content_window",
        tokens_before_abort=200,
        config_applied={},
        partial_content="<thinking>let me consider</thinking>",
    )
    assert exc.partial_content == "<thinking>let me consider</thinking>"


def test_partial_content_can_be_empty_string():
    """Distinguishes 'no tokens arrived' (None) from 'tokens were all CoT/
    empty' (empty string). The adapter / NFR-Obs-1 log line cares about
    the difference."""
    from loa_cheval.streaming import StreamingRecoveryAbort

    exc = StreamingRecoveryAbort(
        reason="empty_content_window",
        tokens_before_abort=200,
        config_applied={},
        partial_content="",
    )
    assert exc.partial_content == ""
    assert exc.partial_content is not None


# ---------------------------------------------------------------------------
# __str__ contract (NFR-Obs-1: log lines must include reason + tokens)
# ---------------------------------------------------------------------------


def test_str_includes_reason():
    from loa_cheval.streaming import StreamingRecoveryAbort

    exc = StreamingRecoveryAbort(
        reason="cot_budget_exhausted",
        tokens_before_abort=523,
        config_applied={},
    )
    assert "cot_budget_exhausted" in str(exc)


def test_str_includes_tokens_before_abort():
    from loa_cheval.streaming import StreamingRecoveryAbort

    exc = StreamingRecoveryAbort(
        reason="empty_content_window",
        tokens_before_abort=200,
        config_applied={},
    )
    assert "200" in str(exc)


# ---------------------------------------------------------------------------
# Reason-value contract: matches StreamingRecoveryDecision.reason vocabulary
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    "reason",
    ["first_token_deadline", "empty_content_window", "cot_budget_exhausted"],
)
def test_accepts_all_three_canonical_reasons(reason):
    """Pins parity with StreamingRecoveryTracker's three abort reasons
    (recovery.py:158-228). If the library adds a fourth reason, this test
    documents the place to extend."""
    from loa_cheval.streaming import StreamingRecoveryAbort

    exc = StreamingRecoveryAbort(
        reason=reason,
        tokens_before_abort=0,
        config_applied={},
    )
    assert exc.reason == reason


def test_accepts_arbitrary_reason_string_for_forward_compat():
    """The class does NOT enum-validate ``reason`` — the library's
    ``StreamingRecoveryReason`` is a plain ``str`` typedef. Adapters MUST
    accept whatever the library emits; reason-value drift is a library
    concern, not an exception concern."""
    from loa_cheval.streaming import StreamingRecoveryAbort

    exc = StreamingRecoveryAbort(
        reason="future_reason_class_added_later",
        tokens_before_abort=42,
        config_applied={},
    )
    assert exc.reason == "future_reason_class_added_later"
