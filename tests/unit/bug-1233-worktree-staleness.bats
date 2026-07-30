#!/usr/bin/env bats
# =============================================================================
# bug-1233-worktree-staleness.bats — cycle-123 T1.4 (#1233)
#
# Observed failure (reproduced 3x): a worktree parked on a branch whose cycle
# merged, archived and tagged keeps reporting `state: complete` and suggesting
# /deploy-production on every new session. generate_cache_key() is built from
# LOCAL file mtimes/hashes only, so origin/main advancing can never invalidate
# the fossil verdict.
#
# The fixture must be a REAL linked worktree with a resolvable origin/main —
# the in-repo `.loa-test-*` pattern cannot express that, so we build a bare
# origin, clone it, and `git worktree add` off the clone.
# =============================================================================

setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT_REAL="$(cd "$BATS_TEST_DIR/../.." && pwd)"

    export BATS_TMPDIR="${BATS_TMPDIR:-/tmp}"
    export TEST_TMPDIR="$BATS_TMPDIR/wt-stale-$$"
    mkdir -p "$TEST_TMPDIR"

    export ORIGIN="$TEST_TMPDIR/origin.git"
    export MAIN_CO="$TEST_TMPDIR/main-checkout"
    export WORKTREE="$TEST_TMPDIR/fossil-wt"
    export STATE_SCRIPT="$PROJECT_ROOT_REAL/.claude/scripts/workflow-state.sh"

    git init --bare --quiet --initial-branch=main "$ORIGIN"

    # Seed: an ACTIVE cycle, sprints complete (so state resolves to complete).
    git init --quiet --initial-branch=main "$MAIN_CO"
    git -C "$MAIN_CO" config user.email t@t.com
    git -C "$MAIN_CO" config user.name t
    _install_framework "$MAIN_CO"
    _write_ledger "$MAIN_CO" "active"
    git -C "$MAIN_CO" add -A
    git -C "$MAIN_CO" commit --quiet -m "seed"
    git -C "$MAIN_CO" remote add origin "$ORIGIN"
    git -C "$MAIN_CO" push --quiet -u origin main
}

