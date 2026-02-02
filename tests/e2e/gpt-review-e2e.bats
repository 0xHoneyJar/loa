#!/usr/bin/env bats
# End-to-end tests for GPT review integration
#
# These tests run actual Claude Code sessions with Loa to verify
# that GPT review is automatically triggered during skill execution.
#
# Requirements:
# - Claude Code CLI installed and authenticated
# - OPENAI_API_KEY set (or mocked)

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

    # Create isolated test directory
    TEST_PROJECT="${BATS_TEST_TMPDIR:-$(mktemp -d)}/test-project"
    mkdir -p "$TEST_PROJECT"

    # Track if we should skip (Claude not available)
    if ! command -v claude &>/dev/null; then
        skip "Claude Code CLI not installed"
    fi
}

teardown() {
    # Cleanup test project
    rm -rf "$TEST_PROJECT"
}

# =============================================================================
# Helper functions
# =============================================================================

# Set up a fresh Loa project with GPT review enabled
setup_loa_project() {
    local project_dir="$1"

    # Copy Loa framework files
    cp -r "$PROJECT_ROOT/.claude" "$project_dir/"
    mkdir -p "$project_dir/grimoires/loa"

    # Create config with GPT review enabled
    cat > "$project_dir/.loa.config.yaml" << 'EOF'
gpt_review:
  enabled: true
  timeout_seconds: 30
  max_iterations: 1
  phases:
    prd: true
    sdd: true
    sprint: true
    implementation: true
EOF

    # Create CLAUDE.md
    cp "$PROJECT_ROOT/CLAUDE.md" "$project_dir/"
}

# Set up mock curl that logs calls
setup_mock_environment() {
    local project_dir="$1"

    mkdir -p "$project_dir/.test-mocks/bin"

    # Create mock curl
    cat > "$project_dir/.test-mocks/bin/curl" << 'MOCK'
#!/usr/bin/env bash
# Log the call
echo "$(date -Iseconds) curl $@" >> "$PROJECT_DIR/.test-mocks/curl-calls.log"

# Return mock GPT response
cat << 'RESPONSE'
HTTP/2 200
content-type: application/json

{
  "choices": [{
    "message": {
      "content": "{\"verdict\": \"APPROVED\", \"summary\": \"Mock approval for testing\"}"
    }
  }]
}
RESPONSE
MOCK
    chmod +x "$project_dir/.test-mocks/bin/curl"

    # Create wrapper script to inject mock
    cat > "$project_dir/.test-mocks/run-with-mocks.sh" << 'WRAPPER'
#!/usr/bin/env bash
export PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="$PROJECT_DIR/.test-mocks/bin:$PATH"
export OPENAI_API_KEY="test-mock-key"
exec "$@"
WRAPPER
    chmod +x "$project_dir/.test-mocks/run-with-mocks.sh"
}

# Run Claude with mocked environment
run_claude_with_mocks() {
    local project_dir="$1"
    shift
    cd "$project_dir"
    "$project_dir/.test-mocks/run-with-mocks.sh" claude "$@"
}

# =============================================================================
# E2E Tests
# =============================================================================

@test "E2E: session start injects GPT review gates" {
    setup_loa_project "$TEST_PROJECT"
    setup_mock_environment "$TEST_PROJECT"

    # Run a minimal Claude session that triggers SessionStart hooks
    cd "$TEST_PROJECT"

    # Run inject script directly (simulates what SessionStart hook does)
    .claude/scripts/inject-gpt-review-gates.sh

    # Verify gates were injected
    grep -q "GPT_REVIEW_GATE_START" "$TEST_PROJECT/.claude/skills/discovering-requirements/SKILL.md"
}

@test "E2E: Claude sees GPT review gate in skill file" {
    setup_loa_project "$TEST_PROJECT"
    setup_mock_environment "$TEST_PROJECT"

    # Inject gates
    cd "$TEST_PROJECT"
    .claude/scripts/inject-gpt-review-gates.sh

    # Use Claude to read the skill file and confirm gate is visible
    # This tests that Claude will see the instruction when executing the skill
    run run_claude_with_mocks "$TEST_PROJECT" --print \
        --dangerously-skip-permissions \
        "Read the file .claude/skills/discovering-requirements/SKILL.md and tell me if it contains GPT_REVIEW_GATE_START. Answer only yes or no."

    echo "$output" | grep -qi "yes"
}

@test "E2E: skill execution triggers GPT review API call" {
    skip "Requires full skill execution - run manually"

    setup_loa_project "$TEST_PROJECT"
    setup_mock_environment "$TEST_PROJECT"

    # Inject gates
    cd "$TEST_PROJECT"
    .claude/scripts/inject-gpt-review-gates.sh

    # Create minimal context so skill can run quickly
    mkdir -p "$TEST_PROJECT/grimoires/loa/context"
    echo "Build a simple hello world CLI app" > "$TEST_PROJECT/grimoires/loa/context/user-requirements.md"

    # Run the skill with Claude
    # Note: This is a long-running test - the skill will interact and create a PRD
    run timeout 120 run_claude_with_mocks "$TEST_PROJECT" --print \
        --dangerously-skip-permissions \
        "/plan-and-analyze --skip-questions"

    # Check if GPT review API was called (via mock log)
    [[ -f "$TEST_PROJECT/.test-mocks/curl-calls.log" ]]
    grep -q "api.openai.com" "$TEST_PROJECT/.test-mocks/curl-calls.log"
}

@test "E2E: GPT review NOT called when disabled" {
    setup_loa_project "$TEST_PROJECT"
    setup_mock_environment "$TEST_PROJECT"

    # DISABLE GPT review
    cat > "$TEST_PROJECT/.loa.config.yaml" << 'EOF'
gpt_review:
  enabled: false
EOF

    # Run inject script - should remove any gates
    cd "$TEST_PROJECT"
    .claude/scripts/inject-gpt-review-gates.sh

    # Verify NO gates in skill files
    ! grep -q "GPT_REVIEW_GATE_START" "$TEST_PROJECT/.claude/skills/discovering-requirements/SKILL.md"

    # Run the API script directly - should return SKIPPED
    export OPENAI_API_KEY="test-key"
    echo "# Test PRD" > "$TEST_PROJECT/grimoires/loa/prd.md"

    run .claude/scripts/gpt-review-api.sh prd "$TEST_PROJECT/grimoires/loa/prd.md"

    [[ "$status" -eq 0 ]]
    echo "$output" | grep -q '"verdict": "SKIPPED"'

    # Mock curl should NOT have been called
    [[ ! -f "$TEST_PROJECT/.test-mocks/curl-calls.log" ]] || [[ ! -s "$TEST_PROJECT/.test-mocks/curl-calls.log" ]]
}
