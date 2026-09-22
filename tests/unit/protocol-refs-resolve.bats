#!/usr/bin/env bats
# =============================================================================
# tests/unit/protocol-refs-resolve.bats — cycle-124 FR-8 / AC-8.3
#
# Every `protocols/<name>.md` string in .claude/, PROCESS.md, CONTRIBUTING.md,
# tests/ and .github/workflows/ resolves to a file under .claude/protocols/,
# so an archived protocol cannot leave a dangling pointer behind. Synthetic
# strings (test fixtures) are listed in tools/protocol-refs.allowlist with a
# reason, and a stale allowlist row is itself a failure.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    ALLOW="$PROJECT_ROOT/tools/protocol-refs.allowlist"
}

# file:name.md pairs for every reference in scope (tracked files only — the
# working tree also holds ignored local docs under .claude/config/)
refs() {
    ( cd "$PROJECT_ROOT" && git ls-files -z -- .claude PROCESS.md CONTRIBUTING.md tests .github/workflows 2>/dev/null \
        | xargs -0 grep -noE 'protocols/[A-Za-z0-9_-]+\.md' 2>/dev/null \
        | awk -F: '{ sub(/^protocols\//, "", $3); print $1 "\t" $3 }' | sort -u )
}

allowed() {  # allowed <file> <name>
    local f n a_sub a_name
    f="$1"; n="$2"
    while IFS=$'\t' read -r a_sub a_name _; do
        [[ "$f" == *"$a_sub"* && "$n" == "$a_name" ]] && return 0
    done < <(grep -v -E '^\s*(#|$)' "$ALLOW")
    return 1
}

@test "PR-1 every protocols/<name>.md reference in scope resolves (or is allowlisted with a reason)" {
    local bad=0 f n
    while IFS=$'\t' read -r f n; do
        [ -f "$PROJECT_ROOT/.claude/protocols/$n" ] && continue
        allowed "$f" "$n" && continue
        echo "DANGLING: $f -> protocols/$n"
        bad=$((bad + 1))
    done < <(refs)
    [ "$bad" -eq 0 ]
}

@test "PR-2 no stale allowlist row (every row still matches an unresolved reference)" {
    local stale=0 a_sub a_name
    while IFS=$'\t' read -r a_sub a_name _; do
        refs | awk -F'\t' -v s="$a_sub" -v n="$a_name" 'index($1, s) && $2 == n { found = 1 } END { exit found ? 0 : 1 }' \
            || { echo "STALE allowlist row: $a_sub $a_name"; stale=$((stale + 1)); }
    done < <(grep -v -E '^\s*(#|$)' "$ALLOW")
    [ "$stale" -eq 0 ]
}

@test "PR-3 the three archived protocols are gone from .claude/protocols and their summary rows with them" {
    for p in risk-analysis upgrade-process sprint-completion; do
        [ ! -e "$PROJECT_ROOT/.claude/protocols/$p.md" ]
        ! grep -q "protocols/$p.md" "$PROJECT_ROOT/.claude/loa/reference/protocols-summary.md"
    done
}
