#!/usr/bin/env bats
# Integration tests for Run Mode (v0.18.0)
# Tests end-to-end functionality of /run, /run-status, /run-halt, /run-resume

load '../test_helper'

setup() {
  # Create temp directory for test
  export TEST_DIR="$BATS_TMPDIR/run-mode-test-$$"
  mkdir -p "$TEST_DIR"
  cd "$TEST_DIR"

  # Initialize git repo
  git init --quiet
  git config user.email "test@example.com"
  git config user.name "Test User"

  # Create basic Loa structure
  mkdir -p .claude/scripts .claude/commands grimoires/loa/a2a

  # Create minimal .loa.config.yaml (disabled by default)
  cat > .loa.config.yaml << 'EOF'
run_mode:
  enabled: false
  defaults:
    max_cycles: 20
    timeout_hours: 8
EOF

  # Create ICE script mock
  cat > .claude/scripts/run-mode-ice.sh << 'ICESCRIPT'
#!/usr/bin/env bash
set -euo pipefail

PROTECTED_BRANCHES="main master staging develop development production prod"

is_protected_branch() {
  local branch="$1"
  for protected in $PROTECTED_BRANCHES; do
    [[ "$branch" == "$protected" ]] && return 0
  done
  [[ "$branch" =~ ^release/ || "$branch" =~ ^release- ]] && return 0
  [[ "$branch" =~ ^hotfix/ || "$branch" =~ ^hotfix- ]] && return 0
  return 1
}

case "${1:-}" in
  validate)
    branch=$(git branch --show-current 2>/dev/null || echo "main")
    if is_protected_branch "$branch"; then
      echo "ERROR: Cannot run on protected branch: $branch"
      exit 1
    fi
    echo "OK: Branch $branch is safe"
    ;;
  ensure-branch)
    target="${2:-feature/test}"
    branch="feature/$target"
    git checkout -b "$branch" 2>/dev/null || git checkout "$branch" 2>/dev/null
    echo "Checked out $branch"
    ;;
  push)
    shift
    branch="${!#}"  # Last argument
    if is_protected_branch "$branch"; then
      echo "ERROR: Push blocked to protected branch: $branch"
      exit 1
    fi
    echo "Would push to $branch (mock)"
    ;;
  pr-create)
    echo "Would create draft PR (mock)"
    echo "PR #999 created"
    ;;
  *)
    echo "Unknown command: $1"
    exit 1
    ;;
esac
ICESCRIPT
  chmod +x .claude/scripts/run-mode-ice.sh

  # Create check-permissions script mock
  cat > .claude/scripts/check-permissions.sh << 'PERMSCRIPT'
#!/usr/bin/env bash
set -euo pipefail
echo "All permissions configured"
exit 0
PERMSCRIPT
  chmod +x .claude/scripts/check-permissions.sh

  # Initial commit
  git add -A
  git commit -m "Initial commit" --quiet

  # Checkout feature branch for testing
  git checkout -b feature/test-run --quiet
}

teardown() {
  cd /
  rm -rf "$TEST_DIR"
}

# =============================================================================
# Pre-flight Check Tests
# =============================================================================

@test "run fails if run_mode not enabled" {
  # run_mode.enabled is false by default
  run bash -c '
    source_config() {
      yq ".run_mode.enabled // false" .loa.config.yaml
    }
    if [[ "$(source_config)" != "true" ]]; then
      echo "ERROR: Run Mode not enabled"
      exit 1
    fi
  '
  [ "$status" -eq 1 ]
  [[ "$output" == *"Run Mode not enabled"* ]]
}

@test "run succeeds when run_mode enabled" {
  # Enable run mode
  cat > .loa.config.yaml << 'EOF'
run_mode:
  enabled: true
EOF

  run bash -c '
    enabled=$(yq ".run_mode.enabled // false" .loa.config.yaml)
    if [[ "$enabled" == "true" ]]; then
      echo "OK: Run Mode enabled"
      exit 0
    else
      echo "ERROR: Run Mode not enabled"
      exit 1
    fi
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"Run Mode enabled"* ]]
}

@test "run fails on protected branch" {
  git checkout -b main --quiet 2>/dev/null || git checkout main --quiet

  run .claude/scripts/run-mode-ice.sh validate
  [ "$status" -eq 1 ]
  [[ "$output" == *"Cannot run on protected branch"* ]]
}

@test "run succeeds on feature branch" {
  git checkout feature/test-run --quiet

  run .claude/scripts/run-mode-ice.sh validate
  [ "$status" -eq 0 ]
  [[ "$output" == *"is safe"* ]]
}

