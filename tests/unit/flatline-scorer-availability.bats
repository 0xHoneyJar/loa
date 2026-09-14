#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    SCRATCH="$BATS_TEST_TMPDIR/scoring"
    mkdir -p "$SCRATCH/temp"
    source "$REPO/.claude/scripts/flatline-orchestrator.sh"
    TEMP_DIR="$SCRATCH/temp"
    set_state() { :; }
    log_trajectory() { :; }
    for name in gpt opus t-opus t-gpt g-tert o-tert; do
        jq -n --arg content '{"scores":[]}' '{content:$content}' > "$SCRATCH/$name.json"
    done
    # Direct consensus fixtures intentionally cross-score one known global ID.
    # Real Phase 2 cases below replace these with their actual dispatch inputs.
    for name in gpt opus tertiary; do
        printf '%s\n' '{"improvements":[{"id":"IMP-1","description":"Known shared fixture finding"}]}' \
            > "$TEMP_DIR/$name-items.json"
    done
    printf '{"content":"{\\"concerns\\":[]}"}\n' > "$SCRATCH/skeptic.json"
}

score() {
    jq -n --argjson value "$2" \
        '{content:({scores:[{id:"IMP-1",score:$value}]} | tojson)}' > "$SCRATCH/$1.json"
}

consensus() {
    run_consensus "$SCRATCH/gpt.json" "$SCRATCH/opus.json" \
        "$SCRATCH/skeptic.json" "$SCRATCH/skeptic.json" \
        "$SCRATCH/t-opus.json" "$SCRATCH/t-gpt.json" \
        "$SCRATCH/g-tert.json" "$SCRATCH/o-tert.json"
}

@test "#1199 failed GPT normalization preserves two independent agreeing scorers" {
    printf '{"content":"PRIVATE_INVALID_SCORER"}\n' > "$SCRATCH/gpt.json"
    score opus 900
    score t-gpt 850
    consensus > "$SCRATCH/result"
    jq -e '.high_consensus[0] | .id == "IMP-1" and .gpt_score == null and .opus_score == 900 and .tertiary_score == 850 and .average_score == 875 and .scorers_available == 2' "$SCRATCH/result"
    jq -e '.consensus_summary | .high_consensus_count == 1 and .model_agreement_percent == 100 and .models_available == 2 and .confidence != "single_model"' "$SCRATCH/result"
    jq -e '.degraded == true' "$SCRATCH/result"
}

@test "#1199 zero is a real score and remains in the observed denominator" {
    score gpt 0
    score opus 900
    score t-gpt 850
    consensus > "$SCRATCH/result"
    jq -e '.high_consensus[0] | .gpt_score == 0 and .average_score == (1750/3) and .scorers_available == 3' "$SCRATCH/result"
}

@test "#1199 one high scorer cannot establish agreement or integration" {
    score opus 900
    consensus > "$SCRATCH/result"
    jq -e '.consensus_summary.high_consensus_count == 0 and .consensus_summary.model_agreement_percent == 0 and
        .consensus_summary.models_available == 1 and .confidence == "degraded"' "$SCRATCH/result"
    jq -e '.medium_value[0] | .gpt_score == null and .would_integrate == false and .scorers_available == 1' "$SCRATCH/result"
}

@test "#1199 tertiary-only evidence survives empty primary score streams" {
    score t-gpt 900
    consensus > "$SCRATCH/result"
    jq -e '.medium_value[0] | .id == "IMP-1" and .gpt_score == null and .opus_score == null and .tertiary_score == 900' "$SCRATCH/result"
    jq -e '.confidence == "degraded" and .consensus_summary.models_available == 1 and
        .consensus_summary.model_agreement_percent == 0' "$SCRATCH/result"
}

@test "#1199 repeated tertiary score streams remain one independent vote" {
    score t-opus 900
    score t-gpt 950
    consensus > "$SCRATCH/result"
    jq -e '.consensus_summary.high_consensus_count == 0 and .medium_value[0].scorers_available == 1' "$SCRATCH/result"
}

