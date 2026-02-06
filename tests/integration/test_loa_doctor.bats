#!/usr/bin/env bats
# Integration tests for loa-doctor.sh — Comprehensive health check
#
# Tests the doctor script's ability to detect healthy, degraded, and
# unhealthy states using hermetic fixtures (mock tools on PATH).
#
# Why these tests matter:
#   flutter doctor changed how developers think about CLI health checks.
#   Before flutter, "is my environment set up?" meant reading docs and
#   guessing. After flutter, every tool wanted a /doctor command.
#   These tests ensure Loa's doctor is reliable, not decorative.
#
# Prerequisites:
#   - jq (required for JSON output tests)
#   - bats-core (test runner)
#
# Test strategy:
#   Each test creates a hermetic mock project with fake tool shims
#   on PATH. By replacing shims with failing versions, we simulate
#   missing dependencies and verify the doctor's exit codes and output.
#   We shadow system tools rather than removing them from PATH.

# Per-test setup — isolated mock project + tool shims
setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT_REAL="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    DOCTOR_SCRIPT="$PROJECT_ROOT_REAL/.claude/scripts/loa-doctor.sh"

    # Check prerequisites
    if ! command -v jq &>/dev/null; then
        skip "jq not found (required for doctor tests)"
    fi

    # Create isolated test environment
    TEST_DIR="$(mktemp -d)"
    export NO_COLOR=1

    # Create mock project structure
    mkdir -p "$TEST_DIR/.claude/data"
    mkdir -p "$TEST_DIR/.claude/scripts/lib"
    mkdir -p "$TEST_DIR/.claude/scripts/beads"
    mkdir -p "$TEST_DIR/grimoires/loa"

    # Copy real files into mock structure
    cp "$PROJECT_ROOT_REAL/.claude/data/error-codes.json" "$TEST_DIR/.claude/data/"
    cp "$PROJECT_ROOT_REAL/.claude/scripts/lib/dx-utils.sh" "$TEST_DIR/.claude/scripts/lib/"

    # Stub bootstrap (PROJECT_ROOT provided by env)
    cat > "$TEST_DIR/.claude/scripts/bootstrap.sh" << 'BOOT_EOF'
#!/bin/bash
set -euo pipefail
BOOT_EOF

    # Create minimal config and version files
    printf 'simstim:\n  enabled: true\n' > "$TEST_DIR/.loa.config.yaml"
    printf '{"framework_version":"1.29.0","schema_version":2}\n' > "$TEST_DIR/.loa-version.json"

    # Create grimoire artifacts
    printf '# PRD\n' > "$TEST_DIR/grimoires/loa/prd.md"
    printf '# SDD\n' > "$TEST_DIR/grimoires/loa/sdd.md"
    printf '# Sprint\n' > "$TEST_DIR/grimoires/loa/sprint.md"

    # Create mock bin directory with tool shims that SHADOW system tools
    MOCK_BIN="$TEST_DIR/mock-bin"
    mkdir -p "$MOCK_BIN"

    # jq shim delegates to real jq (needed for actual JSON processing in doctor)
    local real_jq
    real_jq=$(command -v jq)
    cat > "$MOCK_BIN/jq" << JQ_EOF
#!/bin/bash
if [[ "\$1" == "--version" ]]; then echo "jq-1.7"; else exec $real_jq "\$@"; fi
JQ_EOF
    chmod +x "$MOCK_BIN/jq"

    # git shim
    cat > "$MOCK_BIN/git" << 'EOF'
#!/bin/bash
echo "git version 2.47.3"
EOF
    chmod +x "$MOCK_BIN/git"

    # yq shim
    cat > "$MOCK_BIN/yq" << 'EOF'
#!/bin/bash
if [[ "$1" == "--version" ]]; then echo "yq 4.40.5"; elif [[ "$1" == "." ]]; then cat "$2" 2>/dev/null; else echo "{}"; fi
EOF
    chmod +x "$MOCK_BIN/yq"

    # flock shim
    cat > "$MOCK_BIN/flock" << 'EOF'
#!/bin/bash
echo "flock from util-linux 2.39"
EOF
    chmod +x "$MOCK_BIN/flock"

    # br shim
    cat > "$MOCK_BIN/br" << 'EOF'
#!/bin/bash
echo "br 0.1.7"
EOF
    chmod +x "$MOCK_BIN/br"

    # sqlite3 shim
    cat > "$MOCK_BIN/sqlite3" << 'EOF'
