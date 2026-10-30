#!/usr/bin/env bats
# =============================================================================
# tests/unit/karpathy-surgical-diff.bats — cycle-129 sprint-256 Task 2.3
# (AC-2.3; PRD AC-4.3; SDD D-4.3, D-4.2a; DEC-0141)
#
# The surgical-diff hook keys its running total on the checkpoint task
# (`run-checkpoint.sh read --json`), else the sprint, else the session id;
# keeps one sanitised file per task under the state directory (at most 20);
# deletes the legacy session-long file; writes the summary the review's
# SURGICAL axis reads; and is silent when the knob is off. A fixture
# checkpoint (LOA_RUN_DIR) and a fake `br` on PATH stand in for a live run.
#
# cycle-138: the hook runs from a REAL mirror root under BATS_TEST_TMPDIR
# (copies of the hook, profile-lib, run-checkpoint, verdict-derive and the two
# data files; directories made under umask 022) because the trajectory append
# goes only to a directory inside the checkout (FR-6, KS-9). KS-12/KS-13 pin
# FR-5: KARPATHY_CHECKPOINT_CMD is honoured only under a bats marker.
# =============================================================================

bats_require_minimum_version 1.5.0

setup() {
    R="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    command -v jq >/dev/null 2>&1 || skip "jq not available"
    command -v yq >/dev/null 2>&1 || skip "yq not available"
    T="$BATS_TEST_TMPDIR"
    umask 022
    M="$T/root"
    mkdir -p "$M/.claude/hooks/quality" "$M/.claude/scripts/lib" "$M/.claude/data"
    cp "$R/.claude/hooks/quality/karpathy-surgical-diff-check.sh" "$M/.claude/hooks/quality/"
    cp "$R/.claude/scripts/lib/profile-lib.sh" "$M/.claude/scripts/lib/"
    cp "$R/.claude/scripts/run-checkpoint.sh" "$R/.claude/scripts/verdict-derive.sh" "$M/.claude/scripts/"
    cp "$R/.claude/data/profiles.yaml" "$R/.claude/data/floor.yaml" "$M/.claude/data/"
    HOOK="$M/.claude/hooks/quality/karpathy-surgical-diff-check.sh"
    export LOA_CONFIG_OVERRIDE="$T/config.yaml"
    export KARPATHY_STATE_DIR="$T/state"
    export KARPATHY_SUMMARY_FILE="$T/summary.json"
    export KARPATHY_LEGACY_STATE="$T/karpathy-task-state.jsonl"
    export KARPATHY_TRAJECTORY_DIR="$M/grimoires/loa/a2a/trajectory"
    export LOA_RUN_DIR="$T/run"
    unset LOA_SESSION_ID LOA_PROFILE_CONFIG_FILE LOA_PROFILE_CACHE_FILE KARPATHY_CHECKPOINT_CMD
    mkdir -p "$T/run" "$T/bin"
    printf 'karpathy_principles:\n  surgical_diff_warning: true\n  diff_lines_per_task: 5\n' > "$LOA_CONFIG_OVERRIDE"
    # Fake beads: every bead reports closed unless BR_STATUS says otherwise.
    printf '%s\n' '#!/usr/bin/env bash' 'printf "{\"status\":\"%s\"}\n" "${BR_STATUS:-closed}"' > "$T/bin/br"
    chmod +x "$T/bin/br"
    export PATH="$T/bin:$PATH"
}

# checkpoint <sprint> [task] — a schema-2 run state with that checkpoint
checkpoint() {
    jq -n --arg s "$1" --arg t "${2:-}" \
        '{schema_version: 2, state: "RUNNING",
          checkpoint: {sprint: $s, task: (if $t == "" then null else $t end), phase: "IMPLEMENT", ts: "2026-10-14T00:00:00Z"}}' \
        > "$T/run/sprint-plan-state.json"
}

# write_lines <n> [session_id] — one Write payload adding n lines
write_lines() {
    local n="$1" sid="${2:-sess-1}" content
    content=$(seq 1 "$n" | paste -sd'\n' -)
    jq -nc --arg c "$content" --arg s "$sid" \
        '{tool_name: "Write", session_id: $s, tool_input: {file_path: "/repo/src/x.sh", content: $c}}' \
        | bash "$HOOK"
}

