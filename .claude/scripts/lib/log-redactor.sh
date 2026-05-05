#!/usr/bin/env bash
# =============================================================================
# log-redactor.sh — bash twin per cycle-099 SDD §5.6.
#
# Masks URL userinfo (`://[REDACTED]@`) and 6 query-string secret patterns
# (key, token, secret, password, api_key, auth) case-insensitively while
# preserving the original separator (`?`/`&`) and parameter-name case.
#
# Cross-runtime parity with `.claude/scripts/lib/log-redactor.py` asserted by
# `tests/integration/log-redactor.bats`.
#
# POSIX BRE only — no GNU sed extensions, no `I` flag. Case-insensitivity is
# expressed via explicit `[Aa]`-style character classes per name letter.
#
# Usage:
#   As library:  source log-redactor.sh; printf '%s' "$text" | _redact
#   As filter:   cat input | bash log-redactor.sh
# =============================================================================

# Apply redactor to stdin → stdout. Newlines are natural boundaries because
# sed processes line-by-line and the negated character class `[^&]` / `[^/@]`
# never sees `\n` inside its pattern space. Result: byte-equal to the Python
# canonical for any UTF-8 / ASCII input.
_redact() {
    sed \
        -e 's|://[^/@]*@|://[REDACTED]@|g' \
        -e 's|\([?&][Kk][Ee][Yy]\)=[^&]*|\1=[REDACTED]|g' \
        -e 's|\([?&][Tt][Oo][Kk][Ee][Nn]\)=[^&]*|\1=[REDACTED]|g' \
        -e 's|\([?&][Ss][Ee][Cc][Rr][Ee][Tt]\)=[^&]*|\1=[REDACTED]|g' \
        -e 's|\([?&][Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd]\)=[^&]*|\1=[REDACTED]|g' \
        -e 's|\([?&][Aa][Pp][Ii]_[Kk][Ee][Yy]\)=[^&]*|\1=[REDACTED]|g' \
        -e 's|\([?&][Aa][Uu][Tt][Hh]\)=[^&]*|\1=[REDACTED]|g'
}

# Allow direct invocation as a script (filter mode).
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    _redact
fi
