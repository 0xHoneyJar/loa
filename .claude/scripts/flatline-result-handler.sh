#!/usr/bin/env bash
# =============================================================================
# flatline-result-handler.sh - Mode-aware result handler for Flatline Protocol
# =============================================================================
# Version: 1.1.0
# Part of: Autonomous Flatline Integration v1.22.0, Simstim v1.24.0
#
# Processes Flatline Protocol results based on execution mode and configuration.
# Handles HIGH_CONSENSUS, DISPUTED, BLOCKER, and LOW_VALUE items appropriately.
#
# Modes:
#   interactive - Present all findings to user
#   autonomous  - HIGH_CONSENSUS integrates, BLOCKER halts, DISPUTED logs
#   hitl        - HIGH_CONSENSUS integrates, DISPUTED/BLOCKER prompt user (no halt)
#
# Usage:
#   flatline-result-handler.sh --mode <mode> --result <json> --document <path> \
#                              --phase <type> --run-id <id> [options]
#
# Exit codes:
#   0 - Success (all actions completed)
#   1 - Blocker halt (BLOCKER item triggered halt - autonomous mode only)
#   2 - Resource not found
#   3 - Invalid arguments
#   4 - Disputed threshold exceeded (autonomous mode only)
#   5 - Integration failure
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_FILE="$PROJECT_ROOT/.loa.config.yaml"
TRAJECTORY_DIR="$PROJECT_ROOT/grimoires/loa/a2a/trajectory"
NOTES_FILE="$PROJECT_ROOT/grimoires/loa/NOTES.md"

# Component scripts
LOCK_SCRIPT="$SCRIPT_DIR/flatline-lock.sh"
SNAPSHOT_SCRIPT="$SCRIPT_DIR/flatline-snapshot.sh"
MANIFEST_SCRIPT="$SCRIPT_DIR/flatline-manifest.sh"
EDITOR_SCRIPT="$SCRIPT_DIR/flatline-editor.sh"

# =============================================================================
# Logging
# =============================================================================

log() {
    echo "[result-handler] $*" >&2
}

error() {
    echo "ERROR: $*" >&2
}

warn() {
    echo "WARNING: $*" >&2
}

# Log to trajectory
log_trajectory() {
    local event_type="$1"
    local data="$2"

    (umask 077 && mkdir -p "$TRAJECTORY_DIR")
    local date_str
    date_str=$(date +%Y-%m-%d)
    local log_file="$TRAJECTORY_DIR/flatline-result-$date_str.jsonl"

    touch "$log_file"
    chmod 600 "$log_file"

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    jq -n \
        --arg type "flatline_result_handler" \
        --arg event "$event_type" \
        --arg timestamp "$timestamp" \
        --argjson data "$data" \
        '{type: $type, event: $event, timestamp: $timestamp, data: $data}' >> "$log_file"
}

# =============================================================================
# Configuration
# =============================================================================

read_config() {
    local path="$1"
    local default="$2"
    if [[ -f "$CONFIG_FILE" ]] && command -v yq &> /dev/null; then
        local value
        value=$(yq -r "$path // \"\"" "$CONFIG_FILE" 2>/dev/null)
        if [[ -n "$value" && "$value" != "null" ]]; then
            echo "$value"
            return
        fi
    fi
    echo "$default"
}

# Global variable for current mode (set by main)
CURRENT_MODE=""

get_action() {
    local category="$1"
    # In HITL mode, use HITL-specific defaults
    if [[ "$CURRENT_MODE" == "hitl" ]]; then
        echo "$(get_hitl_action "$category")"
    else
        read_config ".autonomous_mode.actions.$category" "$(get_default_action "$category")"
    fi
}

get_default_action() {
    local category="$1"
    case "$category" in
        high_consensus) echo "integrate" ;;
        disputed) echo "log" ;;
        blocker) echo "halt" ;;
        low_value) echo "skip" ;;
        *) echo "skip" ;;
    esac
}

# HITL mode actions: HIGH_CONSENSUS integrates, DISPUTED/BLOCKER prompt user
get_hitl_action() {
    local category="$1"
    case "$category" in
        high_consensus) echo "integrate" ;;
        disputed) echo "prompt" ;;
        blocker) echo "prompt" ;;  # NOT halt - let human decide
        low_value) echo "skip" ;;
        *) echo "skip" ;;
    esac
}

