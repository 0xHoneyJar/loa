#!/usr/bin/env bash
# test-feedback-routing.sh — Tests for construct attribution and feedback redaction
# Cycle: cycle-025 (Cross-Codebase Feedback Routing)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SCRIPTS_DIR="$PROJECT_ROOT/.claude/scripts"

PASS=0
FAIL=0

assert_eq() {
    local test_name="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        echo "  PASS: $test_name"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $test_name"
        echo "    Expected: $expected"
        echo "    Actual:   $actual"
        FAIL=$((FAIL + 1))
    fi
}

assert_contains() {
    local test_name="$1" expected="$2" actual="$3"
    if printf '%s' "$actual" | grep -qF -- "$expected"; then
        echo "  PASS: $test_name"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $test_name"
        echo "    Expected to contain: $expected"
        echo "    Actual: $actual"
        FAIL=$((FAIL + 1))
    fi
}

assert_not_contains() {
    local test_name="$1" unexpected="$2" actual="$3"
    if ! printf '%s' "$actual" | grep -qF -- "$unexpected"; then
        echo "  PASS: $test_name"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $test_name"
        echo "    Expected NOT to contain: $unexpected"
        echo "    Actual: $actual"
        FAIL=$((FAIL + 1))
    fi
}

# --- Cleanup tracking (BB-201: single trap, array-based) ---

CLEANUP_DIRS=()
cleanup() {
    for dir in "${CLEANUP_DIRS[@]}"; do
        rm -rf "$dir"
    done
}
trap cleanup EXIT

# --- Setup mock construct environment ---

MOCK_DIR=$(mktemp -d)
CLEANUP_DIRS+=("$MOCK_DIR")

# Create mock constructs structure
mkdir -p "$MOCK_DIR/.claude/constructs/packs/observer"
mkdir -p "$MOCK_DIR/.claude/constructs/skills/artisan/deep-interview"

# Create mock manifest
cat > "$MOCK_DIR/.claude/constructs/packs/observer/manifest.yaml" << 'MANIFEST_EOF'
name: observer
vendor: artisan
version: 1.2.0
source_repo: "0xHoneyJar/observer-pack"
MANIFEST_EOF

# Create mock .constructs-meta.json
cat > "$MOCK_DIR/.claude/constructs/.constructs-meta.json" << 'META_EOF'
{
  "schema_version": 1,
  "installed_skills": {
    "artisan/deep-interview": {
      "version": "2.0.1",
      "installed_at": "2026-02-17T10:00:00Z"
    }
  },
  "installed_packs": {
    "artisan/observer": {
      "version": "1.2.0",
      "installed_at": "2026-02-17T10:00:00Z"
    }
  },
  "last_update_check": null
}
META_EOF

echo "════════════════════════════════════════════════════════"
echo "  Feedback Routing Tests (cycle-025)"
echo "════════════════════════════════════════════════════════"

# =============================================
# Attribution Tests
# =============================================

echo ""
echo "--- Attribution Tests ---"

# Test 1: No constructs → attributed=false
echo ""
echo "Test 1: No constructs installed"
NO_META_DIR=$(mktemp -d)
CLEANUP_DIRS+=("$NO_META_DIR")
RESULT=$(echo "some feedback about a bug" | \
    bash "$SCRIPTS_DIR/construct-attribution.sh" --context - 2>/dev/null || true)
ATTRIBUTED=$(echo "$RESULT" | jq -r '.attributed' 2>/dev/null || echo "error")
assert_eq "no constructs returns attributed=false" "false" "$ATTRIBUTED"

# Test 2: Path match → correct construct + confidence
echo ""
echo "Test 2: Path match attribution"
pushd "$MOCK_DIR" > /dev/null
RESULT=$(echo "Error in .claude/constructs/packs/observer/SKILL.md line 42" | \
    bash "$SCRIPTS_DIR/construct-attribution.sh" --context - 2>/dev/null || true)
popd > /dev/null
ATTRIBUTED=$(echo "$RESULT" | jq -r '.attributed' 2>/dev/null || echo "error")
CONSTRUCT=$(echo "$RESULT" | jq -r '.construct' 2>/dev/null || echo "error")
assert_eq "path match returns attributed=true" "true" "$ATTRIBUTED"
assert_eq "path match identifies correct construct" "artisan/observer" "$CONSTRUCT"

