#!/usr/bin/env bats
# Unit tests for bridge-findings-parser.sh
# Sprint 2: Bridge Core — markdown parsing, severity weighting, edge cases

setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    SCRIPT="$PROJECT_ROOT/.claude/scripts/bridge-findings-parser.sh"

    export BATS_TMPDIR="${BATS_TMPDIR:-/tmp}"
    export TEST_TMPDIR="$BATS_TMPDIR/findings-parser-test-$$"
    mkdir -p "$TEST_TMPDIR"

    # Override PROJECT_ROOT
    export PROJECT_ROOT
}

teardown() {
    cd /
    if [[ -d "$TEST_TMPDIR" ]]; then
        rm -rf "$TEST_TMPDIR"
    fi
}

skip_if_deps_missing() {
    if ! command -v jq &>/dev/null; then
        skip "jq not installed"
    fi
}

# =============================================================================
# Basic Parsing
# =============================================================================

@test "findings-parser: script exists and is executable" {
    [ -x "$SCRIPT" ]
}

@test "findings-parser: parses known-good markdown" {
    skip_if_deps_missing

    cat > "$TEST_TMPDIR/review.md" <<'EOF'
# Bridge Review

Some intro text.

<!-- bridge-findings-start -->
## Findings

### [HIGH-1] Missing error handling in API
**Severity**: HIGH
**Category**: quality
**File**: src/api/handler.ts:42
**Description**: No try-catch around database calls
**Suggestion**: Wrap in try-catch with proper error response

### [MEDIUM-1] Inconsistent naming
**Severity**: MEDIUM
**Category**: quality
**File**: src/utils/helpers.ts:10
**Description**: Mix of camelCase and snake_case
**Suggestion**: Standardize to camelCase

### [VISION-1] Cross-repo GT hub
**Type**: vision
**Description**: Could share GT across multiple repos
**Potential**: Unified codebase understanding for multi-repo projects
<!-- bridge-findings-end -->

Some trailing text.
EOF

    run "$SCRIPT" --input "$TEST_TMPDIR/review.md" --output "$TEST_TMPDIR/findings.json"
    [ "$status" -eq 0 ]
    [ -f "$TEST_TMPDIR/findings.json" ]

    local total
    total=$(jq '.total' "$TEST_TMPDIR/findings.json")
    [ "$total" = "3" ]
}

@test "findings-parser: severity weighting is correct" {
    skip_if_deps_missing

    cat > "$TEST_TMPDIR/review.md" <<'EOF'
<!-- bridge-findings-start -->
### [CRITICAL-1] SQL injection
**Severity**: CRITICAL
**Category**: security
**File**: src/db.ts:5
**Description**: Raw SQL concatenation
**Suggestion**: Use parameterized queries

### [HIGH-1] Auth bypass
**Severity**: HIGH
**Category**: security
**File**: src/auth.ts:20
**Description**: Missing token validation
**Suggestion**: Add JWT verification

### [LOW-1] Typo in comment
**Severity**: LOW
**Category**: documentation
**File**: src/index.ts:1
**Description**: Typo in header comment
**Suggestion**: Fix spelling
<!-- bridge-findings-end -->
EOF

    "$SCRIPT" --input "$TEST_TMPDIR/review.md" --output "$TEST_TMPDIR/findings.json"

    local score
    score=$(jq '.severity_weighted_score' "$TEST_TMPDIR/findings.json")
    # CRITICAL=10 + HIGH=5 + LOW=1 = 16
    [ "$score" = "16" ]
}

@test "findings-parser: by_severity counts are correct" {
    skip_if_deps_missing

    cat > "$TEST_TMPDIR/review.md" <<'EOF'
<!-- bridge-findings-start -->
### [HIGH-1] Issue one
**Severity**: HIGH
**Category**: quality
**File**: a.ts:1
**Description**: Desc
**Suggestion**: Fix

### [HIGH-2] Issue two
**Severity**: HIGH
**Category**: quality
**File**: b.ts:2
**Description**: Desc
**Suggestion**: Fix

### [MEDIUM-1] Issue three
**Severity**: MEDIUM
**Category**: quality
**File**: c.ts:3
**Description**: Desc
**Suggestion**: Fix
<!-- bridge-findings-end -->
EOF

    "$SCRIPT" --input "$TEST_TMPDIR/review.md" --output "$TEST_TMPDIR/findings.json"

    local high medium
    high=$(jq '.by_severity.high' "$TEST_TMPDIR/findings.json")
    medium=$(jq '.by_severity.medium' "$TEST_TMPDIR/findings.json")
    [ "$high" = "2" ]
    [ "$medium" = "1" ]
}

# =============================================================================
# Edge Cases
# =============================================================================

@test "findings-parser: empty input produces 0 findings" {
    skip_if_deps_missing

    echo "No findings here" > "$TEST_TMPDIR/empty.md"

    run "$SCRIPT" --input "$TEST_TMPDIR/empty.md" --output "$TEST_TMPDIR/findings.json"
    [ "$status" -eq 0 ]

    local total score
    total=$(jq '.total' "$TEST_TMPDIR/findings.json")
    score=$(jq '.severity_weighted_score' "$TEST_TMPDIR/findings.json")
    [ "$total" = "0" ]
    [ "$score" = "0" ]
}

@test "findings-parser: missing input returns exit 2" {
    run "$SCRIPT" --input "/nonexistent/file.md" --output "$TEST_TMPDIR/findings.json"
    [ "$status" -eq 2 ]
}

@test "findings-parser: missing arguments returns exit 2" {
    run "$SCRIPT"
    [ "$status" -eq 2 ]
}

@test "findings-parser: VISION findings have weight 0" {
    skip_if_deps_missing

    cat > "$TEST_TMPDIR/review.md" <<'EOF'
<!-- bridge-findings-start -->
### [VISION-1] Future insight
**Type**: vision
**Description**: Some insight
**Potential**: Could be great
<!-- bridge-findings-end -->
EOF

    "$SCRIPT" --input "$TEST_TMPDIR/review.md" --output "$TEST_TMPDIR/findings.json"

    local score total
    score=$(jq '.severity_weighted_score' "$TEST_TMPDIR/findings.json")
    total=$(jq '.total' "$TEST_TMPDIR/findings.json")
    [ "$score" = "0" ]
    [ "$total" = "1" ]
}

@test "findings-parser: --help shows usage" {
    run "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}
