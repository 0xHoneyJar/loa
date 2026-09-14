#!/usr/bin/env bash
# =============================================================================
# Safety Hook Regression Test Suite
# =============================================================================
# Persistent, re-runnable test harness for block-destructive-bash.sh.
# Validates all block patterns, allow patterns, edge cases, and failure modes.
#
# Usage:
#   bash .claude/scripts/test-safety-hooks.sh
#   bash .claude/scripts/test-safety-hooks.sh --verbose
#
# Exit codes:
#   0 = all tests pass
#   1 = one or more tests failed
#
# Source: Bridgebuilder Deep Review Critical 1 — "Who Tests the Testers?"
# Part of Loa Harness Engineering (cycle-011, issue #297)
# =============================================================================

set -uo pipefail

HOOK=".claude/hooks/safety/block-destructive-bash.sh"
PASS=0
FAIL=0
TOTAL=0
VERBOSE=false

[[ "${1:-}" == "--verbose" ]] && VERBOSE=true

# ---------------------------------------------------------------------------
# Test helper: run hook with a command, check exit code
# ---------------------------------------------------------------------------
test_hook() {
  local cmd="$1"
  local expected_exit="$2"
  local desc="$3"

  TOTAL=$((TOTAL + 1))

  # Build JSON input matching Claude Code's PreToolUse format
  local json_input
  json_input=$(jq -cn --arg c "$cmd" '{"tool_input":{"command":$c}}')

  # Run hook, capture exit code
  local actual_exit
  echo "$json_input" | bash "$HOOK" >/dev/null 2>/dev/null
  actual_exit=$?

  if [[ "$actual_exit" -eq "$expected_exit" ]]; then
    PASS=$((PASS + 1))
    [[ "$VERBOSE" == "true" ]] && printf "  [PASS] %s\n" "$desc"
  else
    FAIL=$((FAIL + 1))
    printf "  [FAIL] %s (expected exit %d, got %d)\n" "$desc" "$expected_exit" "$actual_exit"
  fi
}

# ---------------------------------------------------------------------------
# Test helper: run hook with raw stdin (for malformed input tests)
# ---------------------------------------------------------------------------
test_hook_raw() {
  local raw_input="$1"
  local expected_exit="$2"
  local desc="$3"

  TOTAL=$((TOTAL + 1))

  local actual_exit
  echo "$raw_input" | bash "$HOOK" >/dev/null 2>/dev/null
  actual_exit=$?

  if [[ "$actual_exit" -eq "$expected_exit" ]]; then
    PASS=$((PASS + 1))
    [[ "$VERBOSE" == "true" ]] && printf "  [PASS] %s\n" "$desc"
  else
    FAIL=$((FAIL + 1))
    printf "  [FAIL] %s (expected exit %d, got %d)\n" "$desc" "$expected_exit" "$actual_exit"
  fi
}

echo "Safety Hook Test Suite"
echo "======================"
echo "Hook: $HOOK"
echo ""

# Check hook exists
if [[ ! -f "$HOOK" ]]; then
  echo "ERROR: Hook not found at $HOOK"
  exit 1
fi

# =========================================================================
# Section 1: BLOCK patterns (should exit 2)
# =========================================================================
echo "--- Block Patterns (expect exit 2) ---"

# cycle-122 new fences ------------------------------------------------------
test_hook "git tag v9.9.9-test"      2 "git tag creation (FR-MERGE-2)"
test_hook "git tag -a v1 -m x"       2 "git tag annotated creation"
test_hook "git stash push | tail -3" 2 "stash push piped to tail (FR-1.2b)"
test_hook "git stash pop || true"    2 "stash pop exit-masked (FR-1.2b)"
test_hook "git stash pop 2>/dev/null" 2 "stash pop stderr-suppressed (FR-1.2b)"
test_hook "git stash pop >/dev/null 2>&1" 2 "stash pop full-suppression (FR-1.2b r2, dissenter F1)"
LOA_ZONE_GUARD_AUTH_FILE=/nonexistent-c122 \
  test_hook "echo x > .claude/overrides/../hooks/evil.sh" 2 "overrides traversal re-protected (FR-SZ2 r2, dissenter F2)"
LOA_ZONE_GUARD_AUTH_FILE=/nonexistent-c122 \
  test_hook "echo x > .claude/foo.sh" 2 "System-Zone redirect write (FR-SZ2, no marker)"
LOA_ZONE_GUARD_AUTH_FILE=/nonexistent-c122 \
  test_hook "sed -i s/a/b/ .claude/hooks/hook-guard.sh" 2 "System-Zone in-place edit (FR-SZ2, no marker)"
LOA_ZONE_GUARD_AUTH_FILE=/nonexistent-c122 \
  test_hook "cp evil.sh .claude/hooks/" 2 "System-Zone copy-in (FR-SZ2, no marker)"
