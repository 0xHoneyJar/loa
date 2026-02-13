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

    # Phase is short and safe for inline sed
    sed -i "s|{{PHASE}}|${phase}|g" "$output_file"

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

    # Use sed/awk for safe template variable substitution
    cp "$COUNTER_TEMPLATE" "$output_file"
    sed -i "s|{{PHASE}}|${phase}|g" "$output_file"

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

    log "Phase 1: Attack generation ($execution_mode mode)"

    # In quick mode, only 2 calls (1 attacker + 1 defender)
    # In standard/deep, 4 calls (2 attackers + 2 defenders)
    # For now, simulate with placeholder output since we can't make real API calls
    # The actual model invocation would use model-adapter.sh

    local result_file="$TEMP_DIR/phase1-attacks.json"

    # Placeholder: In production, this calls model-adapter.sh for each model
    # For quick mode: 1 attacker call → 1 output
    # For standard: 2 attacker calls → merged output
    log "Phase 1: Model invocation (placeholder — requires model-adapter.sh integration)"

    # Create empty structure for downstream phases
    jq -n '{
        attacks: [],
        summary: "Phase 1 placeholder — model invocation required",
        models_used: 0
    }' > "$result_file"

    echo "$result_file"
}

run_phase2_validation() {
    local attacks_file="$1"
    local execution_mode="$2"
    local timeout="$3"

    if [[ "$execution_mode" == "quick" ]]; then
        log "Phase 2: SKIPPED (quick mode — no cross-validation)"
        # In quick mode, use attacker self-scores directly
        echo "$attacks_file"
        return 0
    fi

    log "Phase 2: Cross-validation"

    local result_file="$TEMP_DIR/phase2-validated.json"

    # Placeholder: In production, this invokes scoring-engine.sh --attack-mode
    log "Phase 2: Cross-validation (placeholder — requires scoring-engine.sh --attack-mode)"

    cp "$attacks_file" "$result_file"
    echo "$result_file"
}

run_phase3_consensus() {
    local validated_file="$1"
    local execution_mode="$2"

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
    else
        # Standard/deep: use scoring engine classification
        # In production, this calls scoring-engine.sh --attack-mode
        jq '{
            attack_summary: {
                confirmed_count: 0,
                theoretical_count: 0,
                creative_count: 0,
                defended_count: 0,
                total_attacks: (.attacks | length),
                human_review_required: 0
            },
            attacks: {
                confirmed: [],
                theoretical: [],
                creative: [],
                defended: []
            },
            validated: true,
            execution_mode: "standard"
        }' "$validated_file" > "$result_file"
    fi

    echo "$result_file"
}

run_phase4_counter_design() {
    local consensus_file="$1"
    local phase="$2"
    local execution_mode="$3"

    if [[ "$execution_mode" == "quick" ]]; then
        log "Phase 4: SKIPPED (quick mode — using inline counter-designs)"
        echo "$consensus_file"
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
        # Placeholder: In production, render counter-design template and invoke models
        log "Phase 4: Counter-design synthesis (placeholder — requires model invocation)"
        jq '. + {counter_designs: []}' "$consensus_file" > "$result_file"
    fi

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
    local budget=200000
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

    # Phase 0: Input sanitization
    local sanitized_file="$TEMP_DIR/sanitized.md"
    local sanitize_status=0
    run_phase0_sanitize "$doc" "$sanitized_file" || sanitize_status=$?

    if [[ $sanitize_status -eq 2 ]]; then
        error "Input blocked by sanitizer"
        exit 2
    fi

    # Load surface context
    local surface_file="$TEMP_DIR/surfaces.md"
    load_surface_context "$focus" "$surface" "$surface_file"

    # Render attack prompt
    local prompt_file="$TEMP_DIR/attack-prompt.md"
    render_attack_template "$phase" "$surface_file" "${context_file:-/dev/null}" "$sanitized_file" "$prompt_file"

    # Phase 1: Attack generation
    local attacks_file
    attacks_file=$(run_phase1_attacks "$prompt_file" "$execution_mode" "$timeout")

    # Phase 2: Cross-validation
    local validated_file
    validated_file=$(run_phase2_validation "$attacks_file" "$execution_mode" "$timeout")

    # Phase 3: Attack consensus
    local consensus_file
    consensus_file=$(run_phase3_consensus "$validated_file" "$execution_mode")

    # Phase 4: Counter-design synthesis
    local result_file
    result_file=$(run_phase4_counter_design "$consensus_file" "$phase" "$execution_mode")

    # Collect target surfaces for result
    local target_surfaces_json="[]"
    if [[ -n "$focus" ]]; then
        target_surfaces_json=$(printf '%s' "$focus" | tr ',' '\n' | jq -R . | jq -s .)
    elif [[ -n "$surface" ]]; then
        target_surfaces_json=$(printf '%s' "$surface" | tr ',' '\n' | jq -R . | jq -s .)
    fi

    # Build final result
    local final
    final=$(jq \
        --arg run_id "$run_id" \
        --arg exec_mode "$execution_mode" \
        --argjson depth "$depth" \
        --arg classification "INTERNAL" \
        --argjson sanitize_status "$sanitize_status" \
        --argjson target_surfaces "$target_surfaces_json" \
        --arg focus "${focus:-}" \
        '. + {
            run_id: $run_id,
            execution_mode: $exec_mode,
            depth: $depth,
            classification: $classification,
            target_surfaces: $target_surfaces,
            focus: $focus,
            sanitize_status: (if $sanitize_status == 0 then "clean" elif $sanitize_status == 1 then "needs_review" else "blocked" end)
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