# Test 3: Explicit mention
echo ""
echo "Test 3: Explicit mention attribution"
pushd "$MOCK_DIR" > /dev/null
RESULT=$(echo "The pack:observer has a bug in the interview skill" | \
    bash "$SCRIPTS_DIR/construct-attribution.sh" --context - 2>/dev/null || true)
popd > /dev/null
ATTRIBUTED=$(echo "$RESULT" | jq -r '.attributed' 2>/dev/null || echo "error")
assert_eq "explicit mention returns attributed=true" "true" "$ATTRIBUTED"

# Test 4: Exit code 1 for missing --context
echo ""
echo "Test 4: Missing --context"
EXIT_CODE=0
bash "$SCRIPTS_DIR/construct-attribution.sh" >/dev/null 2>&1 || EXIT_CODE=$?
assert_eq "missing --context returns exit 1" "1" "$EXIT_CODE"

# =============================================
# Disambiguation Tests (BB-104)
# =============================================

echo ""
echo "--- Disambiguation Tests ---"

# Test 5: Two constructs, vendor-only match → ambiguous=true
echo ""
echo "Test 5: Disambiguation with vendor-only match"

# Create a second pack from same vendor to trigger ambiguity
DISAMBIG_DIR=$(mktemp -d)
CLEANUP_DIRS+=("$DISAMBIG_DIR")
mkdir -p "$DISAMBIG_DIR/.claude/constructs/packs/observer"
mkdir -p "$DISAMBIG_DIR/.claude/constructs/packs/sentinel"
mkdir -p "$DISAMBIG_DIR/.claude/constructs/skills/artisan/deep-interview"

# Meta with two packs from same vendor
cat > "$DISAMBIG_DIR/.claude/constructs/.constructs-meta.json" << 'DISAMBIG_META_EOF'
{
  "schema_version": 1,
  "installed_skills": {},
  "installed_packs": {
    "artisan/observer": {
      "version": "1.2.0",
      "installed_at": "2026-02-17T10:00:00Z"
    },
    "artisan/sentinel": {
      "version": "1.0.0",
      "installed_at": "2026-02-17T10:00:00Z"
    }
  },
  "last_update_check": null
}
DISAMBIG_META_EOF

# Create manifests
cat > "$DISAMBIG_DIR/.claude/constructs/packs/observer/manifest.yaml" << 'M1_EOF'
name: observer
vendor: artisan
version: 1.2.0
source_repo: "artisan/observer-pack"
M1_EOF

cat > "$DISAMBIG_DIR/.claude/constructs/packs/sentinel/manifest.yaml" << 'M2_EOF'
name: sentinel
vendor: artisan
version: 1.0.0
source_repo: "artisan/sentinel-pack"
M2_EOF

pushd "$DISAMBIG_DIR" > /dev/null
# Only mention "artisan" (vendor) — both packs match equally
RESULT=$(echo "The artisan vendor packs have a bug" | \
    bash "$SCRIPTS_DIR/construct-attribution.sh" --context - 2>/dev/null || true)
popd > /dev/null
ATTRIBUTED=$(echo "$RESULT" | jq -r '.attributed' 2>/dev/null || echo "error")
AMBIGUOUS=$(echo "$RESULT" | jq -r '.ambiguous' 2>/dev/null || echo "error")
assert_eq "vendor-only match returns attributed=true" "true" "$ATTRIBUTED"
assert_eq "vendor-only match returns ambiguous=true" "true" "$AMBIGUOUS"

# Verify candidates array has entries
CANDIDATE_COUNT=$(echo "$RESULT" | jq -r '.candidates | length' 2>/dev/null || echo "0")
if [[ "$CANDIDATE_COUNT" -ge 2 ]]; then
    echo "  PASS: candidates has $CANDIDATE_COUNT entries"
    PASS=$((PASS + 1))
else
    echo "  FAIL: candidates should have >= 2 entries"
    echo "    Actual count: $CANDIDATE_COUNT"
    FAIL=$((FAIL + 1))
