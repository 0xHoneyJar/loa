#!/usr/bin/env python3
"""Log redactor — canonical Python implementation per cycle-099 SDD §5.6
(URL-shaped scope) + cycle-102 Sprint 1D §5.6 extension (bare secret shapes).

Masks URL userinfo (`://[REDACTED]@`) and 6 query-string secret patterns
(`key`, `token`, `secret`, `password`, `api_key`, `auth`) case-insensitively
while preserving structural identity (separator + parameter-name case).

Sprint 1D additions — three bare secret shapes that do NOT require URL framing:

  - **AKIA-shaped AWS access key**: `AKIA[0-9A-Z]{16}` → `[REDACTED-AKIA]`
  - **PEM private-key block**: `-----BEGIN [A-Z 0-9]*PRIVATE KEY-----...
    -----END [A-Z 0-9]*PRIVATE KEY-----` (multiline-aware via the negated
    `[^-]` body class — base64 PEM body never contains `-`) → `[REDACTED-PRIVATE-KEY]`
  - **Bearer token shape**: `[Bb]earer<sep><base64url-charset>+` (HTTP
    Authorization header form) → `[REDACTED-BEARER-TOKEN]`

Stdlib-only. Cross-runtime parity with `.claude/scripts/lib/log-redactor.sh`
asserted by `tests/integration/log-redactor-cross-runtime.bats`.

Caller contract — IN-SCOPE redactions
=====================================
The redactor handles two classes of secret:

  Class A (URL-shaped, cycle-099 sprint-1E.a):
    URL userinfo + 6 query-string secret-bearing parameters. Patterns require
    URL grammar framing (`://` for userinfo, `?` or `&` for query separators).

  Class B (bare secret shapes, cycle-102 sprint-1D / T1.7):
    Three shapes commonly leaked in audit chains by upstream API responses:
    AKIA-prefixed AWS access keys, PEM private-key blocks (PKCS#1 / PKCS#8 /
    EC), and HTTP Bearer-token headers. These shapes are recognizable
    independently of URL framing and warrant unconditional masking when they
    appear in any string headed for a hash-chained immutable log.

Patterns NOT in scope (caller responsibility):

  - Bare `password=value` log lines without URL framing → caller MUST
    reformat using URL-style framing OR redact the bare value before
    emission. (Same rule as cycle-099.)
  - Generic high-entropy strings without recognizable shape → the redactor
    is shape-driven, not entropy-driven, to avoid the structural-identity
    breakage that entropy thresholds produce in non-secret content (UUIDs,
    git SHAs, content addresses).

The cheval-side `_assert_no_secret_shapes_remain` gate (cycle-102 T1.7.e)
provides defense-in-depth: it runs AFTER this redactor and rejects any
audit_emit whose payload still contains AKIA / PEM / Bearer shapes the
redactor missed. The gate is the fail-closed safety net for shapes the
redactor doesn't yet recognize.

Usage:
  As library:  from log_redactor import redact; redact(text)
  As filter:   cat input | python3 log-redactor.py
"""

from __future__ import annotations

import re
import sys

# -----------------------------------------------------------------------------
# Class A — URL-shaped secrets (cycle-099 sprint-1E.a, unchanged)
# -----------------------------------------------------------------------------

# Order in the alternation does not affect correctness because no name in this
# set is a prefix of another that the engine would silently match; however we
# keep a single combined pattern for performance (one pass through the string).
_QUERY_PARAMS = ("key", "token", "secret", "password", "api_key", "auth")

_USERINFO_RE = re.compile(r"://[^/@\n]*@")

_QUERY_RE = re.compile(
    r"([?&])(" + "|".join(_QUERY_PARAMS) + r")=[^&\n]*",
    re.IGNORECASE,
)

# -----------------------------------------------------------------------------
# Class B — Bare secret shapes (cycle-102 sprint-1D / T1.7.a)
# -----------------------------------------------------------------------------

# AKIA-prefixed AWS access key. Real AWS keys are exactly 20 chars (4 prefix
# + 16 base32 [0-9A-Z]). No word-boundary anchors — POSIX BRE has no `\b`,
# so dropping it here keeps Python ↔ bash byte-equal. False-positive risk on
# arbitrary 24+ char strings ending in AKIA-pattern is negligible at the
# audit-chain layer, and the [REDACTED-AKIA] sentinel preserves debuggability.
_AKIA_RE = re.compile(r"AKIA[0-9A-Z]{16}")

# PEM private-key block. The `[A-Z 0-9]*` allows optional algorithm name
# (RSA, EC, DSA, ED25519) plus padding spaces; the `[^-]*` body class works
# because base64 content never contains `-` (alphabet is `[A-Za-z0-9+/=]` plus
# `\n` whitespace). Cross-runtime parity: bash sed slurps the input with
# `:a;N;$!ba;` so newlines are in pattern space, and `[^-]` in sed (under
# slurp) matches `\n` the same way Python's negated class does.
_PEM_RE = re.compile(
    r"-----BEGIN [A-Z 0-9]*PRIVATE KEY-----[^-]*-----END [A-Z 0-9]*PRIVATE KEY-----"
)

# HTTP Bearer-token shape. Case-insensitive on `Bearer` per RFC 7235 (HTTP
# auth scheme is case-insensitive). Token charset is the OAuth 2.0 / JWT
# union: base64url (`[A-Za-z0-9._-]`) plus standard base64 (`/+=`) plus the
# `~` from RFC 6750. Bash twin uses literal `[ <tab>]` for the separator
# rather than `\s` to keep POSIX BRE parity (POSIX `[[:space:]]` would also
# match `\n` `\f` `\v` which we don't want — Bearer tokens in headers are
# space-or-tab separated in practice).
#
# Minimum token length 16 chars: real OAuth bearer tokens and JWTs are
# always longer (JWTs are ~200+ chars; opaque OAuth tokens are typically
# 20-100+). A 16-char floor excludes natural-language false positives like
# "The Bearer of this letter" (where "of" satisfies the charset but is not
# a token). Per BB iter-1 F-006 (sprint-1D 2026-05-10).
_BEARER_RE = re.compile(r"[Bb]earer[ \t][A-Za-z0-9._~+/=-]{16,}")


def _query_repl(match: re.Match) -> str:
    # Preserve original separator (group 1) and original-case parameter name
    # (group 2). The replacement value is the literal sentinel.
    return f"{match.group(1)}{match.group(2)}=[REDACTED]"


def redact(text: str) -> str:
    """Return `text` with URL userinfo, query-string secrets, and bare secret
    shapes masked.

    Pure function, no I/O. Idempotent: redact(redact(x)) == redact(x).
    Newlines act as natural boundaries for URL/query/AKIA/Bearer passes;
    the PEM pass uses an explicit multi-line negated-`-` body class.

    Pass order (must match bash twin):
      1. URL userinfo
      2. Query-string secrets (6 params)
      3. AKIA AWS access keys
      4. Bearer tokens
      5. PEM private-key blocks
    """
    text = _USERINFO_RE.sub("://[REDACTED]@", text)
    text = _QUERY_RE.sub(_query_repl, text)
    text = _AKIA_RE.sub("[REDACTED-AKIA]", text)
    text = _BEARER_RE.sub("[REDACTED-BEARER-TOKEN]", text)
    text = _PEM_RE.sub("[REDACTED-PRIVATE-KEY]", text)
    return text


def _main() -> int:
    sys.stdout.write(redact(sys.stdin.read()))
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
