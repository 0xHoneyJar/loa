#!/usr/bin/env bats
# =============================================================================
# Issue #961 K-1 — Karpathy surgical-diff hook
# =============================================================================
# Pins the contract for .claude/hooks/quality/karpathy-surgical-diff-check.sh:
# fires `[karpathy-surgical-warn]` stderr line + trajectory event when the
# session diff accumulator exceeds `karpathy_principles.diff_lines_per_task`,
# while remaining non-blocking (always exits 0) per v1 invariant.
# =============================================================================

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    HOOK="$REPO_ROOT/.claude/hooks/quality/karpathy-surgical-diff-check.sh"
    [[ -x "$HOOK" ]] || skip "hook not executable"
    command -v jq >/dev/null 2>&1 || skip "jq not available"
    command -v yq >/dev/null 2>&1 || skip "yq not available"

    TMP_DIR="$(mktemp -d)"
    # cycle-129 D-4.3: per-task state under KARPATHY_STATE_DIR; with no run in
    # progress (empty LOA_RUN_DIR) the key is the session id.
    export KARPATHY_STATE_DIR="$TMP_DIR/state"
    export KARPATHY_SUMMARY_FILE="$TMP_DIR/summary.json"
    export KARPATHY_LEGACY_STATE="$TMP_DIR/legacy-task-state.jsonl"
    export LOA_RUN_DIR="$TMP_DIR/run"
    export LOA_SESSION_ID="test-session"
    KARPATHY_TASK_STATE="$KARPATHY_STATE_DIR/test-session.jsonl"
    export KARPATHY_TRAJECTORY_DIR="$TMP_DIR/trajectory"
    export LOA_CONFIG_OVERRIDE="$TMP_DIR/config.yaml"

    # Default test config — surgical_diff_warning on, threshold deliberately
    # tiny so we can trip it with a few small Write calls.
    cat > "$LOA_CONFIG_OVERRIDE" <<EOF
karpathy_principles:
  surgical_diff_warning: true
  diff_lines_per_task: 5
  enforce: warn
EOF
}

teardown() {
    rm -rf "$TMP_DIR"
}

_write_input() {
    local content="$1"
    jq -nc --arg c "$content" '{tool_name:"Write", tool_input:{file_path:"/tmp/x.txt", content:$c}}'
}

_edit_input() {
    local new="$1"
    jq -nc --arg n "$new" '{tool_name:"Edit", tool_input:{file_path:"/tmp/x.txt", old_string:"", new_string:$n}}'
}

@test "#961 K-1: hook exits 0 with no stdin (graceful degradation)" {
    run bash -c "echo '' | '$HOOK'"
    [ "$status" -eq 0 ]
}

@test "#961 K-1: hook respects surgical_diff_warning:false (no state file written)" {
    cat > "$LOA_CONFIG_OVERRIDE" <<EOF
karpathy_principles:
  surgical_diff_warning: false
EOF
    local input
    input="$(_write_input "line1
line2
line3
line4
line5
line6")"
    run bash -c "echo '$input' | '$HOOK'"
    [ "$status" -eq 0 ]
    [ ! -f "$KARPATHY_TASK_STATE" ]
}

@test "#961 K-1: hook accumulates lines across multiple invocations" {
    local input
    input="$(_write_input "a
b
c")"
    run bash -c "echo '$input' | '$HOOK'"
    [ "$status" -eq 0 ]
    [ -f "$KARPATHY_TASK_STATE" ]
    local n
    n=$(wc -l < "$KARPATHY_TASK_STATE")
    [ "$n" -eq 1 ]

    # Second invocation appends, doesn't overwrite
    run bash -c "echo '$input' | '$HOOK'"
    [ "$status" -eq 0 ]
    n=$(wc -l < "$KARPATHY_TASK_STATE")
    [ "$n" -eq 2 ]
}

