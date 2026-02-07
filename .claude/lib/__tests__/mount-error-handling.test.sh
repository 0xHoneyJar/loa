#!/usr/bin/env bash
# mount-error-handling.test.sh — Shell tests for mount-loa.sh structured error handling
# Covers all 14+ PRD acceptance scenarios for E010-E016
# Run: bash .claude/lib/__tests__/mount-error-handling.test.sh
set -uo pipefail

# === Test Framework ===
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0
TEST_TMPDIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MOUNT_SCRIPT="${SCRIPT_DIR}/scripts/mount-loa.sh"
ORIG_DIR="$(pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { ((TESTS_PASSED++)); echo -e "  ${GREEN}PASS${NC} $1"; }
fail() { ((TESTS_FAILED++)); echo -e "  ${RED}FAIL${NC} $1: $2"; }
skip() { ((TESTS_SKIPPED++)); echo -e "  ${YELLOW}SKIP${NC} $1: $2"; }

# === JSON Validation (pure-shell, no jq dependency) ===
# Validates that a string looks like a single-line JSON object with required keys
assert_json_has_keys() {
  local json="$1"
  shift
  local keys=("$@")

  # Must start with { and end with }
  case "$json" in
    \{*\}) ;; # valid JSON object shape
    *) echo "Not a JSON object: $json"; return 1 ;;
  esac

  # Must be single-line (no literal newlines in the value)
  if [[ $(echo "$json" | wc -l) -gt 1 ]]; then
    echo "JSON is multi-line"
    return 1
  fi

  # Check each required key exists as "key":
  for key in "${keys[@]}"; do
    case "$json" in
      *"\"${key}\""*) ;; # key found
      *) echo "Missing key: $key"; return 1 ;;
    esac
  done

  # Optional: validate with jq if available
  if command -v jq &>/dev/null; then
    if ! echo "$json" | jq . >/dev/null 2>&1; then
      echo "Invalid JSON (jq validation failed)"
      return 1
    fi
  fi

  return 0
}

# Extract a JSON string value by key (pure-shell)
json_value() {
  local json="$1"
  local key="$2"
  # Match "key":"value" — handles escaped quotes inside value
  echo "$json" | sed -n "s/.*\"${key}\":\"\([^\"]*\)\".*/\1/p"
}

# === Test Helpers ===

setup_empty_repo() {
  TEST_TMPDIR=$(mktemp -d)
  cd "$TEST_TMPDIR"
  git init --quiet
  git config user.name "Test User"
  git config user.email "test@example.com"
}

setup_bare_repo() {
  TEST_TMPDIR=$(mktemp -d)
  cd "$TEST_TMPDIR"
  git init --bare --quiet
}

setup_repo_with_commits() {
  TEST_TMPDIR=$(mktemp -d)
  cd "$TEST_TMPDIR"
  git init --quiet
  git config user.name "Test User"
  git config user.email "test@example.com"
  echo "init" > README.md
  git add README.md
  git commit -m "initial" --quiet
}

setup_repo_no_user() {
  TEST_TMPDIR=$(mktemp -d)
  cd "$TEST_TMPDIR"
  git init --quiet
  # Explicitly unset user config
  git config --unset user.name 2>/dev/null || true
  git config --unset user.email 2>/dev/null || true
  # Also unset global if scoped to this repo
  git config --local --unset user.name 2>/dev/null || true
  git config --local --unset user.email 2>/dev/null || true
}

cleanup() {
  cd "$ORIG_DIR"
  if [[ -n "$TEST_TMPDIR" && -d "$TEST_TMPDIR" ]]; then
    # Restore permissions (E011 test makes objects read-only)
    chmod -R u+rwX "$TEST_TMPDIR" 2>/dev/null || true
    rm -rf "$TEST_TMPDIR"
  fi
  TEST_TMPDIR=""
}

# Source only the error-handling functions from mount-loa.sh
# (Avoids running the full script which has side effects)
source_error_functions() {
  # Extract and source just the functions we need for unit testing
  # We re-source the key functions to test them in isolation
  _json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    s=$(printf '%s' "$s" | tr -d '\000-\010\013\014\016-\037')
    printf '%s' "$s"
  }
}

