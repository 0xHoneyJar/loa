#!/usr/bin/env bats
# =============================================================================
# next-bug-sprint-id.bats — tests for .claude/scripts/next-bug-sprint-id.sh
# =============================================================================
# Defends against the sprint-counter collision wart observed during
# 2026-04-28 issue triage session: when multiple `/bug` invocations run from
# the same starting commit (e.g., main HEAD with multiple unmerged sibling
# bugfix branches in flight), each /bug picks counter+1 from local ledger.json
# without checking sibling-branch ledgers or remote state, producing duplicate
# sprint IDs across PRs. Symptom: same sprint-bug-N number appears in two
# unmerged PRs at once, requiring manual renumbering at merge.
#
# This script is the source-of-truth for next-sprint-id picking. It must
# consult:
#   1. local ledger.json's global_sprint_counter
#   2. max sprint-bug-N referenced on disk under grimoires/loa/a2a/bug-*/
#   3. origin/main's ledger.json's global_sprint_counter (if reachable)
# …and return max(all three) + 1.
# =============================================================================

setup() {
    export PROJECT_ROOT="$BATS_TEST_TMPDIR/proj"
    export REAL_REPO="$BATS_TEST_DIRNAME/../.."
    export SCRIPT="$REAL_REPO/.claude/scripts/next-bug-sprint-id.sh"

    [[ -f "$SCRIPT" ]] || skip "next-bug-sprint-id.sh not yet implemented"
    command -v jq >/dev/null || skip "jq required"

    mkdir -p "$PROJECT_ROOT/grimoires/loa/a2a"
}

teardown() {
    # bats handles BATS_TEST_TMPDIR cleanup; nothing to do
    :
}

# Helper: write a minimal ledger.json with a given counter
_write_ledger() {
    local counter="$1"
    cat > "$PROJECT_ROOT/grimoires/loa/ledger.json" <<EOF
{
  "global_sprint_counter": $counter,
  "bugfix_cycles": []
}
EOF
}

# Helper: simulate a bug-cycle sprint.md on disk that references sprint-bug-N
_write_disk_sprint() {
    local n="$1"
    local dir="$PROJECT_ROOT/grimoires/loa/a2a/bug-test-$n"
    mkdir -p "$dir"
    cat > "$dir/sprint.md" <<EOF
# Sprint Plan
**Sprint**: sprint-bug-$n
EOF
}

@test "next-id is N+1 when only local ledger has N" {
    _write_ledger 5
    cd "$PROJECT_ROOT" && git init --quiet
    run bash "$SCRIPT"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "sprint-bug-6" ]]
}

@test "next-id picks disk-scan max when ledger is behind disk" {
    _write_ledger 5
    _write_disk_sprint 121
    _write_disk_sprint 122
    _write_disk_sprint 123
    cd "$PROJECT_ROOT" && git init --quiet
    run bash "$SCRIPT"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "sprint-bug-124" ]]
}

@test "next-id picks ledger when ledger > disk-scan" {
    _write_ledger 200
    _write_disk_sprint 121
    cd "$PROJECT_ROOT" && git init --quiet
    run bash "$SCRIPT"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "sprint-bug-201" ]]
}

@test "next-id handles missing ledger gracefully (returns sprint-bug-1)" {
    cd "$PROJECT_ROOT" && git init --quiet
    run bash "$SCRIPT"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "sprint-bug-1" ]]
}

@test "next-id handles missing/unreachable origin/main gracefully" {
    _write_ledger 50
    _write_disk_sprint 60
    cd "$PROJECT_ROOT" && git init --quiet
    # No origin remote configured — should not fail
    run bash "$SCRIPT"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "sprint-bug-61" ]]
}

@test "next-id consults origin/main when reachable and ahead" {
    # Simulate an origin/main with a higher counter than local
    cd "$PROJECT_ROOT" && git init --quiet
    git config user.email "test@example.com"
    git config user.name "Test"

    # Create an "origin" with counter=300 (simulating someone else merged 300 bugs ahead)
    local upstream="$BATS_TEST_TMPDIR/upstream"
    mkdir -p "$upstream/grimoires/loa"
    cat > "$upstream/grimoires/loa/ledger.json" <<EOF
{"global_sprint_counter": 300, "bugfix_cycles": []}
EOF
    cd "$upstream" && git init --quiet --bare 2>/dev/null || (
        cd "$upstream" && git init --quiet
        git add -A
        git -c user.email=t@t -c user.name=t commit -q -m init
        git checkout -b main 2>/dev/null || true
    )
    cd "$PROJECT_ROOT"
    git remote add origin "$upstream" 2>/dev/null || true
    git fetch --quiet origin main 2>/dev/null || skip "could not set up upstream fetch"

    _write_ledger 50
    _write_disk_sprint 60
    run bash "$SCRIPT"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "sprint-bug-301" ]]
}

