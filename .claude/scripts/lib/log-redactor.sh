#!/usr/bin/env bash
# =============================================================================
# log-redactor.sh — bash twin per cycle-099 SDD §5.6 (URL-shaped scope) +
# cycle-102 Sprint 1D §5.6 extension (bare secret shapes — T1.7.b).
#
# Class A — URL-shaped (cycle-099 sprint-1E.a, unchanged):
#   Masks URL userinfo (`://[REDACTED]@`) and 6 query-string secret patterns
#   (key, token, secret, password, api_key, auth) case-insensitively while
#   preserving the original separator (`?`/`&`) and parameter-name case.
#
# Class B — bare secret shapes (cycle-102 sprint-1D / T1.7.b):
#   - AKIA-prefixed AWS access key   →  [REDACTED-AKIA]
#   - PEM private-key block          →  [REDACTED-PRIVATE-KEY]   (multi-line)
#   - HTTP Bearer-token shape        →  [REDACTED-BEARER-TOKEN]
#
# Cross-runtime parity with `.claude/scripts/lib/log-redactor.py` asserted by
# `tests/integration/log-redactor-cross-runtime.bats`.
#
# POSIX BRE only — no GNU sed extensions, no `I` flag. Case-insensitivity is
# expressed via explicit `[Aa]`-style character classes per name letter.
#
# Pass-order (MUST match Python twin's redact()):
#   1. URL userinfo
#   2. Query-string secrets (6 params, line-by-line)
#   3. AKIA AWS access keys (line-by-line)
#   4. Bearer tokens (line-by-line)
#   5. PEM private-key blocks (slurp-then-replace, multi-line)
#
# Implementation note — two-pass pipeline:
#   Passes 1-4 use line-by-line sed (default), where `\n` is not in pattern
#   space and the existing `[^&]` / `[^/@]` negated classes act as natural
#   boundaries. Pass 5 (PEM) requires multi-line slurp via `:a;N;$!ba;` so
#   the negated `[^-]` body class spans newlines. Slurping at pass 1 would
#   subtly break passes 2-4 because their negated classes become greedy
#   across lines. A pipeline (`sed | sed`) is the simplest correct factoring.
#
# Usage:
#   As library:  source log-redactor.sh; printf '%s' "$text" | _redact
#   As filter:   cat input | bash log-redactor.sh
# =============================================================================

# Apply redactor to stdin → stdout.
#
# First sed pass: line-by-line for URL/query/AKIA/Bearer. Newlines are
# natural boundaries; negated character classes (`[^&]` / `[^/@]`) never see
# `\n` in pattern space.
#
# Second sed pass (after pipe): multi-line slurp for PEM. The `:a;N;$!ba;`
# loop accumulates the entire input into pattern space before the
# substitution runs, so the negated `[^-]` body class can span newlines.
_redact() {
    sed \
        -e 's|://[^/@]*@|://[REDACTED]@|g' \
        -e 's|\([?&][Kk][Ee][Yy]\)=[^&]*|\1=[REDACTED]|g' \
        -e 's|\([?&][Tt][Oo][Kk][Ee][Nn]\)=[^&]*|\1=[REDACTED]|g' \
        -e 's|\([?&][Ss][Ee][Cc][Rr][Ee][Tt]\)=[^&]*|\1=[REDACTED]|g' \
        -e 's|\([?&][Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd]\)=[^&]*|\1=[REDACTED]|g' \
        -e 's|\([?&][Aa][Pp][Ii]_[Kk][Ee][Yy]\)=[^&]*|\1=[REDACTED]|g' \
        -e 's|\([?&][Aa][Uu][Tt][Hh]\)=[^&]*|\1=[REDACTED]|g' \
        -e 's|AKIA[0-9A-Z]\{16\}|[REDACTED-AKIA]|g' \
        -e 's|[Bb]earer[ 	][A-Za-z0-9._~+/=-]\{1,\}|[REDACTED-BEARER-TOKEN]|g' \
    | sed \
        -e ':a' \
        -e 'N' \
        -e '$!ba' \
        -e 's|-----BEGIN [A-Z 0-9]*PRIVATE KEY-----[^-]*-----END [A-Z 0-9]*PRIVATE KEY-----|[REDACTED-PRIVATE-KEY]|g'
}

# Allow direct invocation as a script (filter mode).
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    _redact
fi
