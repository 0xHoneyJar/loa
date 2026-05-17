#!/usr/bin/env bats
# cycle-113 Sprint 1 T1.2 — chunking call-graph audit (FR-A-1, SDD §9.1)
#
# Purpose: verify-only audit that pins whether `loa_cheval.chunking` has
# at least one production caller. Per FR-A-2, synthetically wiring
# chunking to make this test pass is explicitly forbidden — the audit
# exists to surface the gap, not to mask it.
#
# Acceptable outcomes (SDD §9.2):
#   (a) >=1 production caller found      -> test passes, pins call site
#   (b) NO production caller found        -> test FAILS LOUD; T1.3 files
#                                             cycle-114 follow-up + KF
#                                             entry; cycle-113 proceeds
#                                             to close Groups B+C
#
# This test runs all three audit steps and reports each independently
# so failures point at the EXACT missing piece.

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    CHUNKING_DIR="$PROJECT_ROOT/.claude/adapters/loa_cheval/chunking"
    # cycle-113 sprint-170 audit-amendment: original SEARCH_ROOTS scope
    # (loa_cheval/ + scripts/) MISSED .claude/adapters/cheval.py which
    # imports + invokes chunk_pr_for_review at line 1540-1600. Sprint-168
    # T1.2's "no callers" finding was a SCOPE BUG, not a structural defect.
    # Widening to .claude/adapters/ catches cheval.py as the production
    # caller. Cycle-114 #937 closes with this correction.
    SEARCH_ROOTS=(
        "$PROJECT_ROOT/.claude/adapters"
        "$PROJECT_ROOT/.claude/scripts"
    )
}

@test "audit: chunking package itself exists at expected path" {
    [ -d "$CHUNKING_DIR" ]
    [ -f "$CHUNKING_DIR/__init__.py" ]
    [ -f "$CHUNKING_DIR/chunker.py" ]
    [ -f "$CHUNKING_DIR/aggregate.py" ]
}

@test "audit: chunking __init__ exports the SDD-named public API" {
    # SDD §9.1 cites chunk_pr_for_review and aggregate_findings as the
    # public surface to audit for production usage.
    grep -q 'chunk_pr_for_review' "$CHUNKING_DIR/__init__.py"
    grep -q 'aggregate_findings' "$CHUNKING_DIR/__init__.py"
}

@test "audit grep step (SDD §9.1.1): find imports of loa_cheval.chunking outside the package itself" {
    # Step 1 of the SDD §9.1 audit: search for imports of the chunking
    # package. We EXCLUDE the package itself (its own files self-import)
    # and EXCLUDE the .pyc cache.
    #
    # Patterns to match (Python idioms):
    #   from loa_cheval.chunking import ...
    #   from loa_cheval.chunking.chunker import ...
    #   from loa_cheval.chunking.aggregate import ...
    #   import loa_cheval.chunking
    #   from .chunking import ...        (relative; only if caller is in loa_cheval/)

    local matches
    matches=$(grep -rEn \
        --include='*.py' \
        --include='*.sh' \
        --exclude-dir='__pycache__' \
        --exclude-dir='chunking' \
        '(from[[:space:]]+loa_cheval\.chunking|import[[:space:]]+loa_cheval\.chunking|from[[:space:]]+\.chunking[[:space:]]+import)' \
        "${SEARCH_ROOTS[@]}" 2>/dev/null || true)

    # Audit step: print the result so the operator can see EXACTLY what
    # was (or wasn't) found.
    echo "# chunking import audit result:"
    if [[ -z "$matches" ]]; then
        echo "#   (no imports found outside the package)"
    else
        echo "$matches" | sed 's/^/#   /'
    fi

    # FR-A-2 LOUD-FAIL: empty result means no production caller.
    [ -n "$matches" ] || {
        echo "# CYCLE-113 AUDIT FINDING (FR-A-2 outcome b):" >&2
        echo "#   loa_cheval.chunking has ZERO production callers." >&2
        echo "#   The cycle-109 Sprint 4 KF-002 RESOLVED-STRUCTURAL closure" >&2
        echo "#   cited the chunking package as one of three composing pieces;" >&2
        echo "#   this audit verifies that claim is empirically false." >&2
        echo "#" >&2
        echo "#   Required follow-up (T1.3):" >&2
        echo "#     1. File cycle-114 follow-up issue tracking chunking" >&2
        echo "#        call-graph wiring or library deletion decision." >&2
        echo "#     2. Add KF-002 attempts-table row documenting the" >&2
        echo "#        empirical-state finding (2026-05-17)." >&2
        echo "#" >&2
        echo "#   Cycle-113 proceeds to close Groups B+C per SDD §9.2 (b)." >&2
        echo "#   Synthetic wiring is FORBIDDEN per FR-A-2." >&2
        return 1
    }
}

