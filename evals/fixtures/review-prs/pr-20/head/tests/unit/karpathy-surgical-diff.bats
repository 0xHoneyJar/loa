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
# =============================================================================

bats_require_minimum_version 1.5.0

setup() {
    R="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    HOOK="$R/.claude/hooks/quality/karpathy-surgical-diff-check.sh"
    command -v jq >/dev/null 2>&1 || skip "jq not available"
    command -v yq >/dev/null 2>&1 || skip "yq not available"
    T="$BATS_TEST_TMPDIR"
    export LOA_CONFIG_OVERRIDE="$T/config.yaml"
    export KARPATHY_STATE_DIR="$T/state"
    export KARPATHY_SUMMARY_FILE="$T/summary.json"
    export KARPATHY_LEGACY_STATE="$T/karpathy-task-state.jsonl"
    export KARPATHY_TRAJECTORY_DIR="$T/trajectory"
    export LOA_RUN_DIR="$T/run"
    unset LOA_SESSION_ID LOA_PROFILE_CONFIG_FILE LOA_PROFILE_CACHE_FILE
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
        touch -d "2026-01-01 00:00:$i" "$KARPATHY_STATE_DIR/bd-old-$i.jsonl"
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
    [ -z "$output" ] && [ -z "$stderr" ]
    [ ! -e "$KARPATHY_STATE_DIR" ] && [ ! -e "$KARPATHY_SUMMARY_FILE" ]
    # The `lean` profile turns it off without the key; an explicit true wins over lean.
    printf 'loa:\n  profile: lean\nkarpathy_principles:\n  diff_lines_per_task: 1\n' > "$LOA_CONFIG_OVERRIDE"
    run --separate-stderr write_lines 9
    [ -z "$stderr" ] && [ ! -e "$KARPATHY_SUMMARY_FILE" ]
    printf 'loa:\n  profile: lean\nkarpathy_principles:\n  surgical_diff_warning: true\n  diff_lines_per_task: 1\n' > "$LOA_CONFIG_OVERRIDE"
    run --separate-stderr write_lines 9
    [[ "$stderr" == *"[karpathy-surgical-warn]"* ]]
}

@test "KS-9 content never reaches state, summary or trajectory" {
    local REDACTED-TEST-SECRET"
    checkpoint sprint-256 bd-sec
    jq -nc --arg c "a
$secret
b
c
d
e" '{tool_name: "Write", session_id: "s", tool_input: {file_path: "/repo/x", content: $c}}' | bash "$HOOK" 2>/dev/null
    ! grep -rqF "$secret" "$KARPATHY_STATE_DIR" "$KARPATHY_SUMMARY_FILE" "$KARPATHY_TRAJECTORY_DIR"
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
