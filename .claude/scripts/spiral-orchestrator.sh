#!/usr/bin/env bash
# =============================================================================
# spiral-orchestrator.sh - /spiral meta-orchestrator (cycle-066)
# =============================================================================
# Version: 0.1.0 (MVP scaffolding)
# Part of: RFC-060 #483 autopoietic spiral
# Depends on: cycle-063 state coalescer, cycle-064 per-cycle workspace
#
# Usage:
#   spiral-orchestrator.sh --start [--max-cycles N] [--budget-cents N] [--dry-run]
#   spiral-orchestrator.sh --status [--json]
#   spiral-orchestrator.sh --halt [--reason TEXT]
#   spiral-orchestrator.sh --resume
#   spiral-orchestrator.sh --check-stop      Evaluate stopping conditions only
#
# State machine:
#   INIT -> RUNNING -> (COMPLETED | HALTED | FAILED)
#
# Phase within a cycle:
#   SEED -> SIMSTIM -> HARVEST -> EVALUATE
#
# Exit codes:
#   0 - Success
#   1 - Validation error
#   2 - Feature disabled in config
#   3 - State conflict (run in progress)
#   4 - Stopping condition triggered
#   5 - HITL halt requested
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/bootstrap.sh"

STATE_FILE="$PROJECT_ROOT/.run/spiral-state.json"
HALT_SENTINEL="$PROJECT_ROOT/.run/spiral-halt"
TRAJECTORY_DIR=$(get_trajectory_dir)
_GRIMOIRE_DIR=$(get_grimoire_dir)

# Hardcoded safety floors (RFC-060 AD-4) — cannot be overridden by config.
MAX_CYCLES_FLOOR=50
MAX_COST_CENTS_FLOOR=10000       # $100
MAX_WALL_CLOCK_SECONDS_FLOOR=86400  # 24h

log() {
    echo "[spiral] $*" >&2
}

error() {
    echo "ERROR: $*" >&2
}

# =============================================================================
# Config read helpers
# =============================================================================

read_config() {
    local key="$1"
    local default="$2"
    local config="$PROJECT_ROOT/.loa.config.yaml"
    [[ ! -f "$config" ]] && { echo "$default"; return 0; }
    local value
    value=$(yq eval ".$key // null" "$config" 2>/dev/null || echo "null")
    if [[ "$value" == "null" || -z "$value" ]]; then
        echo "$default"
    else
        echo "$value"
    fi
}

is_enabled() {
    local enabled
    enabled=$(read_config "spiral.enabled" "false")
    [[ "$enabled" == "true" ]]
}

# =============================================================================
# Safety-floor clamping
# =============================================================================

clamp_to_floor() {
    local value="$1"
    local floor="$2"
    if [[ "$value" -gt "$floor" ]]; then
        log "Value $value exceeds safety floor $floor — clamping"
        echo "$floor"
    else
        echo "$value"
    fi
}

# =============================================================================
# State management
# =============================================================================

generate_spiral_id() {
    local date_part
    date_part=$(date -u +%Y%m%d)
    local rand_part
    rand_part=$(head -c 3 /dev/urandom | od -An -tx1 | tr -d ' \n')
    echo "spiral-${date_part}-${rand_part}"
}

init_state() {
    local max_cycles="$1"
    local budget_cents="$2"
    local wall_clock_seconds="$3"
    local flatline_min="$4"
    local flatline_consec="$5"

    mkdir -p "$(dirname "$STATE_FILE")"

    local spiral_id
    spiral_id=$(generate_spiral_id)
    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    jq -n \
        --arg id "$spiral_id" \
        --arg ts "$timestamp" \
        --argjson max_cycles "$max_cycles" \
        --argjson budget_cents "$budget_cents" \
        --argjson wall_clock_seconds "$wall_clock_seconds" \
        --argjson flatline_min "$flatline_min" \
        --argjson flatline_consec "$flatline_consec" \
        '{
            schema_version: 1,
            spiral_id: $id,
            state: "RUNNING",
            phase: "SEED",
            cycle_index: 0,
            max_cycles: $max_cycles,
            cycles: [],
            harvest: {
                visions_captured: 0,
                lore_candidates_queued: 0,
                pending_bugs: 0
            },
            flatline_counter: 0,
            flatline: {
                min_new_findings_per_cycle: $flatline_min,
                consecutive_low_cycles_threshold: $flatline_consec
            },
            budget: {
                budget_cents: $budget_cents,
                cost_cents: 0,
                wall_clock_seconds: $wall_clock_seconds
            },
            stopping_condition: null,
            timestamps: {
                started: $ts,
                last_activity: $ts,
                completed_at: null
            }
        }' > "$STATE_FILE"

    chmod 600 "$STATE_FILE"
    echo "$spiral_id"
}

update_phase() {
    local new_phase="$1"
    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local tmp="${STATE_FILE}.tmp"
    jq --arg phase "$new_phase" --arg ts "$timestamp" \
        '.phase = $phase | .timestamps.last_activity = $ts' \
        "$STATE_FILE" > "$tmp"
    mv "$tmp" "$STATE_FILE"
}

coalesce_spiral_terminal_state() {
    local target_state="$1"
    local stopping_condition="$2"
    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local tmp="${STATE_FILE}.tmp"
    jq --arg state "$target_state" \
        --arg condition "$stopping_condition" \
        --arg ts "$timestamp" \
        '.state = $state |
         .stopping_condition = $condition |
         .timestamps.completed_at = $ts |
         .timestamps.last_activity = $ts' \
        "$STATE_FILE" > "$tmp"
    mv "$tmp" "$STATE_FILE"
}

# =============================================================================
# Cycle-067 Helpers: Checkpoint, Timeout, Atomic Write, PID Guard
# =============================================================================

# Checkpoint monotonicity (Bridgebuilder HIGH-2)
readonly CHECKPOINT_ORDER=(INIT WORKSPACE SEED SIMSTIM HARVEST EVALUATE COMPLETE)

checkpoint_ordinal() {
    local phase="$1"
    local i
    for i in "${!CHECKPOINT_ORDER[@]}"; do
        if [[ "${CHECKPOINT_ORDER[$i]}" == "$phase" ]]; then
            echo "$i"
            return 0
        fi
    done
    echo "-1"
}

