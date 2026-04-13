#!/usr/bin/env bats
# =============================================================================
# simstim-state-coalescer.bats — cycle-063 regression tests
# =============================================================================
# RFC-060 Frictions 1+2 fix: when sync_run_mode transitions to a terminal
# state (COMPLETED, AWAITING_HITL, HALTED), the state file must reach an
# internally consistent terminal condition:
#
#   - .state set to the target terminal value
#   - .phase advanced to "complete" for COMPLETED/AWAITING_HITL
#     (HALTED preserves current phase to enable operator resume)
#   - .completed_at timestamp populated
#
# Plus new --archive-completed flag that moves terminal state files to
# .run/archive/simstim-{id}-{ts}.json for clean fresh starts.
# =============================================================================

setup() {
    export PROJECT_ROOT
    PROJECT_ROOT=$(mktemp -d)
    export STATE_FILE="$PROJECT_ROOT/.run/simstim-state.json"
    export RUN_MODE_STATE="$PROJECT_ROOT/.run/sprint-plan-state.json"
    mkdir -p "$PROJECT_ROOT/.run"

    # Init git repo so git_inferred_completion_check works where invoked
    cd "$PROJECT_ROOT"
    git init -q -b main
    git config user.email "test@example.com"
    git config user.name "Test"
    echo "init" > README.md
    git add README.md
    git commit -q -m "initial commit"
    touch .loa.config.yaml

    SCRIPT="$BATS_TEST_DIRNAME/../../.claude/scripts/simstim-orchestrator.sh"
    export LOA_PROJECT_ROOT_OVERRIDE="$PROJECT_ROOT"
}

teardown() {
    cd /
    rm -rf "$PROJECT_ROOT"
}

# Helper: seed a simstim state file at a given phase with matching plan_id
write_simstim_state() {
    local phase="${1:-implementation}"
    local plan_id="${2:-plan-test-001}"
    cat > "$STATE_FILE" <<EOF
{
  "schema_version": 1,
  "simstim_id": "simstim-test-abc123",
  "state": "RUNNING",
  "phase": "$phase",
  "expected_plan_id": "$plan_id",
  "timestamps": {
    "started": "2026-04-14T00:00:00Z",
    "last_activity": "2026-04-14T00:05:00Z"
  },
  "phases": {
    "implementation": { "status": "in_progress", "started_at": "2026-04-14T00:05:00Z" }
  },
  "sync_attempts": 0
}
EOF
}

# Helper: seed a run-mode state file in a terminal condition
write_run_mode_terminal() {
    local state="$1"
    local plan_id="${2:-plan-test-001}"
    cat > "$RUN_MODE_STATE" <<EOF
{
  "plan_id": "$plan_id",
  "state": "$state",
  "sprints": { "total": 2 },
  "pr_url": "https://github.com/owner/repo/pull/999",
  "timestamps": {
    "started": "2026-04-14T00:05:00Z",
    "last_activity": "2026-04-14T00:30:00Z"
  }
}
EOF
}

