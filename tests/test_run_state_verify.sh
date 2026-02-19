#!/usr/bin/env bash
# Tests for run-state-verify.sh (FR-5)
# Plain bash tests — no external test framework required.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VERIFY="${REPO_ROOT}/.claude/scripts/run-state-verify.sh"

# ── Test Harness ──────────────────────────────────────

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

pass() { TESTS_PASSED=$((TESTS_PASSED + 1)); echo "  PASS: $1"; }
fail() { TESTS_FAILED=$((TESTS_FAILED + 1)); echo "  FAIL: $1 — $2"; }

# ── Setup / Teardown ─────────────────────────────────

TEMP_DIR=""
ORIG_KEY_DIR="${HOME}/.claude/.run-keys"
BACKUP_KEY_DIR=""

setup() {
  TEMP_DIR="$(mktemp -d)"
  # Use a temporary key dir to avoid polluting real keys
  BACKUP_KEY_DIR="${TEMP_DIR}/backup-keys"
  if [ -d "$ORIG_KEY_DIR" ]; then
    cp -r "$ORIG_KEY_DIR" "$BACKUP_KEY_DIR"
  fi
  mkdir -p "$ORIG_KEY_DIR"

  # Create a fake .run directory inside a git repo for file safety checks
  mkdir -p "${TEMP_DIR}/repo/.run"
  git -C "${TEMP_DIR}/repo" init --quiet 2>/dev/null
}

teardown() {
  # Restore original key dir
  rm -rf "$ORIG_KEY_DIR"
  if [ -d "$BACKUP_KEY_DIR" ]; then
    mv "$BACKUP_KEY_DIR" "$ORIG_KEY_DIR"
  fi
  rm -rf "$TEMP_DIR"
}

# ── Test Helpers ─────────────────────────────────────

create_state_file() {
  local path="$1"
  cat > "$path" << 'STATEEOF'
{
  "run_id": "run-20260219-test123",
  "target": "sprint-1",
  "state": "RUNNING",
  "timestamps": {
    "started": "2026-02-19T10:00:00Z"
  }
}
STATEEOF
  chmod 644 "$path"
}

# ── Tests ────────────────────────────────────────────

test_sign_verify_roundtrip() {
  TESTS_RUN=$((TESTS_RUN + 1))
  local state_file="${TEMP_DIR}/repo/.run/state.json"
  create_state_file "$state_file"

  "$VERIFY" init "test-run-001" >/dev/null 2>&1
  "$VERIFY" sign "$state_file" "test-run-001" >/dev/null 2>&1

  # Verify should succeed (exit 0)
  if (cd "${TEMP_DIR}/repo" && "$VERIFY" verify "$state_file" >/dev/null 2>&1); then
    pass "sign + verify round-trip"
  else
    fail "sign + verify round-trip" "verify returned non-zero"
  fi
}

test_tampered_content_detection() {
  TESTS_RUN=$((TESTS_RUN + 1))
  local state_file="${TEMP_DIR}/repo/.run/state.json"
  create_state_file "$state_file"

  "$VERIFY" init "test-run-002" >/dev/null 2>&1
  "$VERIFY" sign "$state_file" "test-run-002" >/dev/null 2>&1

  # Tamper with a value
  local tmp="${state_file}.tamper"
  jq '.state = "HALTED"' "$state_file" > "$tmp"
  # Preserve _hmac and _key_id from original
  local hmac key_id
  hmac="$(jq -r '._hmac' "$state_file")"
  key_id="$(jq -r '._key_id' "$state_file")"
  jq --arg h "$hmac" --arg k "$key_id" '. + {"_hmac": $h, "_key_id": $k}' "$tmp" > "$state_file"
  chmod 644 "$state_file"
  rm -f "$tmp"

  local exit_code=0
  (cd "${TEMP_DIR}/repo" && "$VERIFY" verify "$state_file" >/dev/null 2>&1) || exit_code=$?

  if [ "$exit_code" -eq 1 ]; then
    pass "tampered content detection"
  else
    fail "tampered content detection" "expected exit 1, got $exit_code"
  fi
}

test_missing_key_handling() {
  TESTS_RUN=$((TESTS_RUN + 1))
  local state_file="${TEMP_DIR}/repo/.run/state.json"
  create_state_file "$state_file"

  "$VERIFY" init "test-run-003" >/dev/null 2>&1
  "$VERIFY" sign "$state_file" "test-run-003" >/dev/null 2>&1

  # Delete the key
  rm -f "${ORIG_KEY_DIR}/test-run-003.key"

  local exit_code=0
  (cd "${TEMP_DIR}/repo" && "$VERIFY" verify "$state_file" >/dev/null 2>&1) || exit_code=$?

  if [ "$exit_code" -eq 2 ]; then
    pass "missing key handling (exit 2)"
  else
    fail "missing key handling" "expected exit 2, got $exit_code"
  fi
}