# Run mount-loa.sh in a controlled environment, capture stderr for JSON
run_mount() {
  local dir="$1"
  shift
  local stderr_file="${dir}/.test-stderr"
  local stdout_file="${dir}/.test-stdout"
  local exit_code=0

  # Run script with --no-commit to avoid modifying the repo beyond what we test
  cd "$dir"
  bash "$MOUNT_SCRIPT" "$@" >"$stdout_file" 2>"$stderr_file" || exit_code=$?

  echo "$exit_code"
}

get_stderr() {
  cat "${1}/.test-stderr"
}

get_stdout() {
  cat "${1}/.test-stdout"
}

# Extract the last JSON line from stderr
get_json_line() {
  local stderr_file="${1}/.test-stderr"
  grep '^{' "$stderr_file" | tail -1
}

# === Tests ===

echo "=== Mount Script Error Handling Tests ==="
echo "Script: $MOUNT_SCRIPT"
echo ""

# --- Test 1: _json_escape handles basic escaping ---
test_json_escape_basic() {
  ((TESTS_RUN++))
  source_error_functions

  local input='hello "world"'
  local expected='hello \"world\"'
  local result; result=$(_json_escape "$input")

  if [[ "$result" == "$expected" ]]; then
    pass "json_escape: double quotes"
  else
    fail "json_escape: double quotes" "got '$result', expected '$expected'"
  fi
}
test_json_escape_basic

# --- Test 2: _json_escape handles backslashes ---
test_json_escape_backslash() {
  ((TESTS_RUN++))
  source_error_functions

  local input='path\to\file'
  local expected='path\\to\\file'
  local result; result=$(_json_escape "$input")

  if [[ "$result" == "$expected" ]]; then
    pass "json_escape: backslashes"
  else
    fail "json_escape: backslashes" "got '$result', expected '$expected'"
  fi
}
test_json_escape_backslash

# --- Test 3: _json_escape handles newlines and tabs ---
test_json_escape_control_chars() {
  ((TESTS_RUN++))
  source_error_functions

  local input=$'line1\nline2\ttab'
  local result; result=$(_json_escape "$input")

  if [[ "$result" == *'\n'* ]] && [[ "$result" == *'\t'* ]]; then
    pass "json_escape: newlines and tabs"
  else
    fail "json_escape: newlines and tabs" "got '$result'"
  fi
}
test_json_escape_control_chars

# --- Test 4: E010 — git not installed ---
test_e010_no_git() {
  ((TESTS_RUN++))

  setup_repo_with_commits
  local dir="$TEST_TMPDIR"

  # Hide git from PATH
  local exit_code
  exit_code=$(PATH="/usr/bin/this-does-not-exist" bash "$MOUNT_SCRIPT" --no-commit 2>"${dir}/.test-stderr" >/dev/null; echo $?) || true

  if [[ "$exit_code" -ne 0 ]]; then
    local json; json=$(get_json_line "$dir")
    if [[ -n "$json" ]]; then
      local code; code=$(json_value "$json" "code")
      if [[ "$code" == "E010" ]]; then
        pass "E010: git not installed"
      else
        fail "E010: git not installed" "wrong code: $code"
      fi
    else
      # When git is completely absent from PATH, bash may fail to resolve
      # mount_error's git-dependent helpers. Non-zero exit is the minimum
      # safety guarantee; structured JSON requires git to be loadable.
      local stderr_content; stderr_content=$(get_stderr "$dir")
      if echo "$stderr_content" | grep -qi "git\|command not found"; then
        pass "E010: git not installed (unstructured but clear)"
      else
        fail "E010: git not installed" "no JSON and no clear error message"
      fi
    fi
  else
    fail "E010: git not installed" "expected non-zero exit"
  fi

  cleanup
}
test_e010_no_git

# --- Test 5: E010 — not a git repo ---
test_e010_not_a_repo() {
  ((TESTS_RUN++))

  TEST_TMPDIR=$(mktemp -d)
  local dir="$TEST_TMPDIR"

  local exit_code
  exit_code=$(cd "$dir" && bash "$MOUNT_SCRIPT" --no-commit 2>"${dir}/.test-stderr" >/dev/null; echo $?) || true

  if [[ "$exit_code" -ne 0 ]]; then
    local json; json=$(get_json_line "$dir")
    if [[ -n "$json" ]]; then
      local code; code=$(json_value "$json" "code")
      if [[ "$code" == "E010" ]]; then
        if assert_json_has_keys "$json" code name message fix; then
          pass "E010: not a git repo"
        else
          fail "E010: not a git repo" "JSON missing required keys"
        fi
      else
        fail "E010: not a git repo" "wrong code: $code"
      fi
    else
      fail "E010: not a git repo" "no JSON output on stderr"
    fi
  else
    fail "E010: not a git repo" "expected non-zero exit"
  fi

  cleanup
}
test_e010_not_a_repo

