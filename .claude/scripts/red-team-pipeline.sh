#!/usr/bin/env bash
# =============================================================================
# red-team-pipeline.sh — Red team attack generation pipeline
# =============================================================================
# Called by flatline-orchestrator.sh --mode red-team
# Handles: sanitization, attack generation, cross-validation, consensus, counter-design
#
# Exit codes: Same as flatline-orchestrator.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/bootstrap.sh"

SANITIZER="$SCRIPT_DIR/red-team-sanitizer.sh"
SCORING_ENGINE="$SCRIPT_DIR/scoring-engine.sh"
REPORT_GEN="$SCRIPT_DIR/red-team-report.sh"

# Config
CONFIG_FILE="$PROJECT_ROOT/.loa.config.yaml"
ATTACK_SURFACES="$PROJECT_ROOT/.claude/data/attack-surfaces.yaml"
ATTACK_TEMPLATE="$PROJECT_ROOT/.claude/templates/flatline-red-team.md.template"
COUNTER_TEMPLATE="$PROJECT_ROOT/.claude/templates/flatline-counter-design.md.template"
GOLDEN_SET="$PROJECT_ROOT/.claude/data/red-team-golden-set.json"

# =============================================================================
# Logging
# =============================================================================

log() {
    echo "[red-team] $*" >&2
}

error() {
    echo "[red-team] ERROR: $*" >&2
}

# =============================================================================
# Surface loading
# =============================================================================

load_surface_context() {
    local focus="$1"
    local surface="$2"
    local output_file="$3"

    if [[ ! -f "$ATTACK_SURFACES" ]]; then
        log "Warning: Attack surface registry not found, using empty context"
        echo "No attack surface registry available." > "$output_file"
        return 0
    fi

    if [[ -n "$surface" ]]; then
        # Load specific surface
        yq ".surfaces.\"$surface\"" "$ATTACK_SURFACES" > "$output_file" 2>/dev/null || {
            log "Warning: Surface '$surface' not found in registry"
            echo "Surface '$surface' not found." > "$output_file"
        }
    elif [[ -n "$focus" ]]; then
        # Load surfaces matching focus categories
        local IFS=','
        local surfaces_content=""
        for cat in $focus; do
            cat=$(echo "$cat" | tr -d ' ')
            local surface_data
            surface_data=$(yq ".surfaces.\"$cat\"" "$ATTACK_SURFACES" 2>/dev/null || echo "")
            if [[ -n "$surface_data" && "$surface_data" != "null" ]]; then
                surfaces_content="${surfaces_content}## ${cat}\n${surface_data}\n\n"
            fi
        done
        if [[ -n "$surfaces_content" ]]; then
            printf '%b' "$surfaces_content" > "$output_file"
        else
            yq '.surfaces' "$ATTACK_SURFACES" > "$output_file" 2>/dev/null || echo "" > "$output_file"
        fi
    else
        # Load all surfaces
        yq '.surfaces' "$ATTACK_SURFACES" > "$output_file" 2>/dev/null || echo "" > "$output_file"
    fi
}

# =============================================================================
# Template rendering
# =============================================================================

render_attack_template() {
    local phase="$1"
    local surface_context_file="$2"
    local knowledge_context_file="$3"
    local document_content_file="$4"
    local output_file="$5"

    local template_content
    # Use sed for safe template variable substitution
    # Avoids bash expansion issues with large content, backslashes, and template injection
    cp "$ATTACK_TEMPLATE" "$output_file"

    # Phase is short and safe for inline sed (portable: temp-file-and-mv)
    local tmpphase
    tmpphase=$(mktemp -p "$TEMP_DIR")
    sed "s|{{PHASE}}|${phase}|g" "$output_file" > "$tmpphase" && mv "$tmpphase" "$output_file"

    # For large content blocks, use file-based replacement via awk to avoid shell escaping
    local tmpwork
    tmpwork=$(mktemp -p "$TEMP_DIR")

    # Replace {{SURFACE_CONTEXT}} with file content
    awk -v marker="{{SURFACE_CONTEXT}}" -v file="$surface_context_file" '
        index($0, marker) { while ((getline line < file) > 0) print line; close(file); next }
        { print }
    ' "$output_file" > "$tmpwork" && mv "$tmpwork" "$output_file"

    # Replace {{KNOWLEDGE_CONTEXT}} with file content
    awk -v marker="{{KNOWLEDGE_CONTEXT}}" -v file="$knowledge_context_file" '
        index($0, marker) { while ((getline line < file) > 0) print line; close(file); next }
        { print }
    ' "$output_file" > "$tmpwork" && mv "$tmpwork" "$output_file"

    # Replace {{DOCUMENT_CONTENT}} with file content
    awk -v marker="{{DOCUMENT_CONTENT}}" -v file="$document_content_file" '
        index($0, marker) { while ((getline line < file) > 0) print line; close(file); next }
        { print }
    ' "$output_file" > "$tmpwork" && mv "$tmpwork" "$output_file"

    rm -f "$tmpwork"
}

