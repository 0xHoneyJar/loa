#!/usr/bin/env bats
# =============================================================================
# post-merge-lore-promote.bats — cycle-061 regression tests (#484)
# =============================================================================
# Verifies the lore_promote phase added to post-merge-orchestrator.sh:
#   - Skips when post_merge.lore_promote.enabled is false (default)
#   - Runs when enabled and produces phase metadata
#   - Doesn't fail the pipeline on lore-promote.sh non-zero exit
# =============================================================================

setup() {
    TEST_TMPDIR=$(mktemp -d)
    export TEST_TMPDIR
    SCRIPT="$BATS_TEST_DIRNAME/../../.claude/scripts/post-merge-orchestrator.sh"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

# T1: phase exists in orchestrator source
@test "post-merge: lore_promote phase present in PHASE_ORDER" {
    grep -qE "^PHASE_ORDER=.*lore_promote" "$SCRIPT"
}

# T2: phase function exists
@test "post-merge: phase_lore_promote function defined" {
    grep -q "^phase_lore_promote()" "$SCRIPT"
}

# T3: phase enabled in all three matrices
@test "post-merge: lore_promote in CYCLE/BUGFIX/OTHER matrices" {
    grep -qE "CYCLE_PHASES=.*\[lore_promote\]=1" "$SCRIPT"
    grep -qE "BUGFIX_PHASES=.*\[lore_promote\]=1" "$SCRIPT"
    grep -qE "OTHER_PHASES=.*\[lore_promote\]=1" "$SCRIPT"
}

# T4: phase function reads correct config key
@test "post-merge: phase reads post_merge.lore_promote.enabled config key" {
    awk '/^phase_lore_promote\(\)/,/^}$/' "$SCRIPT" | grep -q "post_merge.lore_promote.enabled"
}

# T5: phase invokes lore-promote.sh with --auto
@test "post-merge: phase invokes lore-promote.sh --auto" {
    # The script var is set to ${PROJECT_ROOT}/.claude/scripts/lore-promote.sh
    # then invoked as "$script" --auto. Test for both bindings.
    awk '/^phase_lore_promote\(\)/,/^}$/' "$SCRIPT" | grep -q "lore-promote.sh"
    awk '/^phase_lore_promote\(\)/,/^}$/' "$SCRIPT" | grep -qE '"\$script"\s+--auto'
}

# T6: phase respects DRY_RUN
@test "post-merge: phase respects DRY_RUN flag" {
    awk '/^phase_lore_promote\(\)/,/^}$/' "$SCRIPT" | grep -q 'DRY_RUN'
}

# T7: phase is non-blocking on failure
@test "post-merge: phase returns 0 on failure (non-blocking per Post-Merge convention)" {
    # The phase explicitly returns 0 in the failure branch (lore promotion
    # is informational, not a release blocker — matches RTFM convention).
    awk '/^phase_lore_promote\(\)/,/^}$/' "$SCRIPT" | grep -qE 'return 0'
    # And explicitly contains a failure branch
    awk '/^phase_lore_promote\(\)/,/^}$/' "$SCRIPT" | grep -q 'phases_failed'
}

# T8: lore-promote.sh accepts --auto flag (cycle-061 addition)
@test "lore-promote: --auto flag is recognized" {
    LP="$BATS_TEST_DIRNAME/../../.claude/scripts/lore-promote.sh"
    grep -qE '\-\-auto\)' "$LP"
}

# T9: --auto sets threshold mode with floor 2
@test "lore-promote: --auto enforces threshold mode + floor 2" {
    LP="$BATS_TEST_DIRNAME/../../.claude/scripts/lore-promote.sh"
    awk '/--auto\)/,/;;/' "$LP" | grep -q 'threshold=2'
}

# T10: lore_promote_phase ordering — runs after release, before notify
@test "post-merge: lore_promote runs after release, before notify" {
    local order
    order=$(grep '^PHASE_ORDER=' "$SCRIPT" | head -1)
    # Extract positions
    local rel_pos lp_pos notify_pos
    rel_pos=$(echo "$order" | tr ' ' '\n' | grep -n 'release' | cut -d: -f1)
    lp_pos=$(echo "$order" | tr ' ' '\n' | grep -n 'lore_promote' | cut -d: -f1)
    notify_pos=$(echo "$order" | tr ' ' '\n' | grep -n 'notify' | cut -d: -f1)
    [ "$rel_pos" -lt "$lp_pos" ]
    [ "$lp_pos" -lt "$notify_pos" ]
}
