#!/usr/bin/env bats
# RL-01/RL-03: real filesystem and jq, always invoked from a conditional caller.

setup() {
    export SCRIPT="$BATS_TEST_DIRNAME/../../.claude/scripts/ledger-lib.sh"
    export PROJECT_ROOT="$BATS_TEST_TMPDIR/project"
    export LEDGER="$PROJECT_ROOT/grimoires/loa/ledger.json"
    mkdir -p "$(dirname "$LEDGER")"
    cat > "$LEDGER" <<'JSON'
{"version":1,"next_sprint_number":3,"active_cycle":"cycle-001","cycles":[{"id":"cycle-001","status":"active","sprints":[{"global_id":1,"status":"completed"}]},{"id":"cycle-002","status":"planned","sprints":[{"global_id":2,"status":"completed"}]}]}
JSON
}

archive() {
    bash -c 'source "$SCRIPT"; if archive_cycle "$1"; then exit 0; else exit $?; fi' _ "${1:-finished}"
}

edit_ledger() {
    jq "$1" "$LEDGER" > "$BATS_TEST_TMPDIR/edit"
    mv "$BATS_TEST_TMPDIR/edit" "$LEDGER"
}

@test "RL-01: same-day same-slug cycles keep separate immutable archives" {
    mkdir -p "$PROJECT_ROOT/grimoires/loa/a2a/sprint-1"
    printf 'first PRD\n' > "$PROJECT_ROOT/grimoires/loa/prd.md"
    printf 'first SDD\n' > "$PROJECT_ROOT/grimoires/loa/sdd.md"
    printf 'first evidence\n' > "$PROJECT_ROOT/grimoires/loa/a2a/sprint-1/old.md"
    first="$(archive reused)"
    cp -r "$first" "$BATS_TEST_TMPDIR/first"
    edit_ledger '.active_cycle="cycle-002" | .cycles[1].status="active"'
    printf 'second PRD\n' > "$PROJECT_ROOT/grimoires/loa/prd.md"
    rm "$PROJECT_ROOT/grimoires/loa/sdd.md"
    mkdir -p "$PROJECT_ROOT/grimoires/loa/a2a/sprint-2"
    printf 'second evidence\n' > "$PROJECT_ROOT/grimoires/loa/a2a/sprint-2/new.md"
    second="$(archive reused)"
    diff -r "$first" "$BATS_TEST_TMPDIR/first"
    [ "$first" != "$second" ]
    [ "$(cat "$second/prd.md")" = "second PRD" ]
    [ ! -e "$second/sdd.md" ]
    [ ! -e "$second/a2a/sprint-1" ]
    [ -f "$second/a2a/sprint-2/new.md" ]
    jq -e '.active_cycle == null and (.cycles | all(.status == "archived"))' "$LEDGER"
}

@test "RL-01: existing destination is refused without ledger or archive mutation" {
    first="$(archive reused)"
    printf 'retained\n' > "$first/sentinel"
    cp -r "$first" "$BATS_TEST_TMPDIR/first"
    edit_ledger '.active_cycle="cycle-001" | .cycles[0].status="active"'
    cp "$LEDGER" "$BATS_TEST_TMPDIR/before"
    run archive reused
    [ "$status" -ne 0 ]
    cmp "$LEDGER" "$BATS_TEST_TMPDIR/before"
    diff -r "$first" "$BATS_TEST_TMPDIR/first"
}

@test "RL-01: failed copy leaves no published partial archive and permits retry" {
    printf 'artifact\n' > "$PROJECT_ROOT/grimoires/loa/prd.md"
    cp "$LEDGER" "$BATS_TEST_TMPDIR/before"
    run bash -c '
        source "$SCRIPT"
        cp() { return 73; }
        if archive_cycle failed; then exit 0; else exit $?; fi
    '
    [ "$status" -ne 0 ]
    cmp "$LEDGER" "$BATS_TEST_TMPDIR/before"
    archive_dir="$(bash -c 'source "$SCRIPT"; get_archive_dir')"
    [ -z "$(find "$archive_dir" -mindepth 1 -print)" ]
    run archive failed
    [ "$status" -eq 0 ]
    [ -f "$output/prd.md" ]
}

@test "RL-03: invalid or incomplete selected cycle preserves pointer before archive creation" {
    cp "$LEDGER" "$BATS_TEST_TMPDIR/original"
    for mutation in \
        '.active_cycle="missing"' \
        '.cycles += [.cycles[0]]' \
        '.cycles[0] |= (.cycle_id=.id | del(.id) | .sprints[0].status="in_progress")' \
        '.cycles[0].sprints=["sprint-1"]' \
        '.cycles[0].sprints=null' \
        '.active_cycle=7'; do
        cp "$BATS_TEST_TMPDIR/original" "$LEDGER"
        edit_ledger "$mutation"
        cp "$LEDGER" "$BATS_TEST_TMPDIR/before"
        run archive
        [ "$status" -ne 0 ]
        cmp "$LEDGER" "$BATS_TEST_TMPDIR/before"
        [ ! -e "$LEDGER.bak" ]
        archive_dir="$(bash -c 'source "$SCRIPT"; get_archive_dir')"
        [ ! -e "$archive_dir" ]
    done
}

@test "RL-03: cycle_id selection archives only the pointed completed cycle and its evidence" {
    edit_ledger '.cycles[0] |= (.cycle_id=.id | del(.id)) | .cycles[1].status="active"'
    mkdir -p "$PROJECT_ROOT/grimoires/loa/a2a/sprint-1"
    printf 'selected evidence\n' > "$PROJECT_ROOT/grimoires/loa/a2a/sprint-1/reviewer.md"
    run archive
    [ "$status" -eq 0 ]
    [ -f "$output/a2a/sprint-1/reviewer.md" ]
    jq -e '.active_cycle == null and .cycles[0].status == "archived" and .cycles[1].status == "active"' "$LEDGER"
}