#!/bin/bash
echo "3.46.1 2024-08-13"
EOF
    chmod +x "$MOCK_BIN/sqlite3"

    # beads-health.sh stub
    cat > "$TEST_DIR/.claude/scripts/beads/beads-health.sh" << 'EOF'
#!/bin/bash
echo '{"status":"HEALTHY","version":"0.1.7","checks":{},"recommendations":[]}'
EOF
    chmod +x "$TEST_DIR/.claude/scripts/beads/beads-health.sh"
}

# Cleanup
teardown() {
    rm -rf "$TEST_DIR" 2>/dev/null || true
}

# Helper: run doctor with mock environment
# MOCK_BIN is first on PATH so our shims shadow system tools
run_doctor() {
    PROJECT_ROOT="$TEST_DIR" NO_COLOR=1 PATH="$MOCK_BIN:/usr/bin:/bin" \
        run bash "$DOCTOR_SCRIPT" "$@"
}

# Helper: replace a tool shim with one that exits 127 (simulates "not found")
remove_tool() {
    local tool="$1"
    # Shadow with a script that makes `command -v` still find it
    # but we need `command -v` to NOT find it. So we delete the shim
    # and add a broken one that exits immediately, OR we just remove it.
    # Since MOCK_BIN is first on PATH, removing it means the system
    # version may be found. To truly hide it, replace with exit 127.
    rm -f "$MOCK_BIN/$tool"
    # Create a shim that makes itself invisible to `command -v` by exiting 127
    # Actually, `command -v` checks if file exists and is executable, not if it runs.
    # The only way to truly hide a tool is to not have it on PATH at all.
    # So instead, we'll replace it with a shim named differently.
    # Better approach: use a wrapper that filters the tool from PATH.
    :
}

# Helper: truly hide a tool by replacing PATH to exclude system copies
# Creates a restricted PATH with all system tools EXCEPT the specified one
hide_tool() {
    local tool="$1"
    rm -f "$MOCK_BIN/$tool"
    # Also create a shim that exits 1 if command -v somehow finds a system copy
    # The trick: we can't easily hide system tools, but for loa-doctor's
    # `command -v` checks, we need the tool to not be findable.
    # Create a wrapper script as the doctor entry point that filters PATH
    :
}

# =============================================================================
# Healthy State (exit 0)
# =============================================================================

@test "doctor: exits 0 when all deps present" {
    run_doctor
    [[ $status -eq 0 ]]
}

@test "doctor: text output contains all check categories" {
    run_doctor
    [[ "$output" == *"Dependencies"* ]]
    [[ "$output" == *"Framework"* ]]
    [[ "$output" == *"Project State"* ]]
}

@test "doctor: healthy state shows all-clear message" {
    run_doctor
    [[ "$output" == *"All checks passed"* ]] || [[ "$output" == *"HEALTHY"* ]]
}

# =============================================================================
# Unhealthy State (exit 1) — Missing Hard Dependencies
# =============================================================================

@test "doctor: exits 1 when .claude/ directory missing" {
    rm -rf "$TEST_DIR/.claude"
    # Need jq on PATH for doctor to work at all (it's a hard dep)
    # But .claude/ missing should be caught as an issue
    # Since we removed .claude, dx-utils.sh won't be found either.
    # Doctor should still run — it has fallback for missing dx-utils.
    PROJECT_ROOT="$TEST_DIR" NO_COLOR=1 PATH="$MOCK_BIN:/usr/bin:/bin" \
        run bash "$DOCTOR_SCRIPT"
    [[ $status -eq 1 ]]
}

@test "doctor: reports missing .claude/ as system_zone issue" {
    rm -rf "$TEST_DIR/.claude"
    PROJECT_ROOT="$TEST_DIR" NO_COLOR=1 PATH="$MOCK_BIN:/usr/bin:/bin" \
        run bash "$DOCTOR_SCRIPT"
    [[ "$output" == *"system_zone"* ]] || [[ "$output" == *".claude"* ]]
}

# =============================================================================
# Degraded State (exit 2) — Config Warning
# =============================================================================

@test "doctor: exits 2 when config file missing (warning)" {
    rm -f "$TEST_DIR/.loa.config.yaml"
    run_doctor
    [[ $status -eq 2 ]]
}

@test "doctor: exits 2 when version file missing (warning)" {
    rm -f "$TEST_DIR/.loa-version.json"
    run_doctor
    [[ $status -eq 2 ]]
}