@test "audit production-caller check (SDD §9.1.2): at least one caller exists OUTSIDE tests/" {
    # Step 2 of SDD §9.1: confirm the caller(s) found in step 1 are not
    # purely test code. Tests can legitimately import the library to
    # verify it; what we need is a PRODUCTION caller.
    #
    # We re-run the grep and additionally exclude tests/ paths.

    local production_matches
    production_matches=$(grep -rEln \
        --include='*.py' \
        --include='*.sh' \
        --exclude-dir='__pycache__' \
        --exclude-dir='chunking' \
        --exclude-dir='tests' \
        --exclude-dir='test' \
        '(from[[:space:]]+loa_cheval\.chunking|import[[:space:]]+loa_cheval\.chunking|from[[:space:]]+\.chunking[[:space:]]+import)' \
        "${SEARCH_ROOTS[@]}" 2>/dev/null || true)

    echo "# chunking production-caller audit:"
    if [[ -z "$production_matches" ]]; then
        echo "#   (no production callers — all matches were in tests/)"
    else
        echo "$production_matches" | sed 's/^/#   /'
    fi

    [ -n "$production_matches" ] || {
        echo "# CYCLE-113 AUDIT FINDING (FR-A-2 outcome b cont.):" >&2
        echo "#   chunking has no PRODUCTION caller (production = outside tests/)." >&2
        echo "#   See test '@audit grep step' for full match list (likely empty)." >&2
        return 1
    }
}

@test "audit live-invocation check (SDD §9.1.3): at least one caller invokes the public functions" {
    # Step 3 of SDD §9.1: import isn't enough — confirm at least one
    # caller actually CALLS `chunk_pr_for_review(...)` or
    # `aggregate_findings(...)` (vs. just importing for type hints).

    local invocations
    invocations=$(grep -rEln \
        --include='*.py' \
        --include='*.sh' \
        --exclude-dir='__pycache__' \
        --exclude-dir='chunking' \
        --exclude-dir='tests' \
        --exclude-dir='test' \
        '(chunk_pr_for_review[[:space:]]*\(|aggregate_findings[[:space:]]*\()' \
        "${SEARCH_ROOTS[@]}" 2>/dev/null || true)

    echo "# chunking live-invocation audit:"
    if [[ -z "$invocations" ]]; then
        echo "#   (no production invocations of chunk_pr_for_review or aggregate_findings)"
    else
        echo "$invocations" | sed 's/^/#   /'
    fi

    [ -n "$invocations" ] || {
        echo "# CYCLE-113 AUDIT FINDING (FR-A-2 outcome b final):" >&2
        echo "#   chunking library exists, but no production code invokes" >&2
        echo "#   chunk_pr_for_review() or aggregate_findings()." >&2
        echo "#   The defense layer is dormant — same defect class as" >&2
        echo "#   streaming.recovery prior to cycle-113 Sprint 168." >&2
        echo "#" >&2
        echo "#   Required follow-up issue (T1.3):" >&2
        echo "#     gh issue create --title 'cycle-114: chunking call-graph dormancy" >&2
        echo "#       — wire or remove' ..." >&2
        return 1
    }
}

@test "audit summary: explicit FR-A-2 reminder against synthetic wiring" {
    # Documentary test — always passes. Its purpose is to keep the
    # FR-A-2 anti-pattern statement visible in test output so any
    # operator running this audit suite sees it.

    echo "# FR-A-2 reminder (SDD §9.2 anti-pattern):" >&2
    echo "#   Synthetically wiring chunking in cycle-113 to make the" >&2
    echo "#   audit pass is EXPLICITLY FORBIDDEN. The audit exists to" >&2
    echo "#   surface the gap, not to mask it. If the grep / production-" >&2
    echo "#   caller / invocation tests above fail, the correct action" >&2
    echo "#   is T1.3: file cycle-114 follow-up + KF-002 attempts-table" >&2
    echo "#   entry. Cycle-113 closes Groups B+C regardless." >&2
}
