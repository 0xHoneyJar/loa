#!/usr/bin/env bats
# #1248: exercise real public RMW operations against isolated ledger fixtures.

setup() {
    export SCRIPT="${LEDGER_LIB_UNDER_TEST:-$BATS_TEST_DIRNAME/../../.claude/scripts/ledger-lib.sh}"
    export PROJECT_ROOT="$BATS_TEST_TMPDIR/project"
    export LEDGER="$PROJECT_ROOT/grimoires/loa/ledger.json"
    export SYNC_DIR="$BATS_TEST_TMPDIR/sync"
    mkdir -p "$(dirname "$LEDGER")" "$SYNC_DIR"
    cat > "$LEDGER" <<'JSON'
{"version":1,"created":"fixture","last_updated":"fixture","next_sprint_number":3,"active_cycle":"cycle-001","cycles":[{"id":"cycle-001","label":"original","status":"active","sprints":[{"global_id":1,"local_label":"sprint-1","status":"completed"},{"global_id":2,"local_label":"sprint-2","status":"completed"}]}]}
JSON
    # Delay only the first mutator, after the real jq has read/transformed its
    # snapshot. The second process can commit a stale competing update on the
    # old implementation; transaction locking makes it wait for the first.
    cat > "$SYNC_DIR/worker.sh" <<'SH'
#!/usr/bin/env bash
source "$SCRIPT"
jq() {
    local result arg
    result=$(command jq "$@") || return $?
    for arg in "$@"; do
        if [[ "${PAUSE_FILTER:-}" == "$arg" && -n "$arg" ]]; then
            touch "$SYNC_DIR/snapshot"
            for ((attempt=0; attempt<500; attempt++)); do
                [[ -f "$SYNC_DIR/release" ]] && break
                sleep 0.01
            done
            [[ -f "$SYNC_DIR/release" ]] || return 99
            break
        fi
    done
    printf '%s\n' "$result"
}
touch "$SYNC_DIR/$WORKER.started"
if "$@" > "$SYNC_DIR/$WORKER.stdout" 2> "$SYNC_DIR/$WORKER.stderr"; then
    echo 0 > "$SYNC_DIR/$WORKER.rc"
else
    echo "$?" > "$SYNC_DIR/$WORKER.rc"
fi
SH
}

wait_for_file() {
    for ((attempt=0; attempt<300; attempt++)); do
        [[ -f "$1" ]] && return 0
        sleep 0.01
    done
    return 1
}

# Pass first/second argument arrays and the exact jq filter at which to pause.
interleave() {
    PAUSE_FILTER="$pause_filter" WORKER=first bash "$SYNC_DIR/worker.sh" "${first[@]}" &
    local first_pid=$!
    wait_for_file "$SYNC_DIR/snapshot"
    WORKER=second bash "$SYNC_DIR/worker.sh" "${second[@]}" &
    local second_pid=$!
    wait_for_file "$SYNC_DIR/second.started"
    # A correct second transaction is blocked. An old writer completes here,
    # ensuring the first's later stale write deterministically loses its update.
    for ((attempt=0; attempt<100; attempt++)); do
        [[ -f "$SYNC_DIR/second.rc" ]] && break
        sleep 0.01
    done
    touch "$SYNC_DIR/release"
    wait "$first_pid"
    wait "$second_pid"
    [ "$(cat "$SYNC_DIR/first.rc")" = 0 ]
}

@test "#1248 concurrent cycle field changes retain both updates" {
    first=(update_cycle_field cycle-001 label first)
    second=(update_cycle_field cycle-001 sdd second.md)
    pause_filter='(.cycles[] | select(.id == $id))[$field] = $value'
    interleave
    [ "$(cat "$SYNC_DIR/second.rc")" = 0 ]
    jq -e '.cycles[0] | .label == "first" and .sdd == "second.md"' "$LEDGER"
}

@test "#1248 concurrent allocations return distinct IDs and retain both increments" {
    first=(allocate_sprint_number)
    second=(allocate_sprint_number)
    pause_filter='.next_sprint_number += 1'
    interleave
    [ "$(cat "$SYNC_DIR/second.rc")" = 0 ]
    [ "$(cat "$SYNC_DIR/first.stdout")" = 3 ]
    [ "$(cat "$SYNC_DIR/second.stdout")" = 4 ]
    jq -e '.next_sprint_number == 5' "$LEDGER"
}

