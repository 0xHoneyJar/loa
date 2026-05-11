"""cycle-103 sprint-3 T3.3 — sanitize_provider_error_message tests.

Pins AC-3.3: secret-shape strings (AKIA, PEM, Bearer, sk-ant-*, sk-*,
sk-proj-*, AIza*) are scrubbed before they reach exception args, audit
envelopes, or operator-visible logs. Defense includes JSON-escape-quoted
variants and Unicode-glob (NFKC + zero-width strip) defense per
cycle-099 sprint-1E.c.3.c precedent.

Test taxonomy:
- Direct shapes (each pattern in isolation)
- Real-world embedded forms (URL + JSON + log line)
- JSON-escaped variants
- Unicode bypass attempts (fullwidth + zero-width insertion)
- Idempotence (sentinel doesn't re-trigger)
- Non-secret content preserved
- None / non-string handling
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from loa_cheval.redaction import sanitize_provider_error_message  # noqa: E402


# Real-shape fixtures (≥24 chars in body to satisfy length quantifiers).
_SK_ANT = "sk-ant-api03-XXXXXXXXXXXXXXXXXXXXXXXXXXXX"
_SK_OPENAI = "sk-proj-XXXXXXXXXXXXXXXXXXXXXXXXXXXX"
_SK_OPENAI_LEGACY = "sk-XXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
_AIZA = "AIza" + "X" * 35  # 39-char total
_AKIA = "AKIAIOSFODNN7EXAMPLE"
_BEARER = "Bearer abcdef0123456789xyzABCDE"


# ---------------------------------------------------------------------------
# Direct-shape patterns
# ---------------------------------------------------------------------------


class TestDirectShapes:
    def test_sk_ant_redacted(self) -> None:
        out = sanitize_provider_error_message(f"key={_SK_ANT}")
        assert _SK_ANT not in out
        assert "[REDACTED-API-KEY-ANTHROPIC]" in out

    def test_sk_openai_proj_redacted(self) -> None:
        out = sanitize_provider_error_message(f"key={_SK_OPENAI}")
        assert _SK_OPENAI not in out
        assert "[REDACTED-API-KEY-OPENAI]" in out

    def test_sk_openai_legacy_redacted(self) -> None:
        out = sanitize_provider_error_message(f"key={_SK_OPENAI_LEGACY}")
        assert _SK_OPENAI_LEGACY not in out
        assert "[REDACTED-API-KEY-OPENAI]" in out

    def test_aiza_redacted(self) -> None:
        out = sanitize_provider_error_message(f"key={_AIZA}")
        assert _AIZA not in out
        assert "[REDACTED-API-KEY-GOOGLE]" in out

    def test_akia_redacted(self) -> None:
        # Bridged from log-redactor.py
        out = sanitize_provider_error_message(f"key={_AKIA}")
        assert _AKIA not in out
        assert "[REDACTED-AKIA]" in out

    def test_bearer_redacted(self) -> None:
        # Bridged from log-redactor.py
        out = sanitize_provider_error_message(f"auth={_BEARER}")
        assert _BEARER not in out
        # log-redactor uses [REDACTED-BEARER-TOKEN]
        assert "REDACTED" in out

    def test_pem_redacted(self) -> None:
        pem = (
            "-----BEGIN RSA PRIVATE KEY-----\n"
            "MIIEvAIBADANBgkqhkiG9w0BAQEFAASCBKYwggSiAgEAAoIBAQ"
            "\n-----END RSA PRIVATE KEY-----"
        )
        out = sanitize_provider_error_message(pem)
        assert "MIIEvAIBADANBgkqhkiG" not in out
        assert "REDACTED" in out


# ---------------------------------------------------------------------------
# Anthropic vs OpenAI disambiguation
# ---------------------------------------------------------------------------


class TestKeyDisambiguation:
    def test_sk_ant_not_matched_by_openai_pattern(self) -> None:
        # sk-ant-* should redact as Anthropic, NOT OpenAI.
        out = sanitize_provider_error_message(_SK_ANT)
        assert "[REDACTED-API-KEY-ANTHROPIC]" in out
        assert "[REDACTED-API-KEY-OPENAI]" not in out

    def test_both_keys_in_one_message(self) -> None:
        msg = f"anthropic={_SK_ANT} openai={_SK_OPENAI_LEGACY}"
        out = sanitize_provider_error_message(msg)
        assert "[REDACTED-API-KEY-ANTHROPIC]" in out
        assert "[REDACTED-API-KEY-OPENAI]" in out
        assert _SK_ANT not in out
        assert _SK_OPENAI_LEGACY not in out


# ---------------------------------------------------------------------------
# Real-world embedded forms
# ---------------------------------------------------------------------------


class TestEmbeddedForms:
    def test_in_json_body(self) -> None:
        body = (
            '{"error":{"type":"authentication_error","message":'
            f'"Invalid API key: {_SK_ANT}. Please check your account."'
            "}}"
        )
        out = sanitize_provider_error_message(body)
        assert _SK_ANT not in out
        assert "[REDACTED-API-KEY-ANTHROPIC]" in out

    def test_in_url_query(self) -> None:
        url_msg = f"GET https://generativelanguage.googleapis.com/v1?key={_AIZA}"
        out = sanitize_provider_error_message(url_msg)
        assert _AIZA not in out

    def test_in_log_line(self) -> None:
        log = (
            f"[2026-05-11T12:34:56Z] DEBUG model_invoke headers="
            f'{{"authorization": "{_BEARER}"}}'
        )
        out = sanitize_provider_error_message(log)
        assert _BEARER not in out
        assert "abcdef0123456789xyzABCDE" not in out


# ---------------------------------------------------------------------------
# JSON-escape-quoted variants
# ---------------------------------------------------------------------------


class TestJsonEscapedVariants:
    def test_escaped_quotes_around_sk_ant(self) -> None:
        # `\"sk-ant-...\"` form (the outer JSON encoder escapes inner quotes).
        msg = f'{{"inner": "\\"key={_SK_ANT}\\""}}'
        out = sanitize_provider_error_message(msg)
        assert _SK_ANT not in out
        assert "[REDACTED-API-KEY-ANTHROPIC]" in out

    def test_escaped_aiza(self) -> None:
        msg = f'\\"{_AIZA}\\"'
        out = sanitize_provider_error_message(msg)
        assert _AIZA not in out


# ---------------------------------------------------------------------------
# Unicode bypass attempts (cycle-099 sprint-1E.c.3.c + T3.7 precedent)
# ---------------------------------------------------------------------------


class TestUnicodeBypass:
    def test_fullwidth_aiza_redacted(self) -> None:
        # Ｉｚａ etc. — NFKC normalizes to ASCII before pattern match.
        # Fullwidth chars span U+FF00 region; "AIza" → "ＡＩｚａ".
        fullwidth = "Ａ" + "Ｉ" + "ｚ" + "ａ" + "X" * 35
        out = sanitize_provider_error_message(fullwidth)
        # After NFKC, the leading 4 chars become "AIza" + 35 X's = 39 total.
        assert "[REDACTED-API-KEY-GOOGLE]" in out

    def test_zero_width_in_sk_ant_redacted(self) -> None:
        # B<ZW>S — zero-width insertion would defeat literal regex.
        obfuscated = "sk​ant-api03-" + "X" * 30  # ZWSP at position 2 changes match
        out = sanitize_provider_error_message(obfuscated)
        # After ZW strip, leading is "skant-" not "sk-ant-" — won't trip
        # the Anthropic pattern. Test the inverse case where the
        # zero-width is INSIDE the body, not the prefix.
        in_body = "sk-ant-" + "X" * 12 + "​" + "X" * 12
        out2 = sanitize_provider_error_message(in_body)
        assert "[REDACTED-API-KEY-ANTHROPIC]" in out2


# ---------------------------------------------------------------------------
# Idempotence
# ---------------------------------------------------------------------------


class TestIdempotence:
    def test_sentinel_does_not_re_trigger(self) -> None:
        once = sanitize_provider_error_message(f"k={_SK_ANT}")
        twice = sanitize_provider_error_message(once)
        assert once == twice

    def test_already_redacted_input_unchanged(self) -> None:
        already = "[REDACTED-API-KEY-ANTHROPIC] [REDACTED-AKIA] [REDACTED-BEARER-TOKEN]"
        out = sanitize_provider_error_message(already)
        assert out == already


# ---------------------------------------------------------------------------
# Negative controls
# ---------------------------------------------------------------------------


class TestNegativeControls:
    def test_ordinary_text_unchanged(self) -> None:
        msg = "Request failed: HTTP 429 rate limit exceeded. Retry in 30s."
        assert sanitize_provider_error_message(msg) == msg

    def test_short_sk_does_not_trip(self) -> None:
        # < 24 chars body → not a real key shape.
        msg = "sk-short-abc"
        assert sanitize_provider_error_message(msg) == msg

    def test_aiza_wrong_length_not_redacted(self) -> None:
        # AIza followed by only 20 chars → not the 39-char Google shape.
        msg = "AIza" + "X" * 20
        # The 39-char pattern requires exactly 35 chars after AIza.
        out = sanitize_provider_error_message(msg)
        assert "AIza" in out

    def test_word_bearer_alone_does_not_trip(self) -> None:
        msg = "Bearer authentication is required for this endpoint."
        assert sanitize_provider_error_message(msg) == msg


# ---------------------------------------------------------------------------
# None / non-string handling
# ---------------------------------------------------------------------------


class TestNoneHandling:
    def test_none_returns_empty(self) -> None:
        assert sanitize_provider_error_message(None) == ""

    def test_non_string_coerced(self) -> None:
        # Defensive — should not crash, should coerce.
        out = sanitize_provider_error_message(42)  # type: ignore[arg-type]
        assert out == "42"

    def test_empty_string_unchanged(self) -> None:
        assert sanitize_provider_error_message("") == ""


# ---------------------------------------------------------------------------
# Integration: _extract_error_message in each adapter
# ---------------------------------------------------------------------------


class TestExtractIntegration:
    def test_anthropic_extract_sanitizes(self) -> None:
        from loa_cheval.providers.anthropic_adapter import _extract_error_message

        resp = {"error": {"message": f"Invalid key {_SK_ANT}"}}
        out = _extract_error_message(resp)
        assert _SK_ANT not in out
        assert "[REDACTED-API-KEY-ANTHROPIC]" in out

    def test_openai_extract_sanitizes(self) -> None:
        from loa_cheval.providers.openai_adapter import _extract_error_message

        resp = {"error": {"message": f"Invalid key {_SK_OPENAI_LEGACY}"}}
        out = _extract_error_message(resp)
        assert _SK_OPENAI_LEGACY not in out
        assert "[REDACTED-API-KEY-OPENAI]" in out

    def test_google_extract_sanitizes(self) -> None:
        from loa_cheval.providers.google_adapter import _extract_error_message

        resp = {"error": {"message": f"Invalid key {_AIZA}"}}
        out = _extract_error_message(resp)
        assert _AIZA not in out
        assert "[REDACTED-API-KEY-GOOGLE]" in out