render_counter_template() {
    local phase="$1"
    local attacks_json_file="$2"
    local output_file="$3"

    # Use sed/awk for safe template variable substitution (portable: temp-file-and-mv)
    cp "$COUNTER_TEMPLATE" "$output_file"
    local tmpphase2
    tmpphase2=$(mktemp -p "$TEMP_DIR")
    sed "s|{{PHASE}}|${phase}|g" "$output_file" > "$tmpphase2" && mv "$tmpphase2" "$output_file"

    # Replace {{ATTACKS_JSON}} with file content via awk
    local tmpwork
    tmpwork=$(mktemp -p "$TEMP_DIR")
    awk -v marker="{{ATTACKS_JSON}}" -v file="$attacks_json_file" '
        index($0, marker) { while ((getline line < file) > 0) print line; close(file); next }
        { print }
    ' "$output_file" > "$tmpwork" && mv "$tmpwork" "$output_file"
    rm -f "$tmpwork"
}

# =============================================================================
# Budget tracking
# =============================================================================

# Global budget state
BUDGET_LIMIT=0
BUDGET_CONSUMED=0
BUDGET_EXCEEDED=false

init_budget() {
    local execution_mode="$1"
    local budget_override="$2"

    if [[ "$budget_override" -gt 0 ]]; then
        BUDGET_LIMIT="$budget_override"
    else
        case "$execution_mode" in
            quick)    BUDGET_LIMIT=$(yq '.red_team.budgets.quick_max_tokens // 50000' "$CONFIG_FILE" 2>/dev/null || echo 50000) ;;
            standard) BUDGET_LIMIT=$(yq '.red_team.budgets.standard_max_tokens // 200000' "$CONFIG_FILE" 2>/dev/null || echo 200000) ;;
            deep)     BUDGET_LIMIT=$(yq '.red_team.budgets.deep_max_tokens // 500000' "$CONFIG_FILE" 2>/dev/null || echo 500000) ;;
            *)        BUDGET_LIMIT=200000 ;;
        esac
    fi

    BUDGET_CONSUMED=0
    BUDGET_EXCEEDED=false
    log "Budget initialized: limit=${BUDGET_LIMIT} tokens ($execution_mode mode)"
}

# Record tokens consumed by a phase. Returns 1 if budget exceeded.
record_tokens() {
    local phase_name="$1"
    local tokens="$2"

    BUDGET_CONSUMED=$((BUDGET_CONSUMED + tokens))
    log "Budget: ${phase_name} consumed ${tokens} tokens (${BUDGET_CONSUMED}/${BUDGET_LIMIT} total)"

    if [[ "$BUDGET_LIMIT" -gt 0 ]] && (( BUDGET_CONSUMED > BUDGET_LIMIT )); then
        BUDGET_EXCEEDED=true
        log "WARNING: Budget exceeded (${BUDGET_CONSUMED} > ${BUDGET_LIMIT})"
        return 1
    fi
    return 0
}

# Check if budget allows another phase
check_budget() {
    local next_phase="$1"
    if [[ "$BUDGET_EXCEEDED" == "true" ]]; then
        log "Budget exceeded — skipping ${next_phase}"
        return 1
    fi
    return 0
}

# =============================================================================
# Phase timing
# =============================================================================

# Detect nanosecond support once at load time
_HAS_NANOSECONDS=true
if [[ "$(date +%N 2>/dev/null)" == "N" ]] || [[ "$(date +%N 2>/dev/null)" == "%N" ]]; then
    _HAS_NANOSECONDS=false
fi

phase_start_time() {
    if [[ "$_HAS_NANOSECONDS" == "true" ]]; then
        date +%s%N
    else
        # Fallback: seconds × 1000000000 for consistent units
        echo "$(date +%s)000000000"
    fi
}

phase_elapsed_ms() {
    local start="$1"
    local end
    end=$(phase_start_time)
    echo $(( (end - start) / 1000000 ))
}

