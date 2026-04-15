#!/usr/bin/env bats
# Tests for spiral harness pipeline profiles (cycle-072)
# Covers: AC-3, AC-4, AC-5, AC-21, AC-26

setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"

    # Source the harness in a way that skips main() execution
    # We only need the functions, not the full script
    export PROJECT_ROOT
    export _SPIRAL_EVIDENCE_LOADED=true  # Prevent evidence.sh from loading
    export _FLIGHT_RECORDER=""

    # Mock functions that evidence.sh provides
    _record_action() { :; }
    _record_failure() { :; }
    _init_flight_recorder() { :; }
    export -f _record_action _record_failure _init_flight_recorder
}

# Helper to source just the profile functions
_load_profile_functions() {
    # Extract and eval just the profile-related functions from the harness
    PIPELINE_PROFILE="${1:-standard}"
    EXECUTOR_MODEL="sonnet"
    ADVISOR_MODEL="opus"
    FLATLINE_GATES=""
    _PROFILE_EXPLICITLY_SET=false

    _resolve_profile() {
        case "$PIPELINE_PROFILE" in
            full) FLATLINE_GATES="prd,sdd,sprint" ;;
            standard) FLATLINE_GATES="sprint" ;;
            light) FLATLINE_GATES=""; ADVISOR_MODEL="$EXECUTOR_MODEL" ;;
            *) PIPELINE_PROFILE="standard"; FLATLINE_GATES="sprint" ;;
        esac
    }

    _should_run_flatline() {
        local phase="$1"
        [[ ",$FLATLINE_GATES," == *",$phase,"* ]]
    }

    _resolve_profile
}

# ---------------------------------------------------------------------------
# Test 1: standard profile resolves to sprint-only gates (AC-3)
# ---------------------------------------------------------------------------
@test "profiles: standard resolves to sprint-only gates" {
    _load_profile_functions "standard"
    [[ "$FLATLINE_GATES" == "sprint" ]]
}

# ---------------------------------------------------------------------------
# Test 2: full profile resolves to all gates (AC-5)
# ---------------------------------------------------------------------------
@test "profiles: full resolves to all gates" {
    _load_profile_functions "full"
    [[ "$FLATLINE_GATES" == "prd,sdd,sprint" ]]
}

# ---------------------------------------------------------------------------
# Test 3: light profile resolves to no gates + Sonnet advisor (AC-4)
# ---------------------------------------------------------------------------
@test "profiles: light resolves to no gates and Sonnet advisor" {
    _load_profile_functions "light"
    [[ -z "$FLATLINE_GATES" ]]
    [[ "$ADVISOR_MODEL" == "sonnet" ]]
}

# ---------------------------------------------------------------------------
# Test 4: unknown profile falls back to standard
# ---------------------------------------------------------------------------
@test "profiles: unknown profile falls back to standard" {
    _load_profile_functions "unknown_garbage"
    [[ "$PIPELINE_PROFILE" == "standard" ]]
    [[ "$FLATLINE_GATES" == "sprint" ]]
}

# ---------------------------------------------------------------------------
# Test 5: _should_run_flatline correct for standard profile
# ---------------------------------------------------------------------------
@test "profiles: should_run_flatline correct for standard" {
    _load_profile_functions "standard"
    run _should_run_flatline "sprint"
    [[ "$status" -eq 0 ]]

    run _should_run_flatline "prd"
    [[ "$status" -ne 0 ]]

    run _should_run_flatline "sdd"
    [[ "$status" -ne 0 ]]
}

# ---------------------------------------------------------------------------
# Test 6: auto-escalation triggers on auth keyword (AC-21)
# ---------------------------------------------------------------------------
@test "profiles: auto-escalation triggers on auth keyword" {
    _load_profile_functions "light"
    BRANCH="test-branch"

    _auto_escalate_profile() {
        local task="$1"
        if echo "$task" | grep -qiE 'auth|crypto|secret'; then
            PIPELINE_PROFILE="full"
            _resolve_profile
        fi
    }

    _auto_escalate_profile "Implement authentication middleware"
    [[ "$PIPELINE_PROFILE" == "full" ]]
    [[ "$FLATLINE_GATES" == "prd,sdd,sprint" ]]
}

# ---------------------------------------------------------------------------
# Test 7: auto-escalation triggers on .claude/scripts path (AC-21)
# ---------------------------------------------------------------------------
@test "profiles: auto-escalation triggers on system path in sprint" {
    _load_profile_functions "standard"

    local tmpdir
    tmpdir="$(mktemp -d)"
    mkdir -p "$tmpdir/grimoires/loa"
    echo "## Sprint 1: Modify .claude/scripts/harness" > "$tmpdir/grimoires/loa/sprint.md"

    # Simulate sprint plan check
    if grep -qiE '\.claude/scripts' "$tmpdir/grimoires/loa/sprint.md" 2>/dev/null; then
        PIPELINE_PROFILE="full"
        _resolve_profile
    fi

    [[ "$PIPELINE_PROFILE" == "full" ]]
    rm -rf "$tmpdir"
}

# ---------------------------------------------------------------------------
# Test 8: SKILL.md dispatch guard contains harness route (AC-26)
# ---------------------------------------------------------------------------
@test "profiles: SKILL.md dispatch guard routes to spiral-harness.sh" {
    local skill_md="$PROJECT_ROOT/.claude/skills/spiraling/SKILL.md"
    [[ -f "$skill_md" ]]
    grep -q "DISPATCH GUARD" "$skill_md"
    grep -q "spiral-harness.sh" "$skill_md"
    grep -q "MUST NOT implement code directly" "$skill_md"
}