# write_checkpoint <cycle_id> <phase>
# Writes checkpoint to the last cycle in .cycles, enforcing monotonicity.
write_checkpoint() {
    local cycle_id="$1"
    local new_phase="$2"

    local current
    current=$(jq -r --arg cid "$cycle_id" '
        (.cycles[] | select(.cycle_id == $cid) | .checkpoint) // "NONE"
    ' "$STATE_FILE" 2>/dev/null) || current="NONE"

    if [[ "$current" != "NONE" && "$current" != "null" ]]; then
        local cur_idx new_idx
        cur_idx=$(checkpoint_ordinal "$current")
        new_idx=$(checkpoint_ordinal "$new_phase")
        if [[ "$cur_idx" -ge "$new_idx" ]]; then
            error "Non-monotonic checkpoint: $current → $new_phase (cycle $cycle_id)"
            return 1
        fi
    fi

    atomic_state_write --arg cid "$cycle_id" --arg cp "$new_phase" '
        .cycles = [.cycles[] | if .cycle_id == $cid then .checkpoint = $cp else . end]
    '
}

# atomic_state_write <jq_args...>
# Wraps jq > .tmp && mv with error handling (Flatline IMP-002).
# Sets _SPIRAL_JQ_IN_FLIGHT for trap safety (Bridgebuilder MEDIUM-1).
_SPIRAL_JQ_IN_FLIGHT=0

atomic_state_write() {
    local tmp="${STATE_FILE}.tmp"
    _SPIRAL_JQ_IN_FLIGHT=1

    if ! jq "$@" "$STATE_FILE" > "$tmp" 2>/dev/null; then
        _SPIRAL_JQ_IN_FLIGHT=0
        rm -f "$tmp"
        error "State write failed (jq error)"
        return 1
    fi

    if ! mv "$tmp" "$STATE_FILE" 2>/dev/null; then
        _SPIRAL_JQ_IN_FLIGHT=0
        error "State write failed (mv error). Stale .tmp may exist: $tmp"
        return 1
    fi

    _SPIRAL_JQ_IN_FLIGHT=0
    return 0
}

# require_timeout — detect timeout/gtimeout for step watchdogs (Bridgebuilder MEDIUM-2)
_TIMEOUT_CMD=""

require_timeout() {
    if command -v timeout &>/dev/null; then
        _TIMEOUT_CMD="timeout"
    elif command -v gtimeout &>/dev/null; then
        _TIMEOUT_CMD="gtimeout"
    else
        log "WARNING: timeout/gtimeout not found. Step timeouts disabled."
        log "  Install: brew install coreutils (macOS) or apt install coreutils (Linux)"
        _TIMEOUT_CMD=""
    fi
}

# with_step_timeout <step_name> <seconds> <command...>
# Wraps command in timeout(1). Returns 124 on timeout.
with_step_timeout() {
    local step_name="$1"
    local budget_sec="$2"
    shift 2

    # timeout(1) can only execute external commands, not bash functions.
    # Detect functions and skip timeout — wall-clock provides outer safety net.
    local cmd_type
    cmd_type=$(type -t "$1" 2>/dev/null || echo "external")
    if [[ -z "$_TIMEOUT_CMD" ]] || [[ "$budget_sec" -le 0 ]] || [[ "$cmd_type" == "function" ]]; then
        "$@"
        return $?
    fi

    local exit_code=0
    "$_TIMEOUT_CMD" --signal=TERM --kill-after=10 "$budget_sec" "$@" || exit_code=$?

    if [[ "$exit_code" -eq 124 ]]; then
        log_trajectory "step_timeout" \
            "$(jq -n --arg step "$step_name" --argjson budget "$budget_sec" \
                '{step: $step, budget_sec: $budget, timed_out: true}')"
    fi
    return "$exit_code"
}

# PID guard (Flatline IMP-001 + SKP-004)
# Checks if a spiral is already running, detects stale RUNNING via PID liveness.
check_pid_guard() {
    if [[ ! -f "$STATE_FILE" ]]; then
        return 0  # No state → safe to start
    fi

    local existing_state existing_pid existing_start_time
    existing_state=$(jq -r '.state // "unknown"' "$STATE_FILE" 2>/dev/null) || return 0
    existing_pid=$(jq -r '.pid // 0' "$STATE_FILE" 2>/dev/null) || existing_pid=0
    existing_start_time=$(jq -r '.start_time // ""' "$STATE_FILE" 2>/dev/null) || existing_start_time=""

    if [[ "$existing_state" == "RUNNING" ]]; then
        if [[ "$existing_pid" -gt 0 ]] && kill -0 "$existing_pid" 2>/dev/null; then
            # Process alive — check start_time to guard against PID reuse (Flatline SKP-002)
            if [[ -n "$existing_start_time" ]] && [[ -d "/proc/$existing_pid" ]]; then
                local proc_start
                proc_start=$(stat -c %Y "/proc/$existing_pid" 2>/dev/null) || proc_start=0
                local state_start_epoch
                state_start_epoch=$(date -u -d "$existing_start_time" +%s 2>/dev/null) || state_start_epoch=0
                local diff=$(( proc_start - state_start_epoch ))
                # Allow 5s tolerance
                if [[ "${diff#-}" -gt 5 ]]; then
                    log "WARNING: PID $existing_pid reused (start_time mismatch). Treating as stale."
                    coalesce_spiral_terminal_state "CRASHED" "orphan_detected_pid_reuse"
                    return 0
                fi
            fi
            error "Spiral already RUNNING (PID $existing_pid). Use --halt or --resume."
            return 3
        fi
        # PID dead → stale RUNNING
        log "WARNING: stale RUNNING state (PID $existing_pid dead). Treating as crash."
        coalesce_spiral_terminal_state "CRASHED" "orphan_detected"
        return 0
    fi

    return 0
}

# Record PID + start_time in state
record_pid() {
    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    atomic_state_write --argjson pid "$$" --arg st "$timestamp" \
        '.pid = $pid | .start_time = $st'
}

# =============================================================================
# Stopping-condition predicates (RFC-060 AD-4)
# =============================================================================

check_cycle_budget() {
    local current_index max
    current_index=$(jq -r '.cycle_index' "$STATE_FILE")
    max=$(jq -r '.max_cycles' "$STATE_FILE")
    [[ "$current_index" -ge "$max" ]]
}

check_flatline() {
    local counter threshold
    counter=$(jq -r '.flatline_counter' "$STATE_FILE")
    threshold=$(jq -r '.flatline.consecutive_low_cycles_threshold' "$STATE_FILE")
    [[ "$counter" -ge "$threshold" ]]
}

check_cost_budget() {
    local cost_cents budget
    cost_cents=$(jq -r '.budget.cost_cents' "$STATE_FILE")
    budget=$(jq -r '.budget.budget_cents' "$STATE_FILE")
    [[ "$cost_cents" -ge "$budget" ]]
}

check_wall_clock() {
    local started budget now_epoch started_epoch elapsed
    started=$(jq -r '.timestamps.started' "$STATE_FILE")
    budget=$(jq -r '.budget.wall_clock_seconds' "$STATE_FILE")
    now_epoch=$(date -u +%s)
    started_epoch=$(date -u -d "$started" +%s 2>/dev/null \
        || date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$started" +%s 2>/dev/null \
        || echo "$now_epoch")
    elapsed=$((now_epoch - started_epoch))
    [[ "$elapsed" -ge "$budget" ]]
}

check_hitl_halt() {
    [[ -f "$HALT_SENTINEL" ]]
}

# check_quality_gate — FR-2 (cycle-067)
# Returns 0 if gate should STOP spiral (fail-closed on missing/invalid).
# Returns 1 if spiral should CONTINUE.
check_quality_gate() {
    local last_cycle review_v audit_v
    last_cycle=$(jq -c '.cycles[-1] // null' "$STATE_FILE" 2>/dev/null)
    if [[ "$last_cycle" == "null" || -z "$last_cycle" ]]; then
        log_trajectory "quality_gate_decision" \
            "$(jq -n '{decision: "continue", reason: "no_cycle_yet"}')"
        return 1
    fi

    review_v=$(echo "$last_cycle" | jq -r '.review_verdict // "null"')
    audit_v=$(echo "$last_cycle" | jq -r '.audit_verdict // "null"')

    # Null/missing → fail-closed
    if [[ "$review_v" == "null" ]] || [[ "$audit_v" == "null" ]]; then
        log_trajectory "quality_gate_indeterminate" \
            "$(jq -n --arg r "$review_v" --arg a "$audit_v" \
                '{decision: "stop", review: $r, audit: $a, reason: "null_verdict"}')"
        return 0
    fi

    # Invalid enum → fail-closed
    case "$review_v" in APPROVED|REQUEST_CHANGES) ;;
        *)
            log_trajectory "quality_gate_invalid_verdict" \
                "$(jq -n --arg r "$review_v" '{decision: "stop", review: $r, field: "review_verdict"}')"
            return 0
            ;;
    esac
    case "$audit_v" in APPROVED|CHANGES_REQUIRED) ;;
        *)
            log_trajectory "quality_gate_invalid_verdict" \
                "$(jq -n --arg a "$audit_v" '{decision: "stop", audit: $a, field: "audit_verdict"}')"
            return 0
            ;;
    esac

    # Both-fail → stop (only stopping combo)
    if [[ "$review_v" == "REQUEST_CHANGES" && "$audit_v" == "CHANGES_REQUIRED" ]]; then
        log_trajectory "quality_gate_decision" \
            "$(jq -n '{decision: "stop", reason: "both_gates_failed"}')"
        return 0
    fi

    log_trajectory "quality_gate_decision" \
        "$(jq -n --arg r "$review_v" --arg a "$audit_v" \
            '{decision: "continue", review: $r, audit: $a}')"
    return 1
}