# =============================================================================
# Inter-model sanitization
# =============================================================================

sanitize_inter_model() {
    local input_file="$1"
    local output_file="$2"

    if [[ ! -x "$SANITIZER" ]]; then
        log "Inter-model sanitization: sanitizer not available, passing through"
        cp "$input_file" "$output_file"
        return 0
    fi

    local sanitize_exit=0
    "$SANITIZER" --input-file "$input_file" --output-file "$output_file" --inter-model 2>/dev/null || sanitize_exit=$?

    case $sanitize_exit in
        0)
            log "Inter-model sanitization: clean"
            ;;
        1)
            log "Inter-model sanitization: injection patterns detected in model output (logged, continuing)"
            # Continue with sanitized version — don't block
            ;;
        *)
            log "Inter-model sanitization: sanitizer returned $sanitize_exit, using original"
            cp "$input_file" "$output_file"
            ;;
    esac

    return 0
}

# =============================================================================
# Phase execution
# =============================================================================

run_phase0_sanitize() {
    local doc="$1"
    local output_file="$2"

    log "Phase 0: Input sanitization"

    local sanitize_exit=0
    "$SANITIZER" --input-file "$doc" --output-file "$output_file" || sanitize_exit=$?

    case $sanitize_exit in
        0)
            log "Phase 0: Input clean"
            ;;
        1)
            log "Phase 0: NEEDS_REVIEW — injection patterns suspected"
            # Continue but flag the result
            ;;
        2)
            error "Phase 0: BLOCKED — credential patterns found in document"
            return 2
            ;;
    esac

    return $sanitize_exit
}

run_phase1_attacks() {
    local prompt_file="$1"
    local execution_mode="$2"
    local timeout="$3"

    local phase_start
    phase_start=$(phase_start_time)

    log "Phase 1: Attack generation ($execution_mode mode)"

    local result_file="$TEMP_DIR/phase1-attacks.json"
    local MODEL_ADAPTER="$SCRIPT_DIR/red-team-model-adapter.sh"

    if [[ -x "$MODEL_ADAPTER" ]]; then
        # Use model adapter (mock or live)
        local attacker_output="$TEMP_DIR/phase1-attacker.json"
        "$MODEL_ADAPTER" \
            --role attacker \
            --model opus \
            --prompt-file "$prompt_file" \
            --output-file "$attacker_output" \
            --budget "$BUDGET_LIMIT" \
            --timeout "$timeout" 2>/dev/null || {
            log "Phase 1: Model adapter failed, using empty result"
            jq -n '{ attacks: [], summary: "Model adapter failed", models_used: 0, tokens_used: 0 }' > "$result_file"
            PHASE1_MS=$(phase_elapsed_ms "$phase_start")
            echo "$result_file"
            return 0
        }

        # Record tokens from adapter output
        local tokens_used
        tokens_used=$(jq '.tokens_used // 0' "$attacker_output" 2>/dev/null || echo 0)
        record_tokens "phase1" "$tokens_used" || true

        cp "$attacker_output" "$result_file"
    else
        # Placeholder: model-adapter.sh not yet available
        log "Phase 1: Model invocation (placeholder — requires model-adapter.sh)"
        jq -n '{
            attacks: [],
            summary: "Phase 1 placeholder — model invocation required",
            models_used: 0,
            tokens_used: 0
        }' > "$result_file"
    fi

    PHASE1_MS=$(phase_elapsed_ms "$phase_start")
    echo "$result_file"
}