@test "#1199 scorer normalization finds scores after a prefixed JSON metadata object" {
    jq -n --arg content '{"analysis":"metadata"}
Final scores:
    ```json
    {"scores":[{"id":"IMP-1","score":900}]}
    ```' '{content:$content}' > "$SCRATCH/gpt.json"
    score opus 850
    consensus > "$SCRATCH/result"
    jq -e '.high_consensus[0].gpt_score == 900 and .high_consensus[0].opus_score == 850' "$SCRATCH/result"
}

@test "#1199 scorer normalization unwraps a JSON-encoded fenced response" {
    jq -n --arg content '"```json\n{\"scores\":[{\"id\":\"IMP-1\",\"score\":900}]}\n```"' \
        '{content:$content}' > "$SCRATCH/gpt.json"
    score opus 850
    consensus > "$SCRATCH/result"
    jq -e '.high_consensus[0].gpt_score == 900' "$SCRATCH/result"
}

@test "#1199 malformed scoring entries are unavailable rather than votes" {
    score opus 900
    score t-gpt 850
    for bad in '"900"' 1001 -1 null 3.5; do
        score gpt "$bad"
        consensus > "$SCRATCH/result"
        jq -e '.high_consensus[0].gpt_score == null and .high_consensus[0].scorers_available == 2 and .degraded == true' "$SCRATCH/result"
    done
}

@test "#1199 duplicate scoring IDs reject the response instead of selecting a vote" {
    jq -n --arg content '{"scores":[{"id":"IMP-1","score":0},{"id":"IMP-1","score":900}]}' \
        '{content:$content}' > "$SCRATCH/gpt.json"
    score opus 900
    score t-gpt 850
    consensus > "$SCRATCH/result"
    jq -e '.high_consensus[0].gpt_score == null and .degraded == true' "$SCRATCH/result"
}

@test "#1199 two observed disagreeing scorers remain disputed" {
    score opus 900
    score t-gpt 100
    consensus > "$SCRATCH/result"
    jq -e '.disputed[0] | .gpt_score == null and .delta == 800 and .average_score == 500 and .would_integrate == false' "$SCRATCH/result"
}

@test "#1199 scorer preparation preserves ordinary fences and prose prefixes" {
    for content in \
        $'```json\n{"scores":[{"id":"IMP-1","score":900}]}\n```' \
        'Final scores: {"scores":[{"id":"IMP-1","score":900}]}'; do
        jq -n --arg content "$content" '{content:$content}' > "$SCRATCH/gpt.json"
        score opus 850
        consensus > "$SCRATCH/result"
        jq -e '.high_consensus[0].gpt_score == 900' "$SCRATCH/result"
    done
}

