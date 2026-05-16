"""cycle-103 sprint-3 T3.3 — sanitize provider error messages.

Every place an adapter constructs an exception from upstream bytes (HTTP
error body, mid-stream error frame, JSON-decoded provider error payload)
must route the message string through `sanitize_provider_error_message`
first. Without this gate, secret-shape strings (AKIA / PEM / Bearer /
provider API keys) leak from upstream payloads into:

  - exception args (caught by retry.py, logged to stderr)
  - audit envelopes (MODELINV log_path)
  - operator-visible error messages on terminal failure

Layering on top of `.claude/scripts/lib/log-redactor.py::redact` (which
handles AKIA / PEM / Bearer / URL-userinfo / query-string). T3.3 adds:

  - `sk-ant-*` Anthropic API keys
  - `sk-*` and `sk-proj-*` OpenAI API keys
  - `AIza*` 39-char Google API keys
  - JSON-escaped variants of all the above (where the upstream byte
    arrived nested in a JSON string and the outer JSON encoder produced
    `\\"sk-ant-XXX\\"` style escapes)

Defensive normalization (cycle-099 sprint-1E.c.3.c + T3.7 precedent):
NFKC + zero-width-strip BEFORE pattern match. This prevents fullwidth
(`Ｓ Ｋ ｛ ＝...`) and zero-width insertion bypasses.

Idempotent: re-applying to an already-redacted string is a no-op (the
sentinel forms `[REDACTED-*]` don't match any pattern).
"""

from __future__ import annotations

import importlib.util
import re
import unicodedata
from pathlib import Path
from typing import Callable, Optional


# ---------------------------------------------------------------------------
# Bridge to log-redactor.py for AKIA / PEM / Bearer / URL-userinfo / query.
# ---------------------------------------------------------------------------


def _load_log_redactor() -> Callable[[str], str]:
    """Load `.claude/scripts/lib/log-redactor.py::redact` via importlib
    (hyphenated filename precludes plain import). Same loader pattern as
    `modelinv.py::_load_redactor`.
    """
    redactor_path = (
        Path(__file__).resolve().parent.parent.parent.parent
        / "scripts" / "lib" / "log-redactor.py"
    )
    if not redactor_path.is_file():
        raise RuntimeError(
            f"log-redactor.py not found at {redactor_path}. T3.3 sanitize "
            "depends on the cycle-099 sprint-1E.a + cycle-102 sprint-1D "
            "log redactor library."
        )
    spec = importlib.util.spec_from_file_location(
        "loa_log_redactor", redactor_path
    )
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Failed to load redactor module from {redactor_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.redact


_log_redact: Callable[[str], str] = _load_log_redactor()


# ---------------------------------------------------------------------------
# Additional provider-API-key patterns (T3.3-specific).
# ---------------------------------------------------------------------------

# Anthropic API keys: `sk-ant-<...>` with at least 24 chars in the body
# (real keys are much longer, but we set the lower bound generously to
# catch shapes without false-positive on `sk-ant-` mentions in docs).
_SK_ANT_RE = re.compile(r"sk-ant-[A-Za-z0-9_\-]{24,}")

# OpenAI API keys: `sk-<...>` and `sk-proj-<...>`. The non-`ant` lookahead
# avoids double-redacting the Anthropic pattern. Real OpenAI keys are
# 48+ chars; cap at 24 minimum.
_SK_OPENAI_RE = re.compile(r"sk-(?!ant-)[A-Za-z0-9_\-]{24,}")

# Google API keys: `AIza` followed by exactly 35 characters (total 39).
# This is the documented Google API key length. Use `(?![A-Za-z0-9_\-])`
# negative lookahead so a 40+ char glob is split — preserves the
# documented shape exactly.
_AIZA_RE = re.compile(r"AIza[A-Za-z0-9_\-]{35}(?![A-Za-z0-9_\-])")


# Zero-width / bidi-override character class — mirrors modelinv.py::_ZERO_WIDTH
# and the cycle-099 sprint-1E.c.3.c Unicode-glob bypass closure.
_ZERO_WIDTH = re.compile(
    "[​-‍﻿‪-‮]"
)


def _normalize_for_sanitize(text: str) -> str:
    """NFKC normalize + strip zero-width chars before pattern match.

    Mirrors the defense-in-depth pattern from `modelinv.py::_normalize_for_gate`
    and tools/check-no-raw-curl.sh (cycle-099). Without this, an attacker
    can use FULLWIDTH `ｓｋ-ａｎｔ-...` or zero-width insertions to bypass
    the literal `sk-ant-` prefix match.
    """
    text = unicodedata.normalize("NFKC", text)
    text = _ZERO_WIDTH.sub("", text)
    return text


def sanitize_provider_error_message(message: Optional[str]) -> str:
    """Sanitize an upstream-bytes-derived error message for safe inclusion
    in an exception arg, audit envelope, or operator-visible log line.

    Args:
        message: the upstream-derived string. `None` or non-string is
            coerced to empty string — defensive against callers that
            pass `e.response.get("error")` results where the field may
            be missing or null.

    Returns:
        Sanitized string with secret-shape substrings replaced by
        `[REDACTED-*]` sentinels. Layered passes:

          1. NFKC normalize + zero-width strip (defense in depth).
          2. log-redactor `redact()` for AKIA / PEM / Bearer / userinfo / query.
          3. Provider API keys: `sk-ant-*`, `sk-*`, `sk-proj-*`, `AIza*`.

    Idempotent. Returns empty string for None / non-string input.
    """
    if message is None:
        return ""
    if not isinstance(message, str):
        message = str(message)

    text = _normalize_for_sanitize(message)
    text = _log_redact(text)

    text = _SK_ANT_RE.sub("[REDACTED-API-KEY-ANTHROPIC]", text)
    text = _SK_OPENAI_RE.sub("[REDACTED-API-KEY-OPENAI]", text)
    text = _AIZA_RE.sub("[REDACTED-API-KEY-GOOGLE]", text)

    return text
