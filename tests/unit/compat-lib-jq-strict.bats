#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# =============================================================================
# tests/unit/compat-lib-jq-strict.bats
#
# sprint-bug-208 / #1025 — jq_strict helper in compat-lib.sh.
#
# The output-swallowing shape `jq … 2>/dev/null || echo <default>` turns a jq
# parse/extract failure into a clean default with exit 0 — the literal
# mechanism behind KF-004 (zero-findings canonical verdicts masking real
# findings, recurrence ≥20) and KF-015 (silent-clean red-team gate pass,
# 4/4 sprints). See grimoires/loa/known-failures.md.
#
# jq_strict contract proven here:
#   JS-1:  valid input + filter → emits value, exit 0
#   JS-2:  unparseable input → exit non-zero, stderr diagnostic, NO default
#   JS-3:  filter runtime error on valid JSON → exit non-zero, loud
#          (the literal KF-004 shape: valid envelope, extraction fails,
#           must NOT alias to 0/clean)
#   JS-4:  legitimately-absent field handled by `// default` INSIDE the
#          filter still succeeds — absence within valid JSON ≠ parse failure
#   JS-5:  JQ_STRICT_CTX context tag surfaces in the stderr diagnostic
#   JS-6:  file-argument form (valid + corrupt file)
#   JS-7:  jq's own stderr is NOT suppressed (diagnostics stay visible)
#
# Design choice pinned here (documented in the helper): jq_strict is for
# VALUE EXTRACTION where failure must be loud. It does not add `-e`; callers
# that want boolean falsy-exit semantics use plain `jq -e` directly, so a
# legitimately-falsy value never triggers the loud-failure diagnostic.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    export PROJECT_ROOT

    COMPAT_LIB="$PROJECT_ROOT/.claude/scripts/compat-lib.sh"
    export COMPAT_LIB
    [[ -f "$COMPAT_LIB" ]] || skip "compat-lib.sh not present"
}

# Run jq_strict in a fresh bash with given stdin, so stdout/stderr/exit are
# exactly what production callers observe.
_jqs() {
    local input="$1"; shift
    printf '%s' "$input" | bash -c 'source "$COMPAT_LIB"; jq_strict "$@"' _ "$@"
}

@test "jq_strict: emits value and exits 0 on valid JSON (JS-1)" {
    run --separate-stderr _jqs '{"findings": [1,2,3]}' '.findings | length'
    [[ "$status" -eq 0 ]]
    [[ "$output" == "3" ]]
}

@test "jq_strict: unparseable input exits non-zero, stderr diagnostic, no default on stdout (JS-2)" {
    run --separate-stderr _jqs 'this is not json' '.findings | length'
    [[ "$status" -ne 0 ]]
    [[ -z "$output" ]]
    [[ "$stderr" == *"jq_strict"* ]]
}

@test "jq_strict: filter runtime error on valid JSON is loud, never aliases to a default (JS-3)" {
    # boolean has no length — valid JSON envelope, extraction fails.
    # Pre-#1025 call sites turned exactly this into finding_count=0 → "clean".
    run --separate-stderr _jqs '{"findings": true}' '.findings | length'
    [[ "$status" -ne 0 ]]
    [[ -z "$output" ]]
    [[ "$stderr" == *"jq_strict"* ]]
}

@test "jq_strict: legitimately-absent field via // default inside filter succeeds (JS-4)" {
    run --separate-stderr _jqs '{"other": 1}' -r '.findings // "absent"'
    [[ "$status" -eq 0 ]]
    [[ "$output" == "absent" ]]
}

@test "jq_strict: JQ_STRICT_CTX tag appears in the stderr diagnostic (JS-5)" {
    run --separate-stderr bash -c 'source "$COMPAT_LIB"; printf "nope" | JQ_STRICT_CTX="my-call-site" jq_strict ".x"'
    [[ "$status" -ne 0 ]]
    [[ "$stderr" == *"my-call-site"* ]]
}

@test "jq_strict: file-argument form emits value on valid file (JS-6a)" {
    local f="$BATS_TEST_TMPDIR/valid.json"
    printf '{"findings": []}' > "$f"
    run --separate-stderr bash -c 'source "$COMPAT_LIB"; jq_strict ".findings | length" "$1"' _ "$f"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "0" ]]
}

@test "jq_strict: file-argument form fails loud on corrupt file (JS-6b)" {
    local f="$BATS_TEST_TMPDIR/corrupt.json"
    printf 'garbage{' > "$f"
    run --separate-stderr bash -c 'source "$COMPAT_LIB"; jq_strict ".findings | length" "$1"' _ "$f"
    [[ "$status" -ne 0 ]]
    [[ -z "$output" ]]
    [[ "$stderr" == *"jq_strict"* ]]
}

@test "jq_strict: jq's own parse diagnostic stays visible on stderr (JS-7)" {
    run --separate-stderr _jqs 'not json' '.'
    [[ "$status" -ne 0 ]]
    # jq's native message (wording varies by version) must not be suppressed —
    # assert there is stderr content beyond the helper's own ERROR line.
    [[ "$stderr" == *"parse error"* || "$stderr" == *"Invalid"* || "$stderr" == *"error"* ]]
}