run_scoring_main() (
    local scenario="$1"
    PROJECT_ROOT="$SCRATCH/project"
    mkdir -p "$PROJECT_ROOT/.claude"
    ln -s "$REPO/.claude/adapters" "$PROJECT_ROOT/.claude/adapters"
    printf 'fixture document\n' > "$PROJECT_ROOT/doc.md"
    LOA_FLATLINE_OUTPUT_DIR_OVERRIDE="$SCRATCH/output"
    is_flatline_enabled() { return 0; }
    get_model_primary() { echo first; }
    get_model_secondary() { echo second; }
    get_model_tertiary() { echo third; }
    is_arbiter_enabled() { return 1; }
    check_budget() { return 0; }
    degraded_verdict_maybe_emit() { :; }
    run_phase1() {
        local voice review_content
        review_content='{"improvements":[{"id":"IMP-1","description":"Check every error before publishing","priority":"HIGH"}]}'
        if [[ "$scenario" == valid_empty* ]]; then
            review_content='{"improvements":[],"no_findings_reason":"The dependencies and acceptance criteria are consistent and complete.","reviewed_sections":["Dependencies"]}'
        fi
        for voice in first second third; do
            if [[ "$scenario" == coverage_* ]]; then
                review_content=$(jq -n --arg voice "$voice" '{improvements:[
                    {id:"IMP-1",description:($voice + " requirement 1"),priority:"HIGH"},
                    {id:"IMP-2",description:($voice + " requirement 2"),priority:"HIGH"}
                ]}')
            fi
            jq -n --arg voice "$voice" --arg content "$review_content" \
                '{content:$content,verdict_quality:{status:"APPROVED",
                  consensus_outcome:"consensus",truncation_waiver_applied:false,
                  voices_planned:1,voices_succeeded:1,voices_succeeded_ids:[$voice],
                  voices_dropped:[],chain_health:"ok",confidence_floor:"high",
                  rationale:"Completed review",single_voice_call:true}}' > "$TEMP_DIR/$voice.json"
        done
        printf '%s\n' "$TEMP_DIR/first.json" "$TEMP_DIR/second.json" \
            "$SCRATCH/skeptic.json" "$SCRATCH/skeptic.json" "$TEMP_DIR/third.json" "$SCRATCH/skeptic.json"
    }
    if [[ "$scenario" == coverage_* ]]; then
        # Preserve real Phase 2 dispatch, binding and scoring. Only provider
        # calls return fixtures, with identical reviews in every coverage case.
        call_model() {
            local partial=false
            if [[ "$scenario" == coverage_partial ||
                  ( "$scenario" == coverage_one_scorer && "$1" == second ) ]]; then
                partial=true
            fi
            jq --argjson partial "$partial" '{content:({scores:[
                (if $partial then .improvements[:1] else .improvements end)[] |
                {id,score:900}
            ]} | tojson),cost_usd:0}' "$3"
        }
    else
        run_phase2() {
            local name
            for name in gpt opus tertiary; do
                if [[ "$scenario" == valid_empty* ]]; then
                    printf '%s\n' '{"improvements":[]}' > "$TEMP_DIR/$name-items.json"
                else
                    cp "$SCRATCH/temp/$name-items.json" "$TEMP_DIR/$name-items.json"
                fi
            done
            if [[ "$scenario" != valid_empty* && "$scenario" != missing_scores ]]; then
                score opus 900
                score t-gpt 850
            fi
            if [[ "$scenario" == malformed || "$scenario" == valid_empty_malformed ]]; then
                printf '{"content":"INVALID_SCORER"}\n' > "$SCRATCH/gpt.json"
            fi
            printf '%s\n' "$SCRATCH/gpt.json" "$SCRATCH/opus.json" \
                "$SCRATCH/t-opus.json" "$SCRATCH/t-gpt.json" "$SCRATCH/g-tert.json" "$SCRATCH/o-tert.json"
        }
    fi
    main --doc "$PROJECT_ROOT/doc.md" --phase beads --domain fixture \
        --run-id scoring-main --skip-knowledge --no-silent-noop-detect --json
)

@test "#1199 real main propagates a rejected scorer into canonical verdict and exit" {
    run --separate-stderr run_scoring_main malformed
    [ "$status" = 6 ]
    printf '%s\n' "$output" > "$SCRATCH/result"
    jq -e '.degraded == true and .high_consensus[0].id == "IMP-1" and
        (.verdict_quality | .status == "DEGRADED" and .scoring_degraded == true and
         .voices_planned == 3 and .voices_succeeded == 3 and .chain_health == "ok")' "$SCRATCH/result"
    jq -n -e --slurpfile result "$SCRATCH/result" \
        --slurpfile canonical "$SCRATCH/output/beads-scoring-main-final_consensus.json" \
        '$result[0].verdict_quality == $canonical[0]'
    jq -e '.status == "DEGRADED"' "$SCRATCH/output/beads-final_consensus.json"
}

@test "#1199 real main accepts qualified empty reviews and valid empty scoring responses" {
    run --separate-stderr run_scoring_main valid_empty
    [ "$status" = 0 ]
    printf '%s\n' "$output" > "$SCRATCH/result"
    jq -e '.degraded == false and .confidence == "full" and
        .consensus_summary.high_consensus_count == 0 and
        (.verdict_quality | .status == "APPROVED" and .voices_planned == 3 and .voices_succeeded == 3)' "$SCRATCH/result"
    jq -e '.status == "APPROVED"' "$SCRATCH/output/beads-scoring-main-final_consensus.json"
}