get_max_disputed() {
    read_config '.autonomous_mode.max_disputed_items' '5'
}

get_disputed_scope() {
    read_config '.autonomous_mode.disputed.threshold_scope' 'per_phase'
}

get_warn_percent() {
    read_config '.autonomous_mode.disputed.warn_at_percent' '60'
}

get_critical_percent() {
    read_config '.autonomous_mode.disputed.critical_at_percent' '80'
}

# =============================================================================
# Hash Calculation
# =============================================================================

calculate_hash() {
    local file="$1"
    if [[ -f "$file" ]]; then
        sha256sum "$file" | cut -d' ' -f1
    else
        echo ""
    fi
}

# =============================================================================
# Atomic Integration
# =============================================================================

# Atomic integration sequence: lock → verify_hash → snapshot → integrate → release
integrate_item() {
    local run_id="$1"
    local document="$2"
    local item_json="$3"
    local item_id="$4"
    local expected_hash="$5"

    log "Starting atomic integration: $item_id"

    # Step 1: Acquire document lock
    if [[ -x "$LOCK_SCRIPT" ]]; then
        if ! "$LOCK_SCRIPT" acquire "$document" --type document --timeout 30 --caller "result-handler"; then
            error "Failed to acquire document lock for integration"
            return 5
        fi
        trap '"$LOCK_SCRIPT" release "$document" --type document 2>/dev/null || true' RETURN
    fi

    # Step 2: Verify hash (document hasn't changed since review)
    local current_hash
    current_hash=$(calculate_hash "$PROJECT_ROOT/$document")

    if [[ -n "$expected_hash" && "$current_hash" != "$expected_hash" ]]; then
        warn "Hash mismatch for $document - document modified during review"
        warn "Expected: $expected_hash"
        warn "Current:  $current_hash"
        log_trajectory "hash_mismatch" "{\"item_id\": \"$item_id\", \"document\": \"$document\", \"expected\": \"$expected_hash\", \"current\": \"$current_hash\"}"
        # Skip this integration but don't fail the entire run
        return 0
    fi

    # Step 3: Create snapshot
    local snapshot_result
    snapshot_result=$("$SNAPSHOT_SCRIPT" create "$PROJECT_ROOT/$document" --run-id "$run_id" --integration-id "$item_id" 2>/dev/null) || {
        warn "Snapshot creation failed, proceeding without snapshot"
        snapshot_result="{}"
    }

    local snapshot_id
    snapshot_id=$(echo "$snapshot_result" | jq -r '.snapshot_id // ""')

    # Step 4: Perform integration (apply change to document)
    local change_type
    change_type=$(echo "$item_json" | jq -r '.change_type // "append"')

    local content
    content=$(echo "$item_json" | jq -r '.content // .suggestion // .text // ""')

    local section
    section=$(echo "$item_json" | jq -r '.section // ""')

    if [[ -z "$content" ]]; then
        warn "No content to integrate for item: $item_id"
        return 0
    fi

    # Apply change using editor
    if [[ -x "$EDITOR_SCRIPT" ]]; then
        case "$change_type" in
            append)
                "$EDITOR_SCRIPT" append_section "$PROJECT_ROOT/$document" "$section" "$content"
                ;;
            update)
                "$EDITOR_SCRIPT" update_section "$PROJECT_ROOT/$document" "$section" "$content"
                ;;
            insert)
                "$EDITOR_SCRIPT" insert_after "$PROJECT_ROOT/$document" "$section" "$content"
                ;;
            *)
                # Default: append to end
                "$EDITOR_SCRIPT" append_section "$PROJECT_ROOT/$document" "" "$content"
                ;;
        esac
    else
        # Fallback: simple append
        echo "" >> "$PROJECT_ROOT/$document"
        echo "<!-- Auto-integrated by Flatline: $item_id -->" >> "$PROJECT_ROOT/$document"
        echo "$content" >> "$PROJECT_ROOT/$document"
    fi

    # Step 5: Record integration in manifest
    local new_hash
    new_hash=$(calculate_hash "$PROJECT_ROOT/$document")

    "$MANIFEST_SCRIPT" add-integration "$run_id" \
        --type "high_consensus" \
        --item-id "$item_id" \
        --snapshot-id "$snapshot_id" \
        --document-hash "$new_hash" 2>/dev/null || true

    log "Integration complete: $item_id"
    log_trajectory "integration_complete" "{\"item_id\": \"$item_id\", \"snapshot_id\": \"$snapshot_id\", \"new_hash\": \"$new_hash\"}"

    # Lock released by trap
    return 0
}

