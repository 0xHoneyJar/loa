#!/usr/bin/env bats
# =============================================================================
# tests/unit/charting-lint.bats: decision tickets stay off the build path
# (grimoires/loa/sdd.md D-4.7, D-4.8).
#
#   create-sprint-task.sh refuses type question and a map epic before any bead
#   exists; get-ready-work.sh drops question beads whatever their labels and
#   keeps every other type; the implement path selects work through it;
#   validate-artifact.sh --type sprint flags a question bead with a sprint:
#   label or under a sprint epic; --type map checks the epic's children.
#
# Every br call goes to a PATH stub that answers from fixture files and logs
# its argv, so no beads database is touched.
# =============================================================================

setup() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    CREATE_TASK="$PROJECT_ROOT/.claude/scripts/beads/create-sprint-task.sh"
    GET_READY="$PROJECT_ROOT/.claude/scripts/beads/get-ready-work.sh"
    VALIDATE="$PROJECT_ROOT/.claude/scripts/validate-artifact.sh"
    command -v jq >/dev/null 2>&1 || skip "jq not installed"

    WORK="$(mktemp -d)"
    export BR_FIX="$WORK/fix" BR_LOG="$WORK/br.log"
    mkdir -p "$WORK/bin" "$BR_FIX" "$WORK/cwd"
    : > "$BR_LOG"
    cat > "$WORK/bin/br" <<'STUB'
#!/usr/bin/env bash
# br stub: answers from $BR_FIX, logs argv to $BR_LOG.
printf '%s\n' "$*" >> "$BR_LOG"
sub="${1:-}"; shift || true
case "$sub" in
  show)
    f="$BR_FIX/show-$1.json"
    if [[ -f "$f" ]]; then cat "$f"; else echo '{"error":"not found"}' >&2; exit 1; fi ;;
  create) echo "CREATE $*" >> "$BR_LOG"; echo '{"id":"bd-new1"}' ;;
  label) [[ "${1:-}" == list ]] && cat "$BR_FIX/labels-${2:-x}.txt" 2>/dev/null; exit 0 ;;
  dep) exit 0 ;;
  ready) cat "$BR_FIX/ready.json" ;;
  list)
    type=all
    while [[ $# -gt 0 ]]; do [[ "$1" == --type ]] && type="$2"; shift; done
    cat "$BR_FIX/list-$type.json" ;;
  *) exit 0 ;;
esac
STUB
    chmod +x "$WORK/bin/br"
    export PATH="$WORK/bin:$PATH"
    cd "$WORK/cwd"
}

teardown() {
    cd /
    rm -rf "$WORK"
}

# --- create-sprint-task.sh -----------------------------------------------------

@test "create-sprint-task: type question is refused before any br call" {
    echo '[{"id":"bd-sp","issue_type":"epic","labels":["sprint:3"]}]' > "$BR_FIX/show-bd-sp.json"
    run "$CREATE_TASK" bd-sp "Which transport?" 2 question --deps none
    [ "$status" -eq 1 ]
    [[ "$output" == *"decision tickets never go under a sprint epic; chart them with /chart"* ]]
    [ ! -s "$BR_LOG" ]
}

@test "create-sprint-task: the type check is case-insensitive" {
    run "$CREATE_TASK" bd-sp "Which transport?" 2 Question
    [ "$status" -eq 1 ]
    [[ "$output" == *"chart them with /chart"* ]]
    [ ! -s "$BR_LOG" ]
}

@test "create-sprint-task: a map-labelled epic is refused and br create never runs" {
    echo '[{"id":"bd-map","issue_type":"epic","labels":["map"]}]' > "$BR_FIX/show-bd-map.json"
    run "$CREATE_TASK" bd-map "Build the parser" 2 task --deps none
    [ "$status" -eq 1 ]
    [[ "$output" == *"bd-map is a map epic"* ]]
    [[ "$output" == *"decision tickets never go under a sprint epic; chart them with /chart"* ]]
    ! grep -q '^CREATE' "$BR_LOG"
    ! grep -q '^create' "$BR_LOG"
}

@test "create-sprint-task: labels in the older {name} object shape are read too" {
    echo '[{"id":"bd-map","issue_type":"epic","labels":[{"name":"map"}]}]' > "$BR_FIX/show-bd-map.json"
    run "$CREATE_TASK" bd-map "Build the parser" 2 task --deps none
    [ "$status" -eq 1 ]
    ! grep -q '^create' "$BR_LOG"
}

@test "create-sprint-task: an unreadable epic reply fails closed without creating" {
    echo 'not json' > "$BR_FIX/show-bd-sp.json"
    run "$CREATE_TASK" bd-sp "Build the parser" 2 task --deps none
    [ "$status" -eq 1 ]
    [[ "$output" == *"could not read the labels"* ]]
    ! grep -q '^create' "$BR_LOG"
}

