#!/usr/bin/env bats
# Regression for #1227: transport success is not epistemic participation.

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    ORCH="$PROJECT_ROOT/.claude/scripts/flatline-orchestrator.sh"
    SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/flatline-qualified-quorum.XXXXXX")"
    chmod 700 "$SCRATCH"

    # shellcheck disable=SC1090
    source "$ORCH"
    export TEMP_DIR="$SCRATCH"
    export LOA_FLATLINE_OUTPUT_DIR_OVERRIDE="$SCRATCH/output"
    log() { :; }
    log_trajectory() { :; }
}

teardown() {
    [[ -n "${SCRATCH:-}" && -d "$SCRATCH" ]] && rm -rf "$SCRATCH"
}

write_voice() {
    local file="$1"
    local voice="$2"
    local content="$3"
    jq -n \
        --arg content "$content" \
        --arg voice "$voice" \
        '{
          content: $content,
          verdict_quality: {
            status: "APPROVED",
            consensus_outcome: "consensus",
            truncation_waiver_applied: false,
            voices_planned: 1,
            voices_succeeded: 1,
            voices_succeeded_ids: [$voice],
            voices_dropped: [],
            chain_health: "ok",
            confidence_floor: "high",
            rationale: "single voice completed",
            single_voice_call: true
          }
        }' > "$file"
}

@test "CQ-1: schema-invalid exit-0 prose cannot produce APPROVED 3-of-3 quorum" {
    local first="$SCRATCH/first.json"
    local cursor="$SCRATCH/cursor.json"
    local third="$SCRATCH/third.json"
    write_voice "$first" "claude-headless" '{"improvements":[]}'
    write_voice "$cursor" "cursor-headless" \
        'Reviewing the sprint plan. Delivering the Flatline review as required.'
    write_voice "$third" "codex-headless" '{"improvements":[]}'

    qualify_and_aggregate_reviews "sprint" "$first" "$cursor" "$third"

    [ "${#QUALIFIED_REVIEW_FILES[@]}" -eq 2 ]
    local consensus="$LOA_FLATLINE_OUTPUT_DIR_OVERRIDE/sprint-final_consensus.json"
    [ "$(jq -r '.voices_planned' "$consensus")" -eq 3 ]
    [ "$(jq -r '.voices_succeeded' "$consensus")" -eq 2 ]
    [ "$(jq -r '.chain_health' "$consensus")" = "degraded" ]
    [ "$(jq -r '.status' "$consensus")" != "APPROVED" ]
    [ "$(jq -r '.status' <<< "$FLATLINE_VERDICT_QUALITY")" = "DEGRADED" ]
}

@test "CQ-2: three schema-valid voices retain APPROVED 3-of-3 quorum" {
    local first="$SCRATCH/first.json"
    local second="$SCRATCH/second.json"
    local third="$SCRATCH/third.json"
    write_voice "$first" "claude-headless" '{"improvements":[]}'
    write_voice "$second" "cursor-headless" '{"improvements":[]}'
    write_voice "$third" "codex-headless" '{"improvements":[]}'

    qualify_and_aggregate_reviews "sprint" "$first" "$second" "$third"

    local consensus="$LOA_FLATLINE_OUTPUT_DIR_OVERRIDE/sprint-final_consensus.json"
    [ "$(jq -r '.voices_planned' "$consensus")" -eq 3 ]
    [ "$(jq -r '.voices_succeeded' "$consensus")" -eq 3 ]
    [ "$(jq -r '.chain_health' "$consensus")" = "ok" ]
    [ "$(jq -r '.status' "$consensus")" = "APPROVED" ]
    [ "$(jq -r '.status' <<< "$FLATLINE_VERDICT_QUALITY")" = "APPROVED" ]
}

@test "CQ-3: phase start removes stale APPROVED consensus before provider work" {
    local consensus="$LOA_FLATLINE_OUTPUT_DIR_OVERRIDE/sprint-final_consensus.json"
    mkdir -p "$(dirname "$consensus")"
    printf '%s\n' '{"status":"APPROVED","voices_planned":3,"voices_succeeded":3}' > "$consensus"

    invalidate_final_consensus "sprint"

    [ ! -e "$consensus" ]
}

@test "CQ-4: malformed multi-success input cannot impersonate one clean voice" {
    local forged="$SCRATCH/forged.json"
    write_voice "$forged" "forged" '{"improvements":[]}'
    jq '
      .verdict_quality.voices_planned = 3 |
      .verdict_quality.voices_succeeded = 3 |
      .verdict_quality.voices_succeeded_ids = ["forged-a", "forged-b", "forged-c"] |
      .verdict_quality.single_voice_call = false
    ' "$forged" > "$SCRATCH/forged.tmp"
    mv "$SCRATCH/forged.tmp" "$forged"

    run qualify_and_aggregate_reviews "sprint" "$forged" "" ""

    [ "$status" -ne 0 ]
    [ ! -e "$LOA_FLATLINE_OUTPUT_DIR_OVERRIDE/sprint-final_consensus.json" ]
}

@test "CQ-5: main embeds canonical verdict and skips scoring when it is not APPROVED" {
    run rg -n 'if ! qualify_and_aggregate_reviews' "$ORCH"
    [ "$status" -eq 0 ]

    run rg -n -- '--argjson verdict_quality "\$FLATLINE_VERDICT_QUALITY"' "$ORCH"
    [ "$status" -eq 0 ]

    run rg -n 'Phase 1 verdict quality is .* skipping Phase 2' "$ORCH"
    [ "$status" -eq 0 ]
}
