#!/usr/bin/env bats
# =============================================================================
# tests/unit/no-constraint-temp-files.bats — cycle-124 FR-8
#
# generate-constraints.sh stages each target as `<target>.constraint-XXXXXX`
# (mktemp) and removes the copies on exit; ten such twins were committed by an
# interrupted run and shipped in every mount. None may be tracked or lie on
# disk under .claude/, and no-backup-files.yml must reject the pattern in PRs.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
}

@test "CT-1 no *.constraint-XXXXXX twin is tracked" {
    run bash -c "cd '$PROJECT_ROOT' && git ls-files | grep -E '\.constraint-[A-Za-z0-9]{6}\$'"
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}

@test "CT-2 no *.constraint-XXXXXX twin exists under .claude/" {
    run find "$PROJECT_ROOT/.claude" -name '*.constraint-??????' -print
    [ -z "$output" ]
}

@test "CT-3 no-backup-files.yml rejects the constraint temp-twin pattern" {
    grep -qF '\.constraint-[A-Za-z0-9]{6}$' "$PROJECT_ROOT/.github/workflows/no-backup-files.yml"
    # the workflow's grep, applied to a twin name, must match
    local re
    re="$(grep -oE "grep -E '[^']+'" "$PROJECT_ROOT/.github/workflows/no-backup-files.yml" | head -1 | sed -E "s/^grep -E '//; s/'$//")"
    [ -n "$re" ]
    echo ".claude/loa/CLAUDE.loa.md.constraint-7PuPXe" | grep -qE "$re"
    ! echo ".claude/loa/CLAUDE.loa.md" | grep -qE "$re"
}
