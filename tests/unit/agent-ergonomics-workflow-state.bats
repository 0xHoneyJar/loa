#!/usr/bin/env bats
# =============================================================================
# tests/unit/agent-ergonomics-workflow-state.bats
# agent-ergonomics pass 1 (bd-m1o6) R-004 — completed_sprints scoped to the
# CURRENT sprint plan. Pre-fix: get_completed_sprints counted ALL historical
# a2a/sprint-* COMPLETED markers while get_total_sprints counted only the
# current sprint.md → live JSON reported completed=100/total=1 (95%).
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    WS="$PROJECT_ROOT/.claude/scripts/workflow-state.sh"
    # path-lib rejects grimoire dirs outside the workspace (security
    # boundary), so the synthetic grimoire must live INSIDE the repo —
    # same pattern as test-memory-e2e.bats (.loa-test-* under PROJECT_ROOT).
    TEST_WS="$PROJECT_ROOT/.loa-test-ws-$$"
    TMP_GRIMOIRE="$TEST_WS/grimoire"
    mkdir -p "$TMP_GRIMOIRE/a2a"

    # Current plan declares exactly 2 sprints…
    cat > "$TMP_GRIMOIRE/sprint.md" <<'EOF'
# Sprint Plan
## Sprint 1: Foundation
Tasks here.
## Sprint 2: Polish
Tasks here.
EOF
    touch "$TMP_GRIMOIRE/prd.md" "$TMP_GRIMOIRE/sdd.md"

    # …but a2a carries 5 historical completed sprint dirs.
    local i
    for i in 1 2 3 4 5; do
        mkdir -p "$TMP_GRIMOIRE/a2a/sprint-$i"
        touch "$TMP_GRIMOIRE/a2a/sprint-$i/COMPLETED"
    done
}

teardown() {
    [[ -n "${TEST_WS:-}" && -d "$TEST_WS" ]] && find "$TEST_WS" -mindepth 0 -delete 2>/dev/null || true
}

@test "R-004: completed_sprints counts only sprints in the current plan" {
    run bash -c "LOA_GRIMOIRE_DIR='$TMP_GRIMOIRE' timeout 30 bash '$WS' --json --no-cache 2>/dev/null"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r '.total_sprints')" -eq 2 ]
    [ "$(echo "$output" | jq -r '.completed_sprints')" -eq 2 ]
}

@test "R-004: completed_sprints never exceeds total_sprints" {
    run bash -c "LOA_GRIMOIRE_DIR='$TMP_GRIMOIRE' timeout 30 bash '$WS' --json --no-cache 2>/dev/null"
    [ "$status" -eq 0 ]
    local total completed
    total=$(echo "$output" | jq -r '.total_sprints')
    completed=$(echo "$output" | jq -r '.completed_sprints')
    [ "$completed" -le "$total" ]
}

@test "R-004: partial completion counts correctly (1 of 2)" {
    rm "$TMP_GRIMOIRE/a2a/sprint-2/COMPLETED"
    run bash -c "LOA_GRIMOIRE_DIR='$TMP_GRIMOIRE' timeout 30 bash '$WS' --json --no-cache 2>/dev/null"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r '.completed_sprints')" -eq 1 ]
}

@test "R-004 (fresh-eyes r2): zero-sprint plan yields total=0 completed=0, not a crash" {
    printf '# Sprint Plan\nno sprints declared yet\n' > "$TMP_GRIMOIRE/sprint.md"
    run bash -c "LOA_GRIMOIRE_DIR='$TMP_GRIMOIRE' timeout 30 bash '$WS' --json --no-cache 2>/dev/null"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r '.total_sprints')" -eq 0 ]
    [ "$(echo "$output" | jq -r '.completed_sprints')" -eq 0 ]
}

@test "r251-5 U4: --json on a cache MISS prints the JSON only — cache-manager's own status line never reaches stdout" {
    # (audit LOW-004 root cause: store_cache let `cache-manager.sh set` print "v Cached result for key: …" (green, stdout)
    # ahead of the JSON on every miss; loa-status --json fed it to jq -s → exit 5 "Invalid numeric literal at line 1,
    # column 2" on the first call after any grimoire edit. CACHE_DIR is a fresh directory: the miss is guaranteed.)
    local cache="$BATS_TEST_TMPDIR/cache-miss"
    run bash -c "CACHE_DIR='$cache' LOA_GRIMOIRE_DIR='$TMP_GRIMOIRE' timeout 30 bash '$WS' --json 2>/dev/null"
    [ "$status" -eq 0 ]
    jq -e 'type == "object" and has("state")' >/dev/null <<<"$output" || { printf 'stdout:\n%s\n' "$output" | cat -v; return 1; }
    [ -f "$cache/index.json" ] || { echo "the miss was not cached (the test did not exercise store_cache)"; return 1; }
    # and the hit that follows
    run bash -c "CACHE_DIR='$cache' LOA_GRIMOIRE_DIR='$TMP_GRIMOIRE' timeout 30 bash '$WS' --json 2>/dev/null"
    [ "$status" -eq 0 ]
    jq -e 'type == "object" and has("state")' >/dev/null <<<"$output" || { printf 'stdout:\n%s\n' "$output" | cat -v; return 1; }
}