# =============================================================================
# T1: sync_run_mode with JACKED_OUT coalesces phase + completed_at
# =============================================================================
@test "coalescer: sync with JACKED_OUT sets phase=complete and completed_at" {
    write_simstim_state "implementation"
    write_run_mode_terminal "JACKED_OUT"

    env PROJECT_ROOT="$PROJECT_ROOT" "$SCRIPT" --sync-run-mode >/dev/null 2>&1

    [ "$(jq -r '.state' "$STATE_FILE")" = "COMPLETED" ]
    [ "$(jq -r '.phase' "$STATE_FILE")" = "complete" ]
    # completed_at must be a non-null ISO timestamp
    local completed_at
    completed_at=$(jq -r '.completed_at' "$STATE_FILE")
    [[ "$completed_at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

# =============================================================================
# T2: sync_run_mode with READY_FOR_HITL → AWAITING_HITL + phase=complete
# =============================================================================
@test "coalescer: sync with READY_FOR_HITL sets AWAITING_HITL with phase=complete" {
    write_simstim_state "implementation"
    write_run_mode_terminal "READY_FOR_HITL"

    env PROJECT_ROOT="$PROJECT_ROOT" "$SCRIPT" --sync-run-mode >/dev/null 2>&1

    [ "$(jq -r '.state' "$STATE_FILE")" = "AWAITING_HITL" ]
    [ "$(jq -r '.phase' "$STATE_FILE")" = "complete" ]
    local completed_at
    completed_at=$(jq -r '.completed_at' "$STATE_FILE")
    [[ "$completed_at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

# =============================================================================
# T3: sync_run_mode with HALTED → completed_at set but phase preserved
# =============================================================================
@test "coalescer: sync with HALTED sets completed_at but preserves phase" {
    write_simstim_state "implementation"
    write_run_mode_terminal "HALTED"

    env PROJECT_ROOT="$PROJECT_ROOT" "$SCRIPT" --sync-run-mode >/dev/null 2>&1

    [ "$(jq -r '.state' "$STATE_FILE")" = "HALTED" ]
    # HALTED preserves phase so operator can resume from implementation
    [ "$(jq -r '.phase' "$STATE_FILE")" = "implementation" ]
    local completed_at
    completed_at=$(jq -r '.completed_at' "$STATE_FILE")
    [[ "$completed_at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

# =============================================================================
# T4: sync preserves simstim-specific fields (impl.status, pr_url)
# =============================================================================
@test "coalescer: sync composes with simstim-specific fields atomically" {
    write_simstim_state "implementation"
    write_run_mode_terminal "JACKED_OUT"

    env PROJECT_ROOT="$PROJECT_ROOT" "$SCRIPT" --sync-run-mode >/dev/null 2>&1

    # Simstim-specific fields the extra_filter must preserve/update
    [ "$(jq -r '.phases.implementation.status' "$STATE_FILE")" = "completed" ]
    [ "$(jq -r '.pr_url' "$STATE_FILE")" = "https://github.com/owner/repo/pull/999" ]
    [ "$(jq -r '.sync_attempts' "$STATE_FILE")" = "0" ]
}

# =============================================================================
# T5: --archive-completed moves terminal state to archive dir
# =============================================================================
@test "archive: moves COMPLETED state to .run/archive/ with simstim_id" {
    write_simstim_state "complete"
    # Advance state to terminal
    jq '.state = "COMPLETED" | .completed_at = "2026-04-14T00:35:00Z"' "$STATE_FILE" \
        > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"

    local output
    output=$(env PROJECT_ROOT="$PROJECT_ROOT" "$SCRIPT" --archive-completed 2>&1)

    # Original state file must be gone
    [ ! -f "$STATE_FILE" ]
    # Archive dir must exist with at least one file
    [ -d "$PROJECT_ROOT/.run/archive" ]
    local archived_count
    archived_count=$(ls "$PROJECT_ROOT/.run/archive/" | wc -l | tr -d ' ')
    [ "$archived_count" -ge 1 ]
    # Archive filename must include simstim_id
    ls "$PROJECT_ROOT/.run/archive/" | grep -q "simstim-test-abc123"
    # Output must indicate success
    [[ "$output" == *'"archived": true'* ]] || [[ "$output" == *'"archived":true'* ]]
}

# =============================================================================
# T6: --archive-completed refuses when state is RUNNING
# =============================================================================
@test "archive: refuses to archive RUNNING state (exit 1, file preserved)" {
    write_simstim_state "implementation"
    # State is RUNNING by default from write_simstim_state helper

    set +e
    output=$(env PROJECT_ROOT="$PROJECT_ROOT" "$SCRIPT" --archive-completed 2>&1)
    exit_code=$?
    set -e

    [ "$exit_code" -eq 1 ]
    # File must still exist
    [ -f "$STATE_FILE" ]
    [[ "$output" == *"state_not_terminal"* ]]
}

# =============================================================================
# T7: --archive-completed idempotent (no state file → archived: false)
# =============================================================================
@test "archive: idempotent — returns no_state_file when already archived" {
    # No state file exists
    local output
    output=$(env PROJECT_ROOT="$PROJECT_ROOT" "$SCRIPT" --archive-completed 2>&1)

    [[ "$output" == *'"archived": false'* ]] || [[ "$output" == *'"archived":false'* ]]
    [[ "$output" == *"no_state_file"* ]]
}

# =============================================================================
# T8: --archive-completed handles HALTED state
# =============================================================================
@test "archive: HALTED state is also terminal (archivable)" {
    write_simstim_state "implementation"
    jq '.state = "HALTED" | .completed_at = "2026-04-14T00:40:00Z"' "$STATE_FILE" \
        > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"

    env PROJECT_ROOT="$PROJECT_ROOT" "$SCRIPT" --archive-completed >/dev/null 2>&1

    [ ! -f "$STATE_FILE" ]
    ls "$PROJECT_ROOT/.run/archive/" | grep -q "simstim-test-abc123"
}

# =============================================================================
# T9: --archive-completed refuses corrupt JSON
# =============================================================================
@test "archive: refuses to archive corrupt JSON (exit 1, file preserved)" {
    echo "{ not valid json" > "$STATE_FILE"

    set +e
    env PROJECT_ROOT="$PROJECT_ROOT" "$SCRIPT" --archive-completed >/dev/null 2>&1
    exit_code=$?
    set -e

    [ "$exit_code" -eq 1 ]
    [ -f "$STATE_FILE" ]
}

# =============================================================================
# T10: CLI flag is documented in usage comment header
# =============================================================================
@test "cli: --archive-completed flag appears in script header usage" {
    grep -q "archive-completed" "$SCRIPT"
}

# =============================================================================
# T11: coalesce_terminal_state helper is defined
# =============================================================================
@test "coalescer: coalesce_terminal_state function exists" {
    grep -q "^coalesce_terminal_state()" "$SCRIPT"
}

# =============================================================================
# T12: archive path contains timestamp for traceability
# =============================================================================
@test "archive: path includes ISO-like timestamp" {
    write_simstim_state "complete"
    jq '.state = "COMPLETED"' "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"

    env PROJECT_ROOT="$PROJECT_ROOT" "$SCRIPT" --archive-completed >/dev/null 2>&1

    # Archive filename format: simstim-{id}-{YYYYMMDDTHHMMSSZ}.json
    ls "$PROJECT_ROOT/.run/archive/" | grep -qE 'simstim-.*-[0-9]{8}T[0-9]{6}Z\.json$'
}
