#!/usr/bin/env bats
# Unit tests for thinking-logger.sh
# Part of Sprint 2: Structured Outputs & Extended Thinking

setup() {
    # Create temp directory for test files
    export TEST_DIR="$BATS_TMPDIR/thinking-logger-test-$$"
    mkdir -p "$TEST_DIR/trajectory"

    # Script path
    export SCRIPT="$BATS_TEST_DIRNAME/../../.claude/scripts/thinking-logger.sh"

    # Create test trajectory file
    cat > "$TEST_DIR/trajectory/test-agent-2025-01-11.jsonl" << 'EOF'
{"ts": "2025-01-11T10:00:00Z", "agent": "implementing-tasks", "action": "Created file", "phase": "implementation"}
{"ts": "2025-01-11T10:01:00Z", "agent": "implementing-tasks", "action": "Updated model", "phase": "implementation"}
{"ts": "2025-01-11T10:02:00Z", "agent": "reviewing-code", "action": "Reviewed changes", "phase": "review"}
EOF
}

teardown() {
    rm -rf "$TEST_DIR"
}

# =============================================================================
# Basic Command Tests
# =============================================================================

@test "thinking-logger: shows usage with no arguments" {
    run "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "thinking-logger: shows help with --help" {
    run "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Commands:"* ]]
    [[ "$output" == *"log"* ]]
    [[ "$output" == *"read"* ]]
    [[ "$output" == *"validate"* ]]
}