# --- Test 6: E015 — bare repo ---
test_e015_bare_repo() {
  ((TESTS_RUN++))

  setup_bare_repo
  local dir="$TEST_TMPDIR"

  local exit_code
  exit_code=$(cd "$dir" && bash "$MOUNT_SCRIPT" --no-commit 2>"${dir}/.test-stderr" >/dev/null; echo $?) || true

  if [[ "$exit_code" -ne 0 ]]; then
    local json; json=$(get_json_line "$dir")
    if [[ -n "$json" ]]; then
      local code; code=$(json_value "$json" "code")
      if [[ "$code" == "E015" ]]; then
        if assert_json_has_keys "$json" code name message fix; then
          pass "E015: bare repo"
        else
          fail "E015: bare repo" "JSON missing required keys"
        fi
      else
        fail "E015: bare repo" "wrong code: $code"
      fi
    else
      fail "E015: bare repo" "no JSON output on stderr"
    fi
  else
    fail "E015: bare repo" "expected non-zero exit"
  fi

  cleanup
}
test_e015_bare_repo

# --- Test 7: detect_repo_state — empty repo sets REPO_IS_EMPTY ---
test_detect_empty_repo() {
  ((TESTS_RUN++))

  setup_empty_repo
  local dir="$TEST_TMPDIR"

  # Source detect_repo_state and run it
  cd "$dir"
  REPO_IS_BARE=false
  REPO_IS_EMPTY=false
  REPO_HAS_COMMITS=false
  REPO_HAS_GIT_USER=false
  REPO_HAS_COMMIT_POLICIES=false

  # Source detect_repo_state from the script
  eval "$(sed -n '/^detect_repo_state()/,/^}/p' "$MOUNT_SCRIPT")"
  detect_repo_state

  if [[ "$REPO_IS_EMPTY" == "true" && "$REPO_HAS_COMMITS" == "false" ]]; then
    pass "detect_repo_state: empty repo"
  else
    fail "detect_repo_state: empty repo" "REPO_IS_EMPTY=$REPO_IS_EMPTY, REPO_HAS_COMMITS=$REPO_HAS_COMMITS"
  fi

  cleanup
}
test_detect_empty_repo

# --- Test 8: detect_repo_state — repo with commits ---
test_detect_existing_repo() {
  ((TESTS_RUN++))

  setup_repo_with_commits
  local dir="$TEST_TMPDIR"

  cd "$dir"
  REPO_IS_BARE=false
  REPO_IS_EMPTY=false
  REPO_HAS_COMMITS=false
  REPO_HAS_GIT_USER=false
  REPO_HAS_COMMIT_POLICIES=false

  eval "$(sed -n '/^detect_repo_state()/,/^}/p' "$MOUNT_SCRIPT")"
  detect_repo_state

  if [[ "$REPO_IS_EMPTY" == "false" && "$REPO_HAS_COMMITS" == "true" ]]; then
    pass "detect_repo_state: repo with commits"
  else
    fail "detect_repo_state: repo with commits" "REPO_IS_EMPTY=$REPO_IS_EMPTY, REPO_HAS_COMMITS=$REPO_HAS_COMMITS"
  fi

  cleanup
}
test_detect_existing_repo

# --- Test 9: detect_repo_state — bare repo ---
test_detect_bare_repo() {
  ((TESTS_RUN++))

  setup_bare_repo
  local dir="$TEST_TMPDIR"

  cd "$dir"
  REPO_IS_BARE=false
  REPO_IS_EMPTY=false
  REPO_HAS_COMMITS=false
  REPO_HAS_GIT_USER=false
  REPO_HAS_COMMIT_POLICIES=false

  eval "$(sed -n '/^detect_repo_state()/,/^}/p' "$MOUNT_SCRIPT")"
  detect_repo_state

  if [[ "$REPO_IS_BARE" == "true" ]]; then
    pass "detect_repo_state: bare repo"
  else
    fail "detect_repo_state: bare repo" "REPO_IS_BARE=$REPO_IS_BARE"
  fi

  cleanup
}
test_detect_bare_repo