@test "create-sprint-task: a task under a sprint epic is still created (control)" {
    echo '[{"id":"bd-sp","issue_type":"epic","labels":["sprint:3"]}]' > "$BR_FIX/show-bd-sp.json"
    echo 'sprint:3' > "$BR_FIX/labels-bd-sp.txt"
    run "$CREATE_TASK" bd-sp "Build the parser" 2 task --deps none
    [ "$status" -eq 0 ]
    [[ "$(echo "$output" | tail -1)" == "bd-new1" ]]
    grep -q '^create Build the parser --type task' "$BR_LOG"
    grep -q '^label add bd-new1 sprint:3' "$BR_LOG"
}

# --- get-ready-work.sh -----------------------------------------------------------

ready_fixture() {
    cat > "$BR_FIX/ready.json" <<'EOF'
[
  {"id":"bd-t1","issue_type":"task","priority":2,"title":"t"},
  {"id":"bd-b1","issue_type":"bug","priority":1,"title":"b"},
  {"id":"bd-f1","issue_type":"feature","priority":3,"title":"f"},
  {"id":"bd-c1","issue_type":"chore","priority":2,"title":"c"},
  {"id":"bd-d1","issue_type":"docs","priority":4,"title":"d"},
  {"id":"bd-q1","issue_type":"question","priority":0,"title":"q with sprint label","labels":["sprint:3","decision:grilling"]},
  {"id":"bd-q2","issue_type":"question","priority":0,"title":"q under a sprint epic","labels":["epic:bd-sp","decision:research"],"parent":"bd-sp"}
]
EOF
}

@test "get-ready-work: question beads are dropped even with a sprint: label or a sprint epic parent" {
    ready_fixture
    run "$GET_READY" 10 --ids-only
    [ "$status" -eq 0 ]
    [[ "$output" != *"bd-q1"* ]]
    [[ "$output" != *"bd-q2"* ]]
}

@test "get-ready-work: every other type present passes (task, bug, feature, chore, docs)" {
    ready_fixture
    run "$GET_READY" 10 --ids-only
    [ "$status" -eq 0 ]
    for id in bd-t1 bd-b1 bd-f1 bd-c1 bd-d1; do
        [[ "$output" == *"$id"* ]]
    done
    [ "$(echo "$output" | wc -l | tr -d ' ')" -eq 5 ]
    # priority order is unchanged by the filter
    [ "$(echo "$output" | head -1)" = "bd-b1" ]
}

@test "get-ready-work: --include-questions keeps the decision tickets" {
    ready_fixture
    run "$GET_READY" 10 --ids-only --include-questions
    [ "$status" -eq 0 ]
    [[ "$output" == *"bd-q1"* ]]
    [[ "$output" == *"bd-q2"* ]]
    [ "$(echo "$output" | wc -l | tr -d ' ')" -eq 7 ]
}

@test "get-ready-work: the limit applies after the filter (questions never take a slot)" {
    ready_fixture
    run "$GET_READY" 1 --ids-only
    [ "$status" -eq 0 ]
    [ "$output" = "bd-b1" ]
}

