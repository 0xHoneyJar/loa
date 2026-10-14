#!/usr/bin/env bash
# =============================================================================
# .claude/hooks/hook-guard.sh — parse-guard wrapper for PreToolUse safety hooks
# =============================================================================
# Wraps a safety hook so a SYNTACTICALLY BROKEN hook cannot brick the harness.
# Usage (as a settings.json PreToolUse command):
#   .claude/hooks/hook-guard.sh .claude/hooks/safety/<hook>.sh [args...]
#
# Behaviour:
#   - bash -n "<hook>" passes  → exec the hook with the same interpreter and
#     args; stdin/stdout/stderr/exit-code pass through byte-for-byte (exec
#     replaces this process, and bash -n reads the TARGET FILE — never this
#     guard's stdin — so the inherited stdin fd reaches the real hook intact).
#   - bash -n "<hook>" fails   → print a loud WARN naming the hook to stderr
#     and exit 0 (ALLOW the tool call).
#
# DESIGN NOTES (read before editing — this file is now a single point of
# failure for every wrapped hook):
#   (a) It fails OPEN on parse failure BY DESIGN. A hook that cannot parse
#       provides no protection; blocking on it would convert a broken fence
#       into a total outage — every Bash/Edit call bricked identically. That
#       outage is exactly the defect this guard exists to prevent (#1180).
#   (b) It catches PARSE failures only (bash -n) — e.g. unresolved git
#       conflict markers, unbalanced quotes. A hook that parses cleanly but is
#       semantically broken (sources a missing lib, etc.) is OUT OF SCOPE and
#       still runs exactly as before. Not "fixed" — explicitly not covered.
#   (c) This guard is itself a new (tiny) single point of failure. It is kept
#       dependency-free (no jq/yq), with one conditional and no string
#       processing, so it is categorically less conflict-prone than the hooks
#       it wraps — non-zero residual risk, not zero.
#   (d) Strict-mode asymmetry vs zone-write-guard.sh's LOA_REQUIRE_ZONES
#       fail-CLOSED branch: that hook deliberately BLOCKs when zones.yaml is
#       missing under strict mode. This guard's fail-OPEN-on-parse-failure is a
#       DIFFERENT failure class (the hook file itself won't parse) and does not
#       change that branch — once the hook parses, exec hands control to it and
#       its own strict-mode logic runs untouched. A syntax error still fails
#       open even for strict-mode users; that is a disclosed tradeoff.
# =============================================================================

# No `set -euo pipefail`: like the hooks it wraps, this guard must never fail
# CLOSED. An error here must degrade to ALLOW, never to a spurious block.

target="$1"
shift

if ! "${BASH:-bash}" -n "$target"; then
    echo "[hook-guard] WARN: PreToolUse hook $target failed to parse (bash -n) — failing OPEN (allowing tool); repair the hook, retrying will not help" >&2
    exit 0
fi

exec "${BASH:-bash}" "$target" "$@"