@test "#961 K-1: hook emits [karpathy-surgical-warn] when threshold exceeded" {
    # threshold=5 in setup; this content has 7 lines → exceeds on first call
    local content="a
b
c
d
e
f
g"
    local input
    input="$(_write_input "$content")"
    run bash -c "echo '$input' | '$HOOK' 2>&1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[karpathy-surgical-warn]"* ]]
}

@test "#961 K-1: hook exits 0 even when warning fires (non-blocking invariant)" {
    # Even with enforce: block set, v1 hook MUST return 0
    cat > "$LOA_CONFIG_OVERRIDE" <<EOF
karpathy_principles:
  surgical_diff_warning: true
  diff_lines_per_task: 5
  enforce: block
EOF
    local content="a
b
c
d
e
f
g
h
i
j"
    local input
    input="$(_write_input "$content")"
    run bash -c "echo '$input' | '$HOOK' 2>&1"
    [ "$status" -eq 0 ]
    # Warning STILL fires (the WARN signal is the v1 deliverable)
    [[ "$output" == *"[karpathy-surgical-warn]"* ]]
}

@test "#961 K-1 NFR-Sec-1: tool_input.content NEVER appears in state or trajectory" {
    # The hook MUST log only line counts + file paths, not the content itself.
    # This regression guard prevents secrets in code snippets from leaking
    # into the per-task state (.run/karpathy-surgical/) or the trajectory file.
    local secret="AKIAIOSFODNN7EXAMPLE-DO-NOT-LEAK"
    local content="line1
${secret}
line3
line4
line5
line6
line7"
    local input
    input="$(_write_input "$content")"
    run bash -c "echo '$input' | '$HOOK' 2>&1"
    [ "$status" -eq 0 ]

    # Secret MUST NOT appear in state or trajectory
    if [[ -f "$KARPATHY_TASK_STATE" ]]; then
        ! grep -qF "$secret" "$KARPATHY_TASK_STATE"
    fi
    if [[ -d "$KARPATHY_TRAJECTORY_DIR" ]]; then
        ! grep -rqF "$secret" "$KARPATHY_TRAJECTORY_DIR"
    fi
}

# =============================================================================
# Sprint 286 audit round 1 (DISS-C-001 / DISS-C-002, bd-ooymp): the summary's
# temp file and the state directory.
#
# The summary used to be written with `printf … > "$SUMMARY.tmp.$$"` after a
# `-d` test on its directory alone. `>` is open(O_WRONLY|O_CREAT|O_TRUNC): it
# follows a symlink planted at that predictable name — open(2) refuses a
# symlink "regardless of where the symbolic link points" only for
# O_CREAT|O_EXCL — and `mv -f` then renamed the planted link over the summary
# path (rename(2): "if oldpath refers to a symbolic link, the link is renamed").
# The fixed hook admits the directory only as a real uid-owned non-symlink
# directory, requires the temp name to be truly absent (lstat and stat), opens
# it under noclobber (bash's noclobber_open: stat fails → O_CREAT|O_EXCL), and
# re-checks the path before the rename; any refusal skips the summary silently.
#
# The hook's pid is made known to the test by a wrapper that plants the entry
# under its own $$ and then `exec`s the hook — the exec'd bash keeps the pid.
# =============================================================================

# _run_hook_planted <planter snippet> <payload>
# The snippet runs in the wrapper with T="<summary>.tmp.<pid>" and V="$VICTIM";
# the wrapper records its pid in $TMP_DIR/pid (HOOK_PID) and execs the hook.
_run_hook_planted() {
    printf '%s' "$2" > "$TMP_DIR/in.json"
    run bash -c 'T="$1.tmp.$$"; V="$2"; echo "$$" > "$3/pid"; eval "$4"; exec bash "$0" < "$3/in.json"' \
        "$HOOK" "$KARPATHY_SUMMARY_FILE" "$VICTIM" "$TMP_DIR" "$1"
    HOOK_PID="$(cat "$TMP_DIR/pid")"
}

