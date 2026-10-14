#!/usr/bin/env bats

# Unit tests for run-mode-ice.sh (ICE - Intrusion Countermeasures Electronics)
# Tests the git safety wrapper for Run Mode
#
# Test coverage:
#   - Protected branch detection (exact matches and patterns)
#   - Safe operations (checkout, push with constraints)
#   - Always blocked operations (merge, force push, branch delete)
#   - Feature branch management (ensure-branch)
#   - CLI interface

setup() {
  BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
  export ICE_SCRIPT="$PROJECT_ROOT/.claude/scripts/run-mode-ice.sh"

  # Create temp directory for test artifacts
  export BATS_TMPDIR="${BATS_TMPDIR:-/tmp}"
  export TEST_TMPDIR="$BATS_TMPDIR/run-mode-ice-test-$$"
  mkdir -p "$TEST_TMPDIR"

  # Create test git repo
  export TEST_REPO="$TEST_TMPDIR/repo"
  mkdir -p "$TEST_REPO"
  cd "$TEST_REPO"
  git init --quiet
  git config user.email "test@test.com"
  git config user.name "Test User"
  echo "test" > README.md
  git add README.md
  git commit -m "Initial commit" --quiet

  # Create a feature branch
  git checkout -b feature/test --quiet
}

teardown() {
  cd /
  if [[ -d "$TEST_TMPDIR" ]]; then
    rm -rf "$TEST_TMPDIR"
  fi
}

# Helper to skip if script not available
skip_if_script_missing() {
  if [[ ! -f "$ICE_SCRIPT" ]]; then
    skip "run-mode-ice.sh not available"
  fi
}

# ============================================================================
# Protected Branch Detection Tests
# ============================================================================

@test "is_protected_branch: main is protected" {
  run "$ICE_SCRIPT" is-protected main
  [ "$status" -eq 0 ]
  [[ "$output" == "true" ]]
}

@test "is_protected_branch: master is protected" {
  run "$ICE_SCRIPT" is-protected master
  [ "$status" -eq 0 ]
  [[ "$output" == "true" ]]
}

@test "is_protected_branch: staging is protected" {
  run "$ICE_SCRIPT" is-protected staging
  [ "$status" -eq 0 ]
  [[ "$output" == "true" ]]
}

@test "is_protected_branch: develop is protected" {
  run "$ICE_SCRIPT" is-protected develop
  [ "$status" -eq 0 ]
  [[ "$output" == "true" ]]
}

@test "is_protected_branch: development is protected" {
  run "$ICE_SCRIPT" is-protected development
  [ "$status" -eq 0 ]
  [[ "$output" == "true" ]]
}

@test "is_protected_branch: production is protected" {
  run "$ICE_SCRIPT" is-protected production
  [ "$status" -eq 0 ]
  [[ "$output" == "true" ]]
}

@test "is_protected_branch: prod is protected" {
  run "$ICE_SCRIPT" is-protected prod
  [ "$status" -eq 0 ]
  [[ "$output" == "true" ]]
}

@test "is_protected_branch: release/* pattern matches" {
  run "$ICE_SCRIPT" is-protected release/v1.0.0
  [ "$status" -eq 0 ]
  [[ "$output" == "true" ]]
}

@test "is_protected_branch: release-* pattern matches" {
  run "$ICE_SCRIPT" is-protected release-2.0
  [ "$status" -eq 0 ]
  [[ "$output" == "true" ]]
}

@test "is_protected_branch: hotfix/* pattern matches" {
  run "$ICE_SCRIPT" is-protected hotfix/security-patch
  [ "$status" -eq 0 ]
  [[ "$output" == "true" ]]
}

@test "is_protected_branch: hotfix-* pattern matches" {
  run "$ICE_SCRIPT" is-protected hotfix-urgent
  [ "$status" -eq 0 ]
  [[ "$output" == "true" ]]
}

@test "is_protected_branch: feature branch is NOT protected" {
  run "$ICE_SCRIPT" is-protected feature/new-feature
  [ "$status" -eq 1 ]
  [[ "$output" == "false" ]]
}

@test "is_protected_branch: bugfix branch is NOT protected" {
  run "$ICE_SCRIPT" is-protected bugfix/fix-123
  [ "$status" -eq 1 ]
  [[ "$output" == "false" ]]
}

@test "is_protected_branch: chore branch is NOT protected" {
  run "$ICE_SCRIPT" is-protected chore/update-deps
  [ "$status" -eq 1 ]
  [[ "$output" == "false" ]]
}

@test "is_protected_branch: random branch is NOT protected" {
  run "$ICE_SCRIPT" is-protected my-random-branch
  [ "$status" -eq 1 ]
  [[ "$output" == "false" ]]
}

# ============================================================================
# Validate Working Branch Tests
# ============================================================================

@test "validate: passes on feature branch" {
  run "$ICE_SCRIPT" validate
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
  [[ "$output" == *"feature/test"* ]]
}

@test "validate: fails on main branch" {
  git checkout -b main --quiet 2>/dev/null || git checkout main --quiet
  run "$ICE_SCRIPT" validate
  [ "$status" -eq 1 ]
  [[ "$output" == *"protected branch"* ]]
}