run_phase2_validation() {
    local attacks_file="$1"
    local execution_mode="$2"
    local timeout="$3"

    local phase_start
    phase_start=$(phase_start_time)

    if [[ "$execution_mode" == "quick" ]]; then
        log "Phase 2: SKIPPED (quick mode — no cross-validation)"
        PHASE2_MS=0
        echo "$attacks_file"
        return 0
    fi

    # Budget check before expensive phase
    if ! check_budget "phase2"; then
        PHASE2_MS=0
        echo "$attacks_file"
        return 0
    fi

    log "Phase 2: Cross-validation"

    # Inter-model sanitization: sanitize Phase 1 output before feeding to Phase 2
    local sanitized_attacks="$TEMP_DIR/phase1-sanitized.json"
    sanitize_inter_model "$attacks_file" "$sanitized_attacks"

    local result_file="$TEMP_DIR/phase2-validated.json"

    local MODEL_ADAPTER="$SCRIPT_DIR/red-team-model-adapter.sh"
    if [[ -x "$MODEL_ADAPTER" ]]; then
        "$MODEL_ADAPTER" \
            --role evaluator \
            --model gpt \
            --prompt-file "$sanitized_attacks" \
            --output-file "$result_file" \
            --budget "$BUDGET_LIMIT" \
            --timeout "$timeout" 2>/dev/null || {
            log "Phase 2: Model adapter failed, using unsanitized attacks"
            cp "$sanitized_attacks" "$result_file"
        }

        local tokens_used
        tokens_used=$(jq '.tokens_used // 0' "$result_file" 2>/dev/null || echo 0)
        record_tokens "phase2" "$tokens_used" || true
    else
        log "Phase 2: Cross-validation (placeholder — requires model-adapter.sh)"
        cp "$sanitized_attacks" "$result_file"
    fi

    PHASE2_MS=$(phase_elapsed_ms "$phase_start")
    echo "$result_file"
}

run_phase3_consensus() {
    local validated_file="$1"
    local execution_mode="$2"
    local attacks_file="${3:-}"

    local phase_start
    phase_start=$(phase_start_time)

    log "Phase 3: Attack consensus classification"

    local result_file="$TEMP_DIR/phase3-consensus.json"

    if [[ "$execution_mode" == "quick" ]]; then
        # Quick mode: all findings are THEORETICAL or CREATIVE_ONLY (never CONFIRMED_ATTACK)
        jq '{
            attack_summary: {
                confirmed_count: 0,
                theoretical_count: (.attacks | length),
                creative_count: 0,
                defended_count: 0,
                total_attacks: (.attacks | length),
                human_review_required: 0
            },
            attacks: {
                confirmed: [],
                theoretical: [.attacks[]? | . + {consensus: "THEORETICAL", human_review: "not_required"}],
                creative: [],
                defended: []
            },
            validated: false,
            execution_mode: "quick"
        }' "$validated_file" > "$result_file"
    elif [[ -x "$SCORING_ENGINE" ]] && [[ -n "$attacks_file" ]] && [[ -f "$attacks_file" ]]; then
        # Standard/deep: use scoring engine for consensus classification
        # attacks_file = Phase 1 (attacker model perspective)
        # validated_file = Phase 2 (evaluator model perspective)
        log "Phase 3: Invoking scoring engine for attack consensus"
        "$SCORING_ENGINE" \
            --gpt-scores "$attacks_file" \
            --opus-scores "$validated_file" \
            --attack-mode \
            ${execution_mode:+--json} > "$result_file" 2>/dev/null || {
            log "Phase 3: Scoring engine failed, using fallback classification"
            jq '{
                attack_summary: {
                    confirmed_count: 0,
                    theoretical_count: 0,
                    creative_count: 0,
                    defended_count: 0,
                    total_attacks: (.attacks | length),
                    human_review_required: 0
                },
                attacks: { confirmed: [], theoretical: [], creative: [], defended: [] },
                validated: false,
                execution_mode: "fallback"
            }' "$validated_file" > "$result_file"
        }
    else
        # Scoring engine not available — use inline jq classification
        log "Phase 3: Scoring engine not available, using inline classification"
        jq '{
            attack_summary: {
                confirmed_count: 0,
                theoretical_count: 0,
                creative_count: 0,
                defended_count: 0,
                total_attacks: (.attacks | length),
                human_review_required: 0
            },
            attacks: { confirmed: [], theoretical: [], creative: [], defended: [] },
            validated: false,
            execution_mode: "no-scoring-engine"
        }' "$validated_file" > "$result_file"
    fi

    PHASE3_MS=$(phase_elapsed_ms "$phase_start")
    echo "$result_file"
}