@test "KS-14 Sprint 286 audit DISS-C-001: a symlink planted at the summary temp name <summary>.tmp.<pid> is not followed — the victim keeps its bytes and the summary never becomes the link" {
    VICTIM="$TMP_DIR/victim.json"
    printf 'victim-bytes\n' > "$VICTIM"
    _run_hook_planted 'ln -s "$V" "$T"' "$(_write_input "a
b")"
    [ "$status" -eq 0 ]
    [ "$(cat "$VICTIM")" = "victim-bytes" ]
    [ ! -L "$KARPATHY_SUMMARY_FILE" ]
    [ ! -e "$KARPATHY_SUMMARY_FILE" ]
    # the planted entry is left where it was (it was never ours to remove) …
    [ -L "$KARPATHY_SUMMARY_FILE.tmp.$HOOK_PID" ]
    # … and the per-task append is unaffected by the refused summary
    [ -f "$KARPATHY_TASK_STATE" ]
}

@test "KS-15 Sprint 286 audit DISS-C-001: a DANGLING symlink planted at the temp name creates nothing at its target and is not renamed over the summary" {
    mkdir "$TMP_DIR/outside"
    VICTIM="$TMP_DIR/outside/created-by-hook"
    _run_hook_planted 'ln -s "$V" "$T"' "$(_write_input "a
b")"
    [ "$status" -eq 0 ]
    [ ! -e "$VICTIM" ]
    [ ! -L "$KARPATHY_SUMMARY_FILE" ]
    [ ! -e "$KARPATHY_SUMMARY_FILE" ]
    [ -L "$KARPATHY_SUMMARY_FILE.tmp.$HOOK_PID" ]
}

@test "KS-16 Sprint 286 audit DISS-C-001: a regular file already at the temp name is not ours — not truncated, not renamed over the summary (the name must be truly absent: O_CREAT|O_EXCL under noclobber)" {
    VICTIM="$TMP_DIR/unused"
    _run_hook_planted 'printf "planted\n" > "$T"' "$(_write_input "a
b")"
    [ "$status" -eq 0 ]
    [ -f "$KARPATHY_SUMMARY_FILE.tmp.$HOOK_PID" ]
    [ "$(cat "$KARPATHY_SUMMARY_FILE.tmp.$HOOK_PID")" = "planted" ]
    [ ! -e "$KARPATHY_SUMMARY_FILE" ]
}

@test "KS-17 Sprint 286 audit DISS-C-002: the summary's directory must be a real uid-owned directory — a symlinked directory is refused, nothing lands in its target, the per-task append still happens" {
    mkdir "$TMP_DIR/real-run"
    ln -s "$TMP_DIR/real-run" "$TMP_DIR/run-link"
    export KARPATHY_SUMMARY_FILE="$TMP_DIR/run-link/summary.json"
    local input
    input="$(_write_input "a
b")"
    run bash -c "echo '$input' | '$HOOK'"
    [ "$status" -eq 0 ]
    [ ! -e "$TMP_DIR/real-run/summary.json" ]
    [ -z "$(ls -A "$TMP_DIR/real-run")" ]
    [ -f "$KARPATHY_TASK_STATE" ]
}

@test "KS-18 the clean path still writes the summary: a regular non-symlink file with task/lines/threshold/over/updated_at, no temp left behind, exit 0" {
    local input
    input="$(_write_input "a
b")"
    run bash -c "echo '$input' | '$HOOK'"
    [ "$status" -eq 0 ]
    [ -f "$KARPATHY_SUMMARY_FILE" ]
    [ ! -L "$KARPATHY_SUMMARY_FILE" ]
    jq -e '.task == "test-session" and .lines == 2 and .over == false and (.threshold | type) == "number" and (.updated_at | type) == "string"' "$KARPATHY_SUMMARY_FILE"
    run bash -c "ls -A '$TMP_DIR' | grep -F 'summary.json.tmp.'"
    [ "$status" -ne 0 ]
}
