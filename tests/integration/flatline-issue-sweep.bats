#!/usr/bin/env bats

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    SCRATCH="$(mktemp -d)"
    PROJECT_ROOT="$REPO"
    source "$REPO/.claude/scripts/flatline-orchestrator.sh"
    TEMP_DIR="$SCRATCH/temp"
    mkdir -p "$TEMP_DIR"
    LOA_FLATLINE_OUTPUT_DIR_OVERRIDE="$SCRATCH/output"
    FLATLINE_RUN_ID="run-a"
    log_trajectory() { :; }
    degraded_verdict_maybe_emit() { :; }
}

teardown() { rm -rf "$SCRATCH"; }

voice() {
    jq -n --arg voice "$2" '{content: "{\"improvements\":[],\"no_findings_reason\":\"The dependencies and acceptance criteria are consistent and complete.\",\"reviewed_sections\":[\"Dependencies\"]}",
      verdict_quality: {status:"APPROVED", consensus_outcome:"consensus", truncation_waiver_applied:false,
      voices_planned:1, voices_succeeded:1, voices_succeeded_ids:[$voice], voices_dropped:[], chain_health:"ok",
      confidence_floor:"high", rationale:"completed", single_voice_call:true}}' > "$1"
}

@test "#1229 interleaved runs cannot invalidate or consume each other's consensus" {
    voice "$SCRATCH/a.json" "a"
    voice "$SCRATCH/b.json" "b"
    aggregate_and_write_final_consensus sprint 2 "$SCRATCH/a.json" "$SCRATCH/b.json"
    local a_path="$(final_consensus_path sprint)"
    FLATLINE_RUN_ID="run-b"
    invalidate_final_consensus sprint
    [ -s "$a_path" ]
    aggregate_and_write_final_consensus sprint 3 "$SCRATCH/a.json"
    local b_path="$(final_consensus_path sprint)"
    [ "$a_path" != "$b_path" ]
    [ "$(jq -r .status "$a_path")" = APPROVED ]
    [ "$(jq -r .status "$b_path")" = DEGRADED ]
    FLATLINE_RUN_ID="run-a"
    [ "$(final_consensus_path sprint)" = "$a_path" ]
}

@test "#1230 rejected rationale and control bytes never reach Flatline logs" {
    voice "$SCRATCH/bad.json" "a"
    jq '.verdict_quality.rationale = ("PRIVATE_FIXTURE\u001b[31m" * 90)' "$SCRATCH/bad.json" > "$SCRATCH/edit"
    mv "$SCRATCH/edit" "$SCRATCH/bad.json"
    run aggregate_and_write_final_consensus sprint 2 "$SCRATCH/bad.json"
    [ "$status" -ne 0 ]
    [[ "$output" != *PRIVATE_FIXTURE* ]]
    [[ "$output" != *$'\e'* ]]
    [[ "$output" == *AGGREGATION_REJECTED* ]]
}

@test "#1166 explicit temp retention preserves diagnostic evidence" {
    printf raw-fixture > "$TEMP_DIR/review.json"
    KEEP_FLATLINE_TEMP=1
    cleanup
    [ -s "$TEMP_DIR/review.json" ]
    KEEP_FLATLINE_TEMP=0
    cleanup
    [ ! -d "$TEMP_DIR" ]
}

@test "#1199/#1095 declared model ids, aliases and custom provider pins are accepted" {
    PROJECT_ROOT="$SCRATCH/project"
    mkdir -p "$PROJECT_ROOT/.claude/defaults"
    cp "$REPO/.claude/defaults/model-config.yaml" "$PROJECT_ROOT/.claude/defaults/"
    cat > "$PROJECT_ROOT/.loa.config.yaml" <<'YAML'
hounfour:
  providers:
    ollama:
      type: openai_compat
      models:
        'glm-5.2:cloud':
          endpoint_family: chat
          auth_type: http_api
          dispatch_group: ollama-glm
    openai:
      models:
        gpt-5.6-sol:
          endpoint_family: responses
          auth_type: http_api
          dispatch_group: openai
  aliases:
    glm: 'ollama:glm-5.2:cloud'
    glm-chain: glm
    broken: 'ollama:missing-model'
    cycle-a: cycle-b
    cycle-b: cycle-a
YAML
    for model in gpt-5.6-sol openai:gpt-5.6-sol glm glm-chain ollama:glm-5.2:cloud cursor:composer-2.5; do
        run validate_model "$model" tertiary
        [ "$status" -eq 0 ]
    done
    for model in broken cycle-a ollama:missing-model nonexistent:glm; do
        run validate_model "$model" tertiary
        [ "$status" -ne 0 ]
    done
}