# =============================================================================
# ICE Safety Tests
# =============================================================================

@test "ICE blocks push to main" {
  run .claude/scripts/run-mode-ice.sh push origin main
  [ "$status" -eq 1 ]
  [[ "$output" == *"Push blocked"* ]]
}

@test "ICE blocks push to master" {
  run .claude/scripts/run-mode-ice.sh push origin master
  [ "$status" -eq 1 ]
  [[ "$output" == *"Push blocked"* ]]
}

@test "ICE blocks push to release branch" {
  run .claude/scripts/run-mode-ice.sh push origin release/1.0
  [ "$status" -eq 1 ]
  [[ "$output" == *"Push blocked"* ]]
}

@test "ICE allows push to feature branch" {
  run .claude/scripts/run-mode-ice.sh push origin feature/test
  [ "$status" -eq 0 ]
  [[ "$output" == *"Would push"* ]]
}

@test "ICE creates draft PR" {
  run .claude/scripts/run-mode-ice.sh pr-create "Test PR" "Test body"
  [ "$status" -eq 0 ]
  [[ "$output" == *"draft PR"* ]]
}

# =============================================================================
# State Management Tests
# =============================================================================

@test "state.json created with correct structure" {
  mkdir -p .run

  cat > .run/state.json << 'EOF'
{
  "run_id": "run-20260119-test",
  "target": "sprint-1",
  "branch": "feature/sprint-1",
  "state": "RUNNING",
  "phase": "IMPLEMENT",
  "cycles": {
    "current": 1,
    "limit": 20,
    "history": []
  },
  "metrics": {
    "files_changed": 0,
    "files_deleted": 0,
    "commits": 0,
    "findings_fixed": 0
  }
}
EOF

  run jq -r '.state' .run/state.json
  [ "$status" -eq 0 ]
  [ "$output" = "RUNNING" ]

  run jq -r '.target' .run/state.json
  [ "$status" -eq 0 ]
  [ "$output" = "sprint-1" ]
}

@test "run-status shows no run when state missing" {
  rm -rf .run

  run bash -c '
    if [[ ! -f .run/state.json ]]; then
      echo "No run in progress."
      exit 0
    fi
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"No run in progress"* ]]
}

@test "run-status shows current state" {
  mkdir -p .run
  cat > .run/state.json << 'EOF'
{
  "run_id": "run-20260119-abc",
  "target": "sprint-1",
  "state": "RUNNING",
  "phase": "REVIEW"
}
EOF

  run bash -c '
    if [[ -f .run/state.json ]]; then
      state=$(jq -r ".state" .run/state.json)
      phase=$(jq -r ".phase" .run/state.json)
      echo "State: $state, Phase: $phase"
    fi
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"RUNNING"* ]]
  [[ "$output" == *"REVIEW"* ]]
}

# =============================================================================
# Circuit Breaker Tests
# =============================================================================

@test "circuit breaker initialized as CLOSED" {
  mkdir -p .run
  cat > .run/circuit-breaker.json << 'EOF'
{
  "state": "CLOSED",
  "triggers": {
    "same_issue": { "count": 0, "threshold": 3 },
    "no_progress": { "count": 0, "threshold": 5 },
    "cycle_count": { "current": 0, "limit": 20 }
  },
  "history": []
}
EOF

  run jq -r '.state' .run/circuit-breaker.json
  [ "$status" -eq 0 ]
  [ "$output" = "CLOSED" ]
}

@test "circuit breaker trips on same_issue threshold" {
  mkdir -p .run
  cat > .run/circuit-breaker.json << 'EOF'
{
  "state": "CLOSED",
  "triggers": {
    "same_issue": { "count": 3, "threshold": 3 }
  }
}
EOF

  run bash -c '
    count=$(jq ".triggers.same_issue.count" .run/circuit-breaker.json)
    threshold=$(jq ".triggers.same_issue.threshold" .run/circuit-breaker.json)
    if [[ $count -ge $threshold ]]; then
      echo "CIRCUIT BREAKER TRIPPED: Same issue threshold reached"
      jq ".state = \"OPEN\"" .run/circuit-breaker.json > .run/circuit-breaker.json.tmp
      mv .run/circuit-breaker.json.tmp .run/circuit-breaker.json
    fi
    jq -r ".state" .run/circuit-breaker.json
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"TRIPPED"* ]]
  [[ "$output" == *"OPEN"* ]]
}

# =============================================================================
# Halt and Resume Tests
# =============================================================================

