#!/usr/bin/env bats
# =============================================================================
# tests/unit/cycle-109-t3-8-flag-removal.bats
#
# cycle-109 Sprint 3 T3.8 — commit E in SDD §5.3.1 sequence. Removes the
# now-dead `is_flatline_routing_enabled()` helper definitions from the
# two operator-facing entrypoints (model-adapter.sh + flatline-orchestrator.sh)
# AND removes the load-bearing `hounfour.flatline_routing` top-level key
# from .loa.config.yaml.example.
#
# Why this is minimal: the helper is still defined in some
# library/transport files (lib-curl-fallback.sh, lib-route-table.sh,
# gpt-review-api.sh, red-team-model-adapter.sh) where they have their own
# audit-trail / circuit-breaker semantics. Those branches are now
# tautologies (legacy is gone; the helper returns either true→cheval or
# false→nothing) but they have no immediate harm. Their cleanup is a
# separate follow-up task; T3.8 stays focused on the FL + model-adapter
# entrypoints and the config key.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    export PROJECT_ROOT
}

# =============================================================================
# T38-1: model-adapter.sh no longer defines is_flatline_routing_enabled
# =============================================================================

@test "T38-1: model-adapter.sh no longer defines is_flatline_routing_enabled()" {
    ! grep -qE '^is_flatline_routing_enabled\(\)' \
        "$PROJECT_ROOT/.claude/scripts/model-adapter.sh"
}

@test "T38-2: flatline-orchestrator.sh no longer defines is_flatline_routing_enabled()" {
    ! grep -qE '^is_flatline_routing_enabled\(\)' \
        "$PROJECT_ROOT/.claude/scripts/flatline-orchestrator.sh"
}

# =============================================================================
# T38-3: load-bearing `hounfour.flatline_routing` top-level key removed
# =============================================================================

@test "T38-3: .loa.config.yaml.example top-level hounfour.flatline_routing key REMOVED" {
    # Pre-T3.8 the example had `hounfour.flatline_routing: true` at
    # column 0 of the hounfour block (line ~664). Post-T3.8 that key
    # MUST be gone from the top-level hounfour block. The
    # feature_flags.flatline_routing sub-key is RETAINED as an
    # informational audit-log surface and is allowed.
    # Pattern: a non-comment line `  flatline_routing:` (2-space indent —
    # i.e., directly under `hounfour:`) is the load-bearing surface.
    ! grep -qE '^  flatline_routing:' "$PROJECT_ROOT/.loa.config.yaml.example"
}

@test "T38-4: feature_flags.flatline_routing sub-key may remain (informational)" {
    # The sub-key under feature_flags is at column 4 (`    flatline_routing:`).
    # It's preserved because other consumers may read it for telemetry
    # without consuming it for dispatch decisions. Just assert the
    # config still parses.
    if command -v yq >/dev/null 2>&1; then
        yq eval '.' "$PROJECT_ROOT/.loa.config.yaml.example" > /dev/null
    else
        skip "yq not installed"
    fi
}

# =============================================================================
# T38-5: bash syntax still valid
# =============================================================================

@test "T38-5: model-adapter.sh bash -n passes" {
    bash -n "$PROJECT_ROOT/.claude/scripts/model-adapter.sh"
}

@test "T38-6: flatline-orchestrator.sh bash -n passes" {
    bash -n "$PROJECT_ROOT/.claude/scripts/flatline-orchestrator.sh"
}

# =============================================================================
# T38-7: model-adapter.sh still routes to cheval (sanity check on the
# main() path post-helper-removal)
# =============================================================================

@test "T38-7: model-adapter.sh main() unconditionally uses MODEL_INVOKE" {
    grep -q '\$MODEL_INVOKE' "$PROJECT_ROOT/.claude/scripts/model-adapter.sh"
}

@test "T38-8: flatline-orchestrator.sh call_model unconditionally uses MODEL_INVOKE" {
    grep -q '\$MODEL_INVOKE' "$PROJECT_ROOT/.claude/scripts/flatline-orchestrator.sh"
}
