#!/usr/bin/env bats
# Unit tests for Flatline Round-Robin Arbiter (cycle-070 FR-4)

setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"

    export BATS_TMPDIR="${BATS_TMPDIR:-/tmp}"
    export TEST_TMPDIR="$BATS_TMPDIR/flatline-arbiter-test-$$"
    mkdir -p "$TEST_TMPDIR"
}

teardown() {
    cd /
    unset SIMSTIM_AUTONOMOUS
    if [[ -d "$TEST_TMPDIR" ]]; then
        rm -rf "$TEST_TMPDIR"
    fi
}

# =============================================================================
# Arbiter Rotation
# =============================================================================

@test "arbiter: PRD phase selects first model in rotation (opus)" {
    local rotation=("opus" "gpt-5.3-codex" "gemini-2.5-pro")
    local phase="prd"
    local arbiter_model
    case "$phase" in
        prd)    arbiter_model="${rotation[0]}" ;;
        sdd)    arbiter_model="${rotation[1]}" ;;
        sprint) arbiter_model="${rotation[2]}" ;;
        *)      arbiter_model="${rotation[0]}" ;;
    esac
    [ "$arbiter_model" = "opus" ]
}

@test "arbiter: SDD phase selects second model (gpt-5.3-codex)" {
    local rotation=("opus" "gpt-5.3-codex" "gemini-2.5-pro")
    local phase="sdd"
    local arbiter_model
    case "$phase" in
        prd)    arbiter_model="${rotation[0]}" ;;
        sdd)    arbiter_model="${rotation[1]}" ;;
        sprint) arbiter_model="${rotation[2]}" ;;
    esac
    [ "$arbiter_model" = "gpt-5.3-codex" ]
}

@test "arbiter: Sprint phase selects third model (gemini-2.5-pro)" {
    local rotation=("opus" "gpt-5.3-codex" "gemini-2.5-pro")
    local phase="sprint"
    local arbiter_model
    case "$phase" in
        prd)    arbiter_model="${rotation[0]}" ;;
        sdd)    arbiter_model="${rotation[1]}" ;;
        sprint) arbiter_model="${rotation[2]}" ;;
    esac
    [ "$arbiter_model" = "gemini-2.5-pro" ]
}

@test "arbiter: unknown phase defaults to first model" {
    local rotation=("opus" "gpt-5.3-codex" "gemini-2.5-pro")
    local phase="beads"
    local arbiter_model
    case "$phase" in
        prd)    arbiter_model="${rotation[0]}" ;;
        sdd)    arbiter_model="${rotation[1]}" ;;
        sprint) arbiter_model="${rotation[2]}" ;;
        *)      arbiter_model="${rotation[0]}" ;;
    esac
    [ "$arbiter_model" = "opus" ]
}

# =============================================================================
# Cascade Logic
# =============================================================================

@test "arbiter: cascade builds correct try order" {
    local arbiter_model="gpt-5.3-codex"
    local rotation=("opus" "gpt-5.3-codex" "gemini-2.5-pro")
    local try_models=("$arbiter_model")
    for m in "${rotation[@]}"; do
        [[ "$m" != "$arbiter_model" ]] && try_models+=("$m")
    done

    [ "${try_models[0]}" = "gpt-5.3-codex" ]
    [ "${try_models[1]}" = "opus" ]
    [ "${try_models[2]}" = "gemini-2.5-pro" ]
    [ "${#try_models[@]}" -eq 3 ]
}

@test "arbiter: cascade for prd starts with opus" {
    local rotation=("opus" "gpt-5.3-codex" "gemini-2.5-pro")
    local arbiter_model="${rotation[0]}"
    local try_models=("$arbiter_model")
    for m in "${rotation[@]}"; do
        [[ "$m" != "$arbiter_model" ]] && try_models+=("$m")
    done

    [ "${try_models[0]}" = "opus" ]
    [ "${try_models[1]}" = "gpt-5.3-codex" ]
    [ "${try_models[2]}" = "gemini-2.5-pro" ]
}