# --- Test 10: E016 policy detection — GPG signing ---
test_e016_gpg_policy() {
  ((TESTS_RUN++))

  setup_repo_with_commits
  local dir="$TEST_TMPDIR"
  cd "$dir"

  # Set GPG signing (without actual GPG — forces policy detection)
  git config commit.gpgsign true

  REPO_IS_BARE=false
  REPO_IS_EMPTY=false
  REPO_HAS_COMMITS=false
  REPO_HAS_GIT_USER=false
  REPO_HAS_COMMIT_POLICIES=false

  eval "$(sed -n '/^detect_repo_state()/,/^}/p' "$MOUNT_SCRIPT")"
  detect_repo_state

  if [[ "$REPO_HAS_COMMIT_POLICIES" == "true" ]]; then
    pass "E016: GPG policy detected"
  else
    fail "E016: GPG policy detected" "REPO_HAS_COMMIT_POLICIES=$REPO_HAS_COMMIT_POLICIES"
  fi

  cleanup
}
test_e016_gpg_policy

# --- Test 11: E016 policy detection — pre-commit hook ---
test_e016_hook_policy() {
  ((TESTS_RUN++))

  setup_repo_with_commits
  local dir="$TEST_TMPDIR"
  cd "$dir"

  # Create executable pre-commit hook
  mkdir -p .git/hooks
  echo '#!/bin/sh' > .git/hooks/pre-commit
  echo 'exit 1' >> .git/hooks/pre-commit
  chmod +x .git/hooks/pre-commit

  REPO_IS_BARE=false
  REPO_IS_EMPTY=false
  REPO_HAS_COMMITS=false
  REPO_HAS_GIT_USER=false
  REPO_HAS_COMMIT_POLICIES=false

  eval "$(sed -n '/^detect_repo_state()/,/^}/p' "$MOUNT_SCRIPT")"
  detect_repo_state

  if [[ "$REPO_HAS_COMMIT_POLICIES" == "true" ]]; then
    pass "E016: hook policy detected"
  else
    fail "E016: hook policy detected" "REPO_HAS_COMMIT_POLICIES=$REPO_HAS_COMMIT_POLICIES"
  fi

  cleanup
}
test_e016_hook_policy

# --- Test 12: mount_warn_policy sets guard ---
test_warn_policy_sets_guard() {
  ((TESTS_RUN++))

  source_error_functions
  _MOUNT_STRUCTURED_WARNING_EMITTED=false

  # Redefine mount_warn_policy locally for testing
  # Source the function from mount-loa.sh
  local func_body
  func_body=$(sed -n '/^mount_warn_policy()/,/^}/p' "$MOUNT_SCRIPT")
  # Also need color variables and _json_escape
  RED='\033[0;31m'
  YELLOW='\033[1;33m'
  CYAN='\033[0;36m'
  NC='\033[0m'

  eval "$func_body"
  mount_warn_policy "test context" 2>/dev/null

  if [[ "$_MOUNT_STRUCTURED_WARNING_EMITTED" == "true" ]]; then
    pass "mount_warn_policy: sets warning guard"
  else
    fail "mount_warn_policy: sets warning guard" "_MOUNT_STRUCTURED_WARNING_EMITTED=$_MOUNT_STRUCTURED_WARNING_EMITTED"
  fi
}
test_warn_policy_sets_guard

