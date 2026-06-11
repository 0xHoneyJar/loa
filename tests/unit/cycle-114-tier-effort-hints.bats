#!/usr/bin/env bats
# =============================================================================
# tests/unit/cycle-114-tier-effort-hints.bats
#
# Cycle-114 FR-8 — tier_groups.effort_hints is INFORMATIONAL ONLY.
#
# The hints advise operators/economy roll-up about reasoning depth per tier but
# MUST NOT participate in model resolution. These tests pin that invariant:
#  - effort_hints exists and every value is a valid effort level
#  - effort_hints lives OUTSIDE tier_groups.mappings, so the FR-3.9 resolver
#    (which iterates mappings.<tier>.<provider>) never observes it
#  - the (tier,provider)→alias mappings are unchanged in shape
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    CONFIG="$PROJECT_ROOT/.claude/defaults/model-config.yaml"
}

@test "c114-FR8: effort_hints exists with valid levels" {
    run yq eval '.tier_groups.effort_hints.max' "$CONFIG"
    [ "$status" -eq 0 ]
    [ "$output" = "xhigh" ]
    for tier in max mid cheap tiny; do
        val=$(yq eval ".tier_groups.effort_hints.$tier" "$CONFIG")
        case "$val" in
            low|medium|high|xhigh|max) ;;
            *) echo "invalid effort hint for $tier: $val" >&2; return 1 ;;
        esac
    done
}

@test "c114-FR8: effort_hints is NOT inside mappings (resolver-invisible)" {
    # mappings.<tier> must contain only provider keys, never 'effort'/'effort_hints'.
    for tier in max mid cheap tiny; do
        run yq eval ".tier_groups.mappings.$tier | has(\"effort\")" "$CONFIG"
        [ "$output" = "false" ]
        run yq eval ".tier_groups.mappings.$tier | has(\"effort_hints\")" "$CONFIG"
        [ "$output" = "false" ]
    done
}

@test "c114-FR8: tier mappings shape unchanged (max→fable, providers intact)" {
    # 2026-06-10 intel-routing review: max retargeted opus → fable (the top
    # intelligence tier), with pricing registered before routability.
    run yq eval '.tier_groups.mappings.max.anthropic' "$CONFIG"
    [ "$output" = "fable" ]
    # each tier still maps the three providers
    for tier in max mid cheap tiny; do
        keys=$(yq eval ".tier_groups.mappings.$tier | keys | join(\",\")" "$CONFIG")
        [[ "$keys" == *"anthropic"* && "$keys" == *"openai"* && "$keys" == *"google"* ]]
    done
}
