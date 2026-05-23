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
    export KARPATHY_TASK_STATE="$TMP_DIR/task-state.jsonl"
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
    # into .run/karpathy-task-state.jsonl or the trajectory file.
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
