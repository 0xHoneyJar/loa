#!/usr/bin/env bats
# workflow-position-drift.bats — OKF/ICM cycle Sprint 7 (R8) MANDATORY drift-repro.
#
# Contract (grimoires/loa/runbooks/workflow-position-authority.md): filesystem
# markers (COMPLETED / auditor APPROVED / PRD·SDD·sprint.md presence) are
# AUTHORITATIVE for workflow POSITION; .run/sprint-plan-state.json position fields
# are a DERIVED CACHE that may be stale; circuit-breaker / autonomy counters remain
# first-class .run state with no filesystem analog.
#
# This reproduces the documented RUNNING-while-committed drift: .run says
# state=RUNNING / completed=0 while every sprint has landed (COMPLETED+APPROVED on
# disk). The position resolver (golden-path.sh) must report from the filesystem
# (all complete), and must NOT touch the circuit-breaker counters.

setup() {
    TEST_DIR=$(mktemp -d)
    export PROJECT_ROOT="$TEST_DIR"
    export LOA_USE_LEGACY_PATHS=1
    mkdir -p "$TEST_DIR/.claude/scripts" "$TEST_DIR/grimoires/loa/a2a" "$TEST_DIR/.run"
    REAL_SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.claude/scripts" && pwd)"
    for s in bootstrap.sh path-lib.sh compat-lib.sh golden-path.sh; do
        cp "$REAL_SCRIPT_DIR/$s" "$TEST_DIR/.claude/scripts/"
    done
    (cd "$TEST_DIR" && git init -q 2>/dev/null)
    # 3-sprint plan + full planning artifacts (PRD/SDD/sprint.md present => phase complete)
    : > "$TEST_DIR/grimoires/loa/prd.md"
    : > "$TEST_DIR/grimoires/loa/sdd.md"
    printf '## Sprint 1\n## Sprint 2\n## Sprint 3\n' > "$TEST_DIR/grimoires/loa/sprint.md"
    local i
    for i in 1 2 3; do
        mkdir -p "$TEST_DIR/grimoires/loa/a2a/sprint-$i"
        : > "$TEST_DIR/grimoires/loa/a2a/sprint-$i/COMPLETED"
        printf '# Audit\nAPPROVED\n' > "$TEST_DIR/grimoires/loa/a2a/sprint-$i/auditor-sprint-feedback.md"
    done
    # STALE .run cache: says RUNNING with 0 completed (the drift)
    cat > "$TEST_DIR/.run/sprint-plan-state.json" <<'EOF'
{"state":"RUNNING","sprints":{"total":3,"completed":0,"current":"sprint-1","list":[{"id":"sprint-1","status":"running"},{"id":"sprint-2","status":"pending"},{"id":"sprint-3","status":"pending"}]}}
EOF
    # first-class autonomy counter (no filesystem analog — must be preserved untouched)
    cat > "$TEST_DIR/.run/circuit-breaker-cycle.json" <<'EOF'
{"trigger_count":3,"history":["t1","t2","t3"],"max_cycles":10}
EOF
    cd "$TEST_DIR"
    source "$TEST_DIR/.claude/scripts/golden-path.sh"
}

teardown() { rm -rf "$TEST_DIR"; }

@test "position-drift: filesystem markers win — all-COMPLETED reads as done despite .run RUNNING/0" {
    # golden-path resolves position from COMPLETED markers, not the stale RUNNING cache
    run golden_detect_sprint
    [ "$status" -eq 0 ]
    [ -z "$output" ]   # all three sprints complete on disk => no current sprint
}

@test "position-drift: planning phase is 'complete' from PRD/SDD/sprint.md presence" {
    run golden_detect_plan_phase
    [ "$status" -eq 0 ]
    [ "$output" = "complete" ]
}

@test "position-drift: removing a COMPLETED marker moves position to that sprint (filesystem drives both ways)" {
    rm -f "$PROJECT_ROOT/grimoires/loa/a2a/sprint-2/COMPLETED"
    run golden_detect_sprint
    [ "$status" -eq 0 ]
    [ "$output" = "sprint-2" ]   # filesystem says sprint-2 incomplete, regardless of .run
}

@test "position-drift: the resolver never reads .run/sprint-plan-state.json for position" {
    # the cache claims completed=0/RUNNING; if it were consulted, position would differ.
    # Independently assert golden-path.sh has no code path reading that file.
    ! grep -q 'sprint-plan-state.json' "$PROJECT_ROOT/.claude/scripts/golden-path.sh"
}

@test "position-drift: circuit-breaker / autonomy counters are preserved untouched" {
    local before; before="$(sha256sum "$PROJECT_ROOT/.run/circuit-breaker-cycle.json" | cut -d' ' -f1)"
    golden_detect_sprint >/dev/null
    golden_detect_plan_phase >/dev/null
    golden_detect_review_target >/dev/null 2>&1 || true
    local after; after="$(sha256sum "$PROJECT_ROOT/.run/circuit-breaker-cycle.json" | cut -d' ' -f1)"
    [ "$before" = "$after" ]
    # counter content intact
    grep -q '"trigger_count":3' "$PROJECT_ROOT/.run/circuit-breaker-cycle.json"
}