@test "#1240 beads loop surfaces partial findings and stops nonzero without stabilization" {
    local scripts="$SCRATCH/scripts"
    mkdir -p "$scripts" "$SCRATCH/bin"
    cp "$REPO/.claude/scripts/beads-flatline-loop.sh" "$REPO/.claude/scripts/compat-lib.sh" "$scripts/"
    cat > "$scripts/flatline-orchestrator.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' '{"raw_reviews":{"tertiary":{"content":"partial finding FIXTURE-1240"}},"verdict_quality":{"status":"DEGRADED","voices_planned":3,"voices_succeeded":1}}'
exit 6
SH
    cat > "$SCRATCH/bin/br" <<'SH'
#!/usr/bin/env bash
printf '%s\n' '[{"id":"1","title":"fixture"}]'
SH
    chmod +x "$scripts/flatline-orchestrator.sh" "$SCRATCH/bin/br"
    run env PATH="$SCRATCH/bin:$PATH" bash "$scripts/beads-flatline-loop.sh" --max-iterations 2
    [ "$status" -eq 6 ]
    [[ "$output" == *FIXTURE-1240* ]]
    [[ "$output" == *DEGRADED* ]]
    [[ "$output" != *"Ready for implementation"* ]]
    [[ "$output" != *"FLATLINE DETECTED"* ]]
    rm "$scripts/flatline-orchestrator.sh"
    run env PATH="$SCRATCH/bin:$PATH" bash "$scripts/beads-flatline-loop.sh" --max-iterations 2
    [ "$status" -eq 3 ]
    [[ "$output" != *"Ready for implementation"* ]]
}

run_partial_main() (
    PROJECT_ROOT="$SCRATCH/project"
    mkdir -p "$PROJECT_ROOT/.claude"
    ln -s "$REPO/.claude/adapters" "$PROJECT_ROOT/.claude/adapters"
    echo fixture > "$PROJECT_ROOT/doc.md"
    is_flatline_enabled() { return 0; }
    get_model_primary() { echo first; }
    get_model_secondary() { echo second; }
    get_model_tertiary() { echo third; }
    is_arbiter_enabled() { return 1; }
    check_budget() { return 0; }
    run_phase1() {
        voice "$TEMP_DIR/first.json" first
        jq '.content="unqualified prose"' "$TEMP_DIR/first.json" > "$TEMP_DIR/invalid.json"
        voice "$TEMP_DIR/third.json" third
        jq '.content="{\"improvements\":[{\"id\":\"PARTIAL-TERTIARY\",\"description\":\"Required dependency is missing\",\"priority\":\"HIGH\"}]}"' \
            "$TEMP_DIR/third.json" > "$TEMP_DIR/third-edit"
        mv "$TEMP_DIR/third-edit" "$TEMP_DIR/third.json"
        printf '%s\n' "$TEMP_DIR/invalid.json" "$TEMP_DIR/absent.json" "$TEMP_DIR/absent-skeptic.json" "$TEMP_DIR/absent-skeptic2.json" "$TEMP_DIR/third.json" "$TEMP_DIR/absent-skeptic3.json"
    }
    main --doc "$PROJECT_ROOT/doc.md" --phase beads --domain fixture --skip-knowledge --no-silent-noop-detect --json
)

