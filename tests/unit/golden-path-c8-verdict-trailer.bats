#!/usr/bin/env bats
# Unit tests for golden-path.sh C8 (cycle-119): structured-first gate
# consumption. _gp_sprint_is_reviewed / _gp_sprint_is_audited must:
#   - stay byte-identical in behavior for legacy files (no LOA-VERDICT trailer)
#   - use verdict-derive.sh's derived verdict when a trailer IS present

setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"

    export BATS_TMPDIR="${BATS_TMPDIR:-/tmp}"
    export TEST_TMPDIR="$BATS_TMPDIR/golden-path-c8-test-$$"
    mkdir -p "$TEST_TMPDIR/.claude/scripts" "$TEST_TMPDIR/.run"
    mkdir -p "$TEST_TMPDIR/grimoires/loa/a2a/sprint-1"

    for f in bootstrap.sh golden-path.sh path-lib.sh compat-lib.sh verdict-derive.sh; do
        cp "$PROJECT_ROOT/.claude/scripts/$f" "$TEST_TMPDIR/.claude/scripts/"
    done
    chmod +x "$TEST_TMPDIR/.claude/scripts/verdict-derive.sh"

    # Initialize git repo for bootstrap's PROJECT_ROOT detection
    cd "$TEST_TMPDIR"
    git init -q
    git add -A 2>/dev/null || true
    git commit -q -m "init" --allow-empty

    export PROJECT_ROOT="$TEST_TMPDIR"
    SPRINT_DIR="$TEST_TMPDIR/grimoires/loa/a2a/sprint-1"
}

teardown() {
    cd /
    if [[ -d "$TEST_TMPDIR" ]]; then
        rm -rf "$TEST_TMPDIR"
    fi
}

skip_if_no_jq() {
    command -v jq &>/dev/null || skip "jq not installed"
}

# =============================================================================
# Legacy behavior (no trailer) — must stay byte-identical
# =============================================================================

@test "C8 legacy: reviewed=true when engineer-feedback.md says 'All good' (no trailer)" {
    cat > "$SPRINT_DIR/engineer-feedback.md" <<'EOF'
All good

No issues found.
EOF
    source "$TEST_TMPDIR/.claude/scripts/golden-path.sh"
    run _gp_sprint_is_reviewed sprint-1
    [ "$status" -eq 0 ]
}

@test "C8 legacy: reviewed=false when engineer-feedback.md has a Changes Required heading (no trailer)" {
    cat > "$SPRINT_DIR/engineer-feedback.md" <<'EOF'
## Changes Required

- fix the thing
EOF
    source "$TEST_TMPDIR/.claude/scripts/golden-path.sh"
    run _gp_sprint_is_reviewed sprint-1
    [ "$status" -eq 1 ]
}

@test "C8 legacy: reviewed=false when no engineer-feedback.md exists" {
    source "$TEST_TMPDIR/.claude/scripts/golden-path.sh"
    run _gp_sprint_is_reviewed sprint-1
    [ "$status" -eq 1 ]
}

@test "C8 legacy: audited=true when auditor-sprint-feedback.md contains APPROVED (no trailer)" {
    cat > "$SPRINT_DIR/auditor-sprint-feedback.md" <<'EOF'
APPROVED - LET'S FUCKING GO
EOF
    source "$TEST_TMPDIR/.claude/scripts/golden-path.sh"
    run _gp_sprint_is_audited sprint-1
    [ "$status" -eq 0 ]
}

@test "C8 legacy: audited=false when auditor-sprint-feedback.md lacks APPROVED (no trailer)" {
    cat > "$SPRINT_DIR/auditor-sprint-feedback.md" <<'EOF'
CHANGES_REQUIRED: fix the security bug.
EOF
    source "$TEST_TMPDIR/.claude/scripts/golden-path.sh"
    run _gp_sprint_is_audited sprint-1
    [ "$status" -eq 1 ]
}

@test "C8 legacy: an audited sprint is implicitly reviewed (no trailer)" {
    cat > "$SPRINT_DIR/auditor-sprint-feedback.md" <<'EOF'
APPROVED - LET'S FUCKING GO
EOF
    source "$TEST_TMPDIR/.claude/scripts/golden-path.sh"
    run _gp_sprint_is_reviewed sprint-1
    [ "$status" -eq 0 ]
}

# =============================================================================
# Structured-first behavior (LOA-VERDICT trailer present)
# =============================================================================

@test "C8 structured: reviewed=true when trailer verdict is APPROVED" {
    skip_if_no_jq
    cat > "$SPRINT_DIR/engineer-feedback.md" <<'EOF'
All good
<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"sprint_id":"sprint-1","ts":"2026-07-07T00:00:00Z"} -->
EOF
    source "$TEST_TMPDIR/.claude/scripts/golden-path.sh"
    run _gp_sprint_is_reviewed sprint-1
    [ "$status" -eq 0 ]
}

@test "C8 structured: reviewed=false when trailer verdict is CHANGES_REQUIRED (even if prose looks fine)" {
    skip_if_no_jq
    # Deliberately no findings headings and no 'All good' — the trailer alone
    # must drive the decision once present (structured-first).
    cat > "$SPRINT_DIR/engineer-feedback.md" <<'EOF'
Some prose that would pass the legacy heuristic.
<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":0,"low":0},"sprint_id":"sprint-1","ts":"2026-07-07T00:00:00Z"} -->
EOF
    source "$TEST_TMPDIR/.claude/scripts/golden-path.sh"
    run _gp_sprint_is_reviewed sprint-1
    [ "$status" -eq 1 ]
}

@test "C8 structured: audited=true when trailer verdict is APPROVED" {
    skip_if_no_jq
    cat > "$SPRINT_DIR/auditor-sprint-feedback.md" <<'EOF'
APPROVED - LET'S FUCKING GO
<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"sprint_id":"sprint-1","ts":"2026-07-07T00:00:00Z"} -->
EOF
    source "$TEST_TMPDIR/.claude/scripts/golden-path.sh"
    run _gp_sprint_is_audited sprint-1
    [ "$status" -eq 0 ]
}

@test "C8 structured: audited=false when trailer verdict is CHANGES_REQUIRED" {
    skip_if_no_jq
    cat > "$SPRINT_DIR/auditor-sprint-feedback.md" <<'EOF'
Some prose without the ritual string.
<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":1,"high":0,"medium":0,"low":0},"sprint_id":"sprint-1","ts":"2026-07-07T00:00:00Z"} -->
EOF
    source "$TEST_TMPDIR/.claude/scripts/golden-path.sh"
    run _gp_sprint_is_audited sprint-1
    [ "$status" -eq 1 ]
}