teardown() {
    cd /
    [[ -d "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"
}

skip_if_deps_missing() {
    command -v jq >/dev/null 2>&1 || skip "jq not installed"
}

# Copy the minimum framework surface workflow-state.sh needs.
_install_framework() {
    local root="$1"
    mkdir -p "$root/.claude/scripts" "$root/grimoires/loa"
    local f
    for f in workflow-state.sh path-lib.sh bootstrap.sh cache-manager.sh compat-lib.sh; do
        cp "$PROJECT_ROOT_REAL/.claude/scripts/$f" "$root/.claude/scripts/" 2>/dev/null || true
    done
    # A sprint plan + PRD/SDD so the state machine reaches `complete`.
    printf '# PRD\n' > "$root/grimoires/loa/prd.md"
    printf '# SDD\n' > "$root/grimoires/loa/sdd.md"
    printf '## Sprint 1: Only\n' > "$root/grimoires/loa/sprint.md"
}

_write_ledger() {
    local root="$1" status="$2"
    jq -n --arg st "$status" '{
        schema_version: 1,
        active_cycle: "cycle-fossil-001",
        cycles: [{
            id: "cycle-fossil-001",
            status: $st,
            sprints: [{global_id: 1, local_label: "sprint-1", status: "completed"}]
        }]
    }' > "$root/grimoires/loa/ledger.json"
}

# Archive the cycle on origin/main — what post-merge does after a cycle ships
# (#1234 makes this actually happen), then refresh the clone's tracking ref.
_archive_on_origin() {
    _write_ledger "$MAIN_CO" "archived"
    jq '.active_cycle = null' "$MAIN_CO/grimoires/loa/ledger.json" > "$MAIN_CO/.l.tmp"
    mv "$MAIN_CO/.l.tmp" "$MAIN_CO/grimoires/loa/ledger.json"
    git -C "$MAIN_CO" add -A
    git -C "$MAIN_CO" commit --quiet -m "chore(ledger): archive cycle-fossil-001 after merge"
    git -C "$MAIN_CO" push --quiet origin main
}

# A linked worktree still holding the pre-archive (active) ledger — the fossil.
_make_fossil_worktree() {
    git -C "$MAIN_CO" branch --quiet feature/fossil main 2>/dev/null || true
    git -C "$MAIN_CO" worktree add --quiet "$WORKTREE" feature/fossil
    git -C "$MAIN_CO" fetch --quiet origin main
    _write_ledger "$WORKTREE" "active"
}

_state_json() {
    ( cd "$1" && PROJECT_ROOT="$1" bash "$STATE_SCRIPT" --json ${2:+$2} 2>/dev/null )
}

@test "1233: stale worktree reports .stale == true" {
    skip_if_deps_missing
    _archive_on_origin
    _make_fossil_worktree

    local out
    out=$(_state_json "$WORKTREE")
    [[ "$(echo "$out" | jq -r '.stale')" == "true" ]] || {
        echo "expected stale=true; got: $out"
        return 1
    }
    [[ "$(echo "$out" | jq -r '.stale_cycle')" == "cycle-fossil-001" ]]
}

@test "1233: stale worktree suggests worktree removal, never /deploy-production" {
    skip_if_deps_missing
    _archive_on_origin
    _make_fossil_worktree

    local suggested
    suggested=$(_state_json "$WORKTREE" | jq -r '.suggested_command')
    [[ "$suggested" == *"git worktree remove"* ]] || {
        echo "expected worktree removal; got: $suggested"
        return 1
    }
    [[ "$suggested" != *"/deploy-production"* ]]
}

@test "1233: primary checkout is unaffected apart from stale == false" {
    skip_if_deps_missing
    _archive_on_origin

    local out
    out=$(_state_json "$MAIN_CO")
    [[ "$(echo "$out" | jq -r '.stale')" == "false" ]] || {
        echo "primary checkout flagged stale; got: $out"
        return 1
    }
    [[ "$(echo "$out" | jq -r '.suggested_command')" != *"git worktree remove"* ]]
}

@test "1233: --no-stale-check restores pre-fix behavior in a stale worktree" {
    skip_if_deps_missing
    _archive_on_origin
    _make_fossil_worktree

    local out
    out=$(_state_json "$WORKTREE" "--no-stale-check")
    [[ "$(echo "$out" | jq -r '.stale')" == "false" ]]
    [[ "$(echo "$out" | jq -r '.suggested_command')" != *"git worktree remove"* ]]
    [[ "$(echo "$out" | jq -r '.description')" != *"STALE WORKTREE"* ]]
}

@test "1233: no origin/main ref present → stale false, empty stderr" {
    skip_if_deps_missing
    _make_fossil_worktree
    git -C "$MAIN_CO" remote remove origin
    git -C "$MAIN_CO" update-ref -d refs/remotes/origin/main 2>/dev/null || true

    local err out
    err=$( ( cd "$WORKTREE" && PROJECT_ROOT="$WORKTREE" bash "$STATE_SCRIPT" --json 2>&1 >/dev/null ) )
    out=$(_state_json "$WORKTREE")

    [[ "$(echo "$out" | jq -r '.stale')" == "false" ]] || {
        echo "expected stale=false without origin/main; got: $out"
        return 1
    }
    [[ -z "$err" ]] || {
        echo "expected empty stderr; got: $err"
        return 1
    }
}

@test "1233: verdict is stable across two consecutive runs (cache cannot mask it)" {
    skip_if_deps_missing
    _archive_on_origin
    _make_fossil_worktree

    [[ "$(_state_json "$WORKTREE" | jq -r '.stale')" == "true" ]]
    [[ "$(_state_json "$WORKTREE" | jq -r '.stale')" == "true" ]] || {
        echo "second run lost the stale verdict (cache served a fossil)"
        return 1
    }
}
