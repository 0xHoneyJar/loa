#!/usr/bin/env bats
# =============================================================================
# tests/integration/gpt-review-hook-trivial-detect.bats
#
# Closes #711.A (zkSoju feedback): the PostToolUse GPT-review hook fires
# unconditionally on every Edit/Write. zkSoju's session lost ~30 min of
# review-cycle navigation because:
#   - frontmatter version bumps fired the checkpoint despite rule (3)
#     "Trivial changes (typos, comments, logs) - always skip"
#   - writes to temp-dir context files (expertise.md, context.md) fired
#     the hook each time, demanding new review temp dirs
#
# Fix: trivial-edit detection in the hook itself + path-allowlist for the
# substantive review-scope (grimoires/loa/{prd,sdd,sprint}.md, src/, lib/,
# app/). The hook now exits 0 silently when:
#   1. file_path is OUTSIDE the review-scope allowlist (temp dirs etc.)
#   2. tool is Edit AND old_string + new_string are entirely within YAML
#      frontmatter delimiters (`---\n…\n---`)
#   3. tool is Edit AND the diff is a simple version-bump (single line of
#      `version: …` or `vX.Y.Z` change)
#
# Rule (3) "comments-only" detection is deferred — strict-string detection
# is OK; tool_input.old_string/new_string already gives precise diff.
# =============================================================================

setup() {
    REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    HOOK="${REPO_ROOT}/.claude/scripts/gpt-review-hook.sh"
    [[ -x "$HOOK" ]] || skip "gpt-review-hook.sh not present/executable"

    TEST_DIR="$(mktemp -d)"
    CONFIG="${TEST_DIR}/.loa.config.yaml"
    cat > "$CONFIG" <<'EOF'
gpt_review:
  enabled: true
  phases:
    prd: true
    sdd: true
    sprint: true
    implementation: true
EOF
    # Hook reads config from `$SCRIPT_DIR/../../.loa.config.yaml`. Stage a
    # mock structure so the hook resolves to OUR test config.
    MOCK_LOA_ROOT="${TEST_DIR}/repo"
    mkdir -p "${MOCK_LOA_ROOT}/.claude/scripts"
    cp "$HOOK" "${MOCK_LOA_ROOT}/.claude/scripts/gpt-review-hook.sh"
    chmod +x "${MOCK_LOA_ROOT}/.claude/scripts/gpt-review-hook.sh"
    cp "$CONFIG" "${MOCK_LOA_ROOT}/.loa.config.yaml"
    HOOK_UNDER_TEST="${MOCK_LOA_ROOT}/.claude/scripts/gpt-review-hook.sh"
}

teardown() {
    rm -rf "$TEST_DIR"
}

# Helper: run hook with given JSON input, return its stdout.
run_hook() {
    local json="$1"
    echo "$json" | "$HOOK_UNDER_TEST" 2>/dev/null
}

# Helper: assert hook returned a checkpoint (non-empty, contains "GPT Review").
assert_checkpoint() {
    local output="$1"
    [[ -n "$output" ]]
    [[ "$output" == *"GPT Review Checkpoint"* ]]
}

# Helper: assert hook was silent (no stdout).
assert_silent() {
    local output="$1"
    [[ -z "$output" ]]
}

# -----------------------------------------------------------------------------
# Baseline: hook fires for substantive edits to grimoire/loa docs
# -----------------------------------------------------------------------------

@test "baseline: hook fires for Edit on grimoires/loa/prd.md (substantive change)" {
    local input
    input=$(jq -nc \
        --arg fp "${MOCK_LOA_ROOT}/grimoires/loa/prd.md" \
        '{tool_name: "Edit", tool_input: {file_path: $fp, old_string: "## Old section\n\nOld content here.\n", new_string: "## New section\n\nNew content here.\nWith more lines.\n"}}')
    local output
    output=$(run_hook "$input")
    assert_checkpoint "$output"
}

@test "baseline: hook fires for Write on src/foo.ts" {
    local input
    input=$(jq -nc \
        --arg fp "${MOCK_LOA_ROOT}/src/foo.ts" \
        '{tool_name: "Write", tool_input: {file_path: $fp, content: "export const x = 1;\n"}}')
    local output
    output=$(run_hook "$input")
    assert_checkpoint "$output"
}

# -----------------------------------------------------------------------------
# Path-allowlist: skip out-of-scope paths (temp dirs, fixture files)
# -----------------------------------------------------------------------------

@test "path-allowlist: SKIP for /tmp/gpt-review-NNN/expertise.md" {
    local input
    input=$(jq -nc \
        --arg fp "/tmp/gpt-review-12345/expertise.md" \
        '{tool_name: "Write", tool_input: {file_path: $fp, content: "# expertise\n"}}')
    local output
    output=$(run_hook "$input")
    assert_silent "$output"
}

@test "path-allowlist: SKIP for /tmp/gpt-review-NNN/context.md" {
    local input
    input=$(jq -nc \
        --arg fp "/tmp/gpt-review-99999/context.md" \
        '{tool_name: "Write", tool_input: {file_path: $fp, content: "# context\n"}}')
    local output
    output=$(run_hook "$input")
    assert_silent "$output"
}