@test "KS-1 the counter resets when the checkpoint task changes" {
    checkpoint sprint-256 bd-aaa
    write_lines 3
    write_lines 2
    [ "$(jq -r '.task' "$KARPATHY_SUMMARY_FILE")" = "bd-aaa" ]
    [ "$(jq -r '.lines' "$KARPATHY_SUMMARY_FILE")" = "5" ]
    checkpoint sprint-256 bd-bbb
    write_lines 2
    [ "$(jq -r '.task' "$KARPATHY_SUMMARY_FILE")" = "bd-bbb" ]
    [ "$(jq -r '.lines' "$KARPATHY_SUMMARY_FILE")" = "2" ]
    [ "$(jq -r '.over' "$KARPATHY_SUMMARY_FILE")" = "false" ]
    [ "$(wc -l < "$KARPATHY_STATE_DIR/bd-aaa.jsonl")" -eq 2 ]
    [ "$(wc -l < "$KARPATHY_STATE_DIR/bd-bbb.jsonl")" -eq 1 ]
    [ "$(tail -1 "$KARPATHY_STATE_DIR/bd-aaa.jsonl" | jq -r '.running_total')" = "5" ]
}

@test "KS-2 with no run in progress the key is the payload's session id, then LOA_SESSION_ID" {
    write_lines 1 "abc-123"
    [ -f "$KARPATHY_STATE_DIR/abc-123.jsonl" ]
    [ "$(jq -r '.task' "$KARPATHY_SUMMARY_FILE")" = "abc-123" ]
    jq -nc '{tool_name: "Edit", tool_input: {file_path: "/repo/a", old_string: "", new_string: "x\ny"}}' \
        | LOA_SESSION_ID=env-sess bash "$HOOK"
    [ -f "$KARPATHY_STATE_DIR/env-sess.jsonl" ]
    [ "$(jq -r '.lines' "$KARPATHY_SUMMARY_FILE")" = "2" ]
}

@test "KS-3 a checkpoint whose task is still open in beads keys on the sprint" {
    checkpoint sprint-256 bd-open
    BR_STATUS=open write_lines 2
    [ -f "$KARPATHY_STATE_DIR/sprint-256.jsonl" ]
    [ ! -e "$KARPATHY_STATE_DIR/bd-open.jsonl" ]
    # A sprint-granularity checkpoint (no task) keys on the sprint too.
    checkpoint sprint-257
    write_lines 1
    [ "$(jq -r '.task' "$KARPATHY_SUMMARY_FILE")" = "sprint-257" ]
}

