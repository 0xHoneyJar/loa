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
    # Config file exists and is readable by the sourced orchestrator
    export CONFIG_FILE="$PROJECT_ROOT/.loa.config.yaml"
}

# Helper: call compute_grounding_stats by sourcing the orchestrator.
# The orchestrator has a `BASH_SOURCE[0] == $0` guard that prevents main()
# from running when sourced — so the function becomes addressable.
_grounding_stats() {
    local json="$1"
    local threshold="${2:-0.8}"
    local min_attacks="${3:-3}"
    bash -c "
        PROJECT_ROOT='$PROJECT_ROOT'
        CONFIG_FILE='$CONFIG_FILE'
        source '$ORCH'
        echo '$json' | compute_grounding_stats '$threshold' '$min_attacks'
    "
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

@test "grounding_failure halt path uses exit code 3 (static check)" {
    # Static guarantee that the halt path uses exit 3 specifically, so callers
    # can distinguish it from generic failures (1) and config errors (2).
    run grep -E 'Red team HALTED.*grounding failure' "$ORCH"
    [ "$status" -eq 0 ]
    run grep -B 2 -A 2 'Red team HALTED' "$ORCH"
    [[ "$output" == *"exit 3"* ]]
}

@test "compute_grounding_stats is exported as a sourceable function" {
    # Addresses Gemini's PR #583 review finding M001: exit-code-3 test
    # needs to be dynamic, not just grep. Source the orchestrator and
    # confirm the function is callable.
    run bash -c "
        PROJECT_ROOT='$PROJECT_ROOT'
        CONFIG_FILE='$CONFIG_FILE'
        source '$ORCH'
        type -t compute_grounding_stats
    "
    [ "$status" -eq 0 ]
    [ "$output" = "function" ]
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
# FGF-T5: DYNAMIC tests — address PR #583 M001
# Call the actual sourced function rather than simulating the jq inline.
# =========================================================================

@test "dynamic: 5 of 5 opus_zero trips real compute_grounding_stats" {
    local fixture='{"attacks":{"confirmed":[],"theoretical":[{"opus_score":0},{"opus_score":0},{"opus_score":0},{"opus_score":0},{"opus_score":0}],"creative":[],"defended":[]}}'
    run _grounding_stats "$fixture" 0.8 3
    [ "$status" -eq 0 ]
    [[ "$output" == *'"grounding_failure":true'* ]]
    [[ "$output" == *'"total":5'* ]]
    [[ "$output" == *'"opus_zero":5'* ]]
}

@test "dynamic: 4 of 5 opus_zero (80%) trips real function" {
    local fixture='{"attacks":{"confirmed":[],"theoretical":[{"opus_score":0},{"opus_score":0},{"opus_score":0},{"opus_score":0},{"opus_score":800}],"creative":[],"defended":[]}}'
    run _grounding_stats "$fixture" 0.8 3
    [[ "$output" == *'"grounding_failure":true'* ]]
}

@test "dynamic: 2 of 2 opus_zero does NOT trip real function (small-N)" {
    local fixture='{"attacks":{"confirmed":[],"theoretical":[{"opus_score":0},{"opus_score":0}],"creative":[],"defended":[]}}'
    run _grounding_stats "$fixture" 0.8 3
    [[ "$output" == *'"grounding_failure":false'* ]]
    [[ "$output" == *'"total":2'* ]]
}

@test "dynamic: custom threshold 0.5 trips at 50% zero ratio" {
    local fixture='{"attacks":{"confirmed":[],"theoretical":[{"opus_score":0},{"opus_score":0},{"opus_score":500},{"opus_score":800}],"creative":[],"defended":[]}}'
    run _grounding_stats "$fixture" 0.5 3
    [[ "$output" == *'"grounding_failure":true'* ]]
    [[ "$output" == *'"threshold":0.5'* ]]
}

@test "dynamic: empty attacks returns grounding_failure=false without divide-by-zero" {
    local fixture='{"attacks":{"confirmed":[],"theoretical":[],"creative":[],"defended":[]}}'
    run _grounding_stats "$fixture" 0.8 3
    [ "$status" -eq 0 ]
    [[ "$output" == *'"grounding_failure":false'* ]]
    [[ "$output" == *'"opus_zero_ratio":0'* ]]
}

@test "dynamic: malformed input gracefully returns grounding_failure=false" {
    # Guards the `|| echo '{"grounding_failure":false}'` fallback in the function
    local fixture='not valid json'
    run _grounding_stats "$fixture" 0.8 3
    [ "$status" -eq 0 ]
    [[ "$output" == *'"grounding_failure":false'* ]]
}

@test "dynamic: attacks split across all 4 categories are counted together" {
    local fixture='{
      "attacks": {
        "confirmed":   [{"opus_score":0}],
        "theoretical": [{"opus_score":0}],
        "creative":    [{"opus_score":0}],
        "defended":    [{"opus_score":500}]
      }
    }'
    run _grounding_stats "$fixture" 0.8 3
    [[ "$output" == *'"total":4'* ]]
    [[ "$output" == *'"opus_zero":3'* ]]
    # 3/4 = 0.75 which is below 0.8 — should NOT trip
    [[ "$output" == *'"grounding_failure":false'* ]]
}

# =========================================================================
# FGF-T4: exit code integration — invoke orchestrator help and assert
# =========================================================================

@test "orchestrator --help mentions inquiry mode (#579 drive-by)" {
    run "$ORCH" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"inquiry"* ]]
}