# Returns the triggered stopping condition name, or empty string if none.
evaluate_stopping_conditions() {
    if check_hitl_halt; then
        echo "hitl_halt"
        return 0
    fi
    if check_quality_gate; then
        echo "quality_gate_failure"
        return 0
    fi
    if check_cycle_budget; then
        echo "cycle_budget_exhausted"
        return 0
    fi
    if check_flatline; then
        echo "flatline_convergence"
        return 0
    fi
    if check_cost_budget; then
        echo "cost_budget_exhausted"
        return 0
    fi
    if check_wall_clock; then
        echo "wall_clock_exhausted"
        return 0
    fi
    echo ""
}

# =============================================================================
# Trajectory logging
# =============================================================================

log_trajectory() {
    local event="$1"
    local payload="$2"
    local date_stamp
    date_stamp=$(date -u +%Y-%m-%d)
    local log_file="$TRAJECTORY_DIR/spiral-${date_stamp}.jsonl"
    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    mkdir -p "$TRAJECTORY_DIR"
    jq -c -n \
        --arg ts "$timestamp" \
        --arg event "$event" \
        --argjson payload "$payload" \
        '{timestamp: $ts, event: $event} + $payload' \
        >> "$log_file"
}

# =============================================================================
# Phase Helpers (cycle-067)
# =============================================================================

# Source the HARVEST adapter
ADAPTER_SCRIPT="$SCRIPT_DIR/spiral-harvest-adapter.sh"
if [[ -f "$ADAPTER_SCRIPT" ]]; then
    source "$ADAPTER_SCRIPT"
fi

