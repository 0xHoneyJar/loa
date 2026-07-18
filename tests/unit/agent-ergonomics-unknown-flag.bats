#!/usr/bin/env bats
# =============================================================================
# tests/unit/agent-ergonomics-unknown-flag.bats
# agent-ergonomics pass 1 (bd-m1o6) R-008 — dx_unknown_flag helper
# (did-you-mean + usage echo) wired into 5 scripts.
#
# Pins two things per script:
#   1. Exit code is UNCHANGED from before the rec (verified against git
#      HEAD's version of each script in the session that authored this file).
#   2. stderr now teaches: names the flag, suggests the likely intended
#      flag (edit-distance <=2 or shared prefix >=3 chars), and echoes a
#      one-line Usage string — instead of a bare "Unknown option" dead end.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    DX_UTILS="$PROJECT_ROOT/.claude/scripts/lib/dx-utils.sh"
    BEADS_HEALTH="$PROJECT_ROOT/.claude/scripts/beads/beads-health.sh"
    SEMVER_BUMP="$PROJECT_ROOT/.claude/scripts/semver-bump.sh"
    VALIDATE_SKILLS="$PROJECT_ROOT/.claude/scripts/validate-skill-capabilities.sh"
    CONSTRUCT_RESOLVE="$PROJECT_ROOT/.claude/scripts/construct-resolve.sh"
    MEMORY_QUERY="$PROJECT_ROOT/.claude/scripts/memory-query.sh"
}

# =============================================================================
# Unit tests: dx_unknown_flag itself
# =============================================================================

@test "dx_unknown_flag: suggests a close match (edit-distance <=2) and echoes usage" {
    run bash -c "source '$DX_UTILS' && dx_unknown_flag '--jsno' 'Usage: foo [--json]' --json --verbose --quick"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Unknown option: --jsno" ]]
    [[ "$output" =~ "Did you mean: --json?" ]]
    [[ "$output" =~ "Usage: foo [--json]" ]]
}

@test "dx_unknown_flag: suggests via prefix match (>=3 shared chars) even with larger edit distance" {
    run bash -c "source '$DX_UTILS' && dx_unknown_flag '--downstrea' 'Usage: bar [--downstream]' --from-tag --from-changelog --downstream"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Did you mean: --downstream?" ]]
}

@test "dx_unknown_flag: no suggestion when nothing is close, but usage still prints" {
    run bash -c "source '$DX_UTILS' && dx_unknown_flag '--zzzzzzzz' 'Usage: baz [--json]' --json --verbose"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Unknown option: --zzzzzzzz" ]]
    [[ "$output" != *"Did you mean"* ]]
    [[ "$output" =~ "Usage: baz [--json]" ]]
}

@test "dx_unknown_flag: NEVER calls exit — caller code after the call still runs" {
    run bash -c "source '$DX_UTILS' && dx_unknown_flag '--jsno' 'Usage: foo' --json; echo AFTER-CALL-MARKER"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "AFTER-CALL-MARKER" ]]
}

# =============================================================================
# beads-health.sh (exit 1 preserved)
# =============================================================================

@test "beads-health.sh: --jsno preserves exit 1, suggests --json, shows Usage" {
    run timeout 30 bash "$BEADS_HEALTH" --jsno
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Unknown option: --jsno" ]]
    [[ "$output" =~ "Did you mean: --json?" ]]
    [[ "$output" =~ "Usage: beads-health.sh" ]]
}

# =============================================================================
# semver-bump.sh (exit 2 preserved)
# =============================================================================

@test "semver-bump.sh: --downstrea preserves exit 2, suggests --downstream, shows Usage" {
    run timeout 30 bash "$SEMVER_BUMP" --downstrea
    [ "$status" -eq 2 ]
    [[ "$output" =~ "Unknown option: --downstrea" ]]
    [[ "$output" =~ "Did you mean: --downstream?" ]]
    [[ "$output" =~ "Usage: semver-bump.sh" ]]
}

# =============================================================================
# validate-skill-capabilities.sh (exit 2 preserved)
# =============================================================================

@test "validate-skill-capabilities.sh: --jsno preserves exit 2, suggests --json, shows Usage" {
    run timeout 30 bash "$VALIDATE_SKILLS" --jsno
    [ "$status" -eq 2 ]
    [[ "$output" =~ "Unknown option: --jsno" ]]
    [[ "$output" =~ "Did you mean: --json?" ]]
    [[ "$output" =~ "Usage: validate-skill-capabilities.sh" ]]
}

# =============================================================================
# construct-resolve.sh (exit 1 preserved)
# =============================================================================

@test "construct-resolve.sh: --jsno preserves exit 1, suggests --json, shows Usage" {
    run timeout 30 bash "$CONSTRUCT_RESOLVE" resolve foo --jsno
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Unknown option: --jsno" ]]
    [[ "$output" =~ "Did you mean: --json?" ]]
    [[ "$output" =~ "Usage: construct-resolve.sh" ]]
}

# =============================================================================
# memory-query.sh (exit 1 preserved)
# =============================================================================

@test "memory-query.sh: --jsno preserves exit 1, suggests --json, shows Usage" {
    run timeout 30 bash "$MEMORY_QUERY" --jsno
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Unknown option: --jsno" ]]
    [[ "$output" =~ "Did you mean: --json?" ]]
    [[ "$output" =~ "Usage: memory-query.sh" ]]
}
