#!/usr/bin/env bats
# =============================================================================
# sync-run-mode-git-aware.bats — Issue #474 regression tests
# =============================================================================
# Verifies that sync_run_mode cross-references git history when the run-mode
# state file shows RUNNING. Three scenarios:
#   1. State RUNNING + git shows enough sprint commits → synced=true
#   2. State RUNNING + git shows zero sprint commits   → still_running (preserved)
#   3. State RUNNING + git shows partial commits       → still_running (preserved)
# =============================================================================

setup() {
    export PROJECT_ROOT
    PROJECT_ROOT=$(mktemp -d)
    export STATE_FILE="$PROJECT_ROOT/.run/simstim-state.json"
    export RUN_MODE_STATE="$PROJECT_ROOT/.run/sprint-plan-state.json"
    mkdir -p "$PROJECT_ROOT/.run"

    # Init git repo so `git log` works
    cd "$PROJECT_ROOT"
    git init -q -b main
    git config user.email "test@example.com"
    git config user.name "Test"
    echo "init" > README.md
    git add README.md
    git commit -q -m "initial commit"

    # Empty .loa.config.yaml so yq fallbacks fire
    touch .loa.config.yaml

    # Minimal simstim-state.json so sync_run_mode passes its initial existence check
    cat > "$STATE_FILE" <<'EOF'
{
  "phase": "implementation",
  "sync_attempts": 0
}
EOF

    # Use the script's CLI surface directly. PROJECT_ROOT redirects all
    # state file paths to our temp dir.
    SCRIPT="$BATS_TEST_DIRNAME/../../.claude/scripts/simstim-orchestrator.sh"

    # The script computes PROJECT_ROOT from its own location; override it so
    # state files land in our test sandbox instead of the real repo.
    export LOA_PROJECT_ROOT_OVERRIDE="$PROJECT_ROOT"
}

teardown() {
    cd /
    rm -rf "$PROJECT_ROOT"
}

# Helper: write a sprint-plan-state.json with the given state and sprint count
write_state() {
    local state="$1"
    local total="$2"
    local plan_id="${3:-plan-test-001}"
    cat > "$RUN_MODE_STATE" <<EOF
{
  "plan_id": "$plan_id",
  "state": "$state",
  "sprints": { "total": $total }
}
EOF
}

# Helper: create a feature branch and add N commits matching the default sprint pattern
make_sprint_commits() {
    local n="$1"
    git checkout -q -b feature/test-branch
    for i in $(seq 1 "$n"); do
        echo "sprint $i" > "sprint-${i}.txt"
        git add "sprint-${i}.txt"
        git commit -q -m "feat(sprint-${i}): implementation"
    done
}

# T1: stale state + sufficient commits → git_inferred_completion
@test "git-aware sync: stale RUNNING with N sprint commits returns synced=true" {
    write_state "RUNNING" 3
    make_sprint_commits 3

    # Source the script and call sync_run_mode directly
    set +e
    output=$(env PROJECT_ROOT="$PROJECT_ROOT" "$SCRIPT" --sync-run-mode 2>/dev/null)
    set -e

    [[ "$output" == *'"synced": true'* ]] || [[ "$output" == *'"synced":true'* ]]
    [[ "$output" == *"git_inferred_completion"* ]]
    [[ "$output" == *'"commits_found": 3'* ]] || [[ "$output" == *'"commits_found":3'* ]]
}

# T2: in-flight state (no commits) → still_running preserved
@test "git-aware sync: RUNNING with zero sprint commits returns still_running" {
    write_state "RUNNING" 3
    # No sprint commits — only the initial commit on main

    set +e
    output=$(env PROJECT_ROOT="$PROJECT_ROOT" "$SCRIPT" --sync-run-mode 2>/dev/null)
    set -e

    [[ "$output" == *"still_running"* ]]
    [[ "$output" != *"git_inferred_completion"* ]]
}

# T3: partial commits (less than expected) → still_running preserved
@test "git-aware sync: RUNNING with partial commits returns still_running" {
    write_state "RUNNING" 5
    make_sprint_commits 2  # 2 commits, 5 expected

    set +e
    output=$(env PROJECT_ROOT="$PROJECT_ROOT" "$SCRIPT" --sync-run-mode 2>/dev/null)
    set -e

    [[ "$output" == *"still_running"* ]]
    [[ "$output" != *"git_inferred_completion"* ]]
}

# T4: state file updated to JACKED_OUT with git_inferred flag on success
@test "git-aware sync: success case marks RUN_MODE_STATE as JACKED_OUT with git_inferred flag" {
    write_state "RUNNING" 2
    make_sprint_commits 2

    env PROJECT_ROOT="$PROJECT_ROOT" "$SCRIPT" --sync-run-mode >/dev/null 2>&1

    [ "$(jq -r '.state' "$RUN_MODE_STATE")" = "JACKED_OUT" ]
    [ "$(jq -r '.git_inferred' "$RUN_MODE_STATE")" = "true" ]
    # git_inferred_at must be a valid ISO timestamp string
    inferred_at=$(jq -r '.git_inferred_at' "$RUN_MODE_STATE")
    [[ "$inferred_at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

# T5: sprints.list length used when sprints.total absent (backward compat)
@test "git-aware sync: falls back to sprints.list length when total absent" {
    cat > "$RUN_MODE_STATE" <<EOF
{
  "plan_id": "plan-test-002",
  "state": "RUNNING",
  "sprints": { "list": [{"id":"a"},{"id":"b"}] }
}
EOF
    make_sprint_commits 2

    set +e
    output=$(env PROJECT_ROOT="$PROJECT_ROOT" "$SCRIPT" --sync-run-mode 2>/dev/null)
    set -e

    [[ "$output" == *"git_inferred_completion"* ]]
    [[ "$output" == *'"commits_expected": 2'* ]] || [[ "$output" == *'"commits_expected":2'* ]]
}