fi

# =============================================
# Trust Validation Tests (BB-105)
# =============================================

echo ""
echo "--- Trust Validation Tests ---"

# Test 6: Malformed source_repo → trust_warning set
echo ""
echo "Test 6: Malformed source_repo format"
TRUST_DIR=$(mktemp -d)
CLEANUP_DIRS+=("$TRUST_DIR")
mkdir -p "$TRUST_DIR/.claude/constructs/packs/badrepo"
cat > "$TRUST_DIR/.claude/constructs/.constructs-meta.json" << 'TRUST_META_EOF'
{
  "schema_version": 1,
  "installed_skills": {},
  "installed_packs": {
    "badvendor/badrepo": {
      "version": "1.0.0",
      "installed_at": "2026-02-17T10:00:00Z"
    }
  },
  "last_update_check": null
}
TRUST_META_EOF
cat > "$TRUST_DIR/.claude/constructs/packs/badrepo/manifest.yaml" << 'BADM_EOF'
name: badrepo
vendor: badvendor
version: 1.0.0
source_repo: "invalid-no-slash"
BADM_EOF

pushd "$TRUST_DIR" > /dev/null
RESULT=$(echo "Error in .claude/constructs/packs/badrepo/SKILL.md" | \
    bash "$SCRIPTS_DIR/construct-attribution.sh" --context - 2>/dev/null || true)
popd > /dev/null
TRUST_WARN=$(echo "$RESULT" | jq -r '.trust_warning' 2>/dev/null || echo "null")
SOURCE_REPO=$(echo "$RESULT" | jq -r '.source_repo' 2>/dev/null || echo "null")
assert_contains "malformed repo triggers trust warning" "format invalid" "$TRUST_WARN"
assert_eq "malformed repo clears source_repo" "null" "$SOURCE_REPO"

# Test 7: Org mismatch → trust_warning set
echo ""
echo "Test 7: Org mismatch trust warning"
ORGMIS_DIR=$(mktemp -d)
CLEANUP_DIRS+=("$ORGMIS_DIR")
mkdir -p "$ORGMIS_DIR/.claude/constructs/packs/mismatch"
cat > "$ORGMIS_DIR/.claude/constructs/.constructs-meta.json" << 'ORGMIS_META_EOF'
{
  "schema_version": 1,
  "installed_skills": {},
  "installed_packs": {
    "vendorA/mismatch": {
      "version": "1.0.0",
      "installed_at": "2026-02-17T10:00:00Z"
    }
  },
  "last_update_check": null
}
ORGMIS_META_EOF
cat > "$ORGMIS_DIR/.claude/constructs/packs/mismatch/manifest.yaml" << 'ORGM_EOF'
name: mismatch
vendor: vendorA
version: 1.0.0
source_repo: "different-org/mismatch-pack"
ORGM_EOF

pushd "$ORGMIS_DIR" > /dev/null
RESULT=$(echo "Error in .claude/constructs/packs/mismatch/SKILL.md" | \
    bash "$SCRIPTS_DIR/construct-attribution.sh" --context - 2>/dev/null || true)
popd > /dev/null
TRUST_WARN=$(echo "$RESULT" | jq -r '.trust_warning' 2>/dev/null || echo "null")
assert_contains "org mismatch triggers trust warning" "does not match vendor" "$TRUST_WARN"

# =============================================
# Redaction Tests
# =============================================

echo ""
echo "--- Redaction Tests ---"

# Test 8: AWS key redaction
echo ""
echo "Test 8: AWS key redacted"
RESULT=$(echo "My key is AKIAIOSFODNN7EXAMPLE" | \
    bash "$SCRIPTS_DIR/feedback-redaction.sh" --input - 2>/dev/null)
assert_contains "AWS key replaced" "<redacted-aws-key>" "$RESULT"
assert_not_contains "AWS key removed" "AKIAIOSFODNN7EXAMPLE" "$RESULT"

# Test 9: Absolute path redaction
echo ""
echo "Test 9: Absolute path redacted"
RESULT=$(echo "Error in /home/merlin/project/src/main.ts" | \
    bash "$SCRIPTS_DIR/feedback-redaction.sh" --input - 2>/dev/null)
