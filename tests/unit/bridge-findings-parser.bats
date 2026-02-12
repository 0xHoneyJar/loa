#!/usr/bin/env bats
# Unit tests for bridge-findings-parser.sh
# Sprint 2: Bridge Core — markdown parsing, severity weighting, edge cases
# Sprint 1 cycle-006: JSON extraction, schema validation, PRAISE, enriched fields

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
# Basic Parsing (Legacy)
# =============================================================================

@test "findings-parser: script exists and is executable" {
    [ -x "$SCRIPT" ]
}

@test "findings-parser: parses known-good legacy markdown" {
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

# =============================================================================
# JSON Extraction (v2)
# =============================================================================

@test "findings-parser: extracts findings from JSON fenced block" {
    skip_if_deps_missing

    cat > "$TEST_TMPDIR/review.md" <<'EOF'
# Bridge Review — Iteration 1

Some opening prose about architecture.

<!-- bridge-findings-start -->

```json
{
  "schema_version": 1,
  "findings": [
    {
      "id": "high-1",
      "title": "Missing error handling",
      "severity": "HIGH",
      "category": "quality",
      "file": "src/api.ts:42",
      "description": "No try-catch around database calls",
      "suggestion": "Wrap in try-catch"
    },
    {
      "id": "low-1",
      "title": "Typo in comment",
      "severity": "LOW",
      "category": "documentation",
      "file": "src/index.ts:1",
      "description": "Spelling error",
      "suggestion": "Fix typo"
    }
  ]
}
```

<!-- bridge-findings-end -->

Closing meditation on craft.
EOF

    run "$SCRIPT" --input "$TEST_TMPDIR/review.md" --output "$TEST_TMPDIR/findings.json"
    [ "$status" -eq 0 ]

    local total score
    total=$(jq '.total' "$TEST_TMPDIR/findings.json")
    score=$(jq '.severity_weighted_score' "$TEST_TMPDIR/findings.json")
    [ "$total" = "2" ]
    # HIGH=5 + LOW=1 = 6
    [ "$score" = "6" ]
}

@test "findings-parser: JSON path preserves enriched fields" {
    skip_if_deps_missing

    cat > "$TEST_TMPDIR/review.md" <<'EOF'
<!-- bridge-findings-start -->

```json
{
  "schema_version": 1,
  "findings": [
    {
      "id": "high-1",
      "title": "Missing error handling",
      "severity": "HIGH",
      "category": "quality",
      "file": "src/api.ts:42",
      "description": "No try-catch around database calls",
      "suggestion": "Wrap in try-catch",
      "faang_parallel": "Google's Stubby RPC framework enforces error handling at the protocol level",
      "metaphor": "Like a surgeon operating without anesthesia monitoring",
      "teachable_moment": "Error boundaries should exist at every I/O boundary",
      "connection": "Relates to the hexagonal architecture's port-adapter pattern",
      "praise": false
    }
  ]
}
```

<!-- bridge-findings-end -->
EOF

    "$SCRIPT" --input "$TEST_TMPDIR/review.md" --output "$TEST_TMPDIR/findings.json"

    local faang metaphor teachable connection
    faang=$(jq -r '.findings[0].faang_parallel' "$TEST_TMPDIR/findings.json")
    metaphor=$(jq -r '.findings[0].metaphor' "$TEST_TMPDIR/findings.json")
    teachable=$(jq -r '.findings[0].teachable_moment' "$TEST_TMPDIR/findings.json")
    connection=$(jq -r '.findings[0].connection' "$TEST_TMPDIR/findings.json")

    [[ "$faang" == *"Google"* ]]
    [[ "$metaphor" == *"surgeon"* ]]
    [[ "$teachable" == *"I/O boundary"* ]]
    [[ "$connection" == *"hexagonal"* ]]
}

@test "findings-parser: JSON path recognizes PRAISE severity" {
    skip_if_deps_missing

    cat > "$TEST_TMPDIR/review.md" <<'EOF'
<!-- bridge-findings-start -->

```json
{
  "schema_version": 1,
  "findings": [
    {
      "id": "praise-1",
      "title": "Beautiful hexagonal architecture",
      "severity": "PRAISE",
      "category": "architecture",
      "file": "src/core/ports.ts",
      "description": "Textbook port-adapter separation",
      "suggestion": "No changes needed — this is exemplary",
      "praise": true,
      "teachable_moment": "This is what hexagonal architecture looks like when done right"
    },
    {
      "id": "critical-1",
      "title": "SQL injection",
      "severity": "CRITICAL",
      "category": "security",
      "file": "src/db.ts:5",
      "description": "Raw SQL concatenation",
      "suggestion": "Use parameterized queries"
    }
  ]
}
```

<!-- bridge-findings-end -->
EOF

    "$SCRIPT" --input "$TEST_TMPDIR/review.md" --output "$TEST_TMPDIR/findings.json"

    local total praise_count score
    total=$(jq '.total' "$TEST_TMPDIR/findings.json")
    praise_count=$(jq '.by_severity.praise' "$TEST_TMPDIR/findings.json")
    score=$(jq '.severity_weighted_score' "$TEST_TMPDIR/findings.json")

    [ "$total" = "2" ]
    [ "$praise_count" = "1" ]
    # PRAISE=0 + CRITICAL=10 = 10 (PRAISE does NOT affect score)
    [ "$score" = "10" ]
}

@test "findings-parser: schema_version preserved in output" {
    skip_if_deps_missing

    cat > "$TEST_TMPDIR/review.md" <<'EOF'
<!-- bridge-findings-start -->

```json
{
  "schema_version": 1,
  "findings": [
    {
      "id": "low-1",
      "title": "Minor issue",
      "severity": "LOW",
      "category": "quality",
      "file": "a.ts:1",
      "description": "Minor",
      "suggestion": "Fix"
    }
  ]
}
```

<!-- bridge-findings-end -->
EOF

    "$SCRIPT" --input "$TEST_TMPDIR/review.md" --output "$TEST_TMPDIR/findings.json"

    local version
    version=$(jq '.schema_version' "$TEST_TMPDIR/findings.json")
    [ "$version" = "1" ]
}

@test "findings-parser: by_severity includes praise field" {
    skip_if_deps_missing

    cat > "$TEST_TMPDIR/review.md" <<'EOF'
<!-- bridge-findings-start -->

```json
{
  "schema_version": 1,
  "findings": [
    {
      "id": "high-1",
      "title": "Issue",
      "severity": "HIGH",
      "category": "quality",
      "file": "a.ts:1",
      "description": "Desc",
      "suggestion": "Fix"
    }
  ]
}
```

<!-- bridge-findings-end -->
EOF

    "$SCRIPT" --input "$TEST_TMPDIR/review.md" --output "$TEST_TMPDIR/findings.json"

    # Verify praise field exists in by_severity (even if 0)
    local praise
    praise=$(jq '.by_severity.praise' "$TEST_TMPDIR/findings.json")
    [ "$praise" = "0" ]
}

# =============================================================================
# Strict Grammar Enforcement
# =============================================================================

@test "findings-parser: rejects multiple findings blocks (exit 3)" {
    skip_if_deps_missing

    cat > "$TEST_TMPDIR/review.md" <<'EOF'
<!-- bridge-findings-start -->
### [HIGH-1] First finding
**Severity**: HIGH
**Category**: quality
**File**: a.ts:1
**Description**: First
**Suggestion**: Fix
<!-- bridge-findings-end -->

Some text between blocks.

<!-- bridge-findings-start -->
### [HIGH-2] Second finding
**Severity**: HIGH
**Category**: quality
**File**: b.ts:2
**Description**: Second
**Suggestion**: Fix
<!-- bridge-findings-end -->
EOF

    run "$SCRIPT" --input "$TEST_TMPDIR/review.md" --output "$TEST_TMPDIR/findings.json"
    [ "$status" -eq 3 ]
    [[ "$output" == *"Multiple findings blocks"* ]]
}

@test "findings-parser: rejects multiple JSON fences in block (exit 3)" {
    skip_if_deps_missing

    cat > "$TEST_TMPDIR/review.md" <<'EOF'
<!-- bridge-findings-start -->

```json
{
  "schema_version": 1,
  "findings": [{"id": "high-1", "title": "A", "severity": "HIGH", "category": "q", "file": "a.ts", "description": "d", "suggestion": "s"}]
}
```

```json
{
  "schema_version": 1,
  "findings": [{"id": "high-2", "title": "B", "severity": "HIGH", "category": "q", "file": "b.ts", "description": "d", "suggestion": "s"}]
}
```

<!-- bridge-findings-end -->
EOF

    run "$SCRIPT" --input "$TEST_TMPDIR/review.md" --output "$TEST_TMPDIR/findings.json"
    [ "$status" -eq 3 ]
    [[ "$output" == *"Multiple JSON fences"* ]]
}

@test "findings-parser: rejects invalid JSON in fence (exit 1)" {
    skip_if_deps_missing

    cat > "$TEST_TMPDIR/review.md" <<'EOF'
<!-- bridge-findings-start -->

```json
{ this is not valid json }
```

<!-- bridge-findings-end -->
EOF

    run "$SCRIPT" --input "$TEST_TMPDIR/review.md" --output "$TEST_TMPDIR/findings.json"
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid JSON"* ]]
}

@test "findings-parser: rejects truncated output (unclosed fence, exit 3)" {
    skip_if_deps_missing

    cat > "$TEST_TMPDIR/review.md" <<'EOF'
<!-- bridge-findings-start -->

```json
{
  "schema_version": 1,
  "findings": []
}

<!-- bridge-findings-end -->
EOF

    run "$SCRIPT" --input "$TEST_TMPDIR/review.md" --output "$TEST_TMPDIR/findings.json"
    [ "$status" -eq 3 ]
    [[ "$output" == *"Unclosed JSON fence"* ]]
}

@test "findings-parser: warns on missing schema_version" {
    skip_if_deps_missing

    cat > "$TEST_TMPDIR/review.md" <<'EOF'
<!-- bridge-findings-start -->

```json
{
  "findings": [
    {
      "id": "low-1",
      "title": "Minor",
      "severity": "LOW",
      "category": "quality",
      "file": "a.ts",
      "description": "Minor issue",
      "suggestion": "Fix it"
    }
  ]
}
```

<!-- bridge-findings-end -->
EOF

    run "$SCRIPT" --input "$TEST_TMPDIR/review.md" --output "$TEST_TMPDIR/findings.json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"missing schema_version"* ]] || [[ "$output" == *"WARNING"* ]]

    local total
    total=$(jq '.total' "$TEST_TMPDIR/findings.json")
    [ "$total" = "1" ]
}

@test "findings-parser: no markers produces empty output" {
    skip_if_deps_missing

    cat > "$TEST_TMPDIR/review.md" <<'EOF'
# Just a regular review with no markers

Some text about architecture.

No findings blocks here.
EOF

    run "$SCRIPT" --input "$TEST_TMPDIR/review.md" --output "$TEST_TMPDIR/findings.json"
    [ "$status" -eq 0 ]

    local total
    total=$(jq '.total' "$TEST_TMPDIR/findings.json")
    [ "$total" = "0" ]
}

# =============================================================================
# Legacy Fallback
# =============================================================================

@test "findings-parser: legacy markdown still works when no JSON fence" {
    skip_if_deps_missing

    cat > "$TEST_TMPDIR/review.md" <<'EOF'
<!-- bridge-findings-start -->
### [HIGH-1] Missing validation
**Severity**: HIGH
**Category**: security
**File**: src/api.ts:10
**Description**: No input validation
**Suggestion**: Add Zod schema
<!-- bridge-findings-end -->
EOF

    run "$SCRIPT" --input "$TEST_TMPDIR/review.md" --output "$TEST_TMPDIR/findings.json"
    [ "$status" -eq 0 ]

    local total severity
    total=$(jq '.total' "$TEST_TMPDIR/findings.json")
    severity=$(jq -r '.findings[0].severity' "$TEST_TMPDIR/findings.json")
    [ "$total" = "1" ]
    [ "$severity" = "HIGH" ]
}

@test "findings-parser: legacy output includes schema_version and praise" {
    skip_if_deps_missing

    cat > "$TEST_TMPDIR/review.md" <<'EOF'
<!-- bridge-findings-start -->
### [LOW-1] Minor formatting
**Severity**: LOW
**Category**: style
**File**: src/index.ts:1
**Description**: Inconsistent formatting
**Suggestion**: Run prettier
<!-- bridge-findings-end -->
EOF

    "$SCRIPT" --input "$TEST_TMPDIR/review.md" --output "$TEST_TMPDIR/findings.json"

    local schema_version praise
    schema_version=$(jq '.schema_version' "$TEST_TMPDIR/findings.json")
    praise=$(jq '.by_severity.praise' "$TEST_TMPDIR/findings.json")
    [ "$schema_version" = "1" ]
    [ "$praise" = "0" ]
}

# =============================================================================
# Sprint 3: Fixture-Based Integration Tests
# =============================================================================

@test "fixture-enriched: parser extracts all fields from enriched fixture" {
    skip_if_deps_missing

    local fixture="$BATS_TEST_DIR/../../tests/fixtures/enriched-bridge-review.md"
    [ -f "$fixture" ] || skip "Enriched fixture not found"

    "$SCRIPT" --input "$fixture" --output "$TEST_TMPDIR/findings.json"

    # Check all 5 findings extracted
    local total
    total=$(jq '.total' "$TEST_TMPDIR/findings.json")
    [ "$total" = "5" ]

    # Check enriched fields on critical-1
    local faang metaphor teachable
    faang=$(jq -r '.findings[0].faang_parallel' "$TEST_TMPDIR/findings.json")
    metaphor=$(jq -r '.findings[0].metaphor' "$TEST_TMPDIR/findings.json")
    teachable=$(jq -r '.findings[0].teachable_moment' "$TEST_TMPDIR/findings.json")
    [[ "$faang" == *"Borg"* ]]
    [[ "$metaphor" == *"surgeon"* ]]
    [[ "$teachable" == *"rollback"* ]]

    # Check connection field on high-1
    local connection
    connection=$(jq -r '.findings[1].connection' "$TEST_TMPDIR/findings.json")
    [[ "$connection" == *"parse"* ]]
}

@test "fixture-enriched: PRAISE findings counted correctly" {
    skip_if_deps_missing

    local fixture="$BATS_TEST_DIR/../../tests/fixtures/enriched-bridge-review.md"
    [ -f "$fixture" ] || skip "Enriched fixture not found"

    "$SCRIPT" --input "$fixture" --output "$TEST_TMPDIR/findings.json"

    local praise_count
    praise_count=$(jq '.by_severity.praise' "$TEST_TMPDIR/findings.json")
    [ "$praise_count" = "2" ]

    # Verify praise boolean on praise-1
    local praise_flag
    praise_flag=$(jq '.findings[3].praise' "$TEST_TMPDIR/findings.json")
    [ "$praise_flag" = "true" ]
}

@test "fixture-enriched: severity_weighted_score correct (CRITICAL=10, HIGH=5, MEDIUM=2, PRAISE=0)" {
    skip_if_deps_missing

    local fixture="$BATS_TEST_DIR/../../tests/fixtures/enriched-bridge-review.md"
    [ -f "$fixture" ] || skip "Enriched fixture not found"

    "$SCRIPT" --input "$fixture" --output "$TEST_TMPDIR/findings.json"

    # CRITICAL(10) + HIGH(5) + MEDIUM(2) + PRAISE(0) + PRAISE(0) = 17
    local score
    score=$(jq '.severity_weighted_score' "$TEST_TMPDIR/findings.json")
    [ "$score" = "17" ]
}

@test "fixture-enriched: by_severity includes all 6 levels" {
    skip_if_deps_missing

    local fixture="$BATS_TEST_DIR/../../tests/fixtures/enriched-bridge-review.md"
    [ -f "$fixture" ] || skip "Enriched fixture not found"

    "$SCRIPT" --input "$fixture" --output "$TEST_TMPDIR/findings.json"

    # Check all 6 severity levels exist
    local critical high medium low vision praise
    critical=$(jq '.by_severity.critical' "$TEST_TMPDIR/findings.json")
    high=$(jq '.by_severity.high' "$TEST_TMPDIR/findings.json")
    medium=$(jq '.by_severity.medium' "$TEST_TMPDIR/findings.json")
    low=$(jq '.by_severity.low' "$TEST_TMPDIR/findings.json")
    vision=$(jq '.by_severity.vision' "$TEST_TMPDIR/findings.json")
    praise=$(jq '.by_severity.praise' "$TEST_TMPDIR/findings.json")

    [ "$critical" = "1" ]
    [ "$high" = "1" ]
    [ "$medium" = "1" ]
    [ "$low" = "0" ]
    [ "$vision" = "0" ]
    [ "$praise" = "2" ]
}

@test "fixture-legacy: parser handles legacy markdown format" {
    skip_if_deps_missing

    local fixture="$BATS_TEST_DIR/../../tests/fixtures/legacy-bridge-review.md"
    [ -f "$fixture" ] || skip "Legacy fixture not found"

    "$SCRIPT" --input "$fixture" --output "$TEST_TMPDIR/findings.json"

    local total
    total=$(jq '.total' "$TEST_TMPDIR/findings.json")
    [ "$total" = "4" ]

    # Contract test: verify exact severity breakdown
    local high medium low vision
    high=$(jq '.by_severity.high' "$TEST_TMPDIR/findings.json")
    medium=$(jq '.by_severity.medium' "$TEST_TMPDIR/findings.json")
    low=$(jq '.by_severity.low' "$TEST_TMPDIR/findings.json")
    vision=$(jq '.by_severity.vision' "$TEST_TMPDIR/findings.json")

    [ "$high" = "1" ]
    [ "$medium" = "1" ]
    [ "$low" = "1" ]
    [ "$vision" = "1" ]
}

@test "fixture-legacy: severity_weighted_score correct (HIGH=5, MEDIUM=2, LOW=1, VISION=0)" {
    skip_if_deps_missing

    local fixture="$BATS_TEST_DIR/../../tests/fixtures/legacy-bridge-review.md"
    [ -f "$fixture" ] || skip "Legacy fixture not found"

    "$SCRIPT" --input "$fixture" --output "$TEST_TMPDIR/findings.json"

    # HIGH(5) + MEDIUM(2) + LOW(1) + VISION(0) = 8
    local score
    score=$(jq '.severity_weighted_score' "$TEST_TMPDIR/findings.json")
    [ "$score" = "8" ]
}

@test "fixture-legacy: schema_version and praise present" {
    skip_if_deps_missing

    local fixture="$BATS_TEST_DIR/../../tests/fixtures/legacy-bridge-review.md"
    [ -f "$fixture" ] || skip "Legacy fixture not found"

    "$SCRIPT" --input "$fixture" --output "$TEST_TMPDIR/findings.json"

    local schema_version praise
    schema_version=$(jq '.schema_version' "$TEST_TMPDIR/findings.json")
    praise=$(jq '.by_severity.praise' "$TEST_TMPDIR/findings.json")
    [ "$schema_version" = "1" ]
    [ "$praise" = "0" ]
}

@test "convergence-isolation: PRAISE does not affect severity_weighted_score" {
    skip_if_deps_missing

    # Fixture has: CRITICAL(10) + 2x PRAISE(0) = should be 10
    # If PRAISE were counted, score would be > 10
    local fixture="$BATS_TEST_DIR/../../tests/fixtures/enriched-bridge-review.md"
    [ -f "$fixture" ] || skip "Enriched fixture not found"

    "$SCRIPT" --input "$fixture" --output "$TEST_TMPDIR/findings.json"

    local score praise_count
    score=$(jq '.severity_weighted_score' "$TEST_TMPDIR/findings.json")
    praise_count=$(jq '.by_severity.praise' "$TEST_TMPDIR/findings.json")

    # Score should include CRITICAL+HIGH+MEDIUM but NOT PRAISE
    [ "$praise_count" = "2" ]
    # CRITICAL(10) + HIGH(5) + MEDIUM(2) = 17 (not 17+anything from PRAISE)
    [ "$score" = "17" ]
}

# =============================================================================
# Sprint 3: Performance Sanity Check
# =============================================================================

@test "performance: parser completes in <5s for enriched fixture" {
    skip_if_deps_missing

    local fixture="$BATS_TEST_DIR/../../tests/fixtures/enriched-bridge-review.md"
    [ -f "$fixture" ] || skip "Enriched fixture not found"

    local start end elapsed
    start=$(date +%s)
    "$SCRIPT" --input "$fixture" --output "$TEST_TMPDIR/findings.json"
    end=$(date +%s)
    elapsed=$((end - start))

    [ "$elapsed" -lt 5 ]
}