@test "#1248 nested concurrent add_sprint transactions retain both records and counter" {
    first=(add_sprint sprint-3)
    second=(add_sprint sprint-4)
    pause_filter='(.cycles[] | select(.id == $cycle_id)).sprints += [$sprint]'
    interleave
    [ "$(cat "$SYNC_DIR/second.rc")" = 0 ]
    jq -e '.next_sprint_number == 5 and ([.cycles[0].sprints[].global_id] == [1,2,3,4])' "$LEDGER"
}

@test "#1248 concurrent sprint status changes retain both updates" {
    first=(update_sprint_status 1 in_progress)
    second=(update_sprint_status 2 planned)
    pause_filter='(.cycles[].sprints[]? | select(type == "object") | select(.global_id == $id)).status = $status'
    interleave
    [ "$(cat "$SYNC_DIR/second.rc")" = 0 ]
    jq -e '.cycles[0].sprints | .[0].status == "in_progress" and .[1].status == "planned"' "$LEDGER"
}

@test "#1248 concurrent create_cycle rechecks active cycle under the lock" {
    jq '.active_cycle = null | .cycles = []' "$LEDGER" > "$SYNC_DIR/empty"
    mv "$SYNC_DIR/empty" "$LEDGER"
    first=(create_cycle first)
    second=(create_cycle second)
    pause_filter='.cycles += [$cycle] | .active_cycle = $id'
    interleave
    [ "$(cat "$SYNC_DIR/second.rc")" = 1 ]
    [ ! -s "$SYNC_DIR/second.stdout" ]
    jq -e '.cycles | length == 1 and .[0].label == "first"' "$LEDGER"
}

@test "#1248 archive and add_sprint cannot discard an accepted new sprint" {
    first=(archive_cycle finished)
    second=(add_sprint sprint-3)
    pause_filter='(.cycles[] | select(.id == $id)) |= (.status = "archived" | .archived = $archived | .archive_path = $path) | .active_cycle = null'
    interleave
    [ "$(cat "$SYNC_DIR/second.rc")" = 3 ]
    [ ! -s "$SYNC_DIR/second.stdout" ]
    jq -e '.active_cycle == null and .cycles[0].status == "archived" and .next_sprint_number == 3' "$LEDGER"
}

@test "#1248 missing numeric sprint IDs return not found without writing or backing up" {
    cp "$LEDGER" "$SYNC_DIR/before"
    for new_status in planned completed; do
        run bash -c 'source "$SCRIPT"; if update_sprint_status 999 "$1"; then exit 0; else exit $?; fi' _ "$new_status"
        [ "$status" = 4 ]
        cmp "$LEDGER" "$SYNC_DIR/before"
        [ ! -e "$LEDGER.bak" ]
    done
}

@test "#1248 conditional mutators preserve write failure and do not emit success IDs" {
    cp "$LEDGER" "$SYNC_DIR/before"
    for operation in \
        'update_cycle_field cycle-001 label changed' \
        'allocate_sprint_number' \
        'add_sprint sprint-3' \
        'update_sprint_status 1 in_progress' \
        'archive_cycle done'; do
        run bash -c 'source "$SCRIPT"; _write_ledger() { return 1; }; if $1; then exit 0; else exit $?; fi' _ "$operation"
        [ "$status" = 1 ]
        [ -z "$output" ]
        cmp "$LEDGER" "$SYNC_DIR/before"
        flock -n "$LEDGER.lock" true
    done
}

@test "#1248 conditional mutator preserves jq failure without writing" {
    cp "$LEDGER" "$SYNC_DIR/before"
    run bash -c '
        source "$SCRIPT"
        jq() { return 7; }
        if update_cycle_field cycle-001 label changed; then exit 0; else exit $?; fi
    '
    [ "$status" = 1 ]
    cmp "$LEDGER" "$SYNC_DIR/before"
    [ ! -e "$LEDGER.bak" ]
    flock -n "$LEDGER.lock" true
}

@test "#1248 transaction lock preserves a caller-owned fd9 and its lock" {
    run bash -c '
        source "$SCRIPT"
        exec 9>"$SYNC_DIR/caller-fd"
        flock -x 9
        update_cycle_field cycle-001 label changed
        if flock -n "$SYNC_DIR/caller-fd" true; then exit 90; fi
        printf retained >&9
    '
    [ "$status" = 0 ]
    [ "$(cat "$SYNC_DIR/caller-fd")" = retained ]
}