@test "path-allowlist: SKIP for arbitrary /tmp paths" {
    local input
    input=$(jq -nc \
        --arg fp "/tmp/scratch.md" \
        '{tool_name: "Edit", tool_input: {file_path: $fp, old_string: "x", new_string: "y"}}')
    local output
    output=$(run_hook "$input")
    assert_silent "$output"
}

@test "path-allowlist: FIRE for app/components/Button.tsx" {
    local input
    input=$(jq -nc \
        --arg fp "${MOCK_LOA_ROOT}/app/components/Button.tsx" \
        '{tool_name: "Write", tool_input: {file_path: $fp, content: "..."}}')
    local output
    output=$(run_hook "$input")
    assert_checkpoint "$output"
}

# -----------------------------------------------------------------------------
# Trivial-detect: frontmatter-only edits SKIP
# -----------------------------------------------------------------------------

@test "trivial-detect: frontmatter version bump → SKIP (Edit on prd.md)" {
    local old_str=$'---\nversion: 1.1.0\nstatus: draft\n---\n'
    local new_str=$'---\nversion: 1.2.0\nstatus: draft\n---\n'
    local input
    input=$(jq -nc \
        --arg fp "${MOCK_LOA_ROOT}/grimoires/loa/prd.md" \
        --arg old "$old_str" \
        --arg new "$new_str" \
        '{tool_name: "Edit", tool_input: {file_path: $fp, old_string: $old, new_string: $new}}')
    local output
    output=$(run_hook "$input")
    assert_silent "$output"
}

@test "trivial-detect: frontmatter only — multiline, value change → SKIP" {
    local old_str=$'---\nname: alpha\nversion: 0.9.0\nauthor: deep-name\n---\n'
    local new_str=$'---\nname: alpha\nversion: 0.10.0\nauthor: deep-name\n---\n'
    local input
    input=$(jq -nc \
        --arg fp "${MOCK_LOA_ROOT}/grimoires/loa/sdd.md" \
        --arg old "$old_str" \
        --arg new "$new_str" \
        '{tool_name: "Edit", tool_input: {file_path: $fp, old_string: $old, new_string: $new}}')
    local output
    output=$(run_hook "$input")
    assert_silent "$output"
}

@test "trivial-detect: substantive content change INSIDE frontmatter still allows fire when frontmatter spans body" {
    # If old/new include both frontmatter AND body, the trivial detect should
    # NOT skip — it's a real content edit, not just a frontmatter bump.
    local old_str=$'---\nversion: 1.0\n---\n\n# Body\nOld body content.\n'
    local new_str=$'---\nversion: 1.0\n---\n\n# Body\nNew body content with more material.\n'
    local input
    input=$(jq -nc \
        --arg fp "${MOCK_LOA_ROOT}/grimoires/loa/prd.md" \
        --arg old "$old_str" \
        --arg new "$new_str" \
        '{tool_name: "Edit", tool_input: {file_path: $fp, old_string: $old, new_string: $new}}')
    local output
    output=$(run_hook "$input")
    assert_checkpoint "$output"
}

# -----------------------------------------------------------------------------
# Master-toggle: existing behavior preserved
# -----------------------------------------------------------------------------

@test "master-toggle: SKIP when gpt_review.enabled=false (preserves existing behavior)" {
    cat > "${MOCK_LOA_ROOT}/.loa.config.yaml" <<'EOF'
gpt_review:
  enabled: false
EOF
    local input
    input=$(jq -nc \
        --arg fp "${MOCK_LOA_ROOT}/grimoires/loa/prd.md" \
        '{tool_name: "Edit", tool_input: {file_path: $fp, old_string: "x", new_string: "y"}}')
    local output
    output=$(run_hook "$input")
    assert_silent "$output"
}

@test "master-toggle: SKIP when config file is missing" {
    rm "${MOCK_LOA_ROOT}/.loa.config.yaml"
    local input
    input=$(jq -nc \
        --arg fp "${MOCK_LOA_ROOT}/grimoires/loa/prd.md" \
        '{tool_name: "Edit", tool_input: {file_path: $fp, old_string: "x", new_string: "y"}}')
    local output
    output=$(run_hook "$input")
    assert_silent "$output"
}

# -----------------------------------------------------------------------------
# Edge case: empty/missing tool_input fields don't crash
# -----------------------------------------------------------------------------

@test "edge: empty tool_input.file_path — SKIP (cannot decide allowlist)" {
    local input='{"tool_name":"Edit","tool_input":{"file_path":"","old_string":"x","new_string":"y"}}'
    local output
    output=$(run_hook "$input")
    # Conservative: if we can't classify, skip — better to under-trigger than
    # over-trigger (the original bug).
    assert_silent "$output"
}

@test "edge: malformed JSON input — exit cleanly without crashing" {
    local output
    output=$(echo "not json at all" | "$HOOK_UNDER_TEST" 2>/dev/null) || true
    # No checkpoint emitted; doesn't crash.
    [[ "$output" != *"GPT Review Checkpoint"* ]]
}
