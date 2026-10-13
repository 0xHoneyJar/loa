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

# ============================================================================
# Spike branches (grimoires/loa/sdd.md D-5.3): push allowed, never merged into
# another branch, never a PR; the default branch may be merged into a spike.
# ============================================================================

# The repo's default branch name (git init picks main or master).
ice_default_branch() {
  git -C "$TEST_REPO" for-each-ref --format='%(refname:short)' refs/heads | grep -xE 'main|master' | head -1
}

# A gh stub that records any call, so a refused pr-create provably never ran it.
ice_gh_stub() {
  mkdir -p "$TEST_TMPDIR/bin"
  cat > "$TEST_TMPDIR/bin/gh" <<'STUB'
#!/usr/bin/env bash
echo "gh $*" >> "$GH_LOG"
echo "https://example.invalid/pr/1"
STUB
  chmod +x "$TEST_TMPDIR/bin/gh"
  export GH_LOG="$TEST_TMPDIR/gh.log"
  : > "$GH_LOG"
  export PATH="$TEST_TMPDIR/bin:$PATH"
}

@test "is_spike_branch: spike/x and remote or full spike refs are spike branches" {
  run "$ICE_SCRIPT" is-spike spike/x
  [ "$status" -eq 0 ]
  [[ "$output" == "true" ]]
  run "$ICE_SCRIPT" is-spike origin/spike/x
  [ "$status" -eq 0 ]
  run "$ICE_SCRIPT" is-spike refs/heads/spike/x
  [ "$status" -eq 0 ]
}

@test "is_spike_branch: feature branches and lookalikes are not spike branches" {
  local b
  for b in feature/test main spike spikes/x myspike/x spike-x; do
    run "$ICE_SCRIPT" is-spike "$b"
    [ "$status" -eq 1 ]
    [[ "$output" == "false" ]]
  done
}

@test "cli: is-spike requires branch arg" {
  run "$ICE_SCRIPT" is-spike
  [ "$status" -eq 2 ]
  [[ "$output" == *"Usage"* ]]
}

@test "spike: a spike branch is not protected, and safe_push pushes it" {
  run "$ICE_SCRIPT" is-protected spike/x
  [ "$status" -eq 1 ]
  git init --bare --quiet "$TEST_TMPDIR/remote.git"
  git remote add origin "$TEST_TMPDIR/remote.git"
  git checkout -b spike/x --quiet
  run "$ICE_SCRIPT" push origin spike/x
  [ "$status" -eq 0 ]
  git --git-dir="$TEST_TMPDIR/remote.git" rev-parse --verify --quiet refs/heads/spike/x
}

@test "safe_merge: the old call shape (no source) stays ALWAYS blocked, also on a spike branch" {
  git checkout -b spike/x --quiet
  run "$ICE_SCRIPT" merge
  [ "$status" -eq 1 ]
  [[ "$output" == *"BLOCKED"* ]]
  [[ "$output" == *"Human intervention"* ]]
}

@test "safe_merge: merging the default branch into a spike branch is allowed and merges" {
  local base; base="$(ice_default_branch)"
  [ -n "$base" ]
  git checkout -b spike/x --quiet
  git checkout "$base" --quiet
  echo "more" > MORE.md && git add MORE.md && git commit -m "base moves on" --quiet
  git checkout spike/x --quiet
  run "$ICE_SCRIPT" merge "$base"
  [ "$status" -eq 0 ]
  [ -f MORE.md ]
  [[ "$output" == *"ICE: merging $base into spike branch 'spike/x'"* ]]
  [[ "$output" != *"did not complete"* ]]
}

