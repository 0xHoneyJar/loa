#!/usr/bin/env bats
# =============================================================================
# flatline-grounding-failure.bats — tests for #582 red-team fail-closed guard
# =============================================================================
# Validates:
#   - The grounding-failure jq expression is present in flatline-orchestrator.sh
#   - The ratio + min-N guard math is correct
#   - Exit code 3 is distinct from other failure codes
#   - Threshold + min_attacks are read from config with sensible defaults
# =============================================================================

setup() {
    export PROJECT_ROOT="$BATS_TEST_DIRNAME/../.."
    export ORCH="$PROJECT_ROOT/.claude/scripts/flatline-orchestrator.sh"
}

# =========================================================================
# FGF-T1: the guard code is present in the orchestrator
# =========================================================================

@test "grounding_failure guard is wired into red-team path" {
    run grep -F 'grounding_failure:' "$ORCH"
    [ "$status" -eq 0 ]
}

@test "grounding_failure threshold reads from config with default 0.8" {
    run grep -F 'opus_zero_threshold // 0.8' "$ORCH"
    [ "$status" -eq 0 ]
}

@test "grounding_failure min_attacks reads from config with default 3" {
    run grep -F 'min_attacks // 3' "$ORCH"
    [ "$status" -eq 0 ]
}

@test "grounding_failure exits with distinct code 3" {
    # The halt path must exit 3, not 1 or 2, so callers can distinguish it
    run grep -E 'Red team HALTED.*grounding failure' "$ORCH"
    [ "$status" -eq 0 ]
    # And the exit 3 should be co-located in the halt block
    run grep -B 2 -A 2 'Red team HALTED' "$ORCH"
    [[ "$output" == *"exit 3"* ]]
}

# =========================================================================
# FGF-T2: the guard counts attacks across ALL 4 categories
# =========================================================================

@test "grounding_failure math includes all 4 attack categories" {
    # confirmed + theoretical + creative + defended
    grep -F '.attacks.confirmed' "$ORCH"
    grep -F '.attacks.theoretical' "$ORCH"
    grep -F '.attacks.creative' "$ORCH"
    grep -F '.attacks.defended' "$ORCH"
}

# =========================================================================
# FGF-T3: ratio calculation — simulate via jq inline
# =========================================================================

_ratio_jq='
def scored_attacks:
    [ (.attacks.confirmed // [])[],
      (.attacks.theoretical // [])[],
      (.attacks.creative // [])[],
      (.attacks.defended // [])[]
    ];
(scored_attacks) as $all
| ($all | length) as $total
| ([$all[] | select(.opus_score == 0 or .opus_score == "0")] | length) as $opus_zero
| (if $total > 0 then ($opus_zero / $total) else 0 end) as $ratio
| {
    total: $total,
    opus_zero: $opus_zero,
    opus_zero_ratio: $ratio,
    grounding_failure: ($total >= 3 and $ratio >= 0.8)
}'

@test "grounding ratio: 5 of 5 opus_zero trips the guard" {
    local fixture='{
        "attacks": {
            "confirmed": [],
            "theoretical": [
                {"id":"A1","opus_score":0,"gpt_score":850},
                {"id":"A2","opus_score":0,"gpt_score":700},
                {"id":"A3","opus_score":0,"gpt_score":650},
                {"id":"A4","opus_score":0,"gpt_score":600},
                {"id":"A5","opus_score":0,"gpt_score":550}
            ],
            "creative": [],
            "defended": []
        }
    }'
    run bash -c "echo '$fixture' | jq -c '$_ratio_jq'"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"grounding_failure":true'* ]]
    [[ "$output" == *'"total":5'* ]]
    [[ "$output" == *'"opus_zero":5'* ]]
}

@test "grounding ratio: 4 of 5 opus_zero (80%) trips the guard" {
    local fixture='{
        "attacks": {
            "confirmed": [],
            "theoretical": [
                {"id":"A1","opus_score":0},
                {"id":"A2","opus_score":0},
                {"id":"A3","opus_score":0},
                {"id":"A4","opus_score":0},
                {"id":"A5","opus_score":800}
            ],
            "creative": [],
            "defended": []
        }
    }'
    run bash -c "echo '$fixture' | jq -c '$_ratio_jq'"
    [[ "$output" == *'"grounding_failure":true'* ]]
}

@test "grounding ratio: 3 of 5 opus_zero (60%) does NOT trip" {
    local fixture='{
        "attacks": {
            "confirmed": [],
            "theoretical": [
                {"id":"A1","opus_score":0},
                {"id":"A2","opus_score":0},
                {"id":"A3","opus_score":0},
                {"id":"A4","opus_score":500},
                {"id":"A5","opus_score":800}
            ],
            "creative": [],
            "defended": []
        }
    }'
    run bash -c "echo '$fixture' | jq -c '$_ratio_jq'"
    [[ "$output" == *'"grounding_failure":false'* ]]
}

@test "grounding ratio: 2 of 2 opus_zero does NOT trip (small-N guard)" {
    # Below min_attacks (3), should not trip even at 100% ratio
    local fixture='{
        "attacks": {
            "confirmed": [],
            "theoretical": [
                {"id":"A1","opus_score":0},
                {"id":"A2","opus_score":0}
            ],
            "creative": [],
            "defended": []
        }
    }'
    run bash -c "echo '$fixture' | jq -c '$_ratio_jq'"
    [[ "$output" == *'"grounding_failure":false'* ]]
    [[ "$output" == *'"total":2'* ]]
}

@test "grounding ratio: 0 total attacks does NOT trip and does NOT divide by zero" {
    local fixture='{"attacks":{"confirmed":[],"theoretical":[],"creative":[],"defended":[]}}'
    run bash -c "echo '$fixture' | jq -c '$_ratio_jq'"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"grounding_failure":false'* ]]
    [[ "$output" == *'"opus_zero_ratio":0'* ]]
}

@test "grounding ratio: string '0' opus_score is also counted as zero" {
    # Defensive against models that emit scores as strings
    local fixture='{
        "attacks": {
            "confirmed": [],
            "theoretical": [
                {"id":"A1","opus_score":"0"},
                {"id":"A2","opus_score":"0"},
                {"id":"A3","opus_score":"0"},
                {"id":"A4","opus_score":0}
            ],
            "creative": [],
            "defended": []
        }
    }'
    run bash -c "echo '$fixture' | jq -c '$_ratio_jq'"
    [[ "$output" == *'"grounding_failure":true'* ]]
    [[ "$output" == *'"opus_zero":4'* ]]
}

# =========================================================================
# FGF-T4: exit code integration — invoke orchestrator help and assert
# =========================================================================

@test "orchestrator --help mentions inquiry mode (#579 drive-by)" {
    run "$ORCH" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"inquiry"* ]]
}
