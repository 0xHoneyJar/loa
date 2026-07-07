#!/usr/bin/env bats
# =============================================================================
# post-merge-version-bump.bats — bd-...-header-self-stamp-ze52 regression tests
# =============================================================================
# Verifies the version_bump phase added to post-merge-orchestrator.sh, which
# re-stamps loa's own framework markers (.loa-version.json + the
# .claude/loa/CLAUDE.loa.md:1 @loa-managed header) from the just-computed
# semver target at release time, reusing the unit-tested resolver
# update-loa-bump-version.sh. Follows the static-source template proven in
# post-merge-lore-promote.bats.
# =============================================================================

setup() {
    SCRIPT="$BATS_TEST_DIRNAME/../../.claude/scripts/post-merge-orchestrator.sh"
}

# Extract the phase_version_bump function body for scoped assertions.
_vb_body() {
    awk '/^phase_version_bump\(\)/,/^}$/' "$SCRIPT"
}

# T1: phase present in PHASE_ORDER
@test "post-merge: version_bump phase present in PHASE_ORDER" {
    grep -qE "^PHASE_ORDER=.*version_bump" "$SCRIPT"
}

# T2: phase function defined
@test "post-merge: phase_version_bump function defined" {
    grep -q "^phase_version_bump()" "$SCRIPT"
}

# T3: phase enabled in all three matrices
@test "post-merge: version_bump in CYCLE/BUGFIX/OTHER matrices" {
    grep -qE "CYCLE_PHASES=.*\[version_bump\]=1" "$SCRIPT"
    grep -qE "BUGFIX_PHASES=.*\[version_bump\]=1" "$SCRIPT"
    grep -qE "OTHER_PHASES=.*\[version_bump\]=1" "$SCRIPT"
}

# T4: phase registered in init_state phases object
@test "post-merge: version_bump registered in init_state phases object" {
    grep -qE "version_bump: \{status: \"pending\", result: null\}" "$SCRIPT"
}

# T5: ordering — runs after semver, before tag (so the tag captures stamped markers)
@test "post-merge: version_bump runs after semver, before tag" {
    local order sem_pos vb_pos tag_pos
    order=$(grep '^PHASE_ORDER=' "$SCRIPT" | head -1)
    sem_pos=$(echo "$order" | tr ' ' '\n' | grep -n '\bsemver\b' | head -1 | cut -d: -f1)
    vb_pos=$(echo "$order" | tr ' ' '\n' | grep -n 'version_bump' | cut -d: -f1)
    tag_pos=$(echo "$order" | tr ' ' '\n' | grep -n '\btag\b' | cut -d: -f1)
    [ "$sem_pos" -lt "$vb_pos" ]
    [ "$vb_pos" -lt "$tag_pos" ]
}

# T6: reads the semver target from the semver phase result
@test "post-merge: version_bump reads .phases.semver.result.next" {
    _vb_body | grep -q '.phases.semver.result.next'
}

# T7: invokes the existing resolver with --target
@test "post-merge: version_bump invokes update-loa-bump-version.sh --target" {
    _vb_body | grep -q 'update-loa-bump-version.sh'
    _vb_body | grep -qE '"\$bump_script" --target'
}

# T8: respects DRY_RUN (no side effects in dry-run)
@test "post-merge: version_bump respects DRY_RUN flag" {
    _vb_body | grep -q 'DRY_RUN'
}

# T9: downstream guard — must NOT stamp a downstream repo's own semver
@test "post-merge: version_bump skips when DOWNSTREAM=true" {
    _vb_body | grep -qE 'DOWNSTREAM.*==.*"true"'
}

# T10: read-back verification of BOTH markers + PLACEHOLDER guard
@test "post-merge: version_bump read-back verifies both markers and rejects PLACEHOLDER" {
    _vb_body | grep -q '.loa-version.json'
    _vb_body | grep -q 'CLAUDE.loa.md'
    _vb_body | grep -q 'PLACEHOLDER'
}

# T11: non-blocking on failure (returns 0, records phases_failed)
@test "post-merge: version_bump is non-blocking on failure" {
    _vb_body | grep -qE 'return 0'
    _vb_body | grep -q 'phases_failed'
}

# T12: idempotent commit — only commits when the staged diff is non-empty
@test "post-merge: version_bump commits only on non-empty cached diff" {
    _vb_body | grep -qE 'git .* diff --cached --quiet'
    _vb_body | grep -qE 'chore\(release\).*sync'
}

# T13: the resolver it drives is present and exposes bump_claude_loa_header
# (the acceptance criterion names this specific reused function).
@test "post-merge: resolver update-loa-bump-version.sh defines bump_claude_loa_header" {
    local resolver="$BATS_TEST_DIRNAME/../../.claude/scripts/update-loa-bump-version.sh"
    [ -f "$resolver" ]
    grep -q '^bump_claude_loa_header()' "$resolver"
}
