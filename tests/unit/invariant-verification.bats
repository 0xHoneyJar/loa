#!/usr/bin/env bats
# Tests for verify-invariants.sh (Sprint 8, Task 8.4)
#
# Exercises the invariant verification script against:
# - Valid codebase (all invariants pass)
# - Missing function references
# - Missing file references
# - Empty invariants file
# - Cross-repo references (SKIPped)
# - Exit codes

setup() {
    export PROJECT_ROOT="${BATS_TEST_DIRNAME}/../.."
    export SCRIPT="${PROJECT_ROOT}/.claude/scripts/verify-invariants.sh"
    export INVARIANTS_FILE="${PROJECT_ROOT}/grimoires/loa/invariants.yaml"

    # Create temp directory for test fixtures
    export TMPDIR_BATS="$(mktemp -d)"
}

teardown() {
    rm -rf "$TMPDIR_BATS"
}

# =============================================================================
# Pre-flight Tests
# =============================================================================

@test "verify-invariants.sh exists and is executable" {
    [ -x "$SCRIPT" ]
}

@test "invariants.yaml exists" {
    [ -f "$INVARIANTS_FILE" ]
}

@test "invariants schema exists" {
    [ -f "${PROJECT_ROOT}/.claude/schemas/invariants.schema.json" ]
}

# =============================================================================
# Valid Codebase Tests
# =============================================================================

@test "all declared invariants pass in valid codebase" {
    run "$SCRIPT" --quiet
    [ "$status" -eq 0 ]
}

@test "all declared invariants pass (JSON output)" {
    run "$SCRIPT" --json
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.status == "pass"'
    echo "$output" | jq -e '.failures == 0'
}

@test "JSON output contains check entries for every reference" {
    run "$SCRIPT" --json
    [ "$status" -eq 0 ]
    # We expect at least 15 checks (17 references in invariants.yaml)
    local count
    count=$(echo "$output" | jq '.checks | length')
    [ "$count" -ge 15 ]
}

@test "all 5 invariants are verified" {
    run "$SCRIPT" --json
    [ "$status" -eq 0 ]
    # Extract unique INV IDs from check names
    local inv_count
    inv_count=$(echo "$output" | jq '[.checks[].name | split(":")[0]] | unique | length')
    [ "$inv_count" -eq 5 ]
}

# =============================================================================
# Missing Function Reference Tests
# =============================================================================

@test "detects missing function (non-existent symbol)" {
    # Create invariants file with a reference to a non-existent function
    cat > "${TMPDIR_BATS}/bad-symbol.yaml" <<'YAML'
schema_version: 1
protocol: loa-hounfour@7.0.0
invariants:
  - id: INV-099
    description: "Test invariant with missing symbol reference"
    severity: advisory
    category: conservation
    properties:
      - "test property"
    verified_in:
      - repo: loa
        file: ".claude/adapters/loa_cheval/metering/pricing.py"
        symbol: "this_function_does_not_exist_anywhere"
YAML

    run "$SCRIPT" --file "${TMPDIR_BATS}/bad-symbol.yaml" --quiet
    [ "$status" -eq 1 ]
}

@test "missing function reports as FAIL in JSON" {
    cat > "${TMPDIR_BATS}/bad-symbol.yaml" <<'YAML'
schema_version: 1
protocol: loa-hounfour@7.0.0
invariants:
  - id: INV-099
    description: "Test invariant with missing symbol reference"
    severity: advisory
    category: conservation
    properties:
      - "test property"
    verified_in:
      - repo: loa
        file: ".claude/adapters/loa_cheval/metering/pricing.py"
        symbol: "this_function_does_not_exist_anywhere"
YAML

    run "$SCRIPT" --file "${TMPDIR_BATS}/bad-symbol.yaml" --json
    [ "$status" -eq 1 ]
    echo "$output" | jq -e '.status == "fail"'
    echo "$output" | jq -e '.failures == 1'
}

# =============================================================================
# Missing File Reference Tests
# =============================================================================

@test "detects missing file" {
    cat > "${TMPDIR_BATS}/bad-file.yaml" <<'YAML'
schema_version: 1
protocol: loa-hounfour@7.0.0
invariants:
  - id: INV-098
    description: "Test invariant with missing file reference"
    severity: advisory
    category: bounded
    properties:
      - "test property"
    verified_in:
      - repo: loa
        file: "this/file/does/not/exist.py"
        symbol: "some_function"
YAML

    run "$SCRIPT" --file "${TMPDIR_BATS}/bad-file.yaml" --quiet
    [ "$status" -eq 1 ]
}