# =============================================================================
# Item Processing
# =============================================================================

process_high_consensus() {
    local run_id="$1"
    local document="$2"
    local items_json="$3"
    local expected_hash="$4"

    local action
    action=$(get_action "high_consensus")

    local count=0
    local integrated=0
    local skipped=0

    log "Processing HIGH_CONSENSUS items (action: $action)"

    # Safe iteration: jq -c | while IFS= read -r
    echo "$items_json" | jq -c '.[]' 2>/dev/null | while IFS= read -r item; do
        ((count++)) || true

        # Validate item is valid JSON
        if ! echo "$item" | jq '.' >/dev/null 2>&1; then
            warn "Invalid JSON item, skipping"
            ((skipped++)) || true
            continue
        fi

        local item_id
        item_id=$(echo "$item" | jq -r '.id // .item_id // "IMP-'"$count"'"')

        case "$action" in
            integrate)
                if integrate_item "$run_id" "$document" "$item" "$item_id" "$expected_hash"; then
                    ((integrated++)) || true
                else
                    ((skipped++)) || true
                fi
                ;;
            log)
                log "HIGH_CONSENSUS (logged): $item_id"
                log_trajectory "high_consensus_logged" "$item"
                ;;
            skip)
                log "HIGH_CONSENSUS (skipped): $item_id"
                ;;
        esac
    done

    log "HIGH_CONSENSUS: $count total, $integrated integrated, $skipped skipped"
    echo "$integrated"
}

process_disputed() {
    local run_id="$1"
    local document="$2"
    local items_json="$3"
    local phase="$4"

    local action
    action=$(get_action "disputed")

    local max_disputed
    max_disputed=$(get_max_disputed)

    local warn_percent
    warn_percent=$(get_warn_percent)

    local critical_percent
    critical_percent=$(get_critical_percent)

    local count=0

    log "Processing DISPUTED items (action: $action, threshold: $max_disputed)"

    # Count current disputed items (for threshold check)
    local current_disputed=0

    # Safe iteration: jq -c | while IFS= read -r
    echo "$items_json" | jq -c '.[]' 2>/dev/null | while IFS= read -r item; do
        ((count++)) || true
        ((current_disputed++)) || true

        local item_id
        item_id=$(echo "$item" | jq -r '.id // .item_id // "DISP-'"$count"'"')

        # Progressive warnings
        local threshold_percent=$((current_disputed * 100 / max_disputed))

        if [[ $threshold_percent -ge $critical_percent ]]; then
            warn "CRITICAL: Approaching disputed limit ($current_disputed/$max_disputed)"
        elif [[ $threshold_percent -ge $warn_percent ]]; then
            warn "Warning: $current_disputed disputed items logged ($threshold_percent% of threshold)"
        fi

        case "$action" in
            halt)
                error "DISPUTED item triggered halt: $item_id"
                "$MANIFEST_SCRIPT" add-disputed "$run_id" --item "$item" 2>/dev/null || true
                return 4
                ;;
            prompt)
                # HITL mode: collect for Claude to present to user
                log "DISPUTED (prompt): $item_id"
                "$MANIFEST_SCRIPT" add-disputed "$run_id" --item "$item" 2>/dev/null || true
                log_trajectory "disputed_prompt" "$item"
                # Item will be returned in JSON response for Claude to present
                ;;
            log)
                log "DISPUTED (logged): $item_id"
                "$MANIFEST_SCRIPT" add-disputed "$run_id" --item "$item" 2>/dev/null || true
                log_trajectory "disputed_logged" "$item"

                # Also log to NOTES.md
                append_to_notes "## Flatline Disputed Items - $phase" "- **$item_id**: $(echo "$item" | jq -r '.description // .text // ""' | head -c 200)"
                ;;
            skip)
                log "DISPUTED (skipped): $item_id"
                ;;
        esac

        # Check threshold
        if [[ $current_disputed -ge $max_disputed ]]; then
            error "Disputed threshold exceeded ($current_disputed >= $max_disputed)"
            return 4
        fi
    done

    log "DISPUTED: $count total"
    echo "$count"
}