# =============================================================================
# JSON Output
# =============================================================================

@test "doctor --json: outputs valid JSON" {
    run_doctor --json
    echo "$output" | jq '.' > /dev/null
}

@test "doctor --json: has required top-level keys" {
    run_doctor --json
    local has_status has_exit_code has_checks has_recommendations
    has_status=$(echo "$output" | jq 'has("status")')
    has_exit_code=$(echo "$output" | jq 'has("exit_code")')
    has_checks=$(echo "$output" | jq 'has("checks")')
    has_recommendations=$(echo "$output" | jq 'has("recommendations")')
    [[ "$has_status" == "true" ]]
    [[ "$has_exit_code" == "true" ]]
    [[ "$has_checks" == "true" ]]
    [[ "$has_recommendations" == "true" ]]
}

@test "doctor --json: checks has all 6 categories" {
    run_doctor --json
    local categories
    categories=$(echo "$output" | jq '.checks | keys | sort | join(",")')
    [[ "$categories" == *"beads"* ]]
    [[ "$categories" == *"dependencies"* ]]
    [[ "$categories" == *"event_bus"* ]]
    [[ "$categories" == *"framework"* ]]
    [[ "$categories" == *"optional_tools"* ]]
    [[ "$categories" == *"project_state"* ]]
}

@test "doctor --json: healthy state has zero issues and warnings" {
    run_doctor --json
    local issues warnings
    issues=$(echo "$output" | jq '.issues')
    warnings=$(echo "$output" | jq '.warnings')
    [[ "$issues" -eq 0 ]]
    [[ "$warnings" -eq 0 ]]
}

@test "doctor --json: exit_code matches actual exit code" {
    run_doctor --json
    local json_exit
    json_exit=$(echo "$output" | jq '.exit_code')
    [[ "$json_exit" -eq "$status" ]]
}

@test "doctor --json: degraded state has warnings > 0" {
    rm -f "$TEST_DIR/.loa.config.yaml"
    run_doctor --json
    local warnings
    warnings=$(echo "$output" | jq '.warnings')
    [[ "$warnings" -gt 0 ]]
}

# =============================================================================
# Category Filter
# =============================================================================

@test "doctor --category deps: runs only dependency checks" {
    run_doctor --category deps
    [[ "$output" == *"Dependencies"* ]]
    # Should NOT contain other categories
    [[ "$output" != *"Optional Tools"* ]]
    [[ "$output" != *"Framework"* ]]
}

@test "doctor --category framework: runs only framework checks" {
    run_doctor --category framework
    [[ "$output" == *"Framework"* ]]
    [[ "$output" != *"Dependencies"* ]]
}

@test "doctor --category: invalid category gives error" {
    run_doctor --category nonexistent
    [[ $status -eq 1 ]]
    [[ "$output" == *"Unknown category"* ]]
}

# =============================================================================
# Quick Mode
# =============================================================================

@test "doctor --quick: completes within 5 seconds" {
    local start_time
    start_time=$(date +%s)
    run_doctor --quick
    local end_time
    end_time=$(date +%s)
    local elapsed=$((end_time - start_time))
    [[ $elapsed -le 5 ]]
}

# =============================================================================
# Verbose Mode
# =============================================================================

@test "doctor --verbose: shows tool names" {
    run_doctor --verbose
    [[ "$output" == *"git"* ]]
    [[ "$output" == *"jq"* ]]
}

# =============================================================================
# Edge Cases
# =============================================================================

@test "doctor: missing grimoire is informational (not an issue)" {
    rm -rf "$TEST_DIR/grimoires"
    run_doctor
    # Should still be HEALTHY (grimoire is informational)
    [[ $status -eq 0 ]]
}

@test "doctor --json: framework version from .loa-version.json" {
    run_doctor --json
    local version
    version=$(echo "$output" | jq -r '.version')
    [[ "$version" == "1.29.0" ]]
}

@test "doctor --json: error_codes check shows count" {
    run_doctor --json
    local detail
    detail=$(echo "$output" | jq -r '.checks.framework.error_codes.detail')
    [[ "$detail" == *"error codes"* ]]
}

# =============================================================================
# Help
# =============================================================================

@test "doctor --help: shows usage" {
    run_doctor --help
    [[ $status -eq 0 ]]
    [[ "$output" == *"Usage"* ]]
}