@test "#1240/#1166 main retains the only qualified tertiary finding on a DEGRADED run" {
    run run_partial_main
    [ "$status" -eq 6 ]
    [[ "$output" == *PARTIAL-TERTIARY* ]]
    [[ "$output" != *'"content": "unqualified prose"'* ]]
}

wait_for_file() {
    local attempt
    for ((attempt=0; attempt<500; attempt++)); do
        [[ -e "$1" ]] && return 0
        sleep 0.01
    done
    return 1
}

@test "#1229 two processes consume their own verdict despite latest-pointer replacement" {
    voice "$SCRATCH/a.json" a
    voice "$SCRATCH/b.json" b
    (
        FLATLINE_RUN_ID=parallel-a
        aggregate_and_write_final_consensus sprint 2 "$SCRATCH/a.json" "$SCRATCH/b.json" || exit 1
        touch "$SCRATCH/a-ready"
        wait_for_file "$SCRATCH/b-ready" || exit 1
        [[ "$(jq -r .status "$(final_consensus_path sprint)")" == APPROVED ]] || exit 1
        publish_latest_consensus sprint
    ) > "$SCRATCH/a.log" 2>&1 &
    local a_pid=$!
    (
        FLATLINE_RUN_ID=parallel-b
        wait_for_file "$SCRATCH/a-ready" || exit 1
        invalidate_final_consensus sprint
        aggregate_and_write_final_consensus sprint 3 "$SCRATCH/a.json" || exit 1
        publish_latest_consensus sprint || exit 1
        touch "$SCRATCH/b-ready"
        [[ "$(jq -r .status "$(final_consensus_path sprint)")" == DEGRADED ]]
    ) > "$SCRATCH/b.log" 2>&1 &
    local b_pid=$!
    wait "$a_pid"
    wait "$b_pid"
    [ "$(jq -r .status "$LOA_FLATLINE_OUTPUT_DIR_OVERRIDE/sprint-final_consensus.json")" = APPROVED ]
    [ "$(jq -r .status "$LOA_FLATLINE_OUTPUT_DIR_OVERRIDE/sprint-parallel-b-final_consensus.json")" = DEGRADED ]
}

@test "#1025 corrupt beads JSON fails domain extraction loudly" {
    echo '{not-json' > "$SCRATCH/beads.json"
    run extract_domain "$SCRATCH/beads.json" beads
    [ "$status" -ne 0 ]
    [[ "$output" == *"domain extraction failed"* ]]
    [[ "$output" != *"task graph"* ]]
    echo '[]' > "$SCRATCH/beads.json"
    run extract_domain "$SCRATCH/beads.json" beads
    [ "$status" -eq 0 ]
    [ "$output" = "software development" ]
}

@test "#1199 configured model names and overridden aliases reach dispatch with the declared provider" {
    PROJECT_ROOT="$SCRATCH/project"
    mkdir -p "$PROJECT_ROOT/.claude/defaults"
    cp "$REPO/.claude/defaults/model-config.yaml" "$PROJECT_ROOT/.claude/defaults/"
    cat > "$PROJECT_ROOT/.loa.config.yaml" <<'YAML'
hounfour:
  providers:
    local:
      type: openai_compat
      models:
        honest-new-model:
          auth_type: http_api
          dispatch_group: local
          endpoint_family: chat
  aliases:
    opus: local:honest-new-model
YAML
    MODEL_INVOKE="$SCRATCH/invoke"
    cat > "$MODEL_INVOKE" <<SH
#!/usr/bin/env bash
printf '%s\\n' "\$@" > "$SCRATCH/dispatch-args"
printf '%s\\n' '{"content":"{}"}'
SH
    chmod +x "$MODEL_INVOKE"
    declare -A MODE_TO_AGENT=([review]=flatline-reviewer) MODEL_TO_PROVIDER_ID=([opus]=anthropic:claude-opus-4-7)
    for name in honest-new-model opus; do
        call_model "$name" review "$SCRATCH/input" prd >/dev/null
        [ "$(sed -n '/^--model$/{n;p;}' "$SCRATCH/dispatch-args")" = local:honest-new-model ]
    done
}