process_blockers() {
    local run_id="$1"
    local document="$2"
    local items_json="$3"
    local phase="$4"

    local action
    action=$(get_action "blocker")

    local count=0

    log "Processing BLOCKER items (action: $action)"

    # L-5 FIX: Use process substitution instead of pipeline to preserve return values
    local should_halt=false
    while IFS= read -r item; do
        [[ -z "$item" ]] && continue
        ((count++)) || true

        local item_id
        item_id=$(echo "$item" | jq -r '.id // .item_id // "BLK-'"$count"'"')

        local severity
        severity=$(echo "$item" | jq -r '.severity // "high"')

        case "$action" in
            halt)
                error "BLOCKER triggered halt: $item_id (severity: $severity)"
                "$MANIFEST_SCRIPT" add-blocker "$run_id" --item "$item" 2>/dev/null || true
                log_trajectory "blocker_halt" "$item"
                should_halt=true
                break
                ;;
            prompt)
                # HITL mode: present to user for decision (do NOT halt)
                warn "BLOCKER (prompt): $item_id (severity: $severity)"
                "$MANIFEST_SCRIPT" add-blocker "$run_id" --item "$item" 2>/dev/null || true
                log_trajectory "blocker_prompt" "$item"
                # Item will be returned in JSON response for Claude to present
                # User decides: Override (with rationale) / Reject / Defer
                ;;
            log)
                warn "BLOCKER (logged): $item_id (severity: $severity)"
                "$MANIFEST_SCRIPT" add-blocker "$run_id" --item "$item" 2>/dev/null || true
                log_trajectory "blocker_logged" "$item"
                ;;
            continue)
                warn "BLOCKER (continuing): $item_id (severity: $severity)"
                log_trajectory "blocker_continued" "$item"
                ;;
        esac
    done < <(echo "$items_json" | jq -c '.[]' 2>/dev/null)

    log "BLOCKER: $count total"
    echo "$count"

    # Return 1 if halt was triggered
    if [[ "$should_halt" == "true" ]]; then
        return 1
    fi
}

process_low_value() {
    local items_json="$1"

    local action
    action=$(get_action "low_value")

    local count=0

    # Safe iteration
    echo "$items_json" | jq -c '.[]' 2>/dev/null | while IFS= read -r item; do
        ((count++)) || true

        case "$action" in
            log)
                log_trajectory "low_value_logged" "$item"
                ;;
            skip)
                # Silently skip
                ;;
        esac
    done

    log "LOW_VALUE: $count discarded"
}

# =============================================================================
# HITL Mode Handler
# =============================================================================