@test "missing file reports as FAIL in JSON" {
    cat > "${TMPDIR_BATS}/bad-file.yaml" <<'YAML'
schema_version: 1
protocol: loa-hounfour@7.0.0
invariants:
  - id: INV-098
    description: "Test invariant with missing file reference"
    severity: advisory
    category: bounded
    properties:
      - "test property"
    verified_in:
      - repo: loa
        file: "this/file/does/not/exist.py"
        symbol: "some_function"
YAML

    run "$SCRIPT" --file "${TMPDIR_BATS}/bad-file.yaml" --json
    [ "$status" -eq 1 ]
    echo "$output" | jq -e '.failures == 1'
    echo "$output" | jq -e '.checks[0].detail | test("not found")'
}

# =============================================================================
# Empty Invariants File Tests
# =============================================================================

@test "handles empty invariants gracefully" {
    cat > "${TMPDIR_BATS}/empty.yaml" <<'YAML'
schema_version: 1
protocol: loa-hounfour@7.0.0
invariants: []
YAML

    run "$SCRIPT" --file "${TMPDIR_BATS}/empty.yaml" --quiet
    [ "$status" -eq 0 ]
}

@test "empty invariants JSON output" {
    cat > "${TMPDIR_BATS}/empty.yaml" <<'YAML'
schema_version: 1
protocol: loa-hounfour@7.0.0
invariants: []
YAML

    run "$SCRIPT" --file "${TMPDIR_BATS}/empty.yaml" --json
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.passes == 0'
}

# =============================================================================
# Cross-Repo Reference Tests
# =============================================================================

@test "cross-repo references are SKIPped not FAILed" {
    cat > "${TMPDIR_BATS}/cross-repo.yaml" <<'YAML'
schema_version: 1
protocol: loa-hounfour@7.0.0
invariants:
  - id: INV-097
    description: "Test invariant with cross-repo reference"
    severity: advisory
    category: conservation
    properties:
      - "test property"
    verified_in:
      - repo: hounfour
        file: "src/monetary_policy.rs"
        symbol: "MonetaryPolicy"
      - repo: arrakis
        file: "src/lot_invariant.ts"
        symbol: "lot_invariant"
YAML

    run "$SCRIPT" --file "${TMPDIR_BATS}/cross-repo.yaml" --json
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.skips == 2'
    echo "$output" | jq -e '.failures == 0'
}

@test "cross-repo skip includes repo name in detail" {
    cat > "${TMPDIR_BATS}/cross-repo.yaml" <<'YAML'
schema_version: 1
protocol: loa-hounfour@7.0.0
invariants:
  - id: INV-097
    description: "Test invariant with cross-repo reference"
    severity: advisory
    category: conservation
    properties:
      - "test property"
    verified_in:
      - repo: hounfour
        file: "src/monetary_policy.rs"
        symbol: "MonetaryPolicy"
YAML

    run "$SCRIPT" --file "${TMPDIR_BATS}/cross-repo.yaml" --json
    echo "$output" | jq -e '.checks[0].status == "skip"'
    echo "$output" | jq -e '.checks[0].detail | test("hounfour")'
}

# =============================================================================
# Exit Code Tests
# =============================================================================

@test "exit 0 for all-pass" {
    run "$SCRIPT" --quiet
    [ "$status" -eq 0 ]
}

@test "exit 1 for any-fail" {
    cat > "${TMPDIR_BATS}/failing.yaml" <<'YAML'
schema_version: 1
protocol: loa-hounfour@7.0.0
invariants:
  - id: INV-096
    description: "Test invariant that will fail"
    severity: critical
    category: conservation
    properties:
      - "test property"
    verified_in:
      - repo: loa
        file: "nonexistent/file.py"
        symbol: "nonexistent"
YAML

    run "$SCRIPT" --file "${TMPDIR_BATS}/failing.yaml" --quiet
    [ "$status" -eq 1 ]
}

@test "exit 2 for missing invariants file" {
    run "$SCRIPT" --file "${TMPDIR_BATS}/nonexistent.yaml" --quiet
    [ "$status" -eq 2 ]
}

# =============================================================================
# Mixed Pass/Fail Tests
# =============================================================================

@test "mixed pass and fail reports correct counts" {
    cat > "${TMPDIR_BATS}/mixed.yaml" <<'YAML'
schema_version: 1
protocol: loa-hounfour@7.0.0
invariants:
  - id: INV-095
    description: "Mixed test invariant — one pass one fail"
    severity: advisory
    category: conservation
    properties:
      - "test property"
    verified_in:
      - repo: loa
        file: ".claude/adapters/loa_cheval/metering/pricing.py"
        symbol: "calculate_cost_micro"
      - repo: loa
        file: ".claude/adapters/loa_cheval/metering/pricing.py"
        symbol: "this_does_not_exist_99999"
YAML

    run "$SCRIPT" --file "${TMPDIR_BATS}/mixed.yaml" --json
    [ "$status" -eq 1 ]
    echo "$output" | jq -e '.passes == 1'
    echo "$output" | jq -e '.failures == 1'
}
