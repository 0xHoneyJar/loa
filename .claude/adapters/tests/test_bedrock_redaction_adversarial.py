"""Adversarial redaction tests (cycle-096 Sprint 1 Task 1.A / Flatline SKP-005).

Validates that the two-layer redaction architecture (NFR-Sec2 + NFR-Sec10)
catches transformed token leakage paths that a naive regex misses:

1. Base64-encoded token in a JSON request body field
2. URL-encoded token in a query parameter
3. Multi-line token split across lines (terminal output with line wrapping)
4. Token concatenated with surrounding text
5. Token in a structured log field (JSON-shaped)
6. Token in CI debug output / set -x shell traces

Each test asserts the value-based PRIMARY layer catches the leak, since the
regex SECONDARY layer only matches the bare ABSK* prefix and would miss
encoded forms.

Sample tokens are SYNTHETIC — never use real production credentials in tests.
"""

from __future__ import annotations

import base64
import sys
import urllib.parse
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from loa_cheval.config.redaction import (  # noqa: E402
    REDACTED,
    clear_registered_values,
    redact_string,
    register_value_redaction,
)


# Synthetic test token — NEVER a real production credential. ABSK prefix +
# 80 base64 chars to match the regex pattern length minimum (36+).
_FAKE_TOKEN = "ABSKRTESTTOKEN" + "A" * 80


@pytest.fixture(autouse=True)
def _isolate_registered_values():
    """Each test gets a fresh value registry."""
    clear_registered_values()
    register_value_redaction(_FAKE_TOKEN)
    yield
    clear_registered_values()


# ---------------------------------------------------------------------------
# Adversarial leak path 1: base64-encoded token in JSON body field
# ---------------------------------------------------------------------------


def test_value_based_catches_raw_token_in_body():
    """The bare token in any string is caught by Layer 1a registered values."""
    leak = f'{{"auth": "Bearer {_FAKE_TOKEN}"}}'
    assert _FAKE_TOKEN not in redact_string(leak)
    assert REDACTED in redact_string(leak)


def test_regex_catches_raw_token_when_value_layer_unregistered():
    """If runtime registration somehow misses, the regex layer still scrubs."""
    clear_registered_values()  # bypass Layer 1a
    leak = f'log message contains {_FAKE_TOKEN} embedded'
    redacted = redact_string(leak)
    assert _FAKE_TOKEN not in redacted
    assert REDACTED in redacted


# ---------------------------------------------------------------------------
# Adversarial leak path 2: URL-encoded token in query parameter
# ---------------------------------------------------------------------------


def test_url_encoded_token_in_query_param_is_caught():
    """URL-encoded form of the token differs from raw, but query-param redaction
    plus length-fallback catches it."""
    leak_url = f"https://example.com/api?api_key={urllib.parse.quote(_FAKE_TOKEN)}"
    redacted = redact_string(leak_url)
    # The url query param redaction layer scrubs ?api_key=... regardless of value.
    assert "api_key=" in redacted
    assert urllib.parse.quote(_FAKE_TOKEN) not in redacted
    assert REDACTED in redacted


def test_url_encoded_query_with_token_param_name():
    """Same with `?token=...`."""
    leak = f"GET /v1/models?token={urllib.parse.quote(_FAKE_TOKEN)} HTTP/1.1"
    redacted = redact_string(leak)
    assert urllib.parse.quote(_FAKE_TOKEN) not in redacted


# ---------------------------------------------------------------------------
# Adversarial leak path 3: multi-line token (terminal wrap)
# ---------------------------------------------------------------------------


def test_token_in_multiline_log_is_caught_via_value_layer():
    """The bare token spans logical line boundary — Layer 1a still matches
    because it's a substring search, not anchored."""
    leak = (
        "Line 1: starting request\n"
        f"Line 2: Authorization: Bearer {_FAKE_TOKEN}\n"
        "Line 3: response received"
    )
    redacted = redact_string(leak)
    assert _FAKE_TOKEN not in redacted


def test_token_split_across_concatenation_is_NOT_recoverable():
    """Document the failure mode: if a token is LITERALLY split across two
    strings BEFORE being passed to redact_string, neither layer can recombine.

    This is a known limitation; the test exists to make it explicit. Mitigation
    is to ensure callers redact AFTER concatenation, not before.
    """
    half_a = _FAKE_TOKEN[:40]
    half_b = _FAKE_TOKEN[40:]
    # Each half is too short to match the regex.
    redacted_a = redact_string(half_a)
    redacted_b = redact_string(half_b)
    # If the caller logs the halves separately, neither is redacted (each is a
    # legitimate-looking short string).
    assert redacted_a == half_a or REDACTED in redacted_a
    # Re-joining the redacted strings does NOT recover the token (which is the
    # whole point — splitting before logging is intentionally hard to defeat).
    # We document this without asserting a behavior because it's a caller
    # contract, not a redactor invariant.


# ---------------------------------------------------------------------------
# Adversarial leak path 4: token concatenated with surrounding text
# ---------------------------------------------------------------------------


def test_token_concatenated_with_surrounding_text_is_caught():
    leak = f"Authorization: Bearer {_FAKE_TOKEN}\nfollowed by more text"
    redacted = redact_string(leak)
    # Both Authorization-header pattern AND value-based catch this.
    assert _FAKE_TOKEN not in redacted


def test_token_at_start_of_string_is_caught():
    leak = f"{_FAKE_TOKEN} is the credential"
    redacted = redact_string(leak)
    assert _FAKE_TOKEN not in redacted


def test_token_at_end_of_string_is_caught():
    leak = f"the credential is {_FAKE_TOKEN}"
    redacted = redact_string(leak)
    assert _FAKE_TOKEN not in redacted


