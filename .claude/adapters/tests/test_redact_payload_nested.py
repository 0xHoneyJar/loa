"""cycle-103 sprint-3 T3.6 — redact_payload_strings path-aware nested walk.

Pins AC-3.6 / DISS-003: once an ancestor key is in `_REDACT_FIELDS`, every
descendant string gets routed through the redactor regardless of
immediate-parent key, list nesting, or mixed structure.

The redactor (`log-redactor.py`) is content-pattern based: it transforms
strings containing real secret SHAPES (Bearer tokens, AKIA keys, PEM blocks,
etc.) and passes ordinary strings through unchanged. So these tests embed
real secret shapes inside nested structures under a redact-field ancestor
and assert the shape no longer survives the walk.

Test taxonomy:
- Direct child (regression — original behavior preserved)
- Nested dict under redact-field ancestor (T3.6 fix path)
- Nested list under redact-field ancestor (T3.6 fix path)
- Mixed structure (dict-in-list-in-dict)
- Deep nesting (4+ levels)
- Sibling isolation — strings outside redact-ancestor remain raw
- Structure preservation — keys/order/non-string types unchanged
- Audit-envelope round-trip pin (R8a)
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from loa_cheval.audit.modelinv import (  # noqa: E402
    _REDACT_FIELDS,
    redact_payload_strings,
)


# A real Bearer-token shape that `log-redactor.py::redact` will transform
# into `[REDACTED-BEARER-TOKEN]`. Token portion is ≥16 chars (matches the
# `_GATE_BEARER` quantifier — same shape the cycle-099 sprint-1E.a redactor
# pattern catches).
_BEARER = "Bearer abcdef0123456789xyzABCDE"
_BEARER_REDACTED = "[REDACTED-BEARER-TOKEN]"


def _redacted(s: str) -> bool:
    """True iff the redactor's output marker is present (or string was
    transformed in any visible way that strips the raw secret)."""
    return _BEARER_REDACTED in s and _BEARER not in s


# ---------------------------------------------------------------------------
# Regression: original immediate-parent behavior preserved
# ---------------------------------------------------------------------------


class TestDirectChildRegression:
    def test_redacts_immediate_string_child(self) -> None:
        out = redact_payload_strings({"error_message": _BEARER})
        assert _redacted(out["error_message"])

    def test_leaves_non_redact_field_alone(self) -> None:
        # Operator-controlled field — must NOT route through redactor.
        out = redact_payload_strings({"model": "claude-opus-4.7"})
        assert out["model"] == "claude-opus-4.7"

    def test_each_redact_field_individually(self) -> None:
        for field in _REDACT_FIELDS:
            out = redact_payload_strings({field: _BEARER})
            assert _redacted(out[field]), f"{field} should redact"


# ---------------------------------------------------------------------------
# T3.6 NEW: nested dict under redact ancestor
# ---------------------------------------------------------------------------


class TestNestedDict:
    def test_one_level_nested_dict(self) -> None:
        payload = {"error_message": {"detail": _BEARER}}
        out = redact_payload_strings(payload)
        assert isinstance(out["error_message"], dict)
        assert _redacted(out["error_message"]["detail"])

    def test_two_level_nested_dict(self) -> None:
        payload = {
            "error_message": {"outer": {"inner": _BEARER}}
        }
        out = redact_payload_strings(payload)
        assert _redacted(out["error_message"]["outer"]["inner"])

    def test_intermediate_key_not_in_redact_fields_still_redacts(self) -> None:
        # Intermediate keys "outer", "innocuous" are NOT in _REDACT_FIELDS,
        # but the ancestor "original_exception" IS — every descendant
        # string must route through the redactor.
        payload = {
            "original_exception": {
                "outer": {"innocuous": {"deepest": _BEARER}}
            }
        }
        out = redact_payload_strings(payload)
        assert _redacted(
            out["original_exception"]["outer"]["innocuous"]["deepest"]
        )


# ---------------------------------------------------------------------------
# T3.6 NEW: nested list under redact ancestor
# ---------------------------------------------------------------------------


class TestNestedList:
    def test_list_of_strings_under_redact_field(self) -> None:
        payload = {"error_message": [_BEARER, _BEARER]}
        out = redact_payload_strings(payload)
        assert all(_redacted(s) for s in out["error_message"])

    def test_list_of_dicts_under_redact_field(self) -> None:
        payload = {
            "error_message": [{"inner": _BEARER}, {"inner": _BEARER}]
        }
        out = redact_payload_strings(payload)
        assert _redacted(out["error_message"][0]["inner"])
        assert _redacted(out["error_message"][1]["inner"])

    def test_mixed_list_strings_and_dicts(self) -> None:
        payload = {"error_message": [_BEARER, {"inner": _BEARER}]}
        out = redact_payload_strings(payload)
        assert _redacted(out["error_message"][0])
        assert _redacted(out["error_message"][1]["inner"])


# ---------------------------------------------------------------------------
# T3.6 NEW: mixed dict-list-dict structures
# ---------------------------------------------------------------------------


class TestMixedStructure:
    def test_dict_in_list_in_dict_in_redact(self) -> None:
        payload = {
            "exception_summary": {
                "causes": [
                    {"layer": "transport", "msg": _BEARER},
                    {"layer": "decode", "msg": _BEARER},
                ]
            }
        }
        out = redact_payload_strings(payload)
        causes = out["exception_summary"]["causes"]
        assert _redacted(causes[0]["msg"])
        assert _redacted(causes[1]["msg"])


# ---------------------------------------------------------------------------
# T3.6 NEW: sibling isolation — non-redact ancestors untouched
# ---------------------------------------------------------------------------


class TestSiblingIsolation:
    def test_sibling_dict_untouched(self) -> None:
        # Strings outside any redact-ancestor must NOT be routed through
        # the redactor — even if they contain secret-like content.
        # (Operator-controlled config strings live outside the trust
        # boundary that _REDACT_FIELDS marks.)
        payload = {
            "model": "claude-opus-4.7",
            "error_message": _BEARER,
            "metadata": {"call_id": "abc-123"},
        }
        out = redact_payload_strings(payload)
        assert out["model"] == "claude-opus-4.7"
        assert out["metadata"]["call_id"] == "abc-123"
        assert _redacted(out["error_message"])

    def test_strings_outside_redact_ancestor_stay_intact(self) -> None:
        payload = {
            "request": {
                "model": "gpt-5.3",
                "params": {"temperature": "0.7"},
            },
            "error_message": {"detail": _BEARER},
        }
        out = redact_payload_strings(payload)
        assert out["request"]["model"] == "gpt-5.3"
        assert out["request"]["params"]["temperature"] == "0.7"
        assert _redacted(out["error_message"]["detail"])

    def test_top_level_list_untouched(self) -> None:
        # No redact-field ancestor at all → list stays intact, byte-equal.
        payload = ["raw_a", {"k": "v"}, "raw_b"]
        out = redact_payload_strings(payload)
        assert out == ["raw_a", {"k": "v"}, "raw_b"]


# ---------------------------------------------------------------------------
# T3.6 NEW: deep nesting (4+ levels)
# ---------------------------------------------------------------------------


class TestDeepNesting:
    def test_four_level_dict(self) -> None:
        payload = {
            "original_exception": {
                "a": {"b": {"c": {"d": _BEARER}}}
            }
        }
        out = redact_payload_strings(payload)
        assert _redacted(
            out["original_exception"]["a"]["b"]["c"]["d"]
        )

    def test_alternating_dict_list_dict(self) -> None:
        payload = {
            "error_message": {
                "levels": [
                    {"sub": [{"final": _BEARER}]},
                ]
            }
        }
        out = redact_payload_strings(payload)
        assert _redacted(
            out["error_message"]["levels"][0]["sub"][0]["final"]
        )


# ---------------------------------------------------------------------------
# T3.6 NEW: structure preservation
# ---------------------------------------------------------------------------


class TestStructurePreservation:
    def test_keys_preserved(self) -> None:
        payload = {
            "error_message": {"detail": _BEARER, "code": 500, "tags": ["a"]}
        }
        out = redact_payload_strings(payload)
        assert set(out["error_message"].keys()) == {"detail", "code", "tags"}

    def test_non_string_types_unchanged(self) -> None:
        # Numbers, booleans, None under a redact ancestor stay as-is.
        payload = {
            "error_message": {
                "code": 500,
                "retryable": True,
                "ts": None,
                "weight": 0.85,
                "detail": _BEARER,
            }
        }
        out = redact_payload_strings(payload)
        em = out["error_message"]
        assert em["code"] == 500
        assert em["retryable"] is True
        assert em["ts"] is None
        assert em["weight"] == 0.85
        assert _redacted(em["detail"])

    def test_list_length_preserved(self) -> None:
        payload = {"error_message": [_BEARER, _BEARER, _BEARER]}
        out = redact_payload_strings(payload)
        assert len(out["error_message"]) == 3
        assert all(_redacted(s) for s in out["error_message"])

    def test_empty_dict_and_list_under_redact(self) -> None:
        payload = {"error_message": {"empty_dict": {}, "empty_list": []}}
        out = redact_payload_strings(payload)
        assert out["error_message"]["empty_dict"] == {}
        assert out["error_message"]["empty_list"] == []

    def test_plain_string_under_redact_unchanged(self) -> None:
        # A string under a redact ancestor with NO secret shape passes
        # through the redactor unchanged (content-pattern-based). The
        # redactor was still called — but had nothing to transform.
        payload = {"error_message": {"detail": "ordinary text"}}
        out = redact_payload_strings(payload)
        assert out["error_message"]["detail"] == "ordinary text"


# ---------------------------------------------------------------------------
# T3.6 NEW: audit-envelope round-trip pin (R8a — sprint.md L245)
# ---------------------------------------------------------------------------


class TestAuditEnvelopeRoundTrip:
    def test_json_round_trip_stable(self) -> None:
        # Pin: redacted payload survives JSON encode/decode unchanged.
        payload = {
            "model": "claude-opus-4.7",
            "error_message": {"detail": _BEARER, "code": 500},
            "metadata": {"call_id": "abc"},
        }
        out = redact_payload_strings(payload)
        round_tripped = json.loads(json.dumps(out))
        assert round_tripped == out

    def test_idempotent_under_double_application(self) -> None:
        # Applying redaction twice = applying it once. Critical for any
        # log-replay or chain-recovery flow that re-walks an emitted entry.
        payload = {"error_message": {"detail": _BEARER}}
        once = redact_payload_strings(payload)
        twice = redact_payload_strings(once)
        assert once == twice