run_phase4_counter_design() {
    local consensus_file="$1"
    local phase="$2"
    local execution_mode="$3"

    local phase_start
    phase_start=$(phase_start_time)

    if [[ "$execution_mode" == "quick" ]]; then
        log "Phase 4: SKIPPED (quick mode — using inline counter-designs)"
        PHASE4_MS=0
        echo "$consensus_file"
        return 0
    fi

    # Budget check before expensive phase
    if ! check_budget "phase4"; then
        PHASE4_MS=0
        jq '. + {counter_designs: [], budget_skipped: true}' "$consensus_file" > "$TEMP_DIR/phase4-result.json"
        echo "$TEMP_DIR/phase4-result.json"
        return 0
    fi

    log "Phase 4: Counter-design synthesis"

    local result_file="$TEMP_DIR/phase4-result.json"

    # Extract confirmed attacks for counter-design synthesis
    local confirmed_attacks
    confirmed_attacks=$(jq '.attacks.confirmed' "$consensus_file")

    if [[ "$confirmed_attacks" == "[]" || "$confirmed_attacks" == "null" ]]; then
        log "Phase 4: No confirmed attacks — skipping counter-design synthesis"
        jq '. + {counter_designs: []}' "$consensus_file" > "$result_file"
    else
        local MODEL_ADAPTER="$SCRIPT_DIR/red-team-model-adapter.sh"
        if [[ -x "$MODEL_ADAPTER" ]]; then
            local confirmed_file="$TEMP_DIR/confirmed-attacks.json"
            echo "$confirmed_attacks" > "$confirmed_file"

            local counter_prompt="$TEMP_DIR/counter-prompt.md"
            render_counter_template "$phase" "$confirmed_file" "$counter_prompt"

            "$MODEL_ADAPTER" \
                --role defender \
                --model opus \
                --prompt-file "$counter_prompt" \
                --output-file "$result_file" \
                --budget "$BUDGET_LIMIT" \
                --timeout 300 2>/dev/null || {
                log "Phase 4: Model adapter failed"
                jq '. + {counter_designs: []}' "$consensus_file" > "$result_file"
            }

            local tokens_used
            tokens_used=$(jq '.tokens_used // 0' "$result_file" 2>/dev/null || echo 0)
            record_tokens "phase4" "$tokens_used" || true

            # Merge counter-designs into consensus result
            local counter_designs
            counter_designs=$(jq '.counter_designs // []' "$result_file" 2>/dev/null || echo "[]")
            jq --argjson cds "$counter_designs" '. + {counter_designs: $cds}' "$consensus_file" > "$result_file"
        else
            log "Phase 4: Counter-design synthesis (placeholder — requires model-adapter.sh)"
            jq '. + {counter_designs: []}' "$consensus_file" > "$result_file"
        fi
    fi

    PHASE4_MS=$(phase_elapsed_ms "$phase_start")
    echo "$result_file"
}

# =============================================================================
# Main
# =============================================================================