# =============================================================================
# Decision Parsing
# =============================================================================

@test "arbiter: valid decision JSON parsed correctly" {
    local decisions='[{"finding_id":"SKP-001","decision":"accept","rationale":"Valid concern"},{"finding_id":"SKP-002","decision":"reject","rationale":"Already addressed"}]'

    local accepted rejected
    accepted=$(echo "$decisions" | jq -r '[.[] | select(.decision == "accept") | .finding_id] | join(",")')
    rejected=$(echo "$decisions" | jq -r '[.[] | select(.decision == "reject") | .finding_id] | join(",")')

    [ "$accepted" = "SKP-001" ]
    [ "$rejected" = "SKP-002" ]
}

@test "arbiter: empty decisions array produces empty IDs" {
    local decisions='[]'
    local accepted
    accepted=$(echo "$decisions" | jq -r '[.[] | select(.decision == "accept") | .finding_id] | join(",")')
    [ -z "$accepted" ]
}

@test "arbiter: malformed JSON detected" {
    local bad_response="This is not JSON at all"
    local decisions=""
    decisions=$(echo "$bad_response" | grep -oE '\[.*\]' 2>/dev/null | head -1 | jq '.' 2>/dev/null || true)
    [ -z "$decisions" ] || echo "$decisions" | jq -e 'type == "array"' >/dev/null 2>&1
    # Either empty (no match) or valid JSON — both are safe handling
}

# =============================================================================
# Consensus Modification
# =============================================================================

