#!/usr/bin/env bats
# =============================================================================
# spiral-phase-timeouts.bats — Tests for planning-phase timeout config (#570)
# =============================================================================
# Sprint-bug-112. Validates that spiral-harness.sh reads
# spiral.harness.{discovery,architecture,planning}_timeout_sec from config
# and propagates them to the _invoke_claude call, instead of the hardcoded
# 300s that was too tight for non-trivial specs.

setup() {
    export PROJECT_ROOT="$BATS_TEST_DIRNAME/../.."
    export HARNESS="$PROJECT_ROOT/.claude/scripts/spiral-harness.sh"
}

# =========================================================================
# PT-T1: source file no longer contains the hardcoded 300s on phase calls
# =========================================================================

@test "no hardcoded 300 on _invoke_claude DISCOVERY/ARCHITECTURE/PLANNING" {
    run grep -E '_invoke_claude "(DISCOVERY|ARCHITECTURE|PLANNING)".*"\$PLANNING_BUDGET" 300' "$HARNESS"
    [ "$status" -ne 0 ]
}

# =========================================================================
# PT-T2: each planning phase now references a config-read timeout variable
# =========================================================================

@test "DISCOVERY phase uses DISCOVERY_TIMEOUT variable" {
    run grep -E '_invoke_claude "DISCOVERY".*\$DISCOVERY_TIMEOUT' "$HARNESS"
    [ "$status" -eq 0 ]
}

@test "ARCHITECTURE phase uses ARCHITECTURE_TIMEOUT variable" {
    run grep -E '_invoke_claude "ARCHITECTURE".*\$ARCHITECTURE_TIMEOUT' "$HARNESS"
    [ "$status" -eq 0 ]
}

@test "PLANNING phase uses PLANNING_TIMEOUT variable" {
    run grep -E '_invoke_claude "PLANNING".*\$PLANNING_TIMEOUT' "$HARNESS"
    [ "$status" -eq 0 ]
}

# =========================================================================
# PT-T3: timeout variables are populated via _read_harness_config with
# defaults that clear the observed 300s failure window
# =========================================================================

@test "DISCOVERY_TIMEOUT default is 1200s (was 300s, too tight per #570)" {
    run grep -E 'DISCOVERY_TIMEOUT=.*_read_harness_config.*"1200"' "$HARNESS"
    [ "$status" -eq 0 ]
}

@test "ARCHITECTURE_TIMEOUT default is 1200s" {
    run grep -E 'ARCHITECTURE_TIMEOUT=.*_read_harness_config.*"1200"' "$HARNESS"
    [ "$status" -eq 0 ]
}

@test "PLANNING_TIMEOUT default is 600s" {
    run grep -E 'PLANNING_TIMEOUT=.*_read_harness_config.*"600"' "$HARNESS"
    [ "$status" -eq 0 ]
}

# =========================================================================
# PT-T4: config keys follow the existing naming convention
# =========================================================================

@test "config keys under spiral.harness.{phase}_timeout_sec" {
    run grep -cE 'spiral\.harness\.(discovery|architecture|planning)_timeout_sec' "$HARNESS"
    [ "$status" -eq 0 ]
    [ "$output" -eq 3 ]
}

# =========================================================================
# PT-T5: totals stay under simstim_sec cap (2h = 7200s)
# =========================================================================

@test "new default timeouts total well under simstim_sec cap of 7200s" {
    # 1200 + 1200 + 600 = 3000s = 50 minutes. Leaves 4200s for impl+review+audit.
    local total=$((1200 + 1200 + 600))
    [ "$total" -lt 7200 ]
}
