#!/usr/bin/env python3
"""Log redactor — canonical Python implementation per cycle-099 SDD §5.6.

Masks URL userinfo (`://[REDACTED]@`) and 6 query-string secret patterns
(`key`, `token`, `secret`, `password`, `api_key`, `auth`) case-insensitively
while preserving structural identity (separator + parameter-name case).

Stdlib-only. Cross-runtime parity with `.claude/scripts/lib/log-redactor.sh`
asserted by `tests/integration/log-redactor-cross-runtime.bats`.

Caller contract — IN-SCOPE redactions
=====================================
The redactor handles URL-shaped secrets ONLY. The patterns require a leading
`?` or `&` (query-string separator) before the secret-bearing parameter name
or `://` before the userinfo segment. Any caller emitting `key=value` log
lines WITHOUT URL framing is responsible for either:

  1. Reformatting their log emission to use URL-style framing, e.g.
     `[MODEL-RESOLVE] endpoint=https://host/?api_key=<value>` rather than
     `[MODEL-RESOLVE] api_key=<value>`. The redactor catches the former.

  2. Redacting the secret VALUE in isolation BEFORE log emission, then
     emitting the bare key=value pair safely.

This is in-contract per SDD §5.6.2 — the redactor's stop-character set
intentionally tracks URL grammar (`&`, `\\n`, end-of-string). Extending it
to bare `\\s` would over-match in non-log contexts (file paths, JSON, etc.)
and break the structural-identity guarantee that operators rely on for
log-grep workflows.

Usage:
  As library:  from log_redactor import redact; redact(text)
  As filter:   cat input | python3 log-redactor.py
"""

from __future__ import annotations

import re
import sys

# Order in the alternation does not affect correctness because no name in this
# set is a prefix of another that the engine would silently match; however we
# keep a single combined pattern for performance (one pass through the string).
_QUERY_PARAMS = ("key", "token", "secret", "password", "api_key", "auth")

_USERINFO_RE = re.compile(r"://[^/@\n]*@")

_QUERY_RE = re.compile(
    r"([?&])(" + "|".join(_QUERY_PARAMS) + r")=[^&\n]*",
    re.IGNORECASE,
)


def _query_repl(match: re.Match) -> str:
    # Preserve original separator (group 1) and original-case parameter name
    # (group 2). The replacement value is the literal sentinel.
    return f"{match.group(1)}{match.group(2)}=[REDACTED]"


def redact(text: str) -> str:
    """Return `text` with URL userinfo and known-secret query params masked.

    Pure function, no I/O. Idempotent: redact(redact(x)) == redact(x).
    Newlines act as natural boundaries — a redaction never spans a `\\n`,
    matching the line-by-line semantics of the bash twin's `sed` pipeline.
    """
    text = _USERINFO_RE.sub("://[REDACTED]@", text)
    text = _QUERY_RE.sub(_query_repl, text)
    return text


def _main() -> int:
    sys.stdout.write(redact(sys.stdin.read()))
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
