# Local canonical scorer metadata for tests that supply score content directly.
scorer_metadata() {
    local model="$1"
    case "$model" in
        gpt|g-tert) model=gpt ;;
        opus|o-tert) model=opus ;;
        t-opus|t-gpt) model=tertiary ;;
    esac
    jq -n --arg model "$model" '{
        provider:"fixture", model:$model, requested_model:$model,
        verdict_quality:{
            status:"APPROVED", consensus_outcome:"consensus", truncation_waiver_applied:false,
            voices_planned:1, voices_succeeded:1, voices_succeeded_ids:[$model],
            voices_dropped:[], chain_health:"ok", confidence_floor:"high",
            rationale:"Local scorer fixture", single_voice_call:true
        }
    }'
}

score_response() {
    jq -n --arg content "$2" --argjson metadata "$(scorer_metadata "$1")" \
        '$metadata + {content:$content}' > "$SCRATCH/$1.json"
}