# Handle results in HITL mode:
# - HIGH_CONSENSUS: auto-integrate (no user prompt)
# - DISPUTED: return for user decision
# - BLOCKER: return for user decision (NOT halt)
# - LOW_VALUE: skip silently
handle_hitl_results() {
    local run_id="$1"
    local document="$2"
    local phase="$3"
    local doc_hash="$4"
    local high_consensus="$5"
    local disputed="$6"
    local blockers="$7"
    local low_value="$8"
    local total_high="$9"
    local total_disputed="${10}"
    local total_blockers="${11}"

    local integrated=0
    local items_for_user=()

    # Auto-integrate HIGH_CONSENSUS items
    if [[ $total_high -gt 0 ]]; then
        log "HITL: Auto-integrating $total_high HIGH_CONSENSUS items"
        integrated=$(process_high_consensus "$run_id" "$document" "$high_consensus" "$doc_hash")
    fi

    # Skip LOW_VALUE silently
    process_low_value "$low_value"

    # Build response with items for user decision
    local disputed_items="[]"
    local blocker_items="[]"

    if [[ $total_disputed -gt 0 ]]; then
        # Format disputed items for user presentation
        disputed_items=$(echo "$disputed" | jq '[.[] | {
            id: (.id // .item_id // "DISP-\(.)"),
            type: "DISPUTED",
            suggestion: (.suggestion // .text // .description // ""),
            scores: {
                gpt: (.gpt_score // .score_gpt // 0),
                opus: (.opus_score // .score_opus // 0)
            },
            delta: ((.gpt_score // .score_gpt // 0) - (.opus_score // .score_opus // 0) | if . < 0 then . * -1 else . end)
        }]')
    fi

    if [[ $total_blockers -gt 0 ]]; then
        # Format blocker items for user presentation
        blocker_items=$(echo "$blockers" | jq '[.[] | {
            id: (.id // .item_id // "BLK-\(.)"),
            type: "BLOCKER",
            concern: (.concern // .text // .description // ""),
            severity: (.severity // .skeptic_score // 0),
            requires_rationale: true
        }]')
    fi

    # Log HITL processing
    log_trajectory "hitl_processing" "{\"integrated\": $integrated, \"disputed\": $total_disputed, \"blockers\": $total_blockers}"

    # Update manifest
    "$MANIFEST_SCRIPT" update "$run_id" --field status --value "hitl_pending" 2>/dev/null || true

    # Return structured JSON for Claude to present to user
    jq -n \
        --arg run_id "$run_id" \
        --arg phase "$phase" \
        --arg document "$document" \
        --argjson integrated "$integrated" \
        --argjson disputed_count "$total_disputed" \
        --argjson blocker_count "$total_blockers" \
        --argjson disputed_items "$disputed_items" \
        --argjson blocker_items "$blocker_items" \
        '{
            status: "hitl_pending",
            mode: "hitl",
            run_id: $run_id,
            phase: $phase,
            document: $document,
            auto_integrated: {
                count: $integrated,
                message: "HIGH_CONSENSUS items auto-integrated"
            },
            requires_decision: {
                disputed: $disputed_items,
                blockers: $blocker_items
            },
            summary: {
                integrated: $integrated,
                disputed: $disputed_count,
                blockers: $blocker_count
            },
            instructions: {
                disputed: "For each DISPUTED item: [A]ccept / [R]eject / [S]kip",
                blocker: "For each BLOCKER: [O]verride (requires rationale) / [R]eject / [D]efer"
            }
        }'

    return 0
}

# =============================================================================
# NOTES.md Append
# =============================================================================

append_to_notes() {
    local section="$1"
    local content="$2"

    if [[ ! -f "$NOTES_FILE" ]]; then
        return 0
    fi

    # Check if section exists
    if grep -q "^$section" "$NOTES_FILE" 2>/dev/null; then
        # Append under existing section
        local temp_file
        temp_file=$(mktemp)
        awk -v section="$section" -v content="$content" '
            $0 == section { print; print content; next }
            { print }
        ' "$NOTES_FILE" > "$temp_file"
        mv "$temp_file" "$NOTES_FILE"
    else
        # Add new section at end
        echo "" >> "$NOTES_FILE"
        echo "$section" >> "$NOTES_FILE"
        echo "" >> "$NOTES_FILE"
        echo "$content" >> "$NOTES_FILE"
    fi
}

# =============================================================================
# Extension Point Hooks (v1.23.0 - Flatline-Enhanced Compound Learning)
# =============================================================================

# Run hooks after result handling completes
# Supports function-level hooks for learning extraction (SKP-004)
run_hooks_flatline_result_complete() {
    local run_id="$1"
    local document="$2"
    local result_json="$3"
    local phase="$4"

    log "Running post-result hooks..."

    # Hook 1: Learning extraction (if enabled)
    hook_learning_extraction "$run_id" "$document" "$result_json" "$phase"
}

# Hook: Extract learnings from HIGH_CONSENSUS items
hook_learning_extraction() {
    local run_id="$1"
    local document="$2"
    local result_json="$3"
    local phase="$4"

    # Check if flatline integration is enabled
    local integration_enabled
    integration_enabled=$(read_config '.compound_learning.flatline_integration.enabled' 'false')

    if [[ "$integration_enabled" != "true" ]]; then
        log "Learning extraction skipped (flatline_integration.enabled=false)"
        return 0
    fi

    # Check if extractor script exists
    local extractor_script="$SCRIPT_DIR/flatline-learning-extractor.sh"
    if [[ ! -x "$extractor_script" ]]; then
        log "Learning extraction skipped (extractor not found)"
        return 0
    fi

    log_trajectory "learning_extraction_triggered" "{\"run_id\": \"$run_id\", \"phase\": \"$phase\"}"

    # Output file for extracted learnings
    local output_file="$PROJECT_ROOT/grimoires/loa/a2a/compound/flatline-learnings.jsonl"
    local lock_file="${output_file}.lock"

    # Atomic write with file locking (SKP-007)
    local temp_file
    temp_file=$(mktemp)

    # Run extraction
    if "$extractor_script" --result "$result_json" --output jsonl > "$temp_file" 2>/dev/null; then
        local count
        count=$(wc -l < "$temp_file" | tr -d ' ')

        if [[ "$count" -gt 0 ]]; then
            # Acquire exclusive lock and append
            (
                flock -x -w 10 200 || { log_error "Failed to acquire lock for learning output"; rm -f "$temp_file"; return 1; }

                # Ensure directory exists
                mkdir -p "$(dirname "$output_file")"

                # Append to JSONL file
                cat "$temp_file" >> "$output_file"

                # fsync for durability
                sync

            ) 200>"$lock_file"

            log "Extracted $count learning candidates from Flatline result"
            log_trajectory "learning_extraction_complete" "{\"count\": $count, \"output_file\": \"$output_file\"}"
        else
            log "No learning candidates extracted from Flatline result"
        fi
    else
        log_warning "Learning extraction failed"
        log_trajectory "learning_extraction_failed" "{\"run_id\": \"$run_id\"}"
    fi

    rm -f "$temp_file"
}

# =============================================================================
# Main Handler
# =============================================================================

handle_results() {
    local mode="$1"
    local result_json="$2"
    local document="$3"
    local phase="$4"
    local run_id="$5"

    log "Handling results for $document (mode: $mode, phase: $phase)"

    # Validate result JSON
    if ! echo "$result_json" | jq '.' >/dev/null 2>&1; then
        error "Invalid result JSON"
        return 3
    fi

    # Get document hash at start
    local doc_hash
    doc_hash=$(calculate_hash "$PROJECT_ROOT/$document")

    # Extract item arrays
    local high_consensus disputed blockers low_value

    high_consensus=$(echo "$result_json" | jq '.high_consensus // []')
    disputed=$(echo "$result_json" | jq '.disputed // []')
    blockers=$(echo "$result_json" | jq '.blockers // []')
    low_value=$(echo "$result_json" | jq '.low_value // []')

    local total_high total_disputed total_blockers
    total_high=$(echo "$high_consensus" | jq 'length')
    total_disputed=$(echo "$disputed" | jq 'length')
    total_blockers=$(echo "$blockers" | jq 'length')

    log "Items: HIGH=$total_high, DISPUTED=$total_disputed, BLOCKER=$total_blockers"

    # Interactive mode: just report all findings
    if [[ "$mode" == "interactive" ]]; then
        log "Interactive mode - presenting results for user review"
        echo "$result_json"
        return 0
    fi

    # HITL mode: auto-integrate HIGH_CONSENSUS, return DISPUTED/BLOCKER for user decision
    if [[ "$mode" == "hitl" ]]; then
        log "HITL mode - auto-integrating HIGH_CONSENSUS, collecting DISPUTED/BLOCKER for user"
        handle_hitl_results "$run_id" "$document" "$phase" "$doc_hash" \
            "$high_consensus" "$disputed" "$blockers" "$low_value" \
            "$total_high" "$total_disputed" "$total_blockers"
        return $?
    fi

    # Autonomous mode: process based on actions

    # Process BLOCKERS first (may halt)
    if [[ $total_blockers -gt 0 ]]; then
        if ! process_blockers "$run_id" "$document" "$blockers" "$phase"; then
            return 1  # Blocker halt
        fi
    fi

    # Process HIGH_CONSENSUS (may integrate)
    local integrated=0
    if [[ $total_high -gt 0 ]]; then
        integrated=$(process_high_consensus "$run_id" "$document" "$high_consensus" "$doc_hash")
    fi

    # Process DISPUTED (may hit threshold)
    local disputed_count=0
    if [[ $total_disputed -gt 0 ]]; then
        disputed_count=$(process_disputed "$run_id" "$document" "$disputed" "$phase")
        local disputed_exit=$?
        if [[ $disputed_exit -eq 4 ]]; then
            return 4  # Disputed threshold exceeded
        fi
    fi

    # Process LOW_VALUE (just log/skip)
    process_low_value "$low_value"

    # Update manifest with final status
    "$MANIFEST_SCRIPT" update "$run_id" --field status --value "completed" 2>/dev/null || true

    log "Result handling complete: $integrated integrated, $disputed_count disputed"
    log_trajectory "handling_complete" "{\"integrated\": $integrated, \"disputed\": $disputed_count, \"blockers\": $total_blockers}"

    # Run extension hooks (v1.23.0)
    run_hooks_flatline_result_complete "$run_id" "$document" "$result_json" "$phase"

    # Return summary
    jq -n \
        --arg run_id "$run_id" \
        --arg phase "$phase" \
        --arg document "$document" \
        --argjson integrated "$integrated" \
        --argjson disputed "$disputed_count" \
        --argjson blockers "$total_blockers" \
        '{
            status: "completed",
            run_id: $run_id,
            phase: $phase,
            document: $document,
            metrics: {
                integrated: $integrated,
                disputed: $disputed,
                blockers: $blockers
            }
        }'

    return 0
}

# =============================================================================
# Main
# =============================================================================

usage() {
    cat <<EOF
Usage: flatline-result-handler.sh [options]

Options:
  --mode <mode>            Execution mode: interactive, autonomous, hitl (required)
  --result <json>          Flatline result JSON or path to JSON file (required)
  --document <path>        Document that was reviewed (required)
  --phase <type>           Phase: prd, sdd, sprint (required)
  --run-id <id>            Run ID for manifest tracking (required for autonomous/hitl)

Modes:
  interactive   Present all findings to user
  autonomous    HIGH_CONSENSUS integrates, BLOCKER halts, DISPUTED logs
  hitl          HIGH_CONSENSUS integrates, DISPUTED/BLOCKER prompt user (no halt)

Exit codes:
  0 - Success
  1 - Blocker halt (autonomous mode only)
  2 - Resource not found
  3 - Invalid arguments
  4 - Disputed threshold exceeded (autonomous mode only)
  5 - Integration failure

Examples:
  # Autonomous mode
  flatline-result-handler.sh --mode autonomous --result result.json \\
      --document grimoires/loa/prd.md --phase prd --run-id flatline-run-abc123

  # HITL mode (for /simstim)
  flatline-result-handler.sh --mode hitl --result result.json \\
      --document grimoires/loa/prd.md --phase prd --run-id simstim-run-abc123
EOF
}

main() {
    local mode=""
    local result=""
    local document=""
    local phase=""
    local run_id=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --mode)
                mode="$2"
                shift 2
                ;;
            --result)
                result="$2"
                shift 2
                ;;
            --document)
                document="$2"
                shift 2
                ;;
            --phase)
                phase="$2"
                shift 2
                ;;
            --run-id)
                run_id="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                exit 3
                ;;
        esac
    done

    # Validate required arguments
    if [[ -z "$mode" ]]; then
        error "--mode required"
        exit 3
    fi

    if [[ -z "$result" ]]; then
        error "--result required"
        exit 3
    fi

    if [[ -z "$document" ]]; then
        error "--document required"
        exit 3
    fi

    if [[ -z "$phase" ]]; then
        error "--phase required"
        exit 3
    fi

    if [[ "$mode" == "autonomous" && -z "$run_id" ]]; then
        error "--run-id required for autonomous mode"
        exit 3
    fi

    if [[ "$mode" == "hitl" && -z "$run_id" ]]; then
        error "--run-id required for hitl mode"
        exit 3
    fi

    # Set global mode for get_action() to use
    CURRENT_MODE="$mode"

    # Load result JSON
    local result_json
    if [[ -f "$result" ]]; then
        result_json=$(cat "$result")
    else
        result_json="$result"
    fi

    # Handle results
    handle_results "$mode" "$result_json" "$document" "$phase" "$run_id"
}

main "$@"