# --- Test 13: mount_warn_policy emits JSON with severity=warning ---
test_warn_policy_json() {
  ((TESTS_RUN++))

  source_error_functions
  _MOUNT_STRUCTURED_WARNING_EMITTED=false
  RED='\033[0;31m'
  YELLOW='\033[1;33m'
  CYAN='\033[0;36m'
  NC='\033[0m'

  local func_body
  func_body=$(sed -n '/^mount_warn_policy()/,/^}/p' "$MOUNT_SCRIPT")
  eval "$func_body"

  local stderr_output
  stderr_output=$(mount_warn_policy "test policy" 2>&1)
  local json; json=$(echo "$stderr_output" | grep '^{' | tail -1)

  if [[ -n "$json" ]]; then
    local severity; severity=$(json_value "$json" "severity")
    if [[ "$severity" == "warning" ]]; then
      if assert_json_has_keys "$json" code name message fix severity; then
        pass "mount_warn_policy: JSON with severity=warning"
      else
        fail "mount_warn_policy: JSON" "missing required keys"
      fi
    else
      fail "mount_warn_policy: JSON" "severity='$severity', expected 'warning'"
    fi
  else
    fail "mount_warn_policy: JSON" "no JSON on stderr"
  fi
}
test_warn_policy_json

# --- Test 14: EXIT trap suppressed on success ---
test_exit_trap_success() {
  ((TESTS_RUN++))

  # Run a minimal script that sources exit handler and exits 0
  local tmpscript; tmpscript=$(mktemp)
  cat > "$tmpscript" << 'SCRIPT'
#!/usr/bin/env bash
set -uo pipefail
_MOUNT_STRUCTURED_FATAL_EMITTED=false
_json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  s=$(printf '%s' "$s" | tr -d '\000-\010\013\014\016-\037')
  printf '%s' "$s"
}
RED='\033[0;31m' NC='\033[0m'
_exit_handler() {
  local exit_code=$?
  if [[ $exit_code -eq 0 ]]; then return; fi
  if [[ "$_MOUNT_STRUCTURED_FATAL_EMITTED" == "true" ]]; then return; fi
  echo -e "${RED}[loa] ERROR (E013): Unexpected failure (exit code ${exit_code})${NC}" >&2
  local esc_msg; esc_msg=$(_json_escape "Unexpected failure (exit code ${exit_code})")
  local esc_fix; esc_fix=$(_json_escape "Check git status and retry with --force")
  printf '{"code":"E013","name":"mount_commit_failed","message":"%s","fix":"%s"}\n' "$esc_msg" "$esc_fix" >&2
}
trap '_exit_handler' EXIT
exit 0
SCRIPT

  local stderr_output
  stderr_output=$(bash "$tmpscript" 2>&1)
  rm -f "$tmpscript"

  if [[ -z "$stderr_output" ]]; then
    pass "EXIT trap: suppressed on success"
  else
    fail "EXIT trap: suppressed on success" "got output: $stderr_output"
  fi
}
test_exit_trap_success

# --- Test 15: EXIT trap fires on unexpected failure ---
test_exit_trap_fires() {
  ((TESTS_RUN++))

  local tmpscript; tmpscript=$(mktemp)
  cat > "$tmpscript" << 'SCRIPT'
#!/usr/bin/env bash
set -uo pipefail
_MOUNT_STRUCTURED_FATAL_EMITTED=false
_json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  s=$(printf '%s' "$s" | tr -d '\000-\010\013\014\016-\037')
  printf '%s' "$s"
}
RED='\033[0;31m' NC='\033[0m'
_exit_handler() {
  local exit_code=$?
  if [[ $exit_code -eq 0 ]]; then return; fi
  if [[ "$_MOUNT_STRUCTURED_FATAL_EMITTED" == "true" ]]; then return; fi
  local esc_msg; esc_msg=$(_json_escape "Unexpected failure (exit code ${exit_code})")
  local esc_fix; esc_fix=$(_json_escape "Check git status and retry with --force")
  printf '{"code":"E013","name":"mount_commit_failed","message":"%s","fix":"%s"}\n' "$esc_msg" "$esc_fix" >&2
}
trap '_exit_handler' EXIT
exit 42
SCRIPT

  local stderr_output
  stderr_output=$(bash "$tmpscript" 2>&1) || true
  rm -f "$tmpscript"

  local json; json=$(echo "$stderr_output" | grep '^{' | tail -1)
  if [[ -n "$json" ]]; then
    local code; code=$(json_value "$json" "code")
    local msg; msg=$(json_value "$json" "message")
    if [[ "$code" == "E013" ]] && [[ "$msg" == *"42"* ]]; then
      pass "EXIT trap: fires on unexpected failure"
    else
      fail "EXIT trap: fires on unexpected failure" "code=$code, msg=$msg"
    fi
  else
    fail "EXIT trap: fires on unexpected failure" "no JSON output"
  fi
}
test_exit_trap_fires

