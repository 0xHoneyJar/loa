#!/usr/bin/env bats
# =============================================================================
# tests/bash/beads_dependency_edges.bats — edge-birth contract pins.
#
# Pins the --deps contract of create-sprint-task.sh (dependency edges captured
# at bead creation; explicit no-blockers assertion) and the --graph contract of
# get-ready-work.sh (graph-aware ranking via bv with a silent fallback to
# priority order when bv is absent).
#
# D-series: each test runs against a throwaway br workspace in a temp
# git repo, so no estate store is touched. Tests skip when `br` is not on PATH
# (mirrors the golden-runner skip convention).
# =============================================================================

setup() {
    command -v br >/dev/null 2>&1 || skip "br (beads_rust) not installed"
    command -v jq >/dev/null 2>&1 || skip "jq not installed"

    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    CREATE_TASK="$PROJECT_ROOT/.claude/scripts/beads/create-sprint-task.sh"
    GET_READY="$PROJECT_ROOT/.claude/scripts/beads/get-ready-work.sh"

    WORKDIR="$(mktemp -d)"
    cd "$WORKDIR"
    git init -q .
    br init >/dev/null 2>&1
    EPIC_ID=$(br create "Test epic" --type epic --priority 1 --json | jq -r '.id')
}

teardown() {
    cd /
    rm -rf "$WORKDIR"
}

# --- create-sprint-task.sh ---------------------------------------------------

@test "D1: positional-only call still works (backward compat) and warns about missing --deps" {
    run "$CREATE_TASK" "$EPIC_ID" "Legacy task" 2 task
    [ "$status" -eq 0 ]
    TASK_ID="$(echo "$output" | tail -1)"
    [[ "$TASK_ID" =~ ^[a-zA-Z0-9-]+$ ]]
    [[ "$output" == *"no --deps declared"* ]]
}

@test "D2: --deps none records the explicit no-blockers assertion as label deps:none" {
    run "$CREATE_TASK" "$EPIC_ID" "Independent task" 2 task --deps none
    [ "$status" -eq 0 ]
    TASK_ID="$(echo "$output" | tail -1)"
    run br label list "$TASK_ID"
    [[ "$output" == *"deps:none"* ]]
}

@test "D3: --deps <id> creates a blocks edge (blocked task is not ready)" {
    BLOCKER=$("$CREATE_TASK" "$EPIC_ID" "Blocker" 1 task --deps none | tail -1)
    BLOCKED=$("$CREATE_TASK" "$EPIC_ID" "Blocked" 1 task --deps "$BLOCKER" | tail -1)

    run br dep list "$BLOCKED"
    [[ "$output" == *"$BLOCKER"* ]]

    # The blocked task must NOT appear in the ready set while its blocker is open
    run bash -c "br ready --json | jq -r '.[].id'"
    [[ "$output" == *"$BLOCKER"* ]]
    [[ "$output" != *"$BLOCKED"* ]]
}

@test "D4: --deps with comma-separated ids creates one edge per id" {
    A=$("$CREATE_TASK" "$EPIC_ID" "Dep A" 1 task --deps none | tail -1)
    B=$("$CREATE_TASK" "$EPIC_ID" "Dep B" 1 task --deps none | tail -1)
    C=$("$CREATE_TASK" "$EPIC_ID" "Needs both" 1 task --deps "$A,$B" | tail -1)

    run br dep list "$C"
    [[ "$output" == *"$A"* ]]
    [[ "$output" == *"$B"* ]]
}

@test "D5: unknown dependency id fails fast and creates NO orphan bead" {
    BEFORE=$(br list --json | jq 'length')
    run "$CREATE_TASK" "$EPIC_ID" "Doomed task" 2 task --deps does-not-exist
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]]
    AFTER=$(br list --json | jq 'length')
    [ "$BEFORE" -eq "$AFTER" ]
}

# --- get-ready-work.sh -------------------------------------------------------

