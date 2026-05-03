#!/usr/bin/env python3
"""
jcs-helper.py — RFC 8785 JCS canonicalizer used by lib/jcs.sh.

The bash adapter (lib/jcs.sh) shells out to this helper because RFC 8785 §3.2.2
mandates ECMAScript ToNumber-style number canonicalization, and `jq` does not
implement it. Python's `rfc8785` package is the reference implementation cited
in cycle-098 SDD §2.2.

Usage:
    cat input.json | python3 jcs-helper.py
    python3 jcs-helper.py < input.json

Reads a JSON value on stdin, writes the canonical-JSON serialization (UTF-8
bytes, no trailing newline) on stdout. Exits non-zero on parse error or when
the `rfc8785` package is unavailable.

cycle-098 Sprint 1 — IMP-001 (HIGH_CONSENSUS 736).
"""
from __future__ import annotations

import json
import sys


def main() -> int:
    raw = sys.stdin.read()
    if not raw:
        print("jcs-helper: empty stdin", file=sys.stderr)
        return 2

    try:
        value = json.loads(raw)
    except json.JSONDecodeError as exc:
        print(f"jcs-helper: invalid JSON on stdin: {exc}", file=sys.stderr)
        return 2

    try:
        import rfc8785
    except ImportError:
        print(
            "jcs-helper: 'rfc8785' package not installed. "
            "Install with: pip install rfc8785",
            file=sys.stderr,
        )
        return 3

    try:
        canonical = rfc8785.dumps(value)
    except Exception as exc:  # pragma: no cover — defensive
        print(f"jcs-helper: canonicalization failed: {exc}", file=sys.stderr)
        return 4

    # Write raw bytes; never append a newline (canonical bytes must be exact).
    sys.stdout.buffer.write(canonical)
    return 0


if __name__ == "__main__":
    sys.exit(main())