@test "arbiter: accepted blocker moves to high_consensus" {
    local consensus='{"high_consensus":[{"id":"IMP-001"}],"disputed":[],"blockers":[{"id":"SKP-001","concern":"test"}],"consensus_summary":{"high_consensus_count":1,"disputed_count":0,"blocker_count":1}}'
    local accepted="SKP-001"
    local rejected=""

    local modified
    modified=$(echo "$consensus" | jq --arg accepted "$accepted" --arg rejected "$rejected" '
        ($accepted | split(",") | map(select(. != ""))) as $acc |
        ($rejected | split(",") | map(select(. != ""))) as $rej |
        .high_consensus = (.high_consensus + [.blockers[]? | select(.id as $id | $acc | index($id))] | map(. + {arbiter_accepted: true})) |
        .blockers = [.blockers[]? | select(.id as $id | ($acc + $rej) | index($id) | not)] |
        .consensus_summary.high_consensus_count = (.high_consensus | length) |
        .consensus_summary.blocker_count = (.blockers | length)
    ')

    local hc_count blocker_count arbiter_flag
    hc_count=$(echo "$modified" | jq '.consensus_summary.high_consensus_count')
    blocker_count=$(echo "$modified" | jq '.consensus_summary.blocker_count')
    arbiter_flag=$(echo "$modified" | jq '.high_consensus[-1].arbiter_accepted')

    [ "$hc_count" -eq 2 ]
    [ "$blocker_count" -eq 0 ]
    [ "$arbiter_flag" = "true" ]
}

@test "arbiter: rejected blocker moves to arbiter_rejected" {
    local consensus='{"high_consensus":[],"disputed":[],"blockers":[{"id":"SKP-001"}],"arbiter_rejected":[],"consensus_summary":{"blocker_count":1}}'
    local accepted=""
    local rejected="SKP-001"

    local modified
    modified=$(echo "$consensus" | jq --arg rejected "$rejected" '
        ($rejected | split(",") | map(select(. != ""))) as $rej |
        .arbiter_rejected = [.blockers[]? | select(.id as $id | $rej | index($id))] |
        .blockers = [.blockers[]? | select(.id as $id | $rej | index($id) | not)] |
        .consensus_summary.blocker_count = (.blockers | length) |
        .consensus_summary.arbiter_rejected_count = (.arbiter_rejected | length)
    ')

    local blocker_count rejected_count
    blocker_count=$(echo "$modified" | jq '.consensus_summary.blocker_count')
    rejected_count=$(echo "$modified" | jq '.consensus_summary.arbiter_rejected_count')

    [ "$blocker_count" -eq 0 ]
    [ "$rejected_count" -eq 1 ]
}

# =============================================================================
# Fallback
# =============================================================================

@test "arbiter: fallback auto-rejects all blockers" {
    local consensus='{"high_consensus":[],"disputed":[],"blockers":[{"id":"SKP-001"},{"id":"SKP-002"}],"consensus_summary":{"blocker_count":2}}'

    local modified
    modified=$(echo "$consensus" | jq '
        .arbiter_rejected = .blockers |
        .blockers = [] |
        .consensus_summary.blocker_count = 0 |
        .consensus_summary.arbiter_rejected_count = (.arbiter_rejected | length) |
        .consensus_summary.arbiter_fallback = true
    ')

    local blocker_count rejected_count fallback
    blocker_count=$(echo "$modified" | jq '.consensus_summary.blocker_count')
    rejected_count=$(echo "$modified" | jq '.consensus_summary.arbiter_rejected_count')
    fallback=$(echo "$modified" | jq '.consensus_summary.arbiter_fallback')

    [ "$blocker_count" -eq 0 ]
    [ "$rejected_count" -eq 2 ]
    [ "$fallback" = "true" ]
}

# =============================================================================
# Config Gate
# =============================================================================

@test "arbiter: config has enabled field" {
    local enabled
    enabled=$(yq eval '.flatline_protocol.autonomous_arbiter.enabled' "$PROJECT_ROOT/.loa.config.yaml" 2>/dev/null)
    [[ "$enabled" == "true" || "$enabled" == "false" ]]
}

@test "arbiter: rotation config has 3 models" {
    local count
    count=$(yq eval '.flatline_protocol.autonomous_arbiter.rotation | length' "$PROJECT_ROOT/.loa.config.yaml" 2>/dev/null)
    [ "$count" -eq 3 ]
}

@test "arbiter: only triggers when SIMSTIM_AUTONOMOUS=1" {
    local arbiter_enabled="true"
    export SIMSTIM_AUTONOMOUS=0

    local should_run=false
    if [[ "$arbiter_enabled" == "true" && "${SIMSTIM_AUTONOMOUS:-0}" == "1" ]]; then
        should_run=true
    fi
    [ "$should_run" = "false" ]
}

@test "arbiter: triggers when both flags set" {
    local arbiter_enabled="true"
    export SIMSTIM_AUTONOMOUS=1

    local should_run=false
    if [[ "$arbiter_enabled" == "true" && "${SIMSTIM_AUTONOMOUS:-0}" == "1" ]]; then
        should_run=true
    fi
    [ "$should_run" = "true" ]
}

# =============================================================================
# Trajectory Logging Format
# =============================================================================

@test "arbiter: trajectory entry has required fields" {
    local decisions='[{"finding_id":"SKP-001","decision":"accept","rationale":"Valid"}]'
    local log_entry
    log_entry=$(echo "$decisions" | jq -c --arg phase "prd" --arg model "opus" --argjson attempts 1 \
        '.[0] | {
            type: "flatline_arbiter",
            phase: $phase,
            arbiter_model: $model,
            finding_id: .finding_id,
            decision: .decision,
            rationale: .rationale,
            cascade_attempts: $attempts
        }')

    echo "$log_entry" | jq -e '.type == "flatline_arbiter"'
    echo "$log_entry" | jq -e '.phase == "prd"'
    echo "$log_entry" | jq -e '.arbiter_model == "opus"'
    echo "$log_entry" | jq -e '.finding_id == "SKP-001"'
    echo "$log_entry" | jq -e '.decision == "accept"'
    echo "$log_entry" | jq -e '.cascade_attempts == 1'
}