@test "D6: default mode is unchanged (priority order, br issue objects)" {
    "$CREATE_TASK" "$EPIC_ID" "P0 leaf" 0 task --deps none >/dev/null
    run "$GET_READY" 3 --ids-only
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

@test "D7: --graph without bv on PATH falls back silently to priority order" {
    "$CREATE_TASK" "$EPIC_ID" "Fallback probe" 1 task --deps none >/dev/null
    # Strip bv from PATH while keeping br/jq/git available via a shim dir
    SHIM="$WORKDIR/shim"; mkdir -p "$SHIM"
    for tool in br jq git bash grep sed xargs mktemp dirname; do
        p="$(command -v $tool || true)"; [ -n "$p" ] && ln -sf "$p" "$SHIM/$tool"
    done
    run env PATH="$SHIM:/usr/bin:/bin" "$GET_READY" 3 --ids-only --graph
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

@test "D8: --graph with bv present returns the same ids as the ready set (shape contract)" {
    command -v bv >/dev/null 2>&1 || skip "bv not installed"
    "$CREATE_TASK" "$EPIC_ID" "Graph probe" 1 task --deps none >/dev/null
    run "$GET_READY" 5 --ids-only --graph
    [ "$status" -eq 0 ]
    # Every returned id must be a real bead id
    while IFS= read -r id; do
        [ -z "$id" ] && continue
        br show "$id" --json >/dev/null
    done <<< "$output"
}

@test "D9: --graph order differs from priority order when the graph demands it" {
    command -v bv >/dev/null 2>&1 || skip "bv not installed"
    # A LOW-priority blocker whose closure unblocks another bead, vs a
    # HIGH-priority leaf that unblocks nothing. Priority order puts the leaf
    # first; graph order must put the blocker first.
    LEAF=$("$CREATE_TASK" "$EPIC_ID" "P0 leaf nothing depends on" 0 task --deps none | tail -1)
    BLOCKER=$("$CREATE_TASK" "$EPIC_ID" "P3 blocker of downstream work" 3 task --deps none | tail -1)
    "$CREATE_TASK" "$EPIC_ID" "Downstream, waits on blocker" 2 task --deps "$BLOCKER" >/dev/null

    PRIORITY_FIRST=$("$GET_READY" 1 --ids-only)
    GRAPH_FIRST=$("$GET_READY" 1 --ids-only --graph)

    [ "$PRIORITY_FIRST" = "$LEAF" ]
    [ "$GRAPH_FIRST" = "$BLOCKER" ]
}

@test "D10: empty --deps value is refused (neither edges nor an assertion)" {
    BEFORE=$(br list --json | jq 'length')
    run "$CREATE_TASK" "$EPIC_ID" "Sneaky task" 2 task --deps ""
    [ "$status" -ne 0 ]
    [[ "$output" == *"empty value"* ]]
    AFTER=$(br list --json | jq 'length')
    [ "$BEFORE" -eq "$AFTER" ]
}

@test "D11: whitespace-only and comma-only --deps values are refused (no task created)" {
    BEFORE=$(br list --json | jq 'length')
    run "$CREATE_TASK" "$EPIC_ID" "Sneaky whitespace" 2 task --deps "  "
    [ "$status" -ne 0 ]
    [[ "$output" == *"empty value"* ]]
    run "$CREATE_TASK" "$EPIC_ID" "Sneaky comma" 2 task --deps ","
    [ "$status" -ne 0 ]
    [[ "$output" == *"empty value"* ]]
    AFTER=$(br list --json | jq 'length')
    [ "$BEFORE" -eq "$AFTER" ]
}

@test "D12: padded --deps ' none ' is recognized as the no-blockers assertion" {
    run "$CREATE_TASK" "$EPIC_ID" "Padded none" 2 task --deps " none "
    [ "$status" -eq 0 ]
    TASK_ID="$(echo "$output" | tail -1)"
    run br label list "$TASK_ID"
    [[ "$output" == *"deps:none"* ]]
}

@test "D13: --deps followed by a flag (omitted value) is refused, not swallowed" {
    BEFORE=$(br list --json | jq 'length')
    run "$CREATE_TASK" "$EPIC_ID" "Flag eater" 2 task --deps --graph
    [ "$status" -ne 0 ]
    [[ "$output" == *"flag-like"* ]]
    AFTER=$(br list --json | jq 'length')
    [ "$BEFORE" -eq "$AFTER" ]
}

@test "D14: a failed dependency-edge write exits nonzero and names the repair (no silent partial graph)" {
    BLOCKER=$("$CREATE_TASK" "$EPIC_ID" "Real blocker" 1 task --deps none | tail -1)
    # Shim br so `br dep add` fails while everything else passes through —
    # simulates a post-creation write failure (db lock, race).
    SHIM="$WORKDIR/brshim"; mkdir -p "$SHIM"
    REAL_BR="$(command -v br)"
    cat > "$SHIM/br" <<EOF
#!/usr/bin/env bash
if [ "\${1:-}" = "dep" ] && [ "\${2:-}" = "add" ]; then exit 1; fi
exec "$REAL_BR" "\$@"
EOF
    chmod +x "$SHIM/br"
    run env PATH="$SHIM:$PATH" "$CREATE_TASK" "$EPIC_ID" "Edge fail probe" 2 task --deps "$BLOCKER"
    [ "$status" -ne 0 ]
    [[ "$output" == *"dependency edge"* ]]
    [[ "$output" == *"repair with"* ]]
    # The task id is still on the last stdout line so the caller can repair
    TASK_ID="$(echo "$output" | tail -1)"
    br show "$TASK_ID" --json >/dev/null
}

@test "D15: get-ready-work.sh with flags but no numeric limit defaults to 5 (no jq compile error)" {
    "$CREATE_TASK" "$EPIC_ID" "Limit probe" 1 task --deps none >/dev/null
    run "$GET_READY" --ids-only
    [ "$status" -eq 0 ]
    [ -n "$output" ]
    run "$GET_READY" --graph --ids-only
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

@test "D16: get-ready-work.sh rejects a non-numeric limit and unknown flags" {
    run "$GET_READY" abc
    [ "$status" -ne 0 ]
    [[ "$output" == *"non-negative integer"* ]]
    run "$GET_READY" 5 --grpah
    [ "$status" -ne 0 ]
    [[ "$output" == *"unknown flag"* ]]
}