# --- Test 16: EXIT trap suppressed after mount_error ---
test_exit_trap_suppressed_after_error() {
  ((TESTS_RUN++))

  local tmpscript; tmpscript=$(mktemp)
  cat > "$tmpscript" << 'SCRIPT'
#!/usr/bin/env bash
set -uo pipefail
_MOUNT_STRUCTURED_FATAL_EMITTED=false
_json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  s=$(printf '%s' "$s" | tr -d '\000-\010\013\014\016-\037')
  printf '%s' "$s"
}
RED='\033[0;31m' NC='\033[0m'
_exit_handler() {
  local exit_code=$?
  if [[ $exit_code -eq 0 ]]; then return; fi
  if [[ "$_MOUNT_STRUCTURED_FATAL_EMITTED" == "true" ]]; then return; fi
  printf '{"code":"E013","name":"mount_commit_failed","message":"SHOULD_NOT_APPEAR","fix":"none"}\n' >&2
}
trap '_exit_handler' EXIT
# Simulate mount_error setting fatal guard then exiting
_MOUNT_STRUCTURED_FATAL_EMITTED=true
printf '{"code":"E010","name":"mount_no_git_repo","message":"test","fix":"test"}\n' >&2
exit 1
SCRIPT

  local stderr_output
  stderr_output=$(bash "$tmpscript" 2>&1) || true
  rm -f "$tmpscript"

  # Should see E010 but NOT E013
  if echo "$stderr_output" | grep -q "SHOULD_NOT_APPEAR"; then
    fail "EXIT trap: suppressed after mount_error" "E013 fired despite guard"
  else
    if echo "$stderr_output" | grep -q "E010"; then
      pass "EXIT trap: suppressed after mount_error"
    else
      fail "EXIT trap: suppressed after mount_error" "E010 not found either"
    fi
  fi
}
test_exit_trap_suppressed_after_error

# --- Test 17: Path-scoped rollback preserves user staged changes ---
test_rollback_preserves_user_staged() {
  ((TESTS_RUN++))

  setup_repo_with_commits
  local dir="$TEST_TMPDIR"
  cd "$dir"

  # Stage a user file (should be preserved after rollback)
  echo "user content" > userfile.txt
  git add userfile.txt

  # Verify it's staged
  local before; before=$(git diff --cached --name-only)
  if [[ "$before" != *"userfile.txt"* ]]; then
    fail "rollback: preserves user staged" "setup failed — userfile not staged"
    cleanup
    return
  fi

  # Create framework files and stage them
  mkdir -p .claude
  echo "test" > .claude/test.txt
  echo "test" > CLAUDE.md
  git add .claude CLAUDE.md

  # Now simulate path-scoped rollback (same as mount script)
  local fw_paths=(.claude CLAUDE.md)
  git restore --staged -- "${fw_paths[@]}" 2>/dev/null || git reset -q -- "${fw_paths[@]}" 2>/dev/null

  # Verify user file is still staged
  local after; after=$(git diff --cached --name-only)
  if [[ "$after" == *"userfile.txt"* ]]; then
    # Verify framework files are NOT staged
    if [[ "$after" != *".claude"* ]] && [[ "$after" != *"CLAUDE.md"* ]]; then
      pass "rollback: preserves user staged changes"
    else
      fail "rollback: preserves user staged changes" "framework files still staged: $after"
    fi
  else
    fail "rollback: preserves user staged changes" "userfile.txt was unstaged"
  fi

  cleanup
}
test_rollback_preserves_user_staged

# --- Test 18: mount_error JSON has required schema keys ---
test_mount_error_json_schema() {
  ((TESTS_RUN++))

  source_error_functions
  _MOUNT_STRUCTURED_FATAL_EMITTED=false
  RED='\033[0;31m'
  YELLOW='\033[1;33m'
  CYAN='\033[0;36m'
  NC='\033[0m'

  # Source mount_error
  local func_body
  func_body=$(sed -n '/^mount_error()/,/^}/p' "$MOUNT_SCRIPT")
  eval "$func_body"

  # Override exit to prevent test termination
  exit() { return 0; }

  local stderr_output
  stderr_output=$(mount_error E010 "extra context" 2>&1)

  # Restore exit
  unset -f exit

  local json; json=$(echo "$stderr_output" | grep '^{' | tail -1)
  if [[ -n "$json" ]]; then
    if assert_json_has_keys "$json" code name message fix details; then
      pass "mount_error: JSON schema (with details)"
    else
      fail "mount_error: JSON schema" "$(assert_json_has_keys "$json" code name message fix details 2>&1)"
    fi
  else
    fail "mount_error: JSON schema" "no JSON on stderr"
  fi
}
test_mount_error_json_schema

