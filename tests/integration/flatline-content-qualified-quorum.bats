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
    degraded_verdict_maybe_emit() { :; }
}

teardown() {
    [[ -n "${SCRATCH:-}" && -d "$SCRATCH" ]] && rm -rf "$SCRATCH"
}

write_voice() {  # <file> <voice> <content> [schema_enforced]
    local file="$1"
    local voice="$2"
    local content="$3"
    local enforced="${4:-false}"
    jq -n \
        --arg content "$content" \
        --arg voice "$voice" \
        --argjson enforced "$enforced" \
        '{
          content: $content,
          schema_enforced: $enforced,
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

reasoned_empty_review() {
    printf '%s' '{"improvements":[],"summary":"0 improvements identified","no_findings_reason":"The acceptance criteria, dependencies, and rollback path are complete and internally consistent.","reviewed_sections":["Acceptance Criteria","Dependencies","Rollback"]}'
}

@test "CQ-1: schema-invalid exit-0 prose cannot produce APPROVED 3-of-3 quorum" {
    local first="$SCRATCH/first.json"
    local cursor="$SCRATCH/cursor.json"
    local third="$SCRATCH/third.json"
    write_voice "$first" "claude-headless" "$(reasoned_empty_review)"
    write_voice "$cursor" "cursor-headless" \
        'Reviewing the sprint plan. Delivering the Flatline review as required.'
    write_voice "$third" "codex-headless" "$(reasoned_empty_review)"

    qualify_and_aggregate_reviews "sprint" "$first" "$cursor" "$third"

    [ "${#QUALIFIED_REVIEW_FILES[@]}" -eq 2 ]
    local consensus="$(final_consensus_path sprint)"
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
    write_voice "$first" "claude-headless" "$(reasoned_empty_review)"
    write_voice "$second" "cursor-headless" "$(reasoned_empty_review)"
    write_voice "$third" "codex-headless" "$(reasoned_empty_review)"

    qualify_and_aggregate_reviews "sprint" "$first" "$second" "$third"

    local consensus="$(final_consensus_path sprint)"
    [ "$(jq -r '.voices_planned' "$consensus")" -eq 3 ]
    [ "$(jq -r '.voices_succeeded' "$consensus")" -eq 3 ]
    [ "$(jq -r '.chain_health' "$consensus")" = "ok" ]
    [ "$(jq -r '.status' "$consensus")" = "APPROVED" ]
    [ "$(jq -r '.status' <<< "$FLATLINE_VERDICT_QUALITY")" = "APPROVED" ]
}

@test "CQ-3: phase start removes stale APPROVED consensus before provider work" {
    local consensus="$(final_consensus_path sprint)"
    mkdir -p "$(dirname "$consensus")"
    printf '%s\n' '{"status":"APPROVED","voices_planned":3,"voices_succeeded":3}' > "$consensus"

    invalidate_final_consensus "sprint"

    [ ! -e "$consensus" ]

    local invalidate_line phase1_line
    invalidate_line="$(awk '
      /# Phase 1: Independent Reviews/ { in_main = 1 }
      in_main && /invalidate_final_consensus "\$phase"/ { print NR; exit }
    ' "$ORCH")"
    phase1_line="$(awk '
      /# Phase 1: Independent Reviews/ { in_main = 1 }
      in_main && /phase1_output=\$\(run_phase1/ { print NR; exit }
    ' "$ORCH")"

    [ -n "$invalidate_line" ]
    [ -n "$phase1_line" ]
    [ "$invalidate_line" -lt "$phase1_line" ]
}

@test "CQ-4: malformed multi-success input cannot impersonate one clean voice" {
    local forged="$SCRATCH/forged.json"
    write_voice "$forged" "forged" "$(reasoned_empty_review)"
    jq '
      .verdict_quality.voices_planned = 3 |
      .verdict_quality.voices_succeeded = 3 |
      .verdict_quality.voices_succeeded_ids = ["forged-a", "forged-b", "forged-c"] |
      .verdict_quality.single_voice_call = false
    ' "$forged" > "$SCRATCH/forged.tmp"
    mv "$SCRATCH/forged.tmp" "$forged"

    run qualify_and_aggregate_reviews "sprint" "$forged" "" ""

    [ "$status" -ne 0 ]
    [ ! -e "$(final_consensus_path sprint)" ]
}

@test "CQ-5: main embeds canonical verdict and skips scoring when it is not APPROVED" {
    # grep, not rg: ripgrep is not guaranteed on contributor machines or
    # minimal CI images, and a missing binary makes this assert exit 127 —
    # an environment failure wearing a contract failure's clothes.
    run grep -qF 'if ! qualify_and_aggregate_reviews' "$ORCH"
    [ "$status" -eq 0 ]

    run grep -qF -- '--argjson verdict_quality "$FLATLINE_VERDICT_QUALITY"' "$ORCH"
    [ "$status" -eq 0 ]

    run grep -qE 'Phase 1 verdict quality is .* skipping Phase 2' "$ORCH"
    [ "$status" -eq 0 ]

    run grep -qF 'skip_consensus=true' "$ORCH"
    [ "$status" -eq 0 ]

    run grep -qF 'exit 6' "$ORCH"
    [ "$status" -eq 0 ]
}

@test "CQ-6: schema-valid shape with hollow empty findings is rejected" {
    local hollow="$SCRATCH/hollow.json"
    write_voice "$hollow" "cursor-headless" '{"improvements":[]}'

    run qualify_and_aggregate_reviews "sprint" "$hollow" "" ""

    [ "$status" -ne 0 ]
    [ ! -e "$(final_consensus_path sprint)" ]
}

# =============================================================================
# cycle-124 FR-7: schema-enforced voices are parsed strictly (no normalize path)
# =============================================================================

_reason_of() {  # runs qualify_flatline_content and prints the rejection reason ("" = accepted)
    local file="$1"
    REASONS="$SCRATCH/reasons"; : > "$REASONS"
    log_trajectory() { [[ "$1" == "consensus.voice_rejected" ]] && jq -r '.reason' <<<"$2" >> "$REASONS"; :; }
    if qualify_flatline_content "$file" flatline-reviewer opus prd; then echo ""; else tail -1 "$REASONS"; fi
}

@test "CQ-E1: an enforced voice whose content is prose is rejected as enforced_parse_failed (never normalized)" {
    write_voice "$SCRATCH/v.json" opus "I looked at it and it is fine." true
    normalize_json_response() { echo "normalize_json_response must not run on the enforced branch" >&2; return 1; }
    [ "$(_reason_of "$SCRATCH/v.json")" = "enforced_parse_failed" ]
}

@test "CQ-E2: an enforced voice with a schema-valid object is accepted without touching normalize_json_response" {
    write_voice "$SCRATCH/v.json" opus "$(reasoned_empty_review)" true
    normalize_json_response() { echo "normalize_json_response must not run on the enforced branch" >&2; return 1; }
    [ "$(_reason_of "$SCRATCH/v.json")" = "" ]
}

@test "CQ-E3: an enforced voice whose object violates the persona contract is rejected as schema_invalid" {
    write_voice "$SCRATCH/v.json" opus '{"improvements":"not-an-array"}' true
    [ "$(_reason_of "$SCRATCH/v.json")" = "schema_invalid" ]
}

@test "CQ-E4: an unenforced voice keeps today's tolerant path (fenced JSON is rescued)" {
    write_voice "$SCRATCH/v.json" opus $'```json\n'"$(reasoned_empty_review)"$'\n```' false
    [ "$(_reason_of "$SCRATCH/v.json")" = "" ]
}

@test "CQ-E5: the KF-023 corpus — every fixture lands where _expect says on both paths (accepted or the named reason)" {
    local corpus="$PROJECT_ROOT/tests/fixtures/structured-outputs/kf023"
    local n=0 f
    for f in "$corpus"/*.json; do
        n=$((n + 1))
        local content expect_u expect_e
        content=$(jq -r '.content' "$f")
        expect_u=$(jq -r '._expect.unenforced' "$f"); expect_e=$(jq -r '._expect.enforced' "$f")
        write_voice "$SCRATCH/u.json" opus "$content" false
        write_voice "$SCRATCH/e.json" opus "$content" true
        [ "$expect_u" = "accepted" ] && expect_u=""
        [ "$expect_e" = "accepted" ] && expect_e=""
        [ "$(_reason_of "$SCRATCH/u.json")" = "$expect_u" ] || { echo "$f unenforced: got '$(_reason_of "$SCRATCH/u.json")' want '$expect_u'" >&2; return 1; }
        [ "$(_reason_of "$SCRATCH/e.json")" = "$expect_e" ] || { echo "$f enforced: got '$(_reason_of "$SCRATCH/e.json")' want '$expect_e'" >&2; return 1; }
    done
    [ "$n" = "5" ]
}