# ============================================================================
# Safe Checkout Tests
# ============================================================================

@test "safe_checkout: allows checkout to feature branch" {
  git branch feature/other --quiet
  run "$ICE_SCRIPT" checkout feature/other
  [ "$status" -eq 0 ]
}

@test "safe_checkout: blocks checkout to main" {
  run "$ICE_SCRIPT" checkout main
  [ "$status" -eq 1 ]
  [[ "$output" == *"ICE"* ]]
  [[ "$output" == *"protected branch"* ]]
}

@test "safe_checkout: blocks checkout to master" {
  git branch master --quiet 2>/dev/null || true
  run "$ICE_SCRIPT" checkout master
  [ "$status" -eq 1 ]
  [[ "$output" == *"ICE"* ]]
}

@test "safe_checkout: blocks checkout to release branch" {
  git branch release/v1.0 --quiet
  run "$ICE_SCRIPT" checkout release/v1.0
  [ "$status" -eq 1 ]
  [[ "$output" == *"ICE"* ]]
}

# ============================================================================
# Safe Push Tests
# ============================================================================

@test "safe_push: blocks push to main" {
  run "$ICE_SCRIPT" push origin main
  [ "$status" -eq 1 ]
  [[ "$output" == *"ICE"* ]]
  [[ "$output" == *"protected branch"* ]]
}

@test "safe_push: blocks push to master" {
  run "$ICE_SCRIPT" push origin master
  [ "$status" -eq 1 ]
  [[ "$output" == *"ICE"* ]]
}

@test "safe_push: blocks push to production" {
  run "$ICE_SCRIPT" push origin production
  [ "$status" -eq 1 ]
  [[ "$output" == *"ICE"* ]]
}

@test "safe_push: blocks push to release branch" {
  run "$ICE_SCRIPT" push origin release/v2.0
  [ "$status" -eq 1 ]
  [[ "$output" == *"ICE"* ]]
}

# ============================================================================
# Always Blocked Operations Tests
# ============================================================================

@test "safe_merge: ALWAYS blocked" {
  run "$ICE_SCRIPT" merge
  [ "$status" -eq 1 ]
  [[ "$output" == *"BLOCKED"* ]]
  [[ "$output" == *"Human intervention"* ]]
}

@test "safe_pr_merge: ALWAYS blocked" {
  run "$ICE_SCRIPT" pr-merge
  [ "$status" -eq 1 ]
  [[ "$output" == *"BLOCKED"* ]]
  [[ "$output" == *"Human intervention"* ]]
}

@test "safe_branch_delete: ALWAYS blocked" {
  run "$ICE_SCRIPT" branch-delete feature/test
  [ "$status" -eq 1 ]
  [[ "$output" == *"BLOCKED"* ]]
  [[ "$output" == *"Human intervention"* ]]
}

@test "safe_force_push: ALWAYS blocked" {
  run "$ICE_SCRIPT" force-push
  [ "$status" -eq 1 ]
  [[ "$output" == *"BLOCKED"* ]]
  [[ "$output" == *"dangerous"* ]] || [[ "$output" == *"Force push"* ]]
}

# ============================================================================
# Ensure Feature Branch Tests
# ============================================================================

@test "ensure_feature_branch: creates new branch with prefix" {
  run "$ICE_SCRIPT" ensure-branch sprint-5
  [ "$status" -eq 0 ]

  # Verify branch was created
  run git branch --list feature/sprint-5
  [[ -n "$output" ]]
}

@test "ensure_feature_branch: checks out existing branch" {
  git branch feature/existing --quiet
  run "$ICE_SCRIPT" ensure-branch existing
  [ "$status" -eq 0 ]
  [[ "$output" == *"existing"* ]]
}

@test "ensure_feature_branch: stays on current if already on target" {
  git checkout -b feature/current --quiet
  run "$ICE_SCRIPT" ensure-branch current
  [ "$status" -eq 0 ]
  [[ "$output" == *"Already on"* ]]
}

# ============================================================================
# CLI Interface Tests
# ============================================================================

@test "cli: help shows usage" {
  run "$ICE_SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"ICE"* ]]
  [[ "$output" == *"Commands"* ]]
}

@test "cli: no args shows usage" {
  run "$ICE_SCRIPT"
  [ "$status" -eq 2 ]
}

@test "cli: unknown command returns error" {
  run "$ICE_SCRIPT" unknown-command
  [ "$status" -eq 2 ]
  [[ "$output" == *"Unknown command"* ]]
}

@test "cli: is-protected requires branch arg" {
  run "$ICE_SCRIPT" is-protected
  [ "$status" -eq 2 ]
  [[ "$output" == *"Usage"* ]]
}

@test "cli: checkout requires branch arg" {
  run "$ICE_SCRIPT" checkout
  [ "$status" -eq 2 ]
  [[ "$output" == *"Usage"* ]]
}

@test "cli: ensure-branch requires name arg" {
  run "$ICE_SCRIPT" ensure-branch
  [ "$status" -eq 2 ]
  [[ "$output" == *"Usage"* ]]
}