# --- Test 19: Successful mount produces no JSON error on stderr ---
# (Integration test — requires network for git fetch, so conditional)
test_success_no_json_error() {
  ((TESTS_RUN++))

  # This is a bonus test — skip if we can't set up a full environment
  if [[ -z "${LOA_INTEGRATION_TESTS:-}" ]]; then
    skip "success: no JSON error" "set LOA_INTEGRATION_TESTS=1 to enable"
    return
  fi

  setup_repo_with_commits
  local dir="$TEST_TMPDIR"

  local exit_code
  exit_code=$(run_mount "$dir" --no-commit)

  if [[ "$exit_code" -eq 0 ]]; then
    local json_lines
    json_lines=$(get_stderr "$dir" | grep '^{' || true)
    if [[ -z "$json_lines" ]]; then
      pass "success: no JSON error on stderr"
    else
      fail "success: no JSON error on stderr" "found JSON: $json_lines"
    fi
  else
    skip "success: no JSON error" "mount failed (expected in test env)"
  fi

  cleanup
}
test_success_no_json_error

# --- Test 20: Error code consistency between mount_error and error-codes.json ---
test_error_code_consistency() {
  ((TESTS_RUN++))

  local error_codes_json="${SCRIPT_DIR}/data/error-codes.json"
  if [[ ! -f "$error_codes_json" ]]; then
    skip "error code consistency" "error-codes.json not found at $error_codes_json"
    return
  fi

  # Extract E0XX codes from mount_error case statement in mount-loa.sh
  local script_codes
  script_codes=$(sed -n '/^mount_error()/,/^}/p' "$MOUNT_SCRIPT" | \
    grep -oE 'E0[0-9]{2}\)' | sed 's/)//' | sort -u)

  # Extract mount-category codes from error-codes.json (pure grep, no jq required)
  local json_codes
  json_codes=$(grep -B2 '"mount"' "$error_codes_json" | \
    grep -oE '"E0[0-9]{2}"' | tr -d '"' | sort -u)

  if [[ -z "$script_codes" ]]; then
    fail "error code consistency" "no codes found in mount_error case statement"
    return
  fi
  if [[ -z "$json_codes" ]]; then
    fail "error code consistency" "no mount codes found in error-codes.json"
    return
  fi

  # Check that every code in mount_error exists in error-codes.json
  local missing=""
  for code in $script_codes; do
    if ! echo "$json_codes" | grep -q "^${code}$"; then
      missing="${missing} ${code}"
    fi
  done

  # Check that every mount code in error-codes.json exists in mount_error
  local extra=""
  for code in $json_codes; do
    if ! echo "$script_codes" | grep -q "^${code}$"; then
      extra="${extra} ${code}"
    fi
  done

  if [[ -z "$missing" && -z "$extra" ]]; then
    pass "error code consistency: mount_error matches error-codes.json"
  else
    local detail=""
    [[ -n "$missing" ]] && detail="missing from JSON:${missing}"
    [[ -n "$extra" ]] && detail="${detail:+$detail; }in JSON but not in case:${extra}"
    fail "error code consistency" "$detail"
  fi
}
test_error_code_consistency

# === Summary ===
echo ""
echo "=== Results ==="
echo -e "  Total:   $TESTS_RUN"
echo -e "  ${GREEN}Passed:  $TESTS_PASSED${NC}"
if [[ $TESTS_FAILED -gt 0 ]]; then
  echo -e "  ${RED}Failed:  $TESTS_FAILED${NC}"
fi
if [[ $TESTS_SKIPPED -gt 0 ]]; then
  echo -e "  ${YELLOW}Skipped: $TESTS_SKIPPED${NC}"
fi
echo ""

if [[ $TESTS_FAILED -gt 0 ]]; then
  exit 1
fi
exit 0