test_hook "rm -rf /"                2 "rm -rf catastrophic root"
test_hook "rm -fr ~"                2 "rm -fr catastrophic home"
test_hook 'rm -rfi $HOME'            2 "rm -rfi catastrophic HOME"
test_hook "rm --recursive --force ." 2 "rm --recursive --force long form"
test_hook "rm --force --recursive ." 2 "rm --force --recursive reversed"
test_hook "git push --force"         2 "git push --force"
test_hook "git push -f"              2 "git push -f short flag"
test_hook "git push origin main --force" 2 "git push with remote and --force"
test_hook "git push origin main -f"  2 "git push with remote and -f"
test_hook "git reset --hard"         2 "git reset --hard"
test_hook "git reset --hard HEAD~1"  2 "git reset --hard HEAD~1"
test_hook "git clean -fd"            2 "git clean -fd (no dry-run)"
test_hook "git clean -f"             2 "git clean -f (no dry-run)"
test_hook "git clean -xfd"           2 "git clean -xfd (no dry-run)"

# Path-qualified commands
test_hook "/usr/bin/rm -rf /tmp"     2 "path-qualified /usr/bin/rm -rf"
test_hook "/usr/bin/git push --force" 2 "path-qualified git push --force"

# Chained commands
test_hook "echo hello && rm -rf /"   2 "chained && rm -rf"
test_hook "ls; git push --force"     2 "chained ; git push --force"
test_hook "echo ok | rm -rf /tmp"    2 "piped | rm -rf"

# Sudo prefix
test_hook "sudo git push --force"    2 "sudo git push --force"
test_hook "sudo git reset --hard"    2 "sudo git reset --hard"

# =========================================================================
# Section 2: ALLOW patterns (should exit 0)
# =========================================================================
echo ""
echo "--- Allow Patterns (expect exit 0) ---"

# cycle-122 new-fence allowed forms ------------------------------------------
test_hook "git tag -l"               0 "git tag listing allowed"
test_hook "git tag"                  0 "git tag bare (list) allowed"
test_hook "git tag -d v1.2.3"        0 "git tag delete allowed (not version-minting)"
test_hook "git stash push -m wip"    0 "bare stash push allowed"
test_hook "git stash pop"            0 "bare stash pop allowed"
test_hook "git stash list > /dev/null" 0 "stash LIST null-redirect allowed (scoped to push/pop/apply)"
test_hook "echo x > .claude/overrides/custom.md" 0 "overrides/ write allowed (sanctioned path)"
test_hook "cat .claude/settings.json" 0 "System-Zone read allowed"
test_hook "bash .claude/scripts/check-loa.sh" 0 "System-Zone script exec allowed"
test_hook "rm file.txt"              0 "rm single file (no -rf)"
test_hook "rm -r dir/"               0 "rm -r without -f"
test_hook "rm -rf /tmp/foo"          0 "rm -rf bounded /tmp child"
test_hook "rm -fr /tmp/foo"          0 "rm -fr bounded /tmp child"
test_hook "rm -rfi /tmp/foo"         0 "rm -rfi bounded /tmp child"
test_hook "git push origin feature"  0 "git push to feature branch"
test_hook "git push --force-with-lease" 0 "git push --force-with-lease (safe)"
test_hook "git reset HEAD file.txt"  0 "git reset without --hard"
test_hook "git reset --soft HEAD~1"  0 "git reset --soft"
test_hook "git clean -nd"            0 "git clean -nd (dry-run present)"
test_hook "git clean -nfd"           0 "git clean -nfd (dry-run present)"
test_hook "echo 'rm -rf is dangerous'" 0 "rm -rf inside echo quotes"
test_hook "ls -la"                   0 "safe command: ls"
test_hook "cat README.md"            0 "safe command: cat"
test_hook "npm install"              0 "safe command: npm install"
test_hook "git status"               0 "safe command: git status"
test_hook "git diff HEAD~1"          0 "safe command: git diff"

# =========================================================================
# Section 3: Edge Cases
# =========================================================================
echo ""
echo "--- Edge Cases ---"

# Empty command
test_hook ""                         0 "empty command string"

# Very long command (should not hang or crash)
long_cmd=$(printf 'echo %0.sa' {1..500})
test_hook "$long_cmd"                0 "very long command (500 chars)"

# Unicode in command
test_hook "echo 'hello 世界 🌍'"     0 "unicode in command"

# Newlines in command (multi-line script)
test_hook $'echo hello\necho world'  0 "multi-line command"

# Command with special characters
test_hook "echo \$HOME && ls -la"    0 "command with shell variables"

# =========================================================================
# Section 4: Fail-Open Behavior (malformed input)
# =========================================================================
echo ""
echo "--- Fail-Open Behavior ---"

# Malformed JSON
test_hook_raw "not json at all"      0 "malformed input: plain text"
test_hook_raw "{broken json"         0 "malformed input: broken JSON"
test_hook_raw ""                     0 "malformed input: empty string"
test_hook_raw '{"tool_input":{}}'    0 "malformed input: missing command field"
test_hook_raw '{"wrong_key":"val"}'  0 "malformed input: wrong JSON structure"

# =========================================================================
# Summary
# =========================================================================
echo ""
echo "=============================="
printf "Results: %d pass, %d fail (of %d total)\n" "$PASS" "$FAIL" "$TOTAL"
echo "=============================="

if [[ "$FAIL" -eq 0 ]]; then
  echo "All tests passed."
  exit 0
else
  echo "FAILURES DETECTED."
  exit 1
fi