# seed_phase <cycle_dir> <cycle_id> <prev_cycle_dir>
# FR-5: Degraded mode — reads previous cycle's sidecar and writes seed-context.md
seed_phase() {
    local cycle_dir="$1"
    local cycle_id="$2"
    local prev_cycle_dir="${3:-}"

    local seed_mode
    seed_mode=$(read_config "spiral.seed.mode" "degraded")

    # Full mode: query Vision Registry for relevant cross-cycle visions (#486, cycle-069)
    if [[ "$seed_mode" == "full" ]]; then
        # Check vision_registry.enabled (Flatline SKP-010: defensive guard)
        local vr_enabled
        vr_enabled=$(read_config "vision_registry.enabled" "false")
        if [[ "$vr_enabled" != "true" ]]; then
            log "WARNING: seed.mode=full but vision_registry.enabled=false. Degrading to degraded mode."
            seed_mode="degraded"
            log_trajectory "seed_mode_transition" \
                "$(jq -n --arg c "$cycle_id" '{cycle_id: $c, from: "full", to: "degraded", reason: "vision_registry_disabled"}')"
        else
            # Tag derivation from HARVEST sidecar (Flatline IMP-002)
            local query_tags=""
            local harvest_sidecar="${prev_cycle_dir:+${prev_cycle_dir}/}${SPIRAL_SIDECAR_FILENAME:-cycle-outcome.json}"
            if [[ -n "$prev_cycle_dir" && -f "$harvest_sidecar" ]]; then
                # Validate sidecar structure (Flatline IMP-006)
                if jq -e '.findings | type == "array"' "$harvest_sidecar" >/dev/null 2>&1; then
                    query_tags=$(jq -r '
                        [.findings[]?.category // empty] | unique |
                        map(select(. as $c | ["security","architecture","performance",
                            "reliability","testing","code-quality","documentation"]
                            | index($c))) |
                        join(",")
                    ' "$harvest_sidecar" 2>/dev/null || true)
                else
                    log "WARNING: HARVEST sidecar has unexpected structure, using default tags"
                fi
            fi

            # Fallback to configured default tags
            if [[ -z "$query_tags" ]]; then
                query_tags=$(read_config "spiral.seed.default_tags" "architecture,security" | sed 's/^- //;s/^-//' | tr -d '[]" ' | tr '\n' ',' | sed 's/,$//')
            fi

            local max_visions
            max_visions=$(read_config "spiral.seed.max_seed_visions" "10")

            # Query registry (review fix #3: distinguish no-results from real errors)
            local query_result="" query_exit=0
            query_result=$("$SCRIPT_DIR/vision-query.sh" \
                --tags "$query_tags" \
                --status "Captured,Exploring,Proposed" \
                --format json \
                --limit "$max_visions" 2>/dev/null) || query_exit=$?

            if [[ "$query_exit" -gt 1 ]]; then
                # Exit 2=bad args, 3=parse error, 4=I/O error — real failures
                log "WARNING: vision-query.sh failed (exit $query_exit), cold-starting"
                log_trajectory "seed_full_query_error" \
                    "$(jq -n --arg c "$cycle_id" --argjson ec "$query_exit" \
                        '{cycle_id: $c, query_exit_code: $ec}')"
                return 0
            fi
            # Exit 0=results found, exit 1=no results — both safe
            query_result="${query_result:-[]}"

            local vision_count
            vision_count=$(echo "$query_result" | jq 'length' 2>/dev/null || echo "0")

            if [[ "$vision_count" -eq 0 ]]; then
                # Full mode with zero results → cold start (not degraded)
                log "Full SEED: no relevant visions found, cold-starting"
                log_trajectory "seed_cold" \
                    "$(jq -n --arg c "$cycle_id" --arg tags "$query_tags" \
                        '{cycle_id: $c, reason: "full_mode_zero_results", query_tags: $tags}')"
                return 0
            fi

            # Compute relevance scores via jq (float-safe — Bridgebuilder MEDIUM-1)
            local total_tags
            total_tags=$(echo "$query_tags" | tr ',' '\n' | grep -c . || echo "0")

            local scored_result
            scored_result=$(echo "$query_result" | jq --arg qtags "$query_tags" --argjson total "$total_tags" '
                [.[] | . + {
                    relevance_score: (
                        if $total == 0 then 0
                        else
                            ([.tags[] | select(. as $t | ($qtags | split(",")) | index($t))] | length) / $total
                        end
                    )
                }] | sort_by(-.relevance_score, .date) | reverse
            ')

            # Build structured seed context JSON (Flatline IMP-004 schema)
            local budget=4096
            local seed_json
            seed_json=$(echo "$scored_result" | jq --arg tags "$query_tags" \
                --argjson limit "$max_visions" \
                --argjson budget "$budget" \
                '{
                    mode: "full",
                    query: {tags: ($tags | split(",")), statuses: ["Captured","Exploring","Proposed"], limit: $limit},
                    visions: [.[] | {
                        id: .id,
                        title: .title,
                        tags: .tags,
                        status: .status,
                        date: .date,
                        insight_excerpt: (.insight_excerpt // "")[0:200],
                        relevance_score: .relevance_score
                    }],
                    budget_bytes: $budget
                }')

            # Budget enforcement: drop lowest-ranked visions until under budget (IMP-007)
            # Review fix #4: measure full JSON size, not just visions array
            local total_bytes
            total_bytes=$(printf '%s' "$seed_json" | wc -c)

            if [[ "$total_bytes" -gt "$budget" ]]; then
                seed_json=$(echo "$seed_json" | jq --argjson budget "$budget" '
                    .truncated = true |
                    until((. | tojson | length) <= $budget or (.visions | length) <= 1;
                        .visions |= .[:-1]
                    )
                ')
                total_bytes=$(printf '%s' "$seed_json" | wc -c)
            fi

            seed_json=$(echo "$seed_json" | jq --argjson tb "$total_bytes" \
                '.total_bytes = $tb | .truncated = (.truncated // false)')

            # Write seed context as human-readable markdown wrapping JSON
            local seed_file="${cycle_dir}/seed-context.md"
            {
                printf '# Seed Context (Full Mode — Vision Registry)\n\n'
                printf 'Previous cycle context (machine-generated, advisory only):\n\n'
                printf '```json\n'
                printf '%s\n' "$seed_json"
                printf '```\n'
            } > "$seed_file"

            log "Full SEED: ${vision_count} visions, ${total_bytes} bytes, tags=${query_tags}"
            log_trajectory "seed_full" \
                "$(jq -n --arg c "$cycle_id" --arg tags "$query_tags" \
                    --argjson count "$vision_count" --argjson bytes "$total_bytes" \
                    --argjson budget "$budget" \
                    '{cycle_id: $c, query_tags: $tags, vision_count: $count, total_bytes: $bytes, budget_bytes: $budget}')"
            return 0
        fi
    fi

    if [[ "$seed_mode" == "degraded" ]] && [[ -n "$prev_cycle_dir" ]] && [[ -d "$prev_cycle_dir" ]]; then
        local prev_sidecar="${prev_cycle_dir}/${SPIRAL_SIDECAR_FILENAME:-cycle-outcome.json}"
        if [[ -f "$prev_sidecar" ]]; then
            # Read previous sidecar and compose seed context
            local prev_cycle_id review_v audit_v findings_summary
            prev_cycle_id=$(basename "$prev_cycle_dir")
            review_v=$(jq -r '.review_verdict // "unknown"' "$prev_sidecar" 2>/dev/null)
            audit_v=$(jq -r '.audit_verdict // "unknown"' "$prev_sidecar" 2>/dev/null)
            findings_summary=$(jq -r '
                "- Blocker: \(.findings.blocker // 0), High: \(.findings.high // 0), Medium: \(.findings.medium // 0), Low: \(.findings.low // 0)"
            ' "$prev_sidecar" 2>/dev/null)
            local sig
            sig=$(jq -r '.flatline_signature // "none"' "$prev_sidecar" 2>/dev/null)

            # Write seed context — quoted heredoc prevents shell expansion (security audit O-3)
            {
                printf '# Seed Context for %s\n\n' "$cycle_id"
                printf '**Source**: previous cycle `%s` (harvest sidecar v1)\n\n' "$prev_cycle_id"
                printf '## Verdicts\n- Review: %s\n- Audit: %s\n\n' "$review_v" "$audit_v"
                printf '## Findings Summary\n%s\n\n' "$findings_summary"
                printf '## Flatline Signature\n%s\n\n' "$sig"
                printf '## Pointer\nPrevious reviewer: %s/reviewer.md\n' "$prev_cycle_dir"
                printf 'Previous auditor:  %s/auditor-sprint-feedback.md\n' "$prev_cycle_dir"
            } > "${cycle_dir}/seed-context.md"

            local context_bytes
            context_bytes=$(wc -c < "${cycle_dir}/seed-context.md")
            log_trajectory "seed_degraded" \
                "$(jq -n --arg c "$cycle_id" --arg src "$prev_cycle_id" --argjson bytes "$context_bytes" \
                    '{cycle_id: $c, source_cycle_id: $src, context_bytes: $bytes}')"
            return 0
        fi
        # Previous sidecar missing (corrupt/truncated) → fall through to cold
    fi

    # Cold start (first cycle or no valid predecessor)
    log_trajectory "seed_cold" \
        "$(jq -n --arg c "$cycle_id" --arg r "no_predecessor_or_first_cycle" \
            '{cycle_id: $c, reason: $r}')"
}

# simstim_phase <cycle_dir> <cycle_id>
# Dispatches either stub or real simstim based on env var truth table (cycle-068)
simstim_phase() {
    local cycle_dir="$1"
    local cycle_id="$2"

    local dispatch_mode
    dispatch_mode=$(_resolve_dispatch_mode)

    # Dispatch mode banner (Flatline SKP-001)
    log "Dispatch mode: $dispatch_mode"

    case "$dispatch_mode" in
        STUB) _simstim_stub "$cycle_dir" "$cycle_id" ;;
        REAL) _simstim_real "$cycle_dir" "$cycle_id" ;;
    esac
}

# _resolve_dispatch_mode — FR-3 truth table (cycle-068)
# SPIRAL_USE_STUB=1 always wins. SPIRAL_REAL_DISPATCH=1 → REAL. Neither → STUB default.
_resolve_dispatch_mode() {
    if [[ "${SPIRAL_USE_STUB:-0}" == "1" ]]; then
        echo "STUB"
    elif [[ "${SPIRAL_REAL_DISPATCH:-0}" == "1" ]]; then
        echo "REAL"
    else
        if [[ -z "${CI:-}" ]]; then
            log "WARNING: Dispatch mode: STUB (default — set SPIRAL_REAL_DISPATCH=1 for real execution)"
        fi
        echo "STUB"
    fi
}

# _simstim_stub — cycle-067 stub dispatcher (extracted, unchanged)
_simstim_stub() {
    local cycle_dir="$1"
    local cycle_id="$2"

    local stub_findings="${SPIRAL_STUB_FINDINGS:-3}"
    # Validate: integer ≥ 0, default 3 on malformed (Flatline IMP-005)
    if ! [[ "$stub_findings" =~ ^[0-9]+$ ]]; then
        stub_findings=3
    fi

    log "STUB: simstim dispatch not yet wired"

    # Write mock reviewer.md
    cat > "${cycle_dir}/reviewer.md" <<REVEOF
# Stub Review — ${cycle_id}

## Verdict

APPROVED

## Findings Summary

| Severity | Count |
|----------|-------|
| Blocker | 0 |
| High | ${stub_findings} |
| Medium | 0 |
| Low | 0 |
REVEOF

    # Write mock auditor-sprint-feedback.md
    cat > "${cycle_dir}/auditor-sprint-feedback.md" <<AUDEOF
# Stub Audit — ${cycle_id}

## Final Verdict

APPROVED

## Findings Summary

| Severity | Count |
|----------|-------|
| Blocker | 0 |
| High | 0 |
| Medium | 0 |
| Low | 0 |
AUDEOF

    # Emit sidecar via adapter
    local findings_json
    findings_json=$(jq -n --argjson h "$stub_findings" \
        '{blocker: 0, high: $h, medium: 0, low: 0}')

    if type -t emit_cycle_outcome_sidecar &>/dev/null; then
        emit_cycle_outcome_sidecar "$cycle_dir" "APPROVED" "APPROVED" \
            "$findings_json" "null" "1" "success" >/dev/null
    fi

    log_trajectory "simstim_stub" \
        "$(jq -n --arg c "$cycle_id" --argjson f "$stub_findings" \
            '{cycle_id: $c, mock_findings: $f}')"
}

# _simstim_real — real dispatch via external wrapper (cycle-068 FR-1)
_simstim_real() {
    local cycle_dir="$1"
    local cycle_id="$2"

    # Clean stale artifacts (SKP-003)
    rm -f "$cycle_dir/reviewer.md" "$cycle_dir/auditor-sprint-feedback.md" \
          "$cycle_dir/cycle-outcome.json"

    # Resolve seed context path
    local seed_context=""
    if [[ -f "$cycle_dir/seed-context.md" ]]; then
        seed_context="$cycle_dir/seed-context.md"
    fi

    local dispatch_script="$SCRIPT_DIR/spiral-simstim-dispatch.sh"
    if [[ ! -x "$dispatch_script" ]]; then
        error "Dispatch script not found or not executable: $dispatch_script"
        log_trajectory "simstim_dispatch_error" \
            "$(jq -n --arg c "$cycle_id" '{cycle_id: $c, reason: "dispatch_script_missing"}')"
        return 127
    fi

    local start_sec
    start_sec=$(date +%s)

    # External script — timeout(1) wraps it (FR-5)
    local exit_code=0
    "$dispatch_script" "$cycle_dir" "$cycle_id" "$seed_context" || exit_code=$?

    local elapsed=$(($(date +%s) - start_sec))

    # FR-6 exit code handling
    case "$exit_code" in
        0) ;;
        126|127)
            error "Dispatch failed: exit $exit_code (not found/executable)"
            log_trajectory "simstim_dispatch_error" \
                "$(jq -n --arg c "$cycle_id" --argjson e "$exit_code" \
                    '{cycle_id: $c, exit_code: $e, reason: "dispatch_error"}')"
            return "$exit_code"
            ;;
        *)
            log "WARNING: simstim exited $exit_code (cycle $cycle_id, ${elapsed}s)"
            ;;
    esac

    log_trajectory "simstim_dispatched" \
        "$(jq -n --arg c "$cycle_id" --arg m "real" --argjson e "$exit_code" --argjson el "$elapsed" \
            '{cycle_id: $c, dispatch_mode: $m, exit_code: $e, elapsed_sec: $el}')"

    return "$exit_code"
}

# harvest_phase <cycle_dir> <cycle_id>
# FR-8: Parse cycle outcome via adapter (3-tier precedence)
harvest_phase() {
    local cycle_dir="$1"
    local cycle_id="$2"
    local start_ms
    start_ms=$(date +%s%N 2>/dev/null | cut -b1-13 || date +%s)

    local result
    if type -t parse_cycle_outcome &>/dev/null; then
        result=$(parse_cycle_outcome "$cycle_dir" "$PROJECT_ROOT/.run" "$cycle_id" 2>/dev/null)
    else
        # Adapter not loaded — fail-closed
        log "WARNING: harvest adapter not loaded"
        result=$(jq -n --arg c "$cycle_id" '{
            cycle_id: $c, review_verdict: null, audit_verdict: null,
            findings_critical: 0, findings_minor: 0, exit_status: "failed",
            parse_source: "adapter_missing"
        }')
    fi

    local end_ms
    end_ms=$(date +%s%N 2>/dev/null | cut -b1-13 || date +%s)
    local duration=$((end_ms - start_ms))

    local parse_source
    parse_source=$(echo "$result" | jq -r '.parse_source // "unknown"')

    log_trajectory "harvest_parsed" \
        "$(jq -n --arg c "$cycle_id" --arg src "$parse_source" --argjson dur "$duration" \
            '{cycle_id: $c, parse_source: $src, duration_ms: $dur}')"

    echo "$result"
}

# append_cycle_record <cycle_id> <harvest_result_json>
# Appends cycle to .cycles, idempotent by cycle_id (FR-9.4: dedup on resume)
append_cycle_record() {
    local cycle_id="$1"
    local harvest_json="$2"

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Check for existing cycle_id (dedup)
    local existing
    existing=$(jq -r --arg cid "$cycle_id" '[.cycles[] | select(.cycle_id == $cid)] | length' "$STATE_FILE" 2>/dev/null)
    if [[ "$existing" -gt 0 ]]; then
        log "Cycle $cycle_id already in state (dedup on resume)"
        return 0
    fi

    local cycle_index
    cycle_index=$(jq -r '.cycles | length' "$STATE_FILE")

    atomic_state_write \
        --arg cid "$cycle_id" \
        --argjson idx "$cycle_index" \
        --arg ts "$timestamp" \
        --argjson harvest "$harvest_json" \
        '
        .cycles += [{
            cycle_id: $cid,
            index: $idx,
            started_at: $ts,
            completed_at: $ts,
            review_verdict: $harvest.review_verdict,
            audit_verdict: $harvest.audit_verdict,
            findings_critical: ($harvest.findings_critical // 0),
            findings_minor: ($harvest.findings_minor // 0),
            flatline_signature: ($harvest.flatline_signature // null),
            content_hash: ($harvest.content_hash // null),
            elapsed_sec: ($harvest.elapsed_sec // null),
            exit_status: ($harvest.exit_status // "success"),
            checkpoint: null,
            skipped: false
        }] |
        .cycle_index = ($idx + 1)
        '
}

# run_single_cycle <cycle_index> <prev_cycle_dir>
# Executes one spiral iteration: SEED → SIMSTIM → HARVEST → EVALUATE
run_single_cycle() {
    local i="$1"
    local prev_cycle_dir="${2:-}"

    local cycle_id
    cycle_id="cycle-$(date -u +%s | tail -c 7)$(head -c 2 /dev/urandom | od -An -tx1 | tr -d ' \n')"

    local cycle_dir="${PROJECT_ROOT}/cycles/${cycle_id}"
    mkdir -p "$cycle_dir"

    # Read step timeouts from config
    local t_workspace t_seed t_simstim t_harvest t_state t_evaluate
    t_workspace=$(read_config "spiral.step_timeouts.workspace_init_sec" "10")
    t_seed=$(read_config "spiral.step_timeouts.seed_sec" "5")
    t_simstim=$(read_config "spiral.step_timeouts.simstim_sec" "3600")
    t_harvest=$(read_config "spiral.step_timeouts.harvest_sec" "30")
    t_state=$(read_config "spiral.step_timeouts.state_append_sec" "5")
    t_evaluate=$(read_config "spiral.step_timeouts.evaluate_sec" "5")

    # Append initial cycle record for checkpoint tracking
    local init_harvest
    init_harvest=$(jq -n '{review_verdict: null, audit_verdict: null, findings_critical: 0, findings_minor: 0, exit_status: "pending"}')
    append_cycle_record "$cycle_id" "$init_harvest"

    # Step 1: INIT checkpoint
    write_checkpoint "$cycle_id" "INIT"

    # Step 2: Workspace
    if [[ -x "$SCRIPT_DIR/cycle-workspace.sh" ]]; then
        with_step_timeout "workspace_init" "$t_workspace" \
            "$SCRIPT_DIR/cycle-workspace.sh" init "$cycle_id" 2>/dev/null || true
    fi
    write_checkpoint "$cycle_id" "WORKSPACE"

    # Step 3: SEED
    with_step_timeout "seed" "$t_seed" \
        seed_phase "$cycle_dir" "$cycle_id" "$prev_cycle_dir"
    update_phase "SEED"
    write_checkpoint "$cycle_id" "SEED"

    # Step 4: SIMSTIM
    update_phase "SIMSTIM"
    with_step_timeout "simstim" "$t_simstim" \
        simstim_phase "$cycle_dir" "$cycle_id"
    write_checkpoint "$cycle_id" "SIMSTIM"

    # Step 5: HARVEST
    update_phase "HARVEST"
    local harvest_result
    harvest_result=$(with_step_timeout "harvest" "$t_harvest" \
        harvest_phase "$cycle_dir" "$cycle_id")

    # Update cycle record with harvest data
    atomic_state_write \
        --arg cid "$cycle_id" \
        --argjson harvest "$harvest_result" \
        '
        .cycles = [.cycles[] |
            if .cycle_id == $cid then
                .review_verdict = $harvest.review_verdict |
                .audit_verdict = $harvest.audit_verdict |
                .findings_critical = ($harvest.findings_critical // 0) |
                .findings_minor = ($harvest.findings_minor // 0) |
                .flatline_signature = ($harvest.flatline_signature // null) |
                .content_hash = ($harvest.content_hash // null) |
                .exit_status = ($harvest.exit_status // "success")
            else . end
        ]
        '

    write_checkpoint "$cycle_id" "HARVEST"

    # Step 6: EVALUATE
    update_phase "EVALUATE"
    local stop_reason
    stop_reason=$(evaluate_stopping_conditions)
    write_checkpoint "$cycle_id" "EVALUATE"

    log_trajectory "cycle_completed" \
        "$(jq -n --arg c "$cycle_id" --argjson idx "$i" \
            '{cycle_id: $c, index: $idx}')"

    write_checkpoint "$cycle_id" "COMPLETE"

    # Return stop reason (empty = continue)
    echo "$stop_reason"
    echo "$cycle_dir"  # second line: cycle dir for SEED chaining
}

# run_cycle_loop
# Main loop: dispatches run_single_cycle for each iteration
run_cycle_loop() {
    local max_cycles
    max_cycles=$(jq -r '.max_cycles' "$STATE_FILE")

    local prev_cycle_dir=""
    local i=0

    while [[ "$i" -lt "$max_cycles" ]]; do
        i=$((i + 1))
        log "Cycle $i / $max_cycles"

        local output
        output=$(run_single_cycle "$i" "$prev_cycle_dir")

        local stop_reason cycle_dir
        stop_reason=$(echo "$output" | head -1)
        cycle_dir=$(echo "$output" | tail -1)

        prev_cycle_dir="$cycle_dir"

        if [[ -n "$stop_reason" ]]; then
            log "Stopping: $stop_reason (cycle $i)"
            coalesce_spiral_terminal_state "COMPLETED" "$stop_reason"
            return 0
        fi
    done

    # max_cycles reached
    log "All $max_cycles cycles completed"
    coalesce_spiral_terminal_state "COMPLETED" "cycle_budget_exhausted"
}

# spiral_crash_handler <exit_code>
# Async-signal-safe trap handler (Bridgebuilder MEDIUM-1)
spiral_crash_handler() {
    local exit_code="${1:-0}"

    # Normal exit → skip (Flatline SKP-003)
    if [[ "$exit_code" -eq 0 ]]; then
        return 0
    fi

    # Check if we're in a terminal state already
    local current_state
    current_state=$(jq -r '.state // "unknown"' "$STATE_FILE" 2>/dev/null) || current_state="unknown"
    case "$current_state" in
        COMPLETED|FAILED|HALTED|CRASHED) return 0 ;;
    esac

    # Write crash diagnostic via printf (async-signal-safe, no jq)
    local crash_file="${PROJECT_ROOT}/.run/spiral-crash-$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null || echo unknown).json"
    local pid_val="$$"
    local phase_val
    phase_val=$(jq -r '.phase // "unknown"' "$STATE_FILE" 2>/dev/null) || phase_val="unknown"

    printf '{"exit_code":%d,"pid":%d,"last_phase":"%s","crashed_at":"%s"}\n' \
        "$exit_code" "$pid_val" "$phase_val" "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)" \
        > "$crash_file" 2>/dev/null || true

    # Skip state update if jq was in flight (Bridgebuilder MEDIUM-1)
    if [[ "$_SPIRAL_JQ_IN_FLIGHT" -eq 1 ]] || [[ -f "${STATE_FILE}.tmp" ]]; then
        return 0
    fi

    # Coalesce to CRASHED
    coalesce_spiral_terminal_state "CRASHED" "signal_${exit_code}" 2>/dev/null || true
}

# =============================================================================
# Commands
# =============================================================================

cmd_start() {

    if ! is_enabled; then
        error "/spiral is disabled. Set spiral.enabled: true in .loa.config.yaml"
        return 2
    fi

    if [[ -f "$STATE_FILE" ]]; then
        local current_state
        current_state=$(jq -r '.state // "unknown"' "$STATE_FILE" 2>/dev/null || echo "unknown")
        if [[ "$current_state" == "RUNNING" ]]; then
            error "Spiral already RUNNING. Use --status, --halt, or --resume."
            return 3
        fi
    fi

    # Read config with defaults from RFC-060 schema
    local max_cycles budget_cents wall_clock_seconds flatline_min flatline_consec
    max_cycles=$(read_config "spiral.default_max_cycles" "3")
    budget_cents=$(read_config "spiral.budget_cents" "2000")
    wall_clock_seconds=$(read_config "spiral.wall_clock_seconds" "28800")
    flatline_min=$(read_config "spiral.flatline.min_new_findings_per_cycle" "3")
    flatline_consec=$(read_config "spiral.flatline.consecutive_low_cycles" "2")

    # Parse CLI overrides
    local dry_run=false
    local init_only=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --max-cycles) max_cycles="$2"; shift 2 ;;
            --budget-cents) budget_cents="$2"; shift 2 ;;
            --wall-clock-seconds) wall_clock_seconds="$2"; shift 2 ;;
            --dry-run) dry_run=true; shift ;;
            --init-only) init_only=true; shift ;;
            *) error "Unknown --start option: $1"; return 1 ;;
        esac
    done

    # Apply safety floors (AD-4)
    max_cycles=$(clamp_to_floor "$max_cycles" "$MAX_CYCLES_FLOOR")
    budget_cents=$(clamp_to_floor "$budget_cents" "$MAX_COST_CENTS_FLOOR")
    wall_clock_seconds=$(clamp_to_floor "$wall_clock_seconds" "$MAX_WALL_CLOCK_SECONDS_FLOOR")

    if [[ "$dry_run" == "true" ]]; then
        jq -n \
            --argjson max_cycles "$max_cycles" \
            --argjson budget_cents "$budget_cents" \
            --argjson wall_clock_seconds "$wall_clock_seconds" \
            --argjson flatline_min "$flatline_min" \
            --argjson flatline_consec "$flatline_consec" \
            '{
                dry_run: true,
                computed: {
                    max_cycles: $max_cycles,
                    budget_cents: $budget_cents,
                    wall_clock_seconds: $wall_clock_seconds,
                    flatline_min: $flatline_min,
                    flatline_consecutive: $flatline_consec
                },
                safety_floors: {
                    max_cycles: 50,
                    max_cost_cents: 10000,
                    max_wall_clock_seconds: 86400
                }
            }'
        return 0
    fi

    # Clear any stale halt sentinel from a previous run. Without this,
    # the first evaluate_stopping_conditions() call in the new spiral
    # would instantly report hitl_halt as a ghost-halt. Review feedback.
    rm -f "$HALT_SENTINEL"

    local spiral_id
    spiral_id=$(init_state \
        "$max_cycles" "$budget_cents" "$wall_clock_seconds" \
        "$flatline_min" "$flatline_consec")

    log_trajectory "spiral_started" "$(jq -n --arg id "$spiral_id" '{spiral_id: $id}')"

    # Init-only mode: return after state creation (for tests + internal use)
    if [[ "$init_only" == "true" ]]; then
        jq -n \
            --arg id "$spiral_id" \
            --argjson max_cycles "$max_cycles" \
            '{started: true, spiral_id: $id, max_cycles: $max_cycles, init_only: true}'
        return 0
    fi

    # Record PID for guard (Flatline IMP-001)
    record_pid

    # Detect timeout availability (Bridgebuilder MEDIUM-2)
    require_timeout

    # Install crash trap (FR-9.2) — BEFORE loop (NFR-8)
    trap 'spiral_crash_handler $?' EXIT INT TERM ERR

    # Dispatch cycle loop (cycle-067: replaces MVP scaffolding)
    run_cycle_loop

    # Disable trap on normal exit
    trap - EXIT INT TERM ERR

    jq -n \
        --arg id "$spiral_id" \
        --argjson max_cycles "$max_cycles" \
        --arg state "$(jq -r '.state' "$STATE_FILE")" \
        --arg condition "$(jq -r '.stopping_condition // "none"' "$STATE_FILE")" \
        '{completed: true, spiral_id: $id, max_cycles: $max_cycles, state: $state, stopping_condition: $condition}'
}

cmd_status() {
    local json_mode=false
    [[ "${1:-}" == "--json" ]] && json_mode=true

    if [[ ! -f "$STATE_FILE" ]]; then
        if [[ "$json_mode" == "true" ]]; then
            echo '{"state": "NO_SPIRAL"}'
        else
            echo "No active spiral. Use --start to begin."
        fi
        return 0
    fi

    if [[ "$json_mode" == "true" ]]; then
        cat "$STATE_FILE"
    else
        local state phase cycle_index max_cycles spiral_id
        state=$(jq -r '.state' "$STATE_FILE")
        phase=$(jq -r '.phase' "$STATE_FILE")
        cycle_index=$(jq -r '.cycle_index' "$STATE_FILE")
        max_cycles=$(jq -r '.max_cycles' "$STATE_FILE")
        spiral_id=$(jq -r '.spiral_id' "$STATE_FILE")
        cat <<EOF
Spiral: $spiral_id
State:  $state
Phase:  $phase
Cycle:  $cycle_index / $max_cycles
EOF
    fi
}

cmd_halt() {
    local reason="operator_halt"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --reason) reason="$2"; shift 2 ;;
            *) error "Unknown --halt option: $1"; return 1 ;;
        esac
    done

    # Create the halt sentinel — next evaluate cycle will detect and terminate
    mkdir -p "$(dirname "$HALT_SENTINEL")"
    echo "$reason" > "$HALT_SENTINEL"

    # If a state file exists, coalesce to HALTED immediately
    if [[ -f "$STATE_FILE" ]]; then
        coalesce_spiral_terminal_state "HALTED" "$reason"
        log_trajectory "spiral_halted" "$(jq -n --arg reason "$reason" '{reason: $reason}')"
    fi

    jq -n --arg reason "$reason" '{halted: true, reason: $reason}'
}

cmd_resume() {
    if [[ ! -f "$STATE_FILE" ]]; then
        error "No spiral state to resume. Use --start."
        return 1
    fi

    local current_state
    current_state=$(jq -r '.state' "$STATE_FILE")

    case "$current_state" in
        RUNNING)
            # Check PID liveness — might be stale (orphan detection)
            local existing_pid
            existing_pid=$(jq -r '.pid // 0' "$STATE_FILE")
            if [[ "$existing_pid" -gt 0 ]] && kill -0 "$existing_pid" 2>/dev/null; then
                error "Spiral is already RUNNING (PID $existing_pid). No resume needed."
                return 3
            fi
            # Stale RUNNING → treat as crash
            log "Stale RUNNING detected (PID $existing_pid dead). Auto-coalescing to CRASHED."
            coalesce_spiral_terminal_state "CRASHED" "orphan_detected"
            current_state="CRASHED"
            ;;
        COMPLETED|FAILED)
            error "Cannot resume from terminal state: $current_state. Use --start for a new spiral."
            return 1
            ;;
    esac

    # Resumable states: HALTED, CRASHED
    if [[ "$current_state" != "HALTED" && "$current_state" != "CRASHED" ]]; then
        error "Cannot resume from state: $current_state"
        return 1
    fi

    # Clear halt sentinel
    rm -f "$HALT_SENTINEL"

    # Transition back to RUNNING
    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    atomic_state_write --arg ts "$timestamp" '
        .state = "RUNNING" |
        .stopping_condition = null |
        .timestamps.completed_at = null |
        .timestamps.last_activity = $ts
    '

    # Record new PID
    record_pid

    log_trajectory "spiral_resumed" \
        "$(jq -n --arg from "$current_state" '{from_state: $from}')"

    # Detect timeout availability
    require_timeout

    # Install crash trap
    trap 'spiral_crash_handler $?' EXIT INT TERM ERR

    # Resume cycle loop from where it left off
    run_cycle_loop

    trap - EXIT INT TERM ERR

    jq -n \
        --arg state "$(jq -r '.state' "$STATE_FILE")" \
        --arg condition "$(jq -r '.stopping_condition // "none"' "$STATE_FILE")" \
        '{resumed: true, completed: true, state: $state, stopping_condition: $condition}'
}

cmd_check_stop() {
    if [[ ! -f "$STATE_FILE" ]]; then
        echo '{"stop": false, "reason": "no_state"}'
        return 0
    fi

    local condition
    condition=$(evaluate_stopping_conditions)

    if [[ -n "$condition" ]]; then
        jq -n --arg c "$condition" '{stop: true, condition: $c}'
        return 0
    fi
    echo '{"stop": false}'
}

# =============================================================================
# CLI
# =============================================================================

usage() {
    sed -n '/^# Usage:/,/^# State machine/p' "${BASH_SOURCE[0]}" \
        | sed -e '/^# State machine/d' -e 's/^# \{0,1\}//'
}

main() {
    local cmd="${1:-}"
    shift 2>/dev/null || true

    case "$cmd" in
        --start) cmd_start "$@" ;;
        --status) cmd_status "$@" ;;
        --halt) cmd_halt "$@" ;;
        --resume) cmd_resume ;;
        --check-stop) cmd_check_stop ;;
        -h|--help|help|"")
            usage
            [[ -z "$cmd" ]] && exit 1 || exit 0
            ;;
        *)
            error "Unknown command: $cmd"
            usage >&2
            exit 1
            ;;
    esac
}

# Only run main when executed directly (not sourced for testing)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
