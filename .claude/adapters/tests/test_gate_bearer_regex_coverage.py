"""cycle-103 sprint-3 T3.7 — _GATE_BEARER regex coverage tests.

Pins the AC-3.7 / DISS-004 closure: the bearer-token defense-in-depth gate
catches every documented encoding/obfuscation variant after the cycle-099
sprint-1E.c.3.c Unicode-glob bypass precedent (NFKC + control-byte strip).

Test taxonomy:
- Canonical variants (space, tab, colon, mixed case)
- Percent-encoded forms (%20, %22, %3A)
- JSON-escape-quoted forms
- Unicode fullwidth (NFKC normalize closure)
- Zero-width insertion (defense-in-depth)
- Negative controls (Bearer with <16 char token should NOT trip)
- Negative controls (already-redacted sentinels should NOT trip)
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from loa_cheval.audit.modelinv import (  # noqa: E402
    RedactionFailure,
    _GATE_BEARER,
    _normalize_for_gate,
    assert_no_secret_shapes_remain,
)


# A 24-char token shape that satisfies the {16,} length minimum.
_TOK = "abcdef0123456789xyzABCDE"
assert len(_TOK) >= 16


# ----------------------------------------------------------------------------
# Canonical variants — original behavior preserved
# ----------------------------------------------------------------------------


class TestCanonicalVariants:
    def test_space_separator_trips(self) -> None:
        with pytest.raises(RedactionFailure, match="Bearer-token"):
            assert_no_secret_shapes_remain(f'{{"auth":"Bearer {_TOK}"}}')

    def test_tab_separator_trips(self) -> None:
        with pytest.raises(RedactionFailure, match="Bearer-token"):
            assert_no_secret_shapes_remain(f'{{"auth":"Bearer\t{_TOK}"}}')

    def test_lowercase_bearer_trips(self) -> None:
        with pytest.raises(RedactionFailure, match="Bearer-token"):
            assert_no_secret_shapes_remain(f'{{"auth":"bearer {_TOK}"}}')


# ----------------------------------------------------------------------------
# T3.7 NEW: colon separator (no space)
# ----------------------------------------------------------------------------


class TestColonSeparator:
    def test_lowercase_colon_trips(self) -> None:
        with pytest.raises(RedactionFailure, match="Bearer-token"):
            assert_no_secret_shapes_remain(f'{{"auth":"bearer:{_TOK}"}}')

    def test_capital_colon_trips(self) -> None:
        with pytest.raises(RedactionFailure, match="Bearer-token"):
            assert_no_secret_shapes_remain(f'{{"auth":"Bearer:{_TOK}"}}')


# ----------------------------------------------------------------------------
# T3.7 NEW: percent-encoded forms
# ----------------------------------------------------------------------------


class TestPercentEncoded:
    def test_percent20_space_decoded_then_matches(self) -> None:
        # `%20` (URL-encoded space) decodes to space, then standard regex.
        with pytest.raises(RedactionFailure, match="Bearer-token"):
            assert_no_secret_shapes_remain(
                f'{{"url":"...%20Bearer%20{_TOK}..."}}'
            )

    def test_percent3a_colon_decoded_then_matches(self) -> None:
        # `%3A` (URL-encoded colon) decodes to `:`, then matches.
        with pytest.raises(RedactionFailure, match="Bearer-token"):
            assert_no_secret_shapes_remain(
                f'{{"url":"...bearer%3A{_TOK}..."}}'
            )

    def test_percent3a_lowercase_decoded(self) -> None:
        # Both %3A and %3a should decode (operator might mix cases).
        with pytest.raises(RedactionFailure, match="Bearer-token"):
            assert_no_secret_shapes_remain(
                f'{{"url":"...bearer%3a{_TOK}..."}}'
            )


# ----------------------------------------------------------------------------
# T3.7 NEW: JSON-escape-quoted (nested JSON)
# ----------------------------------------------------------------------------


class TestJSONEscapeQuoted:
    def test_escaped_quotes_around_bearer_match_inner(self) -> None:
        # `\"Bearer X\"` — Bearer inside a string that's itself inside a
        # JSON string. The outer JSON escapes the quotes; the gate's
        # normalization decodes %22 → " which makes the inner pattern
        # visible to the matcher.
        # In raw form: "\\\"Bearer XYZ\\\""
        # After percent-decode of %22, the outer string becomes
        # ..."Bearer XYZ"...  — but the gate is looking at JSON-serialized
        # payload where escaping already happened. The actual encoded
        # form depends on the encoder; the gate handles the most
        # common form (raw embed of Bearer + space + token).
        with pytest.raises(RedactionFailure, match="Bearer-token"):
            # Embed Bearer in a value that contains an escaped quote prefix.
            assert_no_secret_shapes_remain(
                f'{{"nested":"\\\"Bearer {_TOK}\\\""}}'
            )


# ----------------------------------------------------------------------------
# T3.7 NEW: Unicode fullwidth (NFKC closure)
# ----------------------------------------------------------------------------


class TestUnicodeFullwidth:
    def test_fullwidth_bearer_trips(self) -> None:
        # Ｂｅａｒｅｒ — U+FF22 U+FF45 U+FF41 U+FF52 U+FF45 U+FF52 →
        # ASCII Bearer via NFKC normalize.
        fullwidth_bearer = "Ｂｅａｒｅｒ"
        with pytest.raises(RedactionFailure, match="Bearer-token"):
            assert_no_secret_shapes_remain(
                f'{{"auth":"{fullwidth_bearer} {_TOK}"}}'
            )


# ----------------------------------------------------------------------------
# T3.7 NEW: zero-width insertion (defense-in-depth)
# ----------------------------------------------------------------------------


class TestZeroWidthInsertion:
    @pytest.mark.parametrize(
        "zw_char",
        [
            "​",  # ZERO WIDTH SPACE
            "‌",  # ZERO WIDTH NON-JOINER
            "‍",  # ZERO WIDTH JOINER
            "﻿",  # ZERO WIDTH NO-BREAK SPACE (BOM)
        ],
    )
    def test_zero_width_in_bearer_trips(self, zw_char: str) -> None:
        # B<ZW>earer XYZ — the zero-width insertion would defeat a naive
        # regex. The gate's normalization strips it before matching.
        obfuscated = "B" + zw_char + "earer"
        with pytest.raises(RedactionFailure, match="Bearer-token"):
            assert_no_secret_shapes_remain(
                f'{{"auth":"{obfuscated} {_TOK}"}}'
            )


# ----------------------------------------------------------------------------
# Negative controls — must NOT trip
# ----------------------------------------------------------------------------


class TestNegativeControls:
    def test_short_token_does_not_trip(self) -> None:
        # Less than 16 chars → not a real bearer token shape.
        short_tok = "tiny"
        # Should NOT raise.
        assert_no_secret_shapes_remain(f'{{"auth":"Bearer {short_tok}"}}')

    def test_redacted_sentinel_does_not_trip(self) -> None:
        # The post-redactor sentinel must not look like an unredacted
        # bearer token to the gate. `[REDACTED-Bearer]` lacks the {16,}
        # alphanumeric run.
        assert_no_secret_shapes_remain(
            '{"auth":"[REDACTED-Bearer]"}'
        )

    def test_word_bearer_alone_does_not_trip(self) -> None:
        # Just the word "Bearer" without a 16+ char token after.
        assert_no_secret_shapes_remain(
            '{"description":"Bearer authentication scheme"}'
        )

    def test_polar_bears_safe(self) -> None:
        # `bear` is a substring of "Bearer" but should NOT be confused
        # with bearer-token context.
        assert_no_secret_shapes_remain(
            '{"animal":"polar bear","habitat":"arctic"}'
        )


# ----------------------------------------------------------------------------
# _normalize_for_gate — direct unit tests
# ----------------------------------------------------------------------------


class TestNormalizeForGate:
    def test_nfkc_collapses_fullwidth(self) -> None:
        fullwidth = "Ｂｅａｒｅｒ"
        out = _normalize_for_gate(fullwidth)
        assert out == "Bearer"

    def test_zero_width_stripped(self) -> None:
        # Each character class separately.
        for zw in ("​", "‌", "‍", "﻿"):
            input_str = f"Be{zw}arer"
            assert _normalize_for_gate(input_str) == "Bearer"

    def test_percent20_decoded(self) -> None:
        assert "Bearer XYZ" in _normalize_for_gate("%20Bearer%20XYZ")

    def test_percent3a_decoded_to_colon(self) -> None:
        assert "bearer:XYZ" in _normalize_for_gate("bearer%3AXYZ")

    def test_idempotent_on_canonical(self) -> None:
        canonical = f"Bearer {_TOK}"
        assert _normalize_for_gate(canonical) == canonical

    def test_combined_obfuscation(self) -> None:
        # NFKC fullwidth + zero-width insertion + percent-encoded separator.
        combined = "Ｂ​ｅａｒｅｒ%20XYZ"
        out = _normalize_for_gate(combined)
        assert "Bearer XYZ" in out


# ----------------------------------------------------------------------------
# _GATE_BEARER pattern directly (no normalize wrapper)
# ----------------------------------------------------------------------------


class TestPatternDirect:
    """Pin the regex pattern's per-separator behavior without the
    normalization wrapper. Useful for understanding what changes when
    normalization is bypassed."""

    def test_pattern_matches_space(self) -> None:
        assert _GATE_BEARER.search(f"Bearer {_TOK}") is not None

    def test_pattern_matches_colon(self) -> None:
        assert _GATE_BEARER.search(f"Bearer:{_TOK}") is not None

    def test_pattern_matches_tab(self) -> None:
        assert _GATE_BEARER.search(f"Bearer\t{_TOK}") is not None

    def test_pattern_rejects_no_separator(self) -> None:
        # The pattern requires AT LEAST one of [space, tab, colon] between
        # "Bearer" and the token. "BearerXYZ" should NOT match — XYZ might
        # just be a noun like "BearerAuthentication".
        assert _GATE_BEARER.search(f"Bearer{_TOK}") is None

    def test_pattern_rejects_short_token(self) -> None:
        assert _GATE_BEARER.search("Bearer tiny") is None