@test "#1199 empty reviews do not excuse a malformed scoring response" {
    run --separate-stderr run_scoring_main valid_empty_malformed
    [ "$status" = 6 ]
    printf '%s\n' "$output" | jq -e '.degraded == true and .verdict_quality.status == "DEGRADED"'
}

@test "#1199 empty score arrays cannot silently clear nonempty qualified findings" {
    run --separate-stderr run_scoring_main missing_scores
    [ "$status" = 6 ]
    printf '%s\n' "$output" | jq -e '.degraded == true and .verdict_quality.status == "DEGRADED"'
}

phase2_fixture() {
    local mode="$1" name id
    get_model_primary() { echo opus; }
    get_model_secondary() { echo gpt; }
    get_model_tertiary() { [[ "$mode" != triangle ]] || echo tertiary; return 0; }
    add_cost() { :; }
    call_model() {
        jq --arg mode "$mode" '{content:({scores:[.improvements[] |
            {id:(if $mode == "bare_reply" then "IMP-001" else .id end),
             description, score:900}]} | tojson),cost_usd:0}' "$3"
    }
    for name in gpt opus tertiary; do
        id=IMP-001
        [[ "$mode" != distinct || "$name" != opus ]] || id=IMP-002
        jq -n --arg id "$id" --arg description "Distinct $name requirement" \
            '{content:({improvements:[{id:$id,description:$description,priority:"HIGH"}]} | tojson)}' \
            > "$SCRATCH/$name-review.json"
    done
    local extra=() paths=()
    [[ "$mode" != triangle ]] || extra=("$SCRATCH/tertiary-review.json")
    run_phase2 "$SCRATCH/gpt-review.json" "$SCRATCH/opus-review.json" \
        sprint 20 "${extra[@]}" > "$SCRATCH/paths"
    mapfile -t paths < "$SCRATCH/paths"
    [[ "$mode" != missing_input ]] || rm "$TEMP_DIR/opus-items.json"
    run_consensus "${paths[0]}" "${paths[1]}" \
        "$SCRATCH/skeptic.json" "$SCRATCH/skeptic.json" "${paths[@]:2}"
}

@test "#1199 real Phase 2 keeps colliding reviewer-local IDs separate" {
    phase2_fixture collision > "$SCRATCH/result"
    jq -e '.high_consensus == [] and (.medium_value | length) == 2 and
        ([.medium_value[].description] | sort) == ["Distinct gpt requirement","Distinct opus requirement"] and
        ([.medium_value[].id] | unique | length) == 2 and
        all(.medium_value[]; .scorers_available == 1 and .would_integrate == false)' "$SCRATCH/result"
}

@test "#1199 real Phase 2 distinct local IDs also retain separate single votes" {
    phase2_fixture distinct > "$SCRATCH/result"
    jq -e '.high_consensus == [] and (.medium_value | length) == 2 and
        all(.medium_value[]; .scorers_available == 1 and .would_integrate == false)' "$SCRATCH/result"
}

@test "#1199 real triangular Phase 2 combines only cross-votes on the same source finding" {
    phase2_fixture triangle > "$SCRATCH/result"
    jq -e '.degraded == false and (.high_consensus | length) == 3 and
        ([.high_consensus[].id] | unique | length) == 3 and
        ([.high_consensus[].review_source] | sort) == ["gpt","opus","tertiary"] and
        all(.high_consensus[]; .original_id == "IMP-001" and .scorers_available == 2 and
            .average_score == 900 and .would_integrate == true) and
        all(.high_consensus[] | select(.review_source == "gpt"); .gpt_score == null) and
        all(.high_consensus[] | select(.review_source == "opus"); .opus_score == null) and
        all(.high_consensus[] | select(.review_source == "tertiary"); .tertiary_score == null)' "$SCRATCH/result"
}