@test "safe_merge: a diverged spike takes the default branch in even under merge.ff=only" {
  local base; base="$(ice_default_branch)"
  [ -n "$base" ]
  git config merge.ff only
  git checkout "$base" --quiet
  git checkout -b spike/x --quiet
  echo "proto" > PROTO.md && git add PROTO.md && git commit -m "spike work" --quiet
  git checkout "$base" --quiet
  echo "more" > MORE.md && git add MORE.md && git commit -m "base moves on" --quiet
  git checkout spike/x --quiet
  run "$ICE_SCRIPT" merge "$base"
  [ "$status" -eq 0 ]
  [ -f MORE.md ] && [ -f PROTO.md ]
  [[ "$output" != *"did not complete"* ]]
}

@test "safe_merge: a conflicting merge into a spike branch exits non-zero and names the way out" {
  local base; base="$(ice_default_branch)"
  [ -n "$base" ]
  git checkout "$base" --quiet
  git checkout -b spike/x --quiet
  echo "spike line" > README.md && git commit -am "spike edits the line" --quiet
  git checkout "$base" --quiet
  echo "base line" > README.md && git commit -am "base edits the same line" --quiet
  git checkout spike/x --quiet
  run "$ICE_SCRIPT" merge "$base"
  [ "$status" -ne 0 ]
  [[ "$output" == *"ICE: merging $base into spike branch 'spike/x'"* ]]
  [[ "$output" == *"ICE: merge of $base into spike/x did not complete; resolve the conflicts and commit, or abort with plain \`git merge --abort\` (ICE does not wrap abort)"* ]]
  # the merge is left in progress for the operator, not aborted by ICE
  git rev-parse -q --verify MERGE_HEAD >/dev/null
}

@test "safe_merge: a spike source is refused with the spike message, whatever the current branch" {
  git branch spike/x
  run "$ICE_SCRIPT" merge spike/x
  [ "$status" -eq 1 ]
  [[ "$output" == *"ICE: spike branches are never merged into another branch"* ]]
  git checkout -b spike/y --quiet
  run "$ICE_SCRIPT" merge origin/spike/x
  [ "$status" -eq 1 ]
  [[ "$output" == *"never merged into another branch"* ]]
}

@test "safe_merge: the default branch into a feature branch stays blocked" {
  local base; base="$(ice_default_branch)"
  run "$ICE_SCRIPT" merge "$base"
  [ "$status" -eq 1 ]
  [[ "$output" == *"BLOCKED"* ]]
}

@test "safe_merge: on a spike branch, a source other than the default branch stays blocked" {
  git checkout -b spike/x --quiet
  run "$ICE_SCRIPT" merge feature/test
  [ "$status" -eq 1 ]
  [[ "$output" == *"BLOCKED"* ]]
  run "$ICE_SCRIPT" merge --abort
  [ "$status" -eq 1 ]
}

@test "safe_pr_create: a spike head is refused and gh never runs" {
  ice_gh_stub
  git checkout -b spike/x --quiet
  run "$ICE_SCRIPT" pr-create "Title" "Body"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ICE: spike branches never get a PR"* ]]
  [[ "$output" == *"ICE BLOCK"* ]]
  [ ! -s "$GH_LOG" ]
  git checkout feature/test --quiet
  run "$ICE_SCRIPT" pr-create "Title" "Body" main spike/x
  [ "$status" -eq 1 ]
  [ ! -s "$GH_LOG" ]
}

@test "safe_pr_create: a feature head still creates a draft PR (control)" {
  ice_gh_stub
  run "$ICE_SCRIPT" pr-create "Title" "Body"
  [ "$status" -eq 0 ]
  grep -q -- '--draft' "$GH_LOG"
  grep -q -- '--head feature/test' "$GH_LOG"
}

@test "spike: ICE has no cherry-pick operation (a Miss of the ICE seam; the fence rule SP-1 blocks it)" {
  run "$ICE_SCRIPT" cherry-pick spike/x
  [ "$status" -eq 2 ]
  [[ "$output" == *"Unknown command"* ]]
  grep -q 'cherry-pick spike/' "$PROJECT_ROOT/tests/fixtures/fence-corpus/corpus.jsonl"
}