@test "KS-4 the summary carries exactly task, lines, threshold, over, updated_at after each write" {
    checkpoint sprint-256 bd-sum
    write_lines 4
    run jq -c 'keys' "$KARPATHY_SUMMARY_FILE"
    [ "$output" = '["lines","over","task","threshold","updated_at"]' ]
    jq -e '.task == "bd-sum" and .lines == 4 and .threshold == 5 and .over == false
           and (.updated_at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$"))' "$KARPATHY_SUMMARY_FILE" >/dev/null
    run --separate-stderr write_lines 3
    [ "$status" -eq 0 ]
    jq -e '.lines == 7 and .over == true' "$KARPATHY_SUMMARY_FILE" >/dev/null
    # The stderr warning keeps its wording.
    [[ "$stderr" == "[karpathy-surgical-warn] Session diff total 7 lines exceeds threshold 5. Karpathy principle 3 (Surgical Changes): verify every changed line traces to the stated task. State: $KARPATHY_STATE_DIR/bd-sum.jsonl" ]]
    ls "$KARPATHY_SUMMARY_FILE".tmp.* >/dev/null 2>&1 && return 1
    true
}

@test "KS-5 the state directory keeps the 20 most recently written task files" {
    mkdir -p "$KARPATHY_STATE_DIR"
    local i
    for i in $(seq -w 1 25); do
        echo '{"lines_changed":1}' > "$KARPATHY_STATE_DIR/bd-old-$i.jsonl"
        touch -t "202601010000.$i" "$KARPATHY_STATE_DIR/bd-old-$i.jsonl"   # POSIX form: GNU and BSD touch (r256-1 LOW-3)
    done
    checkpoint sprint-256 bd-new
    write_lines 1
    [ "$(ls "$KARPATHY_STATE_DIR"/*.jsonl | wc -l)" -eq 20 ]
    [ -f "$KARPATHY_STATE_DIR/bd-new.jsonl" ]
    [ -f "$KARPATHY_STATE_DIR/bd-old-25.jsonl" ]
    [ ! -e "$KARPATHY_STATE_DIR/bd-old-06.jsonl" ]
    [ ! -e "$KARPATHY_STATE_DIR/bd-old-01.jsonl" ]
}

@test "KS-6 the legacy session-long state file is deleted on the first run" {
    printf '{"lines_changed":900,"running_total":900}\n' > "$KARPATHY_LEGACY_STATE"
    checkpoint sprint-256 bd-leg
    write_lines 1
    [ ! -e "$KARPATHY_LEGACY_STATE" ]
    # The legacy total does not leak into the new layout.
    [ "$(jq -r '.lines' "$KARPATHY_SUMMARY_FILE")" = "1" ]
}

@test "KS-7 task names are sanitised to ^[A-Za-z0-9._-]+\$ and stay inside the state directory" {
    checkpoint sprint-256 'bd-1'
    jq '.checkpoint.task = "Task 2.3: ../../evil\nname"' "$T/run/sprint-plan-state.json" > "$T/s" && mv "$T/s" "$T/run/sprint-plan-state.json"
    write_lines 1
    run ls -A "$KARPATHY_STATE_DIR"
    [ "${#lines[@]}" -eq 1 ]
    [[ "${lines[0]}" =~ ^[A-Za-z0-9._-]+\.jsonl$ ]]
    [ "${lines[0]}" = "Task_2.3__.._.._evil_name.jsonl" ]
    [ "$(find "$T" -name '*evil*' | wc -l)" -eq 1 ]
    # A leading dot cannot make a hidden (unrotated) file.
    jq '.checkpoint.task = ".hidden"' "$T/run/sprint-plan-state.json" > "$T/s" && mv "$T/s" "$T/run/sprint-plan-state.json"
    write_lines 1
    [ -f "$KARPATHY_STATE_DIR/_hidden.jsonl" ]
    [ "$(jq -r '.task' "$KARPATHY_SUMMARY_FILE")" = "_hidden" ]
}

@test "KS-8 knob off is silent: no state, no summary, no stderr" {
    printf 'karpathy_principles:\n  surgical_diff_warning: false\n  diff_lines_per_task: 1\n' > "$LOA_CONFIG_OVERRIDE"
    printf 'x\n' > "$KARPATHY_LEGACY_STATE"
    run --separate-stderr write_lines 9
    [ "$status" -eq 0 ]
    # One assertion per line: an `a && b` chain only fails when a passes and b fails (audit r256-4 MEDIUM-A1).
    [ -z "$output" ]
    [ -z "$stderr" ]
    [ ! -e "$KARPATHY_STATE_DIR" ]
    [ ! -e "$KARPATHY_SUMMARY_FILE" ]
    # The `lean` profile turns it off without the key; an explicit true wins over lean.
    printf 'loa:\n  profile: lean\nkarpathy_principles:\n  diff_lines_per_task: 1\n' > "$LOA_CONFIG_OVERRIDE"
    run --separate-stderr write_lines 9
    [ -z "$stderr" ]
    [ ! -e "$KARPATHY_SUMMARY_FILE" ]
    printf 'loa:\n  profile: lean\nkarpathy_principles:\n  surgical_diff_warning: true\n  diff_lines_per_task: 1\n' > "$LOA_CONFIG_OVERRIDE"
    run --separate-stderr write_lines 9
    [[ "$stderr" == *"[karpathy-surgical-warn]"* ]]
}

@test "KS-9 content never reaches state, summary or trajectory" {
    local secret="AKIAIOSFODNN7EXAMPLE-DO-NOT-LEAK"
    checkpoint sprint-256 bd-sec
    jq -nc --arg c "a
$secret
b
c
d
e" '{tool_name: "Write", session_id: "s", tool_input: {file_path: "/repo/x", content: $c}}' | bash "$HOOK" 2>/dev/null
    # `run` + status: a bare mid-test `! grep` is exempt from errexit and could never fail (audit r256-4 MEDIUM-A1).
    run grep -rqF "$secret" "$KARPATHY_STATE_DIR" "$KARPATHY_SUMMARY_FILE" "$KARPATHY_TRAJECTORY_DIR"
    [ "$status" -ne 0 ]
    [ -f "$KARPATHY_TRAJECTORY_DIR/karpathy-$(date -u +%Y-%m-%d).jsonl" ]
}

@test "KS-10 a symlinked state directory or task file is not written through" {
    mkdir -p "$T/elsewhere"
    ln -s "$T/elsewhere" "$KARPATHY_STATE_DIR"
    checkpoint sprint-256 bd-link
    write_lines 1
    [ -z "$(ls -A "$T/elsewhere")" ]
    rm "$KARPATHY_STATE_DIR"; mkdir -p "$KARPATHY_STATE_DIR"
    ln -s "$T/elsewhere/target" "$KARPATHY_STATE_DIR/bd-link.jsonl"
    write_lines 1
    [ ! -e "$T/elsewhere/target" ]
}

@test "KS-11 malformed or foreign payloads are a silent no-op" {
    run bash -c "printf 'not json' | '$HOOK'"
    [ "$status" -eq 0 ]
    run bash -c "printf '%s' '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls\"}}' | '$HOOK'"
    [ "$status" -eq 0 ]
    run bash -c "printf '%s' '[1,2]' | '$HOOK'"
    [ "$status" -eq 0 ]
    [ ! -e "$KARPATHY_STATE_DIR" ]
}

# cycle-138 FR-5 (DEC-1158): the checkpoint seam redirects a COMMAND, so it is honoured only under a bats
# marker (BATS_TEST_FILENAME / BATS_VERSION); outside bats it is ignored silently and the task comes from
# run-checkpoint.sh. bats exports both markers, so the "outside bats" runs drop them with env -u.
_counter_ck() {
    printf '%s\n' '#!/usr/bin/env bash' "printf 'x' >> '$T/counter'" \
        'printf "{\"checkpoint\":{\"task\":\"bd-counter\",\"sprint\":\"sprint-c\"}}\n"' > "$T/counter-ck.sh"
    chmod +x "$T/counter-ck.sh"
}
_six_lines() { jq -nc '{tool_name: "Write", session_id: "s", tool_input: {file_path: "/repo/x", content: "1\n2\n3\n4\n5\n6"}}'; }

@test "KS-12 FR-5 outside bats an exported KARPATHY_CHECKPOINT_CMD is not run; output byte-identical to a run without it" {
    _counter_ck
    checkpoint sprint-256 bd-real
    _six_lines > "$T/in.json"
    env -u BATS_TEST_FILENAME -u BATS_VERSION KARPATHY_CHECKPOINT_CMD="$T/counter-ck.sh" \
        bash "$HOOK" < "$T/in.json" > "$T/a.out" 2> "$T/a.err"
    echo $? > "$T/a.rc"
    [ ! -e "$T/counter" ]
    [ "$(jq -r '.task' "$KARPATHY_SUMMARY_FILE")" = "bd-real" ]
    cp "$KARPATHY_SUMMARY_FILE" "$T/a.summary"
    rm -rf "$KARPATHY_STATE_DIR"
    env -u BATS_TEST_FILENAME -u BATS_VERSION -u KARPATHY_CHECKPOINT_CMD \
        bash "$HOOK" < "$T/in.json" > "$T/b.out" 2> "$T/b.err"
    echo $? > "$T/b.rc"
    cmp "$T/a.out" "$T/b.out"
    cmp "$T/a.err" "$T/b.err"
    cmp "$T/a.rc" "$T/b.rc"
    [[ "$(cat "$T/a.err")" == "[karpathy-surgical-warn] Session diff total 6 lines exceeds threshold 5."* ]]
    [ "$(jq -r '.task' "$KARPATHY_SUMMARY_FILE")" = "$(jq -r '.task' "$T/a.summary")" ]
}

@test "KS-13 FR-5 with a bats marker the seam is honoured (the counter script runs and keys the task)" {
    _counter_ck
    checkpoint sprint-256 bd-real
    _six_lines > "$T/in.json"
    env -u BATS_VERSION BATS_TEST_FILENAME="$BATS_TEST_FILENAME" KARPATHY_CHECKPOINT_CMD="$T/counter-ck.sh" \
        bash "$HOOK" < "$T/in.json" 2>/dev/null
    [ "$(cat "$T/counter")" = "x" ]
    [ "$(jq -r '.task' "$KARPATHY_SUMMARY_FILE")" = "bd-counter" ]
    env -u BATS_TEST_FILENAME BATS_VERSION="${BATS_VERSION:-1.0.0}" KARPATHY_CHECKPOINT_CMD="$T/counter-ck.sh" \
        bash "$HOOK" < "$T/in.json" 2>/dev/null
    [ "$(cat "$T/counter")" = "xx" ]
}