@test "#1199 real Phase 2 rejects scorer IDs that do not match the dispatched source" {
    phase2_fixture bare_reply > "$SCRATCH/result"
    jq -e '.degraded == true and .high_consensus == [] and (.medium_value // []) == []' "$SCRATCH/result"
}

@test "#1199 multiple complete transport envelopes cannot select the first contradictory score" {
    score gpt 900
    jq -n --arg content '{"scores":[{"id":"IMP-1","score":0}]}' '{content:$content}' \
        >> "$SCRATCH/gpt.json"
    score opus 850
    consensus > "$SCRATCH/result"
    jq -e '.degraded == true and .high_consensus == [] and
        .medium_value[0].gpt_score == null and .medium_value[0].scorers_available == 1' "$SCRATCH/result"
}

@test "#1199 real Phase 2 missing explicit dispatch input rejects that scorers votes" {
    phase2_fixture missing_input > "$SCRATCH/result"
    jq -e '.degraded == true and .degraded_models == ["gpt"] and
        .high_consensus == [] and (.medium_value | length) == 1 and
        .medium_value[0].review_source == "gpt" and .medium_value[0].scorers_available == 1' "$SCRATCH/result"
}

@test "#1199 direct score helper permits an omitted binding but rejects a missing explicit one" {
    score gpt 900
    prepare_flatline_scores "$SCRATCH/gpt.json" > "$SCRATCH/result"
    jq -e '.scores[0].score == 900' "$SCRATCH/result"
    prepare_flatline_scores "$SCRATCH/gpt.json" "$SCRATCH/missing-items.json" > "$SCRATCH/result"
    jq -e '.scores == [] and .scoring_status == "unavailable"' "$SCRATCH/result"
}

@test "#1199 real main complete score coverage preserves all six findings and approval" {
    run --separate-stderr run_scoring_main coverage_complete
    [ "$status" = 0 ]
    printf '%s\n' "$output" > "$SCRATCH/result"
    jq -e '.degraded == false and (.high_consensus | length) == 6 and
        (.verdict_quality | .status == "APPROVED" and .voices_planned == 3 and .voices_succeeded == 3) and
        all(.high_consensus[]; .scorers_available == 2 and .average_score == 900)' "$SCRATCH/result"
}

@test "#1199 real main incomplete score coverage keeps observed votes and every qualified raw finding" {
    run --separate-stderr run_scoring_main coverage_partial
    [ "$status" = 6 ]
    printf '%s\n' "$output" > "$SCRATCH/result"
    jq -e '.degraded == true and .degraded_models == ["gpt","opus","tertiary"] and
        (.high_consensus | length) == 3 and
        all(.high_consensus[]; .original_id == "IMP-1" and .scorers_available == 2 and
            .average_score == 900 and .would_integrate == true) and
        ([.raw_reviews[] | .content | fromjson | .improvements[]] | length) == 6 and
        ([.raw_reviews[] | .content | fromjson | .improvements[] | select(.id == "IMP-2")] | length) == 3 and
        (.raw_reviews | keys) == ["gpt","opus","tertiary"] and
        (.verdict_quality | .status == "DEGRADED" and .scoring_degraded == true and
            .voices_planned == 3 and .voices_succeeded == 3 and .chain_health == "ok")' "$SCRATCH/result"
    jq -n -e --slurpfile result "$SCRATCH/result" \
        --slurpfile canonical "$SCRATCH/output/beads-scoring-main-final_consensus.json" \
        '$result[0].verdict_quality == $canonical[0]'
}

@test "#1199 one incomplete real scorer retains its valid votes and all qualified raw findings" {
    run --separate-stderr run_scoring_main coverage_one_scorer
    [ "$status" = 6 ]
    printf '%s\n' "$output" > "$SCRATCH/result"
    jq -e '.degraded_models == ["gpt"] and (.high_consensus | length) == 4 and
        (.medium_value | length) == 2 and
        all(.medium_value[]; .gpt_score == null and .scorers_available == 1 and .average_score == 900) and
        ([.raw_reviews[] | .content | fromjson | .improvements[]] | length) == 6 and
        .verdict_quality.status == "DEGRADED"' "$SCRATCH/result"
}