@test "#1248 lock timeout fails before mutation and releases transaction descriptors" {
    cp "$LEDGER" "$SYNC_DIR/before"
    (
        flock -x 9
        touch "$SYNC_DIR/locked"
        exec sleep 30
    ) 9>"$LEDGER.lock" &
    local holder=$!
    wait_for_file "$SYNC_DIR/locked"
    run bash -c 'source "$SCRIPT"; if add_sprint sprint-3; then exit 0; else exit $?; fi'
    kill "$holder" 2>/dev/null || true
    wait "$holder" 2>/dev/null || true
    [ "$status" = 1 ]
    [[ "$output" == *"Could not acquire ledger lock"* ]]
    cmp "$LEDGER" "$SYNC_DIR/before"
    flock -n "$LEDGER.lock" true
}

@test "peer P1 scalar backup is rejected by real jq in a conditional recovery" {
    cp "$LEDGER" "$SYNC_DIR/before"
    for invalid in '42' 'null' '[]' 'true' '"text"' '' '{"other":1}' '{} {"version":1}'; do
        printf '%s' "$invalid" > "$LEDGER.bak"
        run bash -c 'source "$SCRIPT"; if recover_from_backup; then exit 0; else exit $?; fi'
        [ "$status" = 2 ]
        [[ "$output" != *"Recovered ledger"* ]]
        cmp "$LEDGER" "$SYNC_DIR/before"
        flock -n "$LEDGER.lock" true
    done
}

@test "peer P1 version lookup failure stops conditional recovery before copying" {
    cp "$LEDGER" "$LEDGER.bak"
    cp "$LEDGER" "$SYNC_DIR/before"
    run bash -c '
        source "$SCRIPT"
        jq() {
            local arg
            for arg in "$@"; do [[ "$arg" == *".version"* ]] && return 7; done
            command jq "$@"
        }
        if recover_from_backup; then exit 0; else exit $?; fi
    '
    [ "$status" = 2 ]
    cmp "$LEDGER" "$SYNC_DIR/before"
}

@test "peer P1 valid object backup still restores in a conditional caller" {
    cp "$LEDGER" "$LEDGER.bak"
    jq '.next_sprint_number = 99' "$LEDGER" > "$SYNC_DIR/edit"
    mv "$SYNC_DIR/edit" "$LEDGER"
    run bash -c 'source "$SCRIPT"; if recover_from_backup; then exit 0; else exit $?; fi'
    [ "$status" = 0 ]
    cmp "$LEDGER" "$LEDGER.bak"
}

@test "peer P2 each required artifact copy failure preserves the active ledger" {
    cp "$LEDGER" "$SYNC_DIR/before"
    for artifact in prd.md sdd.md sprint.md; do
        printf 'real artifact\n' > "$PROJECT_ROOT/grimoires/loa/$artifact"
    done
    for artifact in prd.md sdd.md sprint.md; do
        run bash -c '
            source "$SCRIPT"
            failed_artifact="$1"
            cp() {
                [[ "$1" == "$PROJECT_ROOT/grimoires/loa/$failed_artifact" ]] && return 23
                command cp "$@"
            }
            if archive_cycle "failed-$failed_artifact"; then exit 0; else exit $?; fi
        ' _ "$artifact"
        [ "$status" != 0 ]
        cmp "$LEDGER" "$SYNC_DIR/before"
        [ -f "$PROJECT_ROOT/grimoires/loa/$artifact" ]
        [ ! -e "$LEDGER.bak" ]
        flock -n "$LEDGER.lock" true
    done
}

@test "peer P2 successful conditional archive copies all current artifacts" {
    for artifact in prd.md sdd.md sprint.md; do
        printf '%s contents\n' "$artifact" > "$PROJECT_ROOT/grimoires/loa/$artifact"
    done
    run bash -c 'source "$SCRIPT"; if archive_cycle complete; then exit 0; else exit $?; fi'
    [ "$status" = 0 ]
    local archive_path="$output"
    for artifact in prd.md sdd.md sprint.md; do
        cmp "$PROJECT_ROOT/grimoires/loa/$artifact" "$archive_path/$artifact"
    done
    jq -e '.active_cycle == null and .cycles[0].status == "archived"' "$LEDGER"
}