@test "next-id ignores non-bug sprint references on disk" {
    _write_ledger 50
    # Should NOT be picked up — this is not a bug-cycle dir
    mkdir -p "$PROJECT_ROOT/grimoires/loa/a2a/sprint-99"
    cat > "$PROJECT_ROOT/grimoires/loa/a2a/sprint-99/sprint.md" <<EOF
# Sprint Plan
**Sprint**: sprint-bug-9999
EOF
    cd "$PROJECT_ROOT" && git init --quiet
    run bash "$SCRIPT"
    [[ "$status" -eq 0 ]]
    # 50 + 1 = 51 (the sprint-bug-9999 reference is NOT under bug-*/, so ignored)
    [[ "$output" == "sprint-bug-51" ]]
}

@test "next-id outputs only the id, no other text" {
    _write_ledger 10
    cd "$PROJECT_ROOT" && git init --quiet
    run bash "$SCRIPT"
    [[ "$status" -eq 0 ]]
    # Output must be exactly the id, not wrapped in log lines
    [[ "$(echo "$output" | wc -l)" == "1" ]]
    [[ "$output" =~ ^sprint-bug-[0-9]+$ ]]
}

# =============================================================================
# Issue #942 — cycle-claimed global sprint ids in ledger cycles[].sprints /
# bugfix_cycles[].sprints must be consulted. Observed live 2026-06-10:
# global_sprint_counter=177 while cycle-114 claimed ids 177/178/179, so the
# helper emitted sprint-bug-178 — colliding with cycle-114's sprint-178.
# =============================================================================

@test "issue#942: cycle-claimed object-shape ids beat a stale counter (live 177-vs-179 shape)" {
    cat > "$PROJECT_ROOT/grimoires/loa/ledger.json" <<'EOF'
{
  "global_sprint_counter": 177,
  "cycles": [
    {
      "cycle_id": "cycle-114-harness-modernization",
      "sprints": [
        {"id": "sprint-177", "global_id": 177},
        {"id": "sprint-178", "global_id": 178},
        {"id": "sprint-179", "global_id": 179}
      ]
    }
  ],
  "bugfix_cycles": []
}
EOF
    cd "$PROJECT_ROOT" && git init --quiet
    run bash "$SCRIPT"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "sprint-bug-180" ]]
}

@test "issue#942: string-shape sprint claims in cycles[].sprints are consulted" {
    cat > "$PROJECT_ROOT/grimoires/loa/ledger.json" <<'EOF'
{
  "global_sprint_counter": 50,
  "cycles": [
    {"cycle_id": "cycle-x", "sprints": ["sprint-184", "sprint-bug-185"]}
  ],
  "bugfix_cycles": []
}
EOF
    cd "$PROJECT_ROOT" && git init --quiet
    run bash "$SCRIPT"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "sprint-bug-186" ]]
}

@test "issue#942: bugfix_cycles[].sprints claims are consulted too" {
    cat > "$PROJECT_ROOT/grimoires/loa/ledger.json" <<'EOF'
{
  "global_sprint_counter": 50,
  "cycles": [],
  "bugfix_cycles": [
    {"cycle_id": "cycle-bug-x", "sprints": [{"id": "sprint-bug-240", "global_id": 240}]}
  ]
}
EOF
    cd "$PROJECT_ROOT" && git init --quiet
    run bash "$SCRIPT"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "sprint-bug-241" ]]
}

@test "issue#942: malformed cycles/bugfix_cycles keys degrade gracefully to other sources" {
    cat > "$PROJECT_ROOT/grimoires/loa/ledger.json" <<'EOF'
{
  "global_sprint_counter": 50,
  "cycles": "not-an-array",
  "bugfix_cycles": [
    {"cycle_id": "ok", "sprints": [42, "weird-entry", {"id": "no-global-id"}]},
    {"cycle_id": "no-sprints-key"}
  ]
}
EOF
    cd "$PROJECT_ROOT" && git init --quiet
    run bash "$SCRIPT"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "sprint-bug-51" ]]
}

@test "issue#942: origin/main ledger's cycle claims are consulted (not just its counter)" {
    cd "$PROJECT_ROOT" && git init --quiet
    git config user.email "test@example.com"
    git config user.name "Test"

    local upstream="$BATS_TEST_TMPDIR/upstream-claims"
    mkdir -p "$upstream/grimoires/loa"
    cat > "$upstream/grimoires/loa/ledger.json" <<'EOF'
{
  "global_sprint_counter": 300,
  "cycles": [
    {"cycle_id": "cycle-y", "sprints": [{"id": "sprint-310", "global_id": 310}]}
  ],
  "bugfix_cycles": []
}
EOF
    (
        cd "$upstream" && git init --quiet
        git add -A
        git -c user.email=t@t -c user.name=t commit -q -m init
        git checkout -b main 2>/dev/null || true
    )
    cd "$PROJECT_ROOT"
    git remote add origin "$upstream" 2>/dev/null || true
    git fetch --quiet origin main 2>/dev/null || skip "could not set up upstream fetch"

    _write_ledger 50
    run bash "$SCRIPT"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "sprint-bug-311" ]]
}