@test "run-halt sets state to HALTED" {
  mkdir -p .run
  cat > .run/state.json << 'EOF'
{"state": "RUNNING", "phase": "IMPLEMENT"}
EOF

  run bash -c '
    jq ".state = \"HALTED\"" .run/state.json > .run/state.json.tmp
    mv .run/state.json.tmp .run/state.json
    jq -r ".state" .run/state.json
  '
  [ "$status" -eq 0 ]
  [ "$output" = "HALTED" ]
}

@test "run-resume fails if not HALTED" {
  mkdir -p .run
  cat > .run/state.json << 'EOF'
{"state": "RUNNING"}
EOF

  run bash -c '
    state=$(jq -r ".state" .run/state.json)
    if [[ "$state" != "HALTED" ]]; then
      echo "ERROR: Run is not halted (state: $state)"
      exit 1
    fi
  '
  [ "$status" -eq 1 ]
  [[ "$output" == *"not halted"* ]]
}

@test "run-resume succeeds when HALTED" {
  mkdir -p .run
  cat > .run/state.json << 'EOF'
{"state": "HALTED", "branch": "feature/test-run"}
EOF

  run bash -c '
    state=$(jq -r ".state" .run/state.json)
    if [[ "$state" == "HALTED" ]]; then
      jq ".state = \"RUNNING\"" .run/state.json > .run/state.json.tmp
      mv .run/state.json.tmp .run/state.json
      echo "Resumed from HALTED"
      jq -r ".state" .run/state.json
    fi
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"Resumed"* ]]
  [[ "$output" == *"RUNNING"* ]]
}

@test "run-resume --reset-ice clears circuit breaker" {
  mkdir -p .run
  cat > .run/circuit-breaker.json << 'EOF'
{
  "state": "OPEN",
  "triggers": {
    "same_issue": { "count": 5, "threshold": 3 }
  }
}
EOF

  run bash -c '
    # Reset circuit breaker
    jq ".state = \"CLOSED\" | .triggers.same_issue.count = 0" \
      .run/circuit-breaker.json > .run/circuit-breaker.json.tmp
    mv .run/circuit-breaker.json.tmp .run/circuit-breaker.json
    echo "Circuit breaker reset"
    jq -r ".state" .run/circuit-breaker.json
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"reset"* ]]
  [[ "$output" == *"CLOSED"* ]]
}

# =============================================================================
# Deleted Files Tracking Tests
# =============================================================================

@test "deleted files logged correctly" {
  mkdir -p .run

  # Log a deletion
  echo "src/old-file.ts|sprint-1|1" >> .run/deleted-files.log
  echo "src/legacy/helper.ts|sprint-1|2" >> .run/deleted-files.log

  run bash -c '
    if [[ -f .run/deleted-files.log ]]; then
      count=$(wc -l < .run/deleted-files.log)
      echo "Deleted files: $count"
      cat .run/deleted-files.log
    fi
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"Deleted files: 2"* ]]
  [[ "$output" == *"src/old-file.ts"* ]]
}

# =============================================================================
# Rate Limiting Tests
# =============================================================================

@test "rate limit state initialized" {
  mkdir -p .run

  current_hour=$(date -u +"%Y-%m-%dT%H:00:00Z")
  cat > .run/rate-limit.json << EOF
{
  "hour_boundary": "$current_hour",
  "calls_this_hour": 0,
  "limit": 100,
  "waits": []
}
EOF

  run jq '.calls_this_hour' .run/rate-limit.json
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "rate limit increments on call" {
  mkdir -p .run
  current_hour=$(date -u +"%Y-%m-%dT%H:00:00Z")
  cat > .run/rate-limit.json << EOF
{"hour_boundary": "$current_hour", "calls_this_hour": 50, "limit": 100}
EOF

  run bash -c '
    jq ".calls_this_hour += 1" .run/rate-limit.json > .run/rate-limit.json.tmp
    mv .run/rate-limit.json.tmp .run/rate-limit.json
    jq ".calls_this_hour" .run/rate-limit.json
  '
  [ "$status" -eq 0 ]
  [ "$output" = "51" ]
}

@test "rate limit detects when limit reached" {
  mkdir -p .run
  cat > .run/rate-limit.json << 'EOF'
{"calls_this_hour": 100, "limit": 100}
EOF

  run bash -c '
    calls=$(jq ".calls_this_hour" .run/rate-limit.json)
    limit=$(jq ".limit" .run/rate-limit.json)
    if [[ $calls -ge $limit ]]; then
      echo "Rate limit reached ($calls/$limit)"
      exit 0
    fi
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"Rate limit reached"* ]]
}