test_symlink_detection() {
  TESTS_RUN=$((TESTS_RUN + 1))
  local real_file="${TEMP_DIR}/repo/.run/real-state.json"
  local link_file="${TEMP_DIR}/repo/.run/link-state.json"
  create_state_file "$real_file"

  "$VERIFY" init "test-run-004" >/dev/null 2>&1
  "$VERIFY" sign "$real_file" "test-run-004" >/dev/null 2>&1

  # Create symlink
  ln -sf "$real_file" "$link_file"

  local exit_code=0
  (cd "${TEMP_DIR}/repo" && "$VERIFY" verify "$link_file" >/dev/null 2>&1) || exit_code=$?

  if [ "$exit_code" -eq 1 ]; then
    pass "symlink detection"
  else
    fail "symlink detection" "expected exit 1, got $exit_code"
  fi
}

test_base_directory_enforcement() {
  TESTS_RUN=$((TESTS_RUN + 1))
  local outside_file="${TEMP_DIR}/outside-state.json"
  create_state_file "$outside_file"

  "$VERIFY" init "test-run-005" >/dev/null 2>&1
  "$VERIFY" sign "$outside_file" "test-run-005" >/dev/null 2>&1

  local exit_code=0
  (cd "${TEMP_DIR}/repo" && "$VERIFY" verify "$outside_file" >/dev/null 2>&1) || exit_code=$?

  if [ "$exit_code" -eq 1 ]; then
    pass "base directory enforcement"
  else
    fail "base directory enforcement" "expected exit 1, got $exit_code"
  fi
}

test_json_canonicalization() {
  TESTS_RUN=$((TESTS_RUN + 1))
  local state_file="${TEMP_DIR}/repo/.run/state.json"
  create_state_file "$state_file"

  "$VERIFY" init "test-run-006" >/dev/null 2>&1
  "$VERIFY" sign "$state_file" "test-run-006" >/dev/null 2>&1

  # Reformat the JSON (change whitespace and key order) but preserve content
  local tmp="${state_file}.reformat"
  # Read, strip HMAC fields, reformat with different indentation, re-add HMAC
  local hmac key_id
  hmac="$(jq -r '._hmac' "$state_file")"
  key_id="$(jq -r '._key_id' "$state_file")"

  jq 'del(._hmac, ._key_id)' "$state_file" | \
    jq --indent 4 '.' | \
    jq --arg h "$hmac" --arg k "$key_id" '. + {"_hmac": $h, "_key_id": $k}' > "$tmp"
  chmod 644 "$tmp"
  mv "$tmp" "$state_file"

  if (cd "${TEMP_DIR}/repo" && "$VERIFY" verify "$state_file" >/dev/null 2>&1); then
    pass "JSON canonicalization (reformat + verify)"
  else
    fail "JSON canonicalization" "verify failed after reformatting"
  fi
}

test_concurrent_runs() {
  TESTS_RUN=$((TESTS_RUN + 1))
  local file_a="${TEMP_DIR}/repo/.run/state-a.json"
  local file_b="${TEMP_DIR}/repo/.run/state-b.json"
  create_state_file "$file_a"
  create_state_file "$file_b"
  # Give file_b different content
  jq '.run_id = "run-20260219-other"' "$file_b" > "${file_b}.tmp"
  chmod 644 "${file_b}.tmp"
  mv "${file_b}.tmp" "$file_b"

  "$VERIFY" init "run-a" >/dev/null 2>&1
  "$VERIFY" init "run-b" >/dev/null 2>&1
  "$VERIFY" sign "$file_a" "run-a" >/dev/null 2>&1
  "$VERIFY" sign "$file_b" "run-b" >/dev/null 2>&1

  local ok=true
  (cd "${TEMP_DIR}/repo" && "$VERIFY" verify "$file_a" >/dev/null 2>&1) || ok=false
  (cd "${TEMP_DIR}/repo" && "$VERIFY" verify "$file_b" >/dev/null 2>&1) || ok=false

  if [ "$ok" = true ]; then
    pass "concurrent runs with different run_ids"
  else
    fail "concurrent runs" "one or both verifications failed"
  fi
}

# ── Main ─────────────────────────────────────────────

echo "Testing run-state-verify.sh"
echo "════════════════════════════════════════════"

setup

test_sign_verify_roundtrip
test_tampered_content_detection
test_missing_key_handling
test_symlink_detection
test_base_directory_enforcement
test_json_canonicalization
test_concurrent_runs

teardown

echo "════════════════════════════════════════════"
echo "Results: $TESTS_RUN tests, $TESTS_PASSED passed, $TESTS_FAILED failed"

if [ "$TESTS_FAILED" -gt 0 ]; then
  exit 1
fi
exit 0
