#!/usr/bin/env bats
# =============================================================================
# tests/unit/tier-validator.bats
#
# cycle-098 Sprint 1C — tier-validator.sh (CC-10 enforcement).
#
# Per PRD §Supported Configuration Tiers + SDD §1.4.1 (line ~291):
#   Tier 0: Baseline — none enabled
#   Tier 1: L4 + L7
#   Tier 2: L2 + L4 + L6 + L7
#   Tier 3: L1 + L2 + L3 + L4 + L6 + L7
#   Tier 4: Full Network — L1..L7 (all)
#
# Default: tier_enforcement_mode: warn (Operator Option C per
#   cycles/cycle-098-agent-network/decisions/tier-enforcement-default.md).
#
# Outputs: `tier-N` identifier or `unsupported` warning to stderr.
# Exit codes: 0 = supported, 1 = warn (unsupported, mode=warn), 2 = refuse.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    TIER_VALIDATOR="$PROJECT_ROOT/.claude/scripts/tier-validator.sh"

    [[ -f "$TIER_VALIDATOR" ]] || skip "tier-validator.sh not yet implemented"
    [[ -x "$TIER_VALIDATOR" ]] || chmod +x "$TIER_VALIDATOR" || true

    TEST_DIR="$(mktemp -d)"
    CONFIG="$TEST_DIR/loa.config.yaml"
    export LOA_CONFIG_FILE="$CONFIG"
}

teardown() {
    if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then
        find "$TEST_DIR" -type f -delete 2>/dev/null || true
        rmdir "$TEST_DIR" 2>/dev/null || true
    fi
    unset LOA_CONFIG_FILE
}

# Helper to write a config with a primitive enabled set.
_write_config() {
    local mode="${1:-warn}"
    shift
    local enabled_list="$*"
    {
        echo "tier_enforcement_mode: ${mode}"
        echo "agent_network:"
        echo "  primitives:"
        for p in L1 L2 L3 L4 L5 L6 L7; do
            local enabled=false
            for e in $enabled_list; do
                [[ "$e" == "$p" ]] && enabled=true
            done
            echo "    ${p}:"
            echo "      enabled: ${enabled}"
        done
    } > "$CONFIG"
}

# -----------------------------------------------------------------------------
# Tier 0: nothing enabled (baseline)
# -----------------------------------------------------------------------------
@test "tier-0: no primitives enabled => Tier 0 (Baseline) supported" {
    _write_config warn ""
    run "$TIER_VALIDATOR" check
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"tier-0"* ]]
}

# -----------------------------------------------------------------------------
# Tier 1: L4 + L7
# -----------------------------------------------------------------------------
@test "tier-1: L4+L7 enabled => Tier 1 (Identity & Trust) supported" {
    _write_config warn "L4 L7"
    run "$TIER_VALIDATOR" check
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"tier-1"* ]]
}

# -----------------------------------------------------------------------------
# Tier 2: L2 + L4 + L6 + L7
# -----------------------------------------------------------------------------
@test "tier-2: L2+L4+L6+L7 => Tier 2 (Resource & Handoff) supported" {
    _write_config warn "L2 L4 L6 L7"
    run "$TIER_VALIDATOR" check
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"tier-2"* ]]
}

# -----------------------------------------------------------------------------
# Tier 3: L1 + L2 + L3 + L4 + L6 + L7
# -----------------------------------------------------------------------------
@test "tier-3: L1+L2+L3+L4+L6+L7 => Tier 3 supported" {
    _write_config warn "L1 L2 L3 L4 L6 L7"
    run "$TIER_VALIDATOR" check
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"tier-3"* ]]
}

# -----------------------------------------------------------------------------
# Tier 4: Full Network
# -----------------------------------------------------------------------------
@test "tier-4: all 7 primitives enabled => Tier 4 (Full Network) supported" {
    _write_config warn "L1 L2 L3 L4 L5 L6 L7"
    run "$TIER_VALIDATOR" check
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"tier-4"* ]]
}

# -----------------------------------------------------------------------------
# Unsupported combinations (warn vs refuse)
# -----------------------------------------------------------------------------
@test "tier-unsupported-warn: L1 alone (no L4/L2) => warn mode prints WARNING but exits 1" {
    _write_config warn "L1"
    run "$TIER_VALIDATOR" check
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"unsupported"* ]] || [[ "$stderr" == *"unsupported"* ]]
    [[ "$output" == *"WARNING"* ]] || [[ "$stderr" == *"WARNING"* ]]
}

@test "tier-unsupported-refuse: L1 alone with refuse mode => exit 2 with error" {
    _write_config refuse "L1"
    run "$TIER_VALIDATOR" check
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"unsupported"* ]] || [[ "$stderr" == *"unsupported"* ]]
}

@test "tier-unsupported: L5 alone (no underlying tiers) => unsupported" {
    _write_config warn "L5"
    run "$TIER_VALIDATOR" check
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"unsupported"* ]] || [[ "$stderr" == *"unsupported"* ]]
}

# -----------------------------------------------------------------------------
# Default mode is warn (Operator Option C)
# -----------------------------------------------------------------------------
@test "tier-default: missing tier_enforcement_mode key defaults to warn" {
    {
        echo "agent_network:"
        echo "  primitives:"
        echo "    L1:"
        echo "      enabled: true"
        for p in L2 L3 L4 L5 L6 L7; do
            echo "    ${p}:"
            echo "      enabled: false"
        done
    } > "$CONFIG"

    run "$TIER_VALIDATOR" check
    # Unsupported (L1 alone) — but mode is the default (warn) so exit 1, not 2.
    [[ "$status" -eq 1 ]]
}

# -----------------------------------------------------------------------------
# list-supported subcommand
# -----------------------------------------------------------------------------
@test "tier-list-supported: prints all 5 supported tiers" {
    run "$TIER_VALIDATOR" list-supported
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"tier-0"* ]]
    [[ "$output" == *"tier-1"* ]]
    [[ "$output" == *"tier-2"* ]]
    [[ "$output" == *"tier-3"* ]]
    [[ "$output" == *"tier-4"* ]]
}

# -----------------------------------------------------------------------------
# Missing config falls back to Tier 0 (no primitives enabled = baseline)
# -----------------------------------------------------------------------------
@test "tier-missing-config: no config file => Tier 0 (Baseline) supported" {
    # CONFIG path does not exist
    run "$TIER_VALIDATOR" check
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"tier-0"* ]]
}