@test "thinking-logger: shows help with -h" {
    run "$SCRIPT" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "thinking-logger: rejects unknown command" {
    run "$SCRIPT" unknown
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown command"* ]]
}

# =============================================================================
# Log Command Tests - Basic
# =============================================================================

@test "thinking-logger log: requires --agent" {
    run "$SCRIPT" log --action "Test action"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Agent name is required"* ]]
}

@test "thinking-logger log: requires --action" {
    run "$SCRIPT" log --agent "test-agent"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Action is required"* ]]
}

@test "thinking-logger log: creates entry with required fields" {
    run "$SCRIPT" log --agent "implementing-tasks" --action "Created model" --output "$TEST_DIR/output.jsonl"
    [ "$status" -eq 0 ]
    [ -f "$TEST_DIR/output.jsonl" ]

    # Verify JSON structure
    entry=$(cat "$TEST_DIR/output.jsonl")
    echo "$entry" | jq -e '.ts' > /dev/null
    echo "$entry" | jq -e '.agent == "implementing-tasks"'
    echo "$entry" | jq -e '.action == "Created model"'
}

@test "thinking-logger log: includes optional phase" {
    run "$SCRIPT" log --agent "implementing-tasks" --action "Test" --phase "implementation" --output "$TEST_DIR/output.jsonl"
    [ "$status" -eq 0 ]

    entry=$(cat "$TEST_DIR/output.jsonl")
    echo "$entry" | jq -e '.phase == "implementation"'
}

@test "thinking-logger log: includes optional reasoning" {
    run "$SCRIPT" log --agent "implementing-tasks" --action "Test" --reasoning "Because of X" --output "$TEST_DIR/output.jsonl"
    [ "$status" -eq 0 ]

    entry=$(cat "$TEST_DIR/output.jsonl")
    echo "$entry" | jq -e '.reasoning == "Because of X"'
}

# =============================================================================
# Log Command Tests - Extended Thinking
# =============================================================================

@test "thinking-logger log: --thinking enables thinking trace" {
    run "$SCRIPT" log --agent "designing-architecture" --action "Evaluated" --thinking --output "$TEST_DIR/output.jsonl"
    [ "$status" -eq 0 ]

    entry=$(cat "$TEST_DIR/output.jsonl")
    echo "$entry" | jq -e '.thinking_trace.enabled == true'
}

@test "thinking-logger log: --think-step adds thinking steps" {
    run "$SCRIPT" log \
        --agent "designing-architecture" \
        --action "Evaluated patterns" \
        --think-step "1:analysis:Consider options" \
        --think-step "2:decision:Chose monolith" \
        --output "$TEST_DIR/output.jsonl"
    [ "$status" -eq 0 ]

    entry=$(cat "$TEST_DIR/output.jsonl")
    echo "$entry" | jq -e '.thinking_trace.steps | length == 2'
    echo "$entry" | jq -e '.thinking_trace.steps[0].step == 1'
    echo "$entry" | jq -e '.thinking_trace.steps[0].type == "analysis"'
    echo "$entry" | jq -e '.thinking_trace.steps[1].step == 2'
    echo "$entry" | jq -e '.thinking_trace.steps[1].type == "decision"'
}

@test "thinking-logger log: think-step without type is valid" {
    run "$SCRIPT" log \
        --agent "implementing-tasks" \
        --action "Test" \
        --think-step "1::Just a thought" \
        --output "$TEST_DIR/output.jsonl"
    [ "$status" -eq 0 ]

    entry=$(cat "$TEST_DIR/output.jsonl")
    echo "$entry" | jq -e '.thinking_trace.steps[0].step == 1'
}

# =============================================================================
# Log Command Tests - Grounding
# =============================================================================

@test "thinking-logger log: --grounding adds grounding type" {
    run "$SCRIPT" log \
        --agent "reviewing-code" \
        --action "Found issue" \
        --grounding "code_reference" \
        --output "$TEST_DIR/output.jsonl"
    [ "$status" -eq 0 ]

    entry=$(cat "$TEST_DIR/output.jsonl")
    echo "$entry" | jq -e '.grounding.type == "code_reference"'
}

@test "thinking-logger log: --ref adds reference" {
    run "$SCRIPT" log \
        --agent "reviewing-code" \
        --action "Found issue" \
        --grounding "code_reference" \
        --ref "src/db.ts:45-50" \
        --output "$TEST_DIR/output.jsonl"
    [ "$status" -eq 0 ]

    entry=$(cat "$TEST_DIR/output.jsonl")
    echo "$entry" | jq -e '.grounding.refs[0].file == "src/db.ts"'
    echo "$entry" | jq -e '.grounding.refs[0].lines == "45-50"'
}

@test "thinking-logger log: --confidence adds confidence" {
    run "$SCRIPT" log \
        --agent "reviewing-code" \
        --action "Found issue" \
        --grounding "inference" \
        --confidence 0.85 \
        --output "$TEST_DIR/output.jsonl"
    [ "$status" -eq 0 ]

    entry=$(cat "$TEST_DIR/output.jsonl")
    echo "$entry" | jq -e '.grounding.confidence == 0.85'
}

@test "thinking-logger log: multiple --ref options work" {
    run "$SCRIPT" log \
        --agent "auditing-security" \
        --action "Checked auth" \
        --grounding "code_reference" \
        --ref "src/auth.ts:10-20" \
        --ref "src/middleware.ts:5-15" \
        --output "$TEST_DIR/output.jsonl"
    [ "$status" -eq 0 ]

    entry=$(cat "$TEST_DIR/output.jsonl")
    echo "$entry" | jq -e '.grounding.refs | length == 2'
}

# =============================================================================
# Log Command Tests - Context
# =============================================================================

@test "thinking-logger log: --sprint adds sprint context" {
    run "$SCRIPT" log \
        --agent "implementing-tasks" \
        --action "Test" \
        --sprint "sprint-2" \
        --output "$TEST_DIR/output.jsonl"
    [ "$status" -eq 0 ]

    entry=$(cat "$TEST_DIR/output.jsonl")
    echo "$entry" | jq -e '.context.sprint_id == "sprint-2"'
}

@test "thinking-logger log: --task adds task context" {
    run "$SCRIPT" log \
        --agent "implementing-tasks" \
        --action "Test" \
        --task "TASK-2.6" \
        --output "$TEST_DIR/output.jsonl"
    [ "$status" -eq 0 ]

    entry=$(cat "$TEST_DIR/output.jsonl")
    echo "$entry" | jq -e '.context.task_id == "TASK-2.6"'
}

# =============================================================================
# Log Command Tests - Outcome
# =============================================================================

@test "thinking-logger log: --status adds outcome status" {
    run "$SCRIPT" log \
        --agent "implementing-tasks" \
        --action "Test" \
        --status "success" \
        --output "$TEST_DIR/output.jsonl"
    [ "$status" -eq 0 ]

    entry=$(cat "$TEST_DIR/output.jsonl")
    echo "$entry" | jq -e '.outcome.status == "success"'
}

@test "thinking-logger log: --result adds outcome result" {
    run "$SCRIPT" log \
        --agent "implementing-tasks" \
        --action "Test" \
        --status "success" \
        --result "Created 5 files" \
        --output "$TEST_DIR/output.jsonl"
    [ "$status" -eq 0 ]

    entry=$(cat "$TEST_DIR/output.jsonl")
    echo "$entry" | jq -e '.outcome.result == "Created 5 files"'
}

# =============================================================================
# Read Command Tests
# =============================================================================

@test "thinking-logger read: requires file argument" {
    run "$SCRIPT" read
    [ "$status" -eq 1 ]
    [[ "$output" == *"No file specified"* ]]
}

@test "thinking-logger read: reports missing file" {
    run "$SCRIPT" read "$TEST_DIR/nonexistent.jsonl"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not found"* ]] || [[ "$output" == *"File not found"* ]]
}

@test "thinking-logger read: displays entries" {
    run "$SCRIPT" read "$TEST_DIR/trajectory/test-agent-2025-01-11.jsonl"
    [ "$status" -eq 0 ]
    [[ "$output" == *"implementing-tasks"* ]]
    [[ "$output" == *"Created file"* ]]
}

@test "thinking-logger read: --last limits entries" {
    run "$SCRIPT" read "$TEST_DIR/trajectory/test-agent-2025-01-11.jsonl" --last 1
    [ "$status" -eq 0 ]
    # Should show only the last entry
    count=$(echo "$output" | grep -c '"agent"' || true)
    [ "$count" -eq 1 ]
}

@test "thinking-logger read: --agent filters by agent" {
    run "$SCRIPT" read "$TEST_DIR/trajectory/test-agent-2025-01-11.jsonl" --agent "reviewing-code"
    [ "$status" -eq 0 ]
    [[ "$output" == *"reviewing-code"* ]]
    [[ ! "$output" == *"implementing-tasks"* ]] || [[ "$output" == *"Reviewed changes"* ]]
}

@test "thinking-logger read: --json outputs JSON array" {
    run "$SCRIPT" read "$TEST_DIR/trajectory/test-agent-2025-01-11.jsonl" --json
    [ "$status" -eq 0 ]
    [[ "$output" == "["* ]]
    # Should be valid JSON array
    echo "$output" | jq empty
}

# =============================================================================
# Validate Command Tests
# =============================================================================

@test "thinking-logger validate: requires file argument" {
    run "$SCRIPT" validate
    [ "$status" -eq 1 ]
    [[ "$output" == *"No file specified"* ]]
}

@test "thinking-logger validate: reports missing file" {
    run "$SCRIPT" validate "$TEST_DIR/nonexistent.jsonl"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not found"* ]]
}

@test "thinking-logger validate: validates good file" {
    run "$SCRIPT" validate "$TEST_DIR/trajectory/test-agent-2025-01-11.jsonl"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Valid"* ]]
}

@test "thinking-logger validate: reports invalid JSON" {
    echo "not json" > "$TEST_DIR/invalid.jsonl"
    run "$SCRIPT" validate "$TEST_DIR/invalid.jsonl"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid JSON"* ]]
}

@test "thinking-logger validate: reports missing required fields" {
    echo '{"ts": "2025-01-11T10:00:00Z"}' > "$TEST_DIR/missing-fields.jsonl"
    run "$SCRIPT" validate "$TEST_DIR/missing-fields.jsonl"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Missing"* ]] || [[ "$output" == *"errors"* ]]
}

# =============================================================================
# Init Command Tests
# =============================================================================

@test "thinking-logger init: creates trajectory directory" {
    rm -rf "$TEST_DIR/new-trajectory"
    run "$SCRIPT" init "$TEST_DIR/new-trajectory"
    [ "$status" -eq 0 ]
    [ -d "$TEST_DIR/new-trajectory" ]
}

@test "thinking-logger init: handles existing directory" {
    mkdir -p "$TEST_DIR/existing"
    run "$SCRIPT" init "$TEST_DIR/existing"
    [ "$status" -eq 0 ]
    [[ "$output" == *"exists"* ]]
}

# =============================================================================
# Output File Tests
# =============================================================================

@test "thinking-logger log: creates directories for output path" {
    run "$SCRIPT" log \
        --agent "implementing-tasks" \
        --action "Test" \
        --output "$TEST_DIR/deep/nested/path/output.jsonl"
    [ "$status" -eq 0 ]
    [ -f "$TEST_DIR/deep/nested/path/output.jsonl" ]
}

@test "thinking-logger log: appends to existing file" {
    run "$SCRIPT" log --agent "test" --action "First" --output "$TEST_DIR/append.jsonl"
    run "$SCRIPT" log --agent "test" --action "Second" --output "$TEST_DIR/append.jsonl"
    [ "$status" -eq 0 ]

    count=$(wc -l < "$TEST_DIR/append.jsonl")
    [ "$count" -eq 2 ]
}

@test "thinking-logger log: outputs compact JSON (single line)" {
    run "$SCRIPT" log --agent "test" --action "Test" --output "$TEST_DIR/compact.jsonl"
    [ "$status" -eq 0 ]

    # Each entry should be a single line
    lines=$(wc -l < "$TEST_DIR/compact.jsonl")
    [ "$lines" -eq 1 ]
}

# =============================================================================
# Edge Cases
# =============================================================================

@test "thinking-logger log: handles special characters in action" {
    run "$SCRIPT" log \
        --agent "test" \
        --action "Created 'test' with \"quotes\" and \$pecial chars" \
        --output "$TEST_DIR/special.jsonl"
    [ "$status" -eq 0 ]

    entry=$(cat "$TEST_DIR/special.jsonl")
    echo "$entry" | jq empty  # Should be valid JSON
}

@test "thinking-logger log: handles empty thinking step thought" {
    run "$SCRIPT" log \
        --agent "test" \
        --action "Test" \
        --think-step "1:analysis:" \
        --output "$TEST_DIR/empty-thought.jsonl"
    [ "$status" -eq 0 ]
}