main() {
    local doc=""
    local phase=""
    local context_file=""
    local execution_mode="standard"
    local depth=1
    local run_id=""
    local timeout=300
    local budget=0
    local focus=""
    local surface=""
    # json_output removed: pipeline always outputs JSON (callers expect it)

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --doc)           doc="$2"; shift 2 ;;
            --phase)         phase="$2"; shift 2 ;;
            --context-file)  context_file="$2"; shift 2 ;;
            --execution-mode) execution_mode="$2"; shift 2 ;;
            --depth)         depth="$2"; shift 2 ;;
            --run-id)        run_id="$2"; shift 2 ;;
            --timeout)       timeout="$2"; shift 2 ;;
            --budget)        budget="$2"; shift 2 ;;
            --focus)         focus="$2"; shift 2 ;;
            --surface)       surface="$2"; shift 2 ;;
            --json)          shift ;;  # Accepted for compat; pipeline always outputs JSON
            *)               error "Unknown option: $1"; exit 1 ;;
        esac
    done

    if [[ -z "$doc" || -z "$phase" ]]; then
        error "--doc and --phase are required"
        exit 1
    fi

    # Generate run_id if not provided (must start with rt- for retention compatibility)
    if [[ -z "$run_id" ]]; then
        run_id="rt-$(date +%s)-$$"
    fi

    TEMP_DIR=$(mktemp -d)
    trap 'rm -rf "$TEMP_DIR"' EXIT

    # Initialize phase timing variables
    PHASE0_MS=0
    PHASE1_MS=0
    PHASE2_MS=0
    PHASE3_MS=0
    PHASE4_MS=0

    # Initialize budget tracking
    init_budget "$execution_mode" "$budget"

    # Phase 0: Input sanitization
    local phase0_start
    phase0_start=$(phase_start_time)

    local sanitized_file="$TEMP_DIR/sanitized.md"
    local sanitize_status=0
    run_phase0_sanitize "$doc" "$sanitized_file" || sanitize_status=$?

    if [[ $sanitize_status -eq 2 ]]; then
        error "Input blocked by sanitizer"
        exit 2
    fi

    PHASE0_MS=$(phase_elapsed_ms "$phase0_start")

    # Load surface context (with graceful degradation)
    local surface_file="$TEMP_DIR/surfaces.md"
    load_surface_context "$focus" "$surface" "$surface_file"

    # Check if surface context is empty/generic — log warning for non-matching focus
    local surface_size
    surface_size=$(wc -c < "$surface_file" 2>/dev/null || echo 0)
    if [[ -n "$focus" ]] && (( surface_size < 50 )); then
        log "Warning: Focus categories '$focus' produced minimal surface context (${surface_size} bytes)"
        log "Proceeding with generic attack generation — model will infer surfaces from document content"
    fi

    # Render attack prompt
    local prompt_file="$TEMP_DIR/attack-prompt.md"
    render_attack_template "$phase" "$surface_file" "${context_file:-/dev/null}" "$sanitized_file" "$prompt_file"

    # Phase 1: Attack generation
    local attacks_file
    attacks_file=$(run_phase1_attacks "$prompt_file" "$execution_mode" "$timeout")

    # Phase 2: Cross-validation
    local validated_file
    validated_file=$(run_phase2_validation "$attacks_file" "$execution_mode" "$timeout")

    # Phase 3: Attack consensus (pass both Phase 1 and Phase 2 outputs for cross-model scoring)
    local consensus_file
    consensus_file=$(run_phase3_consensus "$validated_file" "$execution_mode" "$attacks_file")

    # Phase 4: Counter-design synthesis
    local result_file
    result_file=$(run_phase4_counter_design "$consensus_file" "$phase" "$execution_mode")

    # Calculate total latency
    local total_ms=$((PHASE0_MS + PHASE1_MS + PHASE2_MS + PHASE3_MS + PHASE4_MS))

    # Collect target surfaces for result
    local target_surfaces_json="[]"
    if [[ -n "$focus" ]]; then
        target_surfaces_json=$(printf '%s' "$focus" | tr ',' '\n' | jq -R . | jq -s .)
    elif [[ -n "$surface" ]]; then
        target_surfaces_json=$(printf '%s' "$surface" | tr ',' '\n' | jq -R . | jq -s .)
    fi

    # Build final result with metrics
    local final
    final=$(jq \
        --arg run_id "$run_id" \
        --arg phase "$phase" \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg exec_mode "$execution_mode" \
        --argjson depth "$depth" \
        --arg classification "INTERNAL" \
        --argjson sanitize_status "$sanitize_status" \
        --argjson target_surfaces "$target_surfaces_json" \
        --arg focus "${focus:-}" \
        --argjson phase0_ms "$PHASE0_MS" \
        --argjson phase1_ms "$PHASE1_MS" \
        --argjson phase2_ms "$PHASE2_MS" \
        --argjson phase3_ms "$PHASE3_MS" \
        --argjson phase4_ms "$PHASE4_MS" \
        --argjson total_ms "$total_ms" \
        --argjson budget_limit "$BUDGET_LIMIT" \
        --argjson budget_consumed "$BUDGET_CONSUMED" \
        --argjson budget_exceeded "$BUDGET_EXCEEDED" \
        '. + {
            run_id: $run_id,
            phase: $phase,
            timestamp: $timestamp,
            execution_mode: $exec_mode,
            depth: $depth,
            classification: $classification,
            target_surfaces: $target_surfaces,
            focus: $focus,
            sanitize_status: (if $sanitize_status == 0 then "clean" elif $sanitize_status == 1 then "needs_review" else "blocked" end),
            metrics: ((.metrics // {}) + {
                phase0_sanitize_ms: $phase0_ms,
                phase1_attacks_ms: $phase1_ms,
                phase2_validation_ms: $phase2_ms,
                phase3_consensus_ms: $phase3_ms,
                phase4_counter_design_ms: $phase4_ms,
                total_latency_ms: $total_ms,
                budget_limit: $budget_limit,
                budget_consumed: $budget_consumed,
                budget_exceeded: $budget_exceeded
            })
        }' "$result_file")

    # Generate report if report generator exists
    if [[ -x "$REPORT_GEN" ]]; then
        local report_dir="$PROJECT_ROOT/.run/red-team"
        mkdir -p "$report_dir"

        echo "$final" > "$report_dir/${run_id}-result.json"

        "$REPORT_GEN" \
            --input "$report_dir/${run_id}-result.json" \
            --output-dir "$report_dir" \
            --run-id "$run_id" 2>/dev/null || log "Warning: Report generation failed"
    fi

    echo "$final"
}

main "$@"