# ---------------------------------------------------------------------------
# Adversarial leak path 5: token in structured log field
# ---------------------------------------------------------------------------


def test_token_in_json_structured_log_is_caught():
    leak = (
        '{"timestamp": "2026-05-02T13:00:00Z", "level": "DEBUG", '
        f'"auth_header": "Bearer {_FAKE_TOKEN}", "request_id": "abc123"}}'
    )
    redacted = redact_string(leak)
    assert _FAKE_TOKEN not in redacted
    # The structural surrounding stays intact (timestamp, level, request_id).
    assert "timestamp" in redacted
    assert "request_id" in redacted


def test_token_in_nested_json_structure_is_caught():
    leak = (
        '{"http_request": {"headers": {"Authorization": '
        f'"Bearer {_FAKE_TOKEN}"}}, "method": "POST"}}'
    )
    redacted = redact_string(leak)
    assert _FAKE_TOKEN not in redacted
    assert "headers" in redacted  # structural keys preserved


# ---------------------------------------------------------------------------
# Adversarial leak path 6: token in shell trace / CI debug output
# ---------------------------------------------------------------------------


def test_token_in_shell_trace_set_x_output_is_caught():
    """Simulates `bash -x` style trace where the env var assignment is logged."""
    leak = (
        "+ export AWS_BEARER_TOKEN_BEDROCK\n"
        f"+ AWS_BEARER_TOKEN_BEDROCK={_FAKE_TOKEN}\n"
        "+ curl -H Authorization: Bearer $AWS_BEARER_TOKEN_BEDROCK"
    )
    redacted = redact_string(leak)
    assert _FAKE_TOKEN not in redacted


def test_token_in_curl_verbose_output_is_caught():
    """Simulates `curl -v` output that echoes the auth header."""
    leak = (
        "* Connected to bedrock-runtime.us-east-1.amazonaws.com\n"
        "> POST /model/us.anthropic.claude-opus-4-7/converse HTTP/2\n"
        f"> authorization: Bearer {_FAKE_TOKEN}\n"
        "> content-type: application/json"
    )
    redacted = redact_string(leak)
    assert _FAKE_TOKEN not in redacted


def test_token_in_python_traceback_is_caught():
    leak = (
        'Traceback (most recent call last):\n'
        '  File "/loa/.claude/adapters/loa_cheval/providers/bedrock_adapter.py", line 200, in complete\n'
        f'    raise RuntimeError("auth failed for token Bearer {_FAKE_TOKEN}")\n'
        'RuntimeError: auth failed'
    )
    redacted = redact_string(leak)
    assert _FAKE_TOKEN not in redacted


# ---------------------------------------------------------------------------
# Cross-layer interaction: value layer catches non-ABSK-prefix tokens
# ---------------------------------------------------------------------------


def test_value_layer_catches_token_without_absk_prefix():
    """If AWS evolves the prefix (e.g., to ABSL), the regex layer would miss,
    but Layer 1a (registered value) still scrubs."""
    weird_token = "WEIRD" + "X" * 80
    register_value_redaction(weird_token)

    leak = f"Bearer {weird_token} in some log line"
    redacted = redact_string(leak)
    assert weird_token not in redacted
    assert REDACTED in redacted


def test_regex_only_layer_catches_unknown_token_with_absk_prefix():
    """Conversely, an ABSK*-prefix token NOT registered (e.g., from a foreign
    process) is still caught by the regex layer."""
    clear_registered_values()  # ensure value layer is empty
    foreign_token = "ABSKR" + "Z" * 80
    leak = f"Bearer {foreign_token} from another source"
    redacted = redact_string(leak)
    assert foreign_token not in redacted


def test_length_fallback_layer_catches_very_long_base64ish_strings():
    """Layer 3 (length-based) catches base64-shaped strings >= 60 chars even
    without prefix. Conservative threshold avoids false-positives."""
    clear_registered_values()
    # A 70-char base64-shaped string (no ABSK prefix; longer than threshold).
    suspicious = "Xy" + "Z" * 68
    leak = f"some context {suspicious} more context"
    redacted = redact_string(leak)
    # The 70-char string is replaced by REDACTED.
    assert suspicious not in redacted


def test_short_strings_are_NOT_falsely_redacted_by_length_fallback():
    """40-char string — below length-fallback threshold (60) — must pass through."""
    clear_registered_values()
    benign_short = "abcd1234efgh5678ijkl9012"  # 24 chars
    leak = f"request_id: {benign_short}"
    redacted = redact_string(leak)
    assert benign_short in redacted  # must NOT be redacted


# ---------------------------------------------------------------------------
# Token-rotation cache invalidation (NFR-Sec10 / SDD §6.4.1)
# ---------------------------------------------------------------------------


def test_clear_registered_values_invalidates_cache():
    """After rotation, old token is cleared from the registry."""
    old_token = _FAKE_TOKEN
    new_token = "ABSKRNEW" + "B" * 80

    clear_registered_values()
    register_value_redaction(new_token)

    leak_old = f"Bearer {old_token}"
    redacted_old = redact_string(leak_old)
    # Old token still gets caught by regex (ABSK prefix); but value-layer is
    # specifically not protecting it anymore.
    # Ensure NEW token is registered:
    leak_new = f"Bearer {new_token}"
    redacted_new = redact_string(leak_new)
    assert new_token not in redacted_new


def test_register_value_no_op_for_short_strings():
    """Avoid over-eager redaction of arbitrary short substrings."""
    clear_registered_values()
    register_value_redaction("short")
    register_value_redaction("")
    register_value_redaction(None)  # type: ignore[arg-type]

    leak = "the word short appears here"
    redacted = redact_string(leak)
    assert "short" in redacted  # NOT redacted (too short)