assert_contains "path redacted" "<redacted-path>" "$RESULT"
assert_not_contains "username removed" "merlin" "$RESULT"

# Test 10: GitHub token redaction
echo ""
echo "Test 10: GitHub token redacted"
RESULT=$(echo "Token: ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklm" | \
    bash "$SCRIPTS_DIR/feedback-redaction.sh" --input - 2>/dev/null)
assert_contains "github token replaced" "<redacted-github-token>" "$RESULT"

# Test 11: Clean input passes through unchanged
echo ""
echo "Test 11: Clean input passes through"
CLEAN_INPUT="The observer pack crashes when given empty input to the interview skill."
RESULT=$(echo "$CLEAN_INPUT" | \
    bash "$SCRIPTS_DIR/feedback-redaction.sh" --input - 2>/dev/null)
assert_eq "clean input unchanged" "$CLEAN_INPUT" "$RESULT"

# Test 12: Exit code 1 for missing --input
echo ""
echo "Test 12: Missing --input"
EXIT_CODE=0
bash "$SCRIPTS_DIR/feedback-redaction.sh" >/dev/null 2>&1 || EXIT_CODE=$?
assert_eq "missing --input returns exit 1" "1" "$EXIT_CODE"

# Test 13: Preview mode writes to stderr
echo ""
echo "Test 13: Preview mode"
STDERR_OUTPUT=$(echo "password=supersecret123" | \
    bash "$SCRIPTS_DIR/feedback-redaction.sh" --input - --preview 2>&1 1>/dev/null)
assert_contains "preview writes summary" "Redaction Summary" "$STDERR_OUTPUT"

# =============================================
# Classifier Tests
# =============================================

echo ""
echo "--- Classifier Tests ---"

# Test 14: Construct path in context → classification: construct
echo ""
echo "Test 14: Construct path classification"
pushd "$MOCK_DIR" > /dev/null
RESULT=$(echo "Bug in .claude/constructs/packs/observer/SKILL.md" | \
    bash "$SCRIPTS_DIR/feedback-classifier.sh" --context - 2>/dev/null || true)
popd > /dev/null
CLASSIFICATION=$(echo "$RESULT" | jq -r '.classification' 2>/dev/null || echo "error")
CONSTRUCT_SCORE=$(echo "$RESULT" | jq -r '.scores.construct' 2>/dev/null || echo "0")
# construct score should be > 0 from signal matching
if [[ "$CONSTRUCT_SCORE" -gt 0 ]]; then
    echo "  PASS: construct score > 0 ($CONSTRUCT_SCORE)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: construct score should be > 0"
    echo "    Actual score: $CONSTRUCT_SCORE"
    FAIL=$((FAIL + 1))
fi

# Test 15: No construct path → existing classification (backward compat)
echo ""
echo "Test 15: Backward compatibility"
RESULT=$(echo "Error in .claude/skills/implementing-tasks/SKILL.md" | \
    bash "$SCRIPTS_DIR/feedback-classifier.sh" --context - 2>/dev/null || true)
CLASSIFICATION=$(echo "$RESULT" | jq -r '.classification' 2>/dev/null || echo "error")
CONSTRUCT_SCORE=$(echo "$RESULT" | jq -r '.scores.construct' 2>/dev/null || echo "error")
# No construct paths → construct score = 0, classification should be loa_framework
assert_eq "no construct paths: construct score = 0" "0" "$CONSTRUCT_SCORE"
if [[ "$CLASSIFICATION" != "construct" ]]; then
    echo "  PASS: non-construct context does not classify as construct ($CLASSIFICATION)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: non-construct context should not classify as construct"
    FAIL=$((FAIL + 1))
fi

# =============================================
# Summary
# =============================================

echo ""
echo "════════════════════════════════════════════════════════"
echo "  RESULTS"
echo "════════════════════════════════════════════════════════"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
echo ""

if [[ $FAIL -gt 0 ]]; then
    echo "  STATUS: FAIL"
    exit 1
else
    echo "  STATUS: PASS"
    exit 0
fi
