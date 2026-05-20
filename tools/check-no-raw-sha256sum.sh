#!/usr/bin/env bash
# =============================================================================
# tools/check-no-raw-sha256sum.sh
#
# sprint-bug-172 / bug-911 — strict scan: NO raw `sha256sum` invocations in
# bash scripts outside the canonical exemption set. All hashing in Loa bash
# code MUST funnel through `sha256_portable` (the helper in
# `.claude/scripts/compat-lib.sh`) so macOS / BSD hosts where sha256sum is
# genuinely absent fall back cleanly to `shasum -a 256`.
#
# Pre-existing context (KF-006 structural pattern, cycle-099 sprint-1E.c.3.c
# precedent): every PR adding a `sha256sum` invocation without bumping a
# schema/helper has caused multi-cycle ambient CI reds. This scanner catches
# the regression at PR time.
#
# Detection logic (in order):
#   1. File-type filter: scan `.sh` / `.bash` extensions PLUS extension-less
#      files with a bash/sh shebang. Skip binaries, docs, JSON, etc.
#   2. Skip line-leading comments (`# ...`).
#   3. Skip `command -v sha256sum` / `which sha256sum` (existence checks).
#   4. Skip lines with `# check-no-raw-sha256sum: ok` suppression marker.
#   5. Skip exempt files (compat-lib.sh defines sha256_portable;
#      audit-envelope.sh references sha256sum in comments documenting the
#      legacy / defense-in-depth python3 fallback).
#   6. Match `(^|[^[:alnum:]_])sha256sum([[:space:]]|$|"|\047|\|)` —
#      word-boundary on both sides so `sha256_portable` and other identifiers
#      containing the substring don't match.
#
# **Tripwire scope (NOT exhaustive defense)**: same caveats as
# tools/check-no-raw-curl.sh. Variable-expanded calls, eval, or printf-
# assembled invocations are out of scope. The helper itself + portability
# tests + integration test are the load-bearing portability boundary; this
# scanner is one tripwire layer.
#
# Usage:
#   tools/check-no-raw-sha256sum.sh                  # scan .claude/scripts/
#   tools/check-no-raw-sha256sum.sh --root <dir>     # scan custom root
#   tools/check-no-raw-sha256sum.sh --quiet          # exit-code only
#
# Exit codes:
#   0  no violations
#   1  violations found (paths printed to stderr)
#   2  argument / I/O error
#
# Tested by tests/integration/check-no-raw-sha256sum.bats.
# =============================================================================

set -euo pipefail

# Files explicitly allowed to mention `sha256sum` directly. Path-match is
# exact (rooted at PROJECT_ROOT); env-overridable list would be a footgun.
EXEMPT_FILES=(
    # The helper itself uses raw `sha256sum` in its GNU dispatch branch.
    ".claude/scripts/compat-lib.sh"
    # audit-envelope.sh references sha256sum in comments documenting the
    # defense-in-depth python3 last-resort fallback. The executable line uses
    # sha256_portable via compat-lib delegation.
    ".claude/scripts/audit-envelope.sh"
    # The scanner itself (this file) references sha256sum in its regex.
    "tools/check-no-raw-sha256sum.sh"
)

QUIET=0
ROOT=".claude/scripts"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --quiet|-q) QUIET=1; shift ;;
        --root) ROOT="$2"; shift 2 ;;
        --help|-h)
            sed -n '/^# Usage:/,/^# Tested/p' "$0" | sed 's/^# \?//'
            exit 0
            ;;
        *)
            printf 'check-no-raw-sha256sum.sh: unknown arg %q\n' "$1" >&2
            exit 2
            ;;
    esac
done

[[ -d "$ROOT" ]] || {
    printf 'check-no-raw-sha256sum.sh: scan root %q not a directory\n' "$ROOT" >&2
    exit 2
}

_is_exempt() {
    local path="$1" ex
    for ex in "${EXEMPT_FILES[@]}"; do
        [[ "$path" == "$ex" ]] && return 0
    done
    return 1
}

# Bash/sh script detection — same approach as check-no-raw-curl.sh.
_is_script() {
    local path="$1"
    case "$path" in
        *.sh|*.bash|*.legacy|*.bats) return 0 ;;
    esac
    local first_line
    first_line=$(head -c 256 "$path" 2>/dev/null | head -1 || true)
    [[ "$first_line" == "#!"*"bash"* ]] && return 0
    [[ "$first_line" == "#!"*"sh" ]] && return 0
    [[ "$first_line" == "#!"*"sh "* ]] && return 0
    return 1
}

AWK_SCAN=$(cat <<'AWK'
# Step 1: skip line-leading comments.
/^[[:space:]]*#/ { next }

# Step 2: skip lines with the suppression marker. Requires `#` leader so
# string-literal mentions don't silence real invocations.
/#[^\n]*check-no-raw-sha256sum:[[:space:]]*ok/ { next }

# Step 3 (DISS-001 closure): there is NO existence-check skip. The
# post-sprint-bug-172 invariant is that NO production code references
# raw `sha256sum` — neither as an invocation nor as a `command -v`
# existence check. Existence checks should use `_COMPAT_SHA256_CMD`
# instead. If a future PR adds `command -v sha256sum`, the scanner
# correctly flags it. (Original draft of this scanner had a
# `command -v sha256sum` line-skip — the cross-model adversarial review
# flagged it as a smuggling vector: `command -v sha256sum && sha256sum
# "$file"` would have been accepted because the whole line was skipped
# before the invocation match ran. Removed entirely; matches the strict
# tripwire semantics this scanner is meant to provide.)

# Step 4: match raw sha256sum (word-boundary both sides).
# LHS: start-of-line or non-alphanumeric/non-underscore.
# RHS: whitespace, end-of-line, pipe, quote, etc. — so `sha256_portable` and
# `sha256sum_something` don't match.
/(^|[^[:alnum:]_])sha256sum([[:space:]]|$|"|\047|\|)/ {
    print FILENAME ":" NR ":" $0
}
AWK
)

violations=""
while IFS= read -r -d '' f; do
    rel="${f#./}"
    if _is_exempt "$rel"; then
        continue
    fi
    if ! _is_script "$f"; then
        continue
    fi
    file_hits=$(awk "$AWK_SCAN" "$f" 2>/dev/null || true)
    if [[ -n "$file_hits" ]]; then
        violations+="$file_hits"$'\n'
    fi
done < <(find "$ROOT" -type f -print0 | sort -z)

if [[ -n "$violations" ]]; then
    if [[ $QUIET -eq 0 ]]; then
        printf 'sprint-bug-172 / bug-911: raw sha256sum detected outside sha256_portable\n' >&2
        printf 'All bash SHA-256 hashing MUST funnel through .claude/scripts/compat-lib.sh::sha256_portable\n' >&2
        printf 'so macOS / BSD hosts where sha256sum is absent fall back cleanly to shasum -a 256.\n' >&2
        printf '\nExempt files:\n' >&2
        for ex in "${EXEMPT_FILES[@]}"; do
            printf '  - %s\n' "$ex" >&2
        done
        printf '\nSuppression marker (use sparingly with reviewer rationale):\n' >&2
        printf '  # check-no-raw-sha256sum: ok\n' >&2
        printf '\nViolations:\n' >&2
        printf '%s' "$violations" | sed '/^$/d' >&2
    fi
    exit 1
fi

[[ $QUIET -eq 0 ]] && printf 'OK — no raw sha256sum callers outside exempt set\n'
exit 0