@test "get-ready-work: a ready set of only questions reads as no ready work" {
    echo '[{"id":"bd-q1","issue_type":"question","priority":0}]' > "$BR_FIX/ready.json"
    run "$GET_READY" 5
    [ "$status" -eq 0 ]
    [[ "$output" == *"No ready tasks available."* ]]
    run "$GET_READY" 5 --ids-only
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "get-ready-work: --include-questions is listed in the usage text" {
    run "$GET_READY" --bogus
    [ "$status" -eq 1 ]
    [[ "$output" == *"--include-questions"* ]]
}

# --- implement path ------------------------------------------------------------

@test "implement path: /implement and implementing-tasks select work through get-ready-work.sh, not bare br ready" {
    local f line
    for f in "$PROJECT_ROOT/.claude/commands/implement.md" "$PROJECT_ROOT/.claude/skills/implementing-tasks/SKILL.md"; do
        grep -q 'get-ready-work.sh' "$f"
        # the selection step names the helper; a bare `br ready` step is gone
        line="$(grep -nE 'Get Work|br sync --import-only` →' "$f" | head -1)"
        [[ "$line" == *"get-ready-work.sh"* ]]
        ! grep -qE '(→|\*\*Get Work\*\*:) `br ready`' "$f"
    done
}

# --- validate-artifact.sh --type sprint: beads cross-check -------------------------

sprint_fixture() {
    cat > "$1" <<'EOF'
## Sprint 1 (Final): Only

### Sprint Goal
g

### Deliverables
- [ ] d

### Acceptance Criteria
- [ ] c

### Technical Tasks
- [ ] Task 1.E2E: End-to-End Goal Validation → **[G-1]**

### Dependencies
- none

### Security Considerations
- none

### Risks & Mitigation
| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| r | Low | Low | m |

### Success Metrics
- m

## Appendix

| Goal ID | Goal Description | Contributing Tasks | Validation Task |
|---|---|---|---|
| G-1 | thing | Sprint 1 | Sprint 1 |
EOF
}

beads_project() {
    PROJ="$WORK/proj"
    mkdir -p "$PROJ/.beads" "$PROJ/grimoires/loa"
    sprint_fixture "$PROJ/grimoires/loa/sprint.md"
    cat > "$BR_FIX/list-epic.json" <<'EOF'
{"issues":[
  {"id":"bd-sp","issue_type":"epic","status":"open","labels":["sprint:3"]},
  {"id":"bd-map","issue_type":"epic","status":"open","labels":["map"]}
]}
EOF
}

@test "validate-artifact sprint: a question bead with a sprint: label fails the cross-check" {
    beads_project
    cat > "$BR_FIX/list-question.json" <<'EOF'
{"issues":[{"id":"bd-q1","issue_type":"question","labels":["decision:grilling","sprint:3"],"dependencies":[]}]}
EOF
    PROJECT_ROOT="$PROJ" run "$VALIDATE" --type sprint --file "$PROJ/grimoires/loa/sprint.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"question bead bd-q1 carries sprint:3"* ]]
    grep -q -- 'list --type question --limit 0 --json' "$BR_LOG"
}

@test "validate-artifact sprint: a question bead under a sprint epic fails (parent edge or epic: label)" {
    beads_project
    cat > "$BR_FIX/list-question.json" <<'EOF'
[
  {"id":"bd-q2","issue_type":"question","labels":["decision:research"],
   "dependencies":[{"issue_id":"bd-q2","depends_on_id":"bd-sp","type":"parent-child"}]},
  {"id":"bd-q3","issue_type":"question","labels":["decision:unblock","epic:bd-sp"]}
]
EOF
    PROJECT_ROOT="$PROJ" run "$VALIDATE" --type sprint --file "$PROJ/grimoires/loa/sprint.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"question bead bd-q2 sits under sprint epic bd-sp"* ]]
    [[ "$output" == *"question bead bd-q3 sits under sprint epic bd-sp"* ]]
}

@test "validate-artifact sprint: question beads under a map epic pass the cross-check" {
    beads_project
    cat > "$BR_FIX/list-question.json" <<'EOF'
{"issues":[{"id":"bd-q4","issue_type":"question","labels":["decision:grilling"],
  "dependencies":[{"issue_id":"bd-q4","depends_on_id":"bd-map","type":"parent-child"}]}]}
EOF
    PROJECT_ROOT="$PROJ" run "$VALIDATE" --type sprint --file "$PROJ/grimoires/loa/sprint.md"
    [ "$status" -eq 0 ]
}

@test "validate-artifact sprint: without .beads/ the cross-check is one info line and br is never called" {
    PROJ="$WORK/proj-nobeads"
    mkdir -p "$PROJ/grimoires/loa"
    sprint_fixture "$PROJ/grimoires/loa/sprint.md"
    PROJECT_ROOT="$PROJ" run "$VALIDATE" --type sprint --file "$PROJ/grimoires/loa/sprint.md"
    [ "$status" -eq 0 ]
    [ "$(grep -c 'beads cross-check skipped' <<< "$output")" -eq 1 ]
    [ ! -s "$BR_LOG" ]
}

@test "validate-artifact sprint: a plan outside the project is not cross-checked against its beads" {
    beads_project
    sprint_fixture "$WORK/elsewhere.md"
    PROJECT_ROOT="$PROJ" run "$VALIDATE" --type sprint --file "$WORK/elsewhere.md"
    [ "$status" -eq 0 ]
    [[ "$output" == *"beads cross-check skipped"* ]]
    [ ! -s "$BR_LOG" ]
}

# --- validate-artifact.sh --type map: beads checks -------------------------------

map_doc() {
    cat <<EOF
# Map: Ceiling arc

**Slug**: ceiling-arc
**Status**: ${1:-charting}
**Epic**: bd-map
**Created**: 2026-10-14

## Destination
The Opus ceiling is measured on every transport.

## Decisions so far
- Transport (DEC-0001, bd-c1): headless first

## Not yet specified
- retry budget

## Out of scope
- pricing: another cycle
EOF
}

map_project() {
    PROJ="$WORK/proj"
    mkdir -p "$PROJ/.beads" "$PROJ/grimoires/loa/maps"
    map_doc "${1:-charting}" > "$PROJ/grimoires/loa/maps/ceiling-arc.md"
    cat > "$PROJ/ledger.yaml" <<'EOF'
schema_version: 1
decisions:
  - id: "DEC-0001"
  - id: "DEC-0002"
EOF
    echo "[{\"id\":\"bd-map\",\"issue_type\":\"epic\",\"status\":\"${2:-open}\",\"labels\":[\"map\"]}]" > "$BR_FIX/show-bd-map.json"
}

skip_without_yq4() {
    command -v yq >/dev/null 2>&1 || skip "yq not installed"
    yq --version 2>&1 | grep -q 'mikefarah.*version v4\.' || skip "needs mikefarah yq v4"
}

run_map() {
    PROJECT_ROOT="$PROJ" run "$VALIDATE" --type map --file "$PROJ/grimoires/loa/maps/ceiling-arc.md" --ledger "$PROJ/ledger.yaml"
}

@test "validate-artifact map: question children with one decision label and a ledger external_ref pass" {
    skip_without_yq4
    map_project
    cat > "$BR_FIX/list-all.json" <<'EOF'
{"issues":[
  {"id":"bd-map","issue_type":"epic","labels":["map"]},
  {"id":"bd-c1","issue_type":"question","labels":["decision:grilling"],"external_ref":"DEC-0001",
   "dependencies":[{"issue_id":"bd-c1","depends_on_id":"bd-map","type":"parent-child"}]},
  {"id":"bd-c2","issue_type":"question","labels":["decision:research","epic:bd-map"],"external_ref":"DEC-0002"},
  {"id":"bd-other","issue_type":"task","labels":["sprint:3"]}
]}
EOF
    run_map
    [ "$status" -eq 0 ]
    grep -q -- 'list --all --limit 0 --json' "$BR_LOG"
}

@test "validate-artifact map: a non-question child, two decision labels, a sprint label and a bad external_ref each fail" {
    skip_without_yq4
    map_project
    cat > "$BR_FIX/list-all.json" <<'EOF'
{"issues":[
  {"id":"bd-t1","issue_type":"task","labels":["decision:grilling","epic:bd-map"],"external_ref":"DEC-0001"},
  {"id":"bd-c3","issue_type":"question","labels":["decision:grilling","decision:unblock","epic:bd-map"],"external_ref":"DEC-0001"},
  {"id":"bd-c4","issue_type":"question","labels":["decision:research","sprint:3","epic:bd-map"],"external_ref":"DEC-0002"},
  {"id":"bd-c5","issue_type":"question","labels":["decision:grilling","epic:bd-map"]},
  {"id":"bd-c6","issue_type":"question","labels":["decision:grilling","epic:bd-map"],"external_ref":"DEC-0099"},
  {"id":"bd-c7","issue_type":"question","labels":["decision:build","epic:bd-map"],"external_ref":"DEC-0002"}
]}
EOF
    run_map
    [ "$status" -eq 1 ]
    [[ "$output" == *"bd-t1 is a task bead under map epic bd-map"* ]]
    [[ "$output" == *"bd-c3 carries 2 decision: labels"* ]]
    [[ "$output" == *"bd-c4 carries sprint:3"* ]]
    [[ "$output" == *"bd-c5 has external_ref"* ]]
    [[ "$output" == *"bd-c6 points at DEC-0099, which is not in the decision ledger"* ]]
    [[ "$output" == *"bd-c7 carries decision:build"* ]]
}

@test "validate-artifact map: a Status that disagrees with the epic WARNs with the repair, the doc wins" {
    skip_without_yq4
    echo '{"issues":[]}' > "$BR_FIX/list-all.json"
    map_project charting closed
    run_map
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: map Status is charting but epic bd-map is closed"* ]]
    [[ "$output" == *"/chart close ceiling-arc"* ]]
    map_project abandoned open
    run_map
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: map Status is abandoned but epic bd-map is open"* ]]
    [[ "$output" == *"br close bd-map"* ]]
}

@test "validate-artifact map: with br on PATH but no .beads/ at the project root, the children check is one WARN and the doc rules still apply" {
    # The condition exercised is the missing .beads/ directory: the br stub is
    # on PATH (setup) and PATH is left alone, so jq and yq stay reachable.
    command -v br >/dev/null 2>&1
    PROJ="$WORK/proj"
    mkdir -p "$PROJ/grimoires/loa/maps"
    [ ! -d "$PROJ/.beads" ]
    map_doc > "$PROJ/grimoires/loa/maps/ceiling-arc.md"
    PROJECT_ROOT="$PROJ" run "$VALIDATE" --type map --file "$PROJ/grimoires/loa/maps/ceiling-arc.md"
    [ "$status" -eq 0 ]
    [ "$(grep -c 'WARN: beads cross-check skipped' <<< "$output")" -eq 1 ]
    # the stub logs every call: br was never invoked
    [ ! -s "$BR_LOG" ]
}
