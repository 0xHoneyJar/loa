#!/usr/bin/env bash
# =============================================================================
# spiral-harness.sh — Evidence-Gated Orchestrator for /spiral
# =============================================================================
# Version: 1.1.0
# Part of: Spiral Harness Architecture (cycle-071, cost optimization cycle-072)
#
# Replaces monolithic claude -p dispatch with sequenced phases + evidence gates.
# Each phase is a separate claude -p call. Quality gates run in bash (unskippable).
# Flight recorder logs every action with checksums and costs.
#
# Pipeline Profiles (cycle-072):
#   full     = all 3 Flatline gates + Opus advisor ($15)
#   standard = Sprint Flatline only + Opus advisor ($12) [DEFAULT]
#   light    = no Flatline + Sonnet advisor ($8)
#
# "The orchestrator controls the loop. The model does targeted work." — Harness Engineering
#
# Usage:
#   spiral-harness.sh --task "Build X" --cycle-dir .run/cycles/cycle-1 \
#     --cycle-id cycle-1 --branch feat/spiral-xxx-cycle-1 --budget 10 \
#     [--seed-context path/to/seed.md] [--profile standard]
#
# Exit codes:
#   0   — Success (PR created, all gates passed)
#   1   — Gate failure (circuit breaker tripped)
#   2   — Invalid arguments
#   3   — Budget exceeded
#   127 — claude CLI not found
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source dependencies
source "$SCRIPT_DIR/bootstrap.sh" 2>/dev/null || true
source "$SCRIPT_DIR/spiral-evidence.sh"

# =============================================================================
# Configuration
# =============================================================================

_read_harness_config() {
    local key="$1" default="$2"
    local config="${PROJECT_ROOT:-.}/.loa.config.yaml"
    [[ ! -f "$config" ]] && { echo "$default"; return 0; }
    local value
    value=$(yq eval ".$key // null" "$config" 2>/dev/null || echo "null")
    [[ "$value" == "null" || -z "$value" ]] && { echo "$default"; return 0; }
    echo "$value"
}

MAX_RETRIES=$(_read_harness_config "spiral.harness.max_phase_retries" "3")
PLANNING_BUDGET=$(_read_harness_config "spiral.harness.planning_budget_usd" "1")
IMPLEMENT_BUDGET=$(_read_harness_config "spiral.harness.implement_budget_usd" "5")
REVIEW_BUDGET=$(_read_harness_config "spiral.harness.review_budget_usd" "2")
AUDIT_BUDGET=$(_read_harness_config "spiral.harness.audit_budget_usd" "2")

# Advisor Strategy (cycle-071): Sonnet executes, Opus judges
EXECUTOR_MODEL=$(_read_harness_config "spiral.harness.executor_model" "sonnet")
ADVISOR_MODEL=$(_read_harness_config "spiral.harness.advisor_model" "opus")

# Pipeline Profiles (cycle-072): match intensity to task complexity
# full    = all 3 Flatline gates + Opus advisor ($15, architecture/security)
# standard = Sprint Flatline only + Opus advisor ($12, most features) [DEFAULT]
# light   = no Flatline + Sonnet advisor ($8, bug fixes/flags/config)
PIPELINE_PROFILE=$(_read_harness_config "spiral.harness.pipeline_profile" "standard")
FLATLINE_GATES=""
_PROFILE_EXPLICITLY_SET=false

# Resolve profile to concrete settings
_resolve_profile() {
    case "$PIPELINE_PROFILE" in
        full)
            FLATLINE_GATES="prd,sdd,sprint"
            ;;
        standard)
            FLATLINE_GATES="sprint"
            ;;
        light)
            FLATLINE_GATES=""
            ADVISOR_MODEL="$EXECUTOR_MODEL"  # Sonnet reviews too
            ;;
        *)
            log "Unknown profile '$PIPELINE_PROFILE', falling back to standard"
            PIPELINE_PROFILE="standard"
            FLATLINE_GATES="sprint"
            ;;
    esac
}
_resolve_profile

# Check if a Flatline gate should run for the given phase
_should_run_flatline() {
    local phase="$1"
    [[ ",$FLATLINE_GATES," == *",$phase,"* ]]
}

# Auto-escalation classifier (cycle-072, Bridgebuilder HIGH-1: runs at startup)
# Escalates light/standard → full when security/system/schema paths detected
_auto_escalate_profile() {
    local task="$1"
    local escalation_reason=""

    # Skip if operator explicitly set --profile (operator has final say)
    [[ "$_PROFILE_EXPLICITLY_SET" == "true" ]] && return 0

    # Pattern-based escalation from task description
    if echo "$task" | grep -qiE 'auth|crypto|secret|token|key|cert|permission|security'; then
        escalation_reason="security-keyword-in-task"
    fi

    # Sprint plan path check (if exists at startup)
    if [[ -z "$escalation_reason" && -f "grimoires/loa/sprint.md" ]]; then
        if grep -qiE '\.claude/scripts|\.claude/protocols|auth|crypto|migration|schema' \
            "grimoires/loa/sprint.md" 2>/dev/null; then
            escalation_reason="security-path-in-sprint-plan"
        fi
    fi

    if [[ -n "$escalation_reason" && "$PIPELINE_PROFILE" != "full" ]]; then
        log "Auto-escalating profile: $PIPELINE_PROFILE → full (reason: $escalation_reason)"
        _record_action "CONFIG" "auto-escalation" "profile_escalated" "" "" "" 0 0 0 \
            "from=$PIPELINE_PROFILE to=full reason=$escalation_reason"
        PIPELINE_PROFILE="full"
        _resolve_profile
    fi

    # Conservative default: if no diff available and profile is light, escalate to standard
    if [[ "$PIPELINE_PROFILE" == "light" ]]; then
        if ! git rev-parse --verify "main" &>/dev/null; then
            log "Auto-escalating light → standard (no main branch for diff)"
            _record_action "CONFIG" "auto-escalation" "profile_escalated" "" "" "" 0 0 0 \
                "from=light to=standard reason=no-diff-available"
            PIPELINE_PROFILE="standard"
            _resolve_profile
        fi
    fi
}

log() { echo "[harness] $*" >&2; }
error() { echo "ERROR: $*" >&2; }

# =============================================================================
# Argument Parsing
# =============================================================================

TASK=""
CYCLE_DIR=""
CYCLE_ID=""
BRANCH=""
TOTAL_BUDGET=10
SEED_CONTEXT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --task) TASK="$2"; shift 2 ;;
        --cycle-dir) CYCLE_DIR="$2"; shift 2 ;;
        --cycle-id) CYCLE_ID="$2"; shift 2 ;;
        --branch) BRANCH="$2"; shift 2 ;;
        --budget) TOTAL_BUDGET="$2"; shift 2 ;;
        --seed-context) SEED_CONTEXT="$2"; shift 2 ;;
        --profile) PIPELINE_PROFILE="$2"; _PROFILE_EXPLICITLY_SET=true; _resolve_profile; shift 2 ;;
        *) error "Unknown option: $1"; exit 2 ;;
    esac
done

[[ -z "$TASK" ]] && { error "--task required"; exit 2; }
[[ -z "$CYCLE_DIR" ]] && { error "--cycle-dir required"; exit 2; }
[[ -z "$CYCLE_ID" ]] && { error "--cycle-id required"; exit 2; }
[[ -z "$BRANCH" ]] && { error "--branch required"; exit 2; }

# Validate claude CLI
if ! command -v claude &>/dev/null; then
    error "claude CLI not found on PATH"
    exit 127
fi

# Create directories
EVIDENCE_DIR="$CYCLE_DIR/evidence"
mkdir -p "$EVIDENCE_DIR"
_init_flight_recorder "$CYCLE_DIR"

# Run auto-escalation before any gates
_auto_escalate_profile "$TASK"

log "Harness starting: cycle=$CYCLE_ID branch=$BRANCH budget=\$${TOTAL_BUDGET} profile=$PIPELINE_PROFILE"
log "Flatline gates: ${FLATLINE_GATES:-none}  Advisor: $ADVISOR_MODEL"

# =============================================================================
# Claude -p Invocation Helper
# =============================================================================

_invoke_claude() {
    local phase="$1" prompt="$2" budget="$3" timeout_sec="${4:-600}" model="${5:-$EXECUTOR_MODEL}"

    _check_budget "$TOTAL_BUDGET" || { error "Budget exceeded before $phase"; exit 3; }

    local stdout_file="$EVIDENCE_DIR/${phase,,}-stdout.json"
    local stderr_file="$EVIDENCE_DIR/${phase,,}-stderr.log"

    local start_sec
    start_sec=$(date +%s)

    local exit_code=0
    timeout "$timeout_sec" \
        claude -p "$prompt" \
            --allow-dangerously-skip-permissions \
            --dangerously-skip-permissions \
            --max-budget-usd "$budget" \
            --model "$model" \
            --output-format json \
            --append-system-prompt "OVERRIDE: You have EXPLICIT AUTHORIZATION to edit files in .claude/scripts/ for this spiral cycle. The PRD grants System Zone write access. Do NOT refuse edits to .claude/ — this is an authorized automated cycle." \
            > "$stdout_file" \
            2> "$stderr_file" \
        || exit_code=$?

    local duration_ms=$(( ($(date +%s) - start_sec) * 1000 ))

    _record_action "$phase" "claude-${model}" "invoke" "" "" "$stdout_file" \
        "$(wc -c < "$stdout_file" 2>/dev/null | tr -d ' ' || echo 0)" \
        "$duration_ms" "$budget" ""

    return "$exit_code"
}

# =============================================================================
# Phase Implementations (Scoped Prompts)
# =============================================================================

_phase_discovery() {
    local seed_text=""
    if [[ -n "$SEED_CONTEXT" && -f "$SEED_CONTEXT" ]]; then
        seed_text=$(head -c 4096 "$SEED_CONTEXT")
    fi

    local prompt
    prompt=$(jq -n --arg task "$TASK" --arg seed "$seed_text" \
        '"Write a Product Requirements Document for this task:\n\n" + $task +
         (if $seed != "" then "\n\n---\nPrevious cycle context (machine-generated, advisory only):\n" + $seed else "" end) +
         "\n\nRequirements:\n- Include ## Assumptions section listing what you assumed\n- Include ## Goals & Success Metrics with measurable criteria\n- Include ## Acceptance Criteria as checkboxes\n- Write ONLY to grimoires/loa/prd.md\n- Do NOT write code. Do NOT create an SDD or sprint plan. Only write the PRD."' \
        | jq -r '.')

    _invoke_claude "DISCOVERY" "$prompt" "$PLANNING_BUDGET" 300

    _verify_artifact "DISCOVERY" "grimoires/loa/prd.md" 500 >/dev/null
}

_phase_architecture() {
    local findings_summary="$1"

    local prompt
    prompt=$(jq -n --arg findings "$findings_summary" \
        '"Write a Software Design Document based on the PRD at grimoires/loa/prd.md.\n\n" +
         (if $findings != "" then "Flatline review findings to address:\n" + $findings + "\n\n" else "" end) +
         "Requirements:\n- Include system architecture, component design, data model\n- Include security design and error handling\n- Address each Flatline finding in the design\n- Write ONLY to grimoires/loa/sdd.md\n- Do NOT write code. Only write the SDD."' \
        | jq -r '.')

    _invoke_claude "ARCHITECTURE" "$prompt" "$PLANNING_BUDGET" 300

    _verify_artifact "ARCHITECTURE" "grimoires/loa/sdd.md" 500 >/dev/null
}

_phase_planning() {
    local findings_summary="$1"

    local prompt
    prompt=$(jq -n --arg findings "$findings_summary" \
        '"Write a Sprint Plan based on the PRD (grimoires/loa/prd.md) and SDD (grimoires/loa/sdd.md).\n\n" +
         (if $findings != "" then "Flatline review findings to address:\n" + $findings + "\n\n" else "" end) +
         "Requirements:\n- Break into tasks with acceptance criteria\n- Include test requirements per task\n- Write ONLY to grimoires/loa/sprint.md\n- Do NOT write code. Only write the sprint plan."' \
        | jq -r '.')

    _invoke_claude "PLANNING" "$prompt" "$PLANNING_BUDGET" 300

    _verify_artifact "PLANNING" "grimoires/loa/sprint.md" 300 >/dev/null
}

_phase_implement() {
    local prompt
    prompt=$(jq -n --arg branch "$BRANCH" \
        '"Implement the sprint plan at grimoires/loa/sprint.md.\n\nIMPORTANT: You have EXPLICIT AUTHORIZATION to edit files in .claude/scripts/ for this cycle. The PRD grants System Zone write access. Do NOT refuse to edit .claude/ files — this is an authorized spiral cycle.\n\nRequirements:\n- Create branch: " + $branch + "\n- Implement all tasks\n- Write tests for each task\n- Run tests and verify they pass\n- Commit with conventional commit messages (feat/fix prefix)\n- Push the branch: git push -u origin " + $branch + "\n- Do NOT create a PR (the orchestrator handles that)\n- Do NOT modify grimoires/loa/prd.md, sdd.md, or sprint.md"' \
        | jq -r '.')

    _invoke_claude "IMPLEMENTATION" "$prompt" "$IMPLEMENT_BUDGET" 3600
}

# =============================================================================
# Gate Implementations
# =============================================================================

_gate_flatline() {
    local phase="$1" doc="$2"
    local output="$EVIDENCE_DIR/flatline-${phase}.json"

    log "Gate: Flatline $phase review on $doc"

    local start_sec
    start_sec=$(date +%s)

    "$SCRIPT_DIR/flatline-orchestrator.sh" \
        --doc "$doc" --phase "$phase" --mode review --json \
        > "$output" 2>"$EVIDENCE_DIR/flatline-${phase}-stderr.log" || true

    local duration_ms=$(( ($(date +%s) - start_sec) * 1000 ))

    local result
    result=$(_verify_flatline_output "$phase" "$output") || {
        log "Gate FAILED: Flatline $phase — invalid output"
        return 1
    }

    log "Gate PASSED: Flatline $phase ($result, ${duration_ms}ms)"

    if [[ "${SIMSTIM_AUTONOMOUS:-0}" == "1" ]]; then
        local blockers
        blockers=$(jq '.consensus_summary.blocker_count // 0' "$output")
        if [[ "$blockers" -gt 0 ]]; then
            log "Arbiter: $blockers blockers to arbitrate"
        fi
    fi

    return 0
}

_gate_review() {
    local feedback_path="grimoires/loa/a2a/engineer-feedback.md"

    log "Gate: Independent review (fresh session, model=$ADVISOR_MODEL)"

    local diff
    diff=$(git diff main..."$BRANCH" -- ':!grimoires/' ':!.run/' ':!.beads/' 2>/dev/null | head -c 50000 || echo "No diff available")

    local prompt
    prompt=$(jq -n --arg diff "$diff" \
        '"You are a senior tech lead reviewer. Review this implementation independently.\n\nGit diff:\n```\n" + $diff + "\n```\n\nRead grimoires/loa/sprint.md for acceptance criteria.\nFor each AC, verify it is met with file:line evidence.\n\nWrite your review to grimoires/loa/a2a/engineer-feedback.md\nWrite \"All good\" if approved, or \"CHANGES_REQUIRED\" with specific issues.\n\nDo NOT modify any code. Only review and write feedback."' \
        | jq -r '.')

    _invoke_claude "REVIEW" "$prompt" "$REVIEW_BUDGET" 600 "$ADVISOR_MODEL"

    _verify_review_verdict "REVIEW" "$feedback_path"
}

_gate_audit() {
    local feedback_path="grimoires/loa/a2a/auditor-sprint-feedback.md"

    log "Gate: Independent security audit (fresh session, model=$ADVISOR_MODEL)"

    local diff
    diff=$(git diff main..."$BRANCH" -- ':!grimoires/' ':!.run/' ':!.beads/' 2>/dev/null | head -c 50000 || echo "No diff available")

    local prompt
    prompt=$(jq -n --arg diff "$diff" \
        '"You are a security auditor. Audit this implementation for security issues.\n\nGit diff:\n```\n" + $diff + "\n```\n\nCheck:\n- No hardcoded secrets\n- Input validation on all external inputs\n- No command injection (jq --arg, not string interpolation)\n- Proper file permissions\n- No path traversal\n\nWrite audit to grimoires/loa/a2a/auditor-sprint-feedback.md\nWrite \"APPROVED\" if no critical issues, or \"CHANGES_REQUIRED\" with findings.\n\nDo NOT modify any code. Only audit and write feedback."' \
        | jq -r '.')

    _invoke_claude "AUDIT" "$prompt" "$AUDIT_BUDGET" 600 "$ADVISOR_MODEL"

    _verify_review_verdict "AUDIT" "$feedback_path"
}

_gate_bridgebuilder() {
    log "Gate: Bridgebuilder PR review"

    local pr_url="$1"
    [[ -z "$pr_url" ]] && { log "No PR URL for Bridgebuilder, skipping"; return 0; }

    local pr_number
    pr_number=$(echo "$pr_url" | grep -oE '[0-9]+$')
    [[ -z "$pr_number" ]] && { log "Could not extract PR number, skipping"; return 0; }

    local entry_script="$SCRIPT_DIR/../skills/bridgebuilder-review/resources/entry.sh"
    if [[ -x "$entry_script" ]]; then
        "$entry_script" --pr "$pr_number" 2>"$EVIDENCE_DIR/bridgebuilder-stderr.log" || true
        _record_action "GATE_BRIDGEBUILDER" "bridgebuilder" "pr_review" "" "" "" 0 0 0 "posted"
    else
        log "Bridgebuilder not available, skipping"
    fi
}

# =============================================================================
# Gate Runner with Retry + Circuit Breaker
# =============================================================================

_run_gate() {
    local gate_name="$1"; shift
    local attempt=0

    while [[ $attempt -lt $MAX_RETRIES ]]; do
        attempt=$((attempt + 1))
        log "Gate: $gate_name (attempt $attempt/$MAX_RETRIES)"

        if "$@"; then
            return 0
        fi

        if [[ $attempt -lt $MAX_RETRIES ]]; then
            log "Gate $gate_name failed (attempt $attempt), will retry..."
            sleep 2
        fi
    done

    _record_failure "$gate_name" "CIRCUIT_BREAKER" "Failed after $MAX_RETRIES attempts"
    error "Circuit breaker: $gate_name failed after $MAX_RETRIES attempts"
    return 1
}

# =============================================================================
# Main Pipeline
# =============================================================================

main() {
    local pr_url=""
    local prd_findings="" sdd_findings=""

    _record_action "CONFIG" "spiral-harness" "profile" "" "" "" 0 0 0 \
        "profile=$PIPELINE_PROFILE gates=${FLATLINE_GATES:-none} advisor=$ADVISOR_MODEL"

    # ── Phase 1: Discovery ──────────────────────────────────────────────
    log "Phase 1: DISCOVERY"
    _phase_discovery || { error "Discovery failed"; exit 1; }

    # ── Gate 1: Flatline PRD (conditional) ──────────────────────────────
    if _should_run_flatline "prd"; then
        _run_gate "FLATLINE_PRD" _gate_flatline "prd" "grimoires/loa/prd.md" || exit 1
        prd_findings=$(_summarize_flatline "$EVIDENCE_DIR/flatline-prd.json")
    else
        log "Skipping Flatline PRD (profile=$PIPELINE_PROFILE)"
        _record_action "GATE_prd" "spiral-harness" "skipped" "" "" "" 0 0 0 "profile=$PIPELINE_PROFILE"
    fi

    # ── Phase 2: Architecture ───────────────────────────────────────────
    log "Phase 2: ARCHITECTURE"
    _phase_architecture "$prd_findings" || { error "Architecture failed"; exit 1; }

    # ── Gate 2: Flatline SDD (conditional) ──────────────────────────────
    if _should_run_flatline "sdd"; then
        _run_gate "FLATLINE_SDD" _gate_flatline "sdd" "grimoires/loa/sdd.md" || exit 1
        sdd_findings=$(_summarize_flatline "$EVIDENCE_DIR/flatline-sdd.json")
    else
        log "Skipping Flatline SDD (profile=$PIPELINE_PROFILE)"
        _record_action "GATE_sdd" "spiral-harness" "skipped" "" "" "" 0 0 0 "profile=$PIPELINE_PROFILE"
    fi

    # ── Phase 3: Planning ───────────────────────────────────────────────
    log "Phase 3: PLANNING"
    _phase_planning "$sdd_findings" || { error "Planning failed"; exit 1; }

    # ── Gate 3: Flatline Sprint (conditional) ───────────────────────────
    if _should_run_flatline "sprint"; then
        _run_gate "FLATLINE_SPRINT" _gate_flatline "sprint" "grimoires/loa/sprint.md" || exit 1
    else
        log "Skipping Flatline Sprint (profile=$PIPELINE_PROFILE)"
        _record_action "GATE_sprint" "spiral-harness" "skipped" "" "" "" 0 0 0 "profile=$PIPELINE_PROFILE"
    fi

    # ── Pre-check: Deterministic validation before Implementation ───────
    log "Pre-check: validating planning artifacts"
    if ! _pre_check_implementation; then
        error "Pre-check failed: planning artifacts incomplete"
        exit 1
    fi

    # ── Phase 4: Implementation ─────────────────────────────────────────
    log "Phase 4: IMPLEMENTATION"
    _phase_implement || { error "Implementation failed"; exit 1; }

    # ── Post-implementation auto-escalation check ───────────────────────
    if git diff "main...${BRANCH}" --name-only 2>/dev/null | \
        grep -qiE '(auth|crypto|secrets|\.claude/scripts|\.claude/protocols|schema\.json|migrations|deploy)'; then
        if [[ "$PIPELINE_PROFILE" != "full" ]]; then
            log "WARNING: Implementation touched security-sensitive paths but profile=$PIPELINE_PROFILE (not full)"
            _record_action "CONFIG" "auto-escalation" "post_impl_warning" "" "" "" 0 0 0 \
                "profile=$PIPELINE_PROFILE paths_touched=security advisory=consider-full-profile-next-cycle"
        fi
    fi

    # ── Pre-check: Deterministic validation before Review ───────────────
    log "Pre-check: validating implementation before review"
    if ! _pre_check_review; then
        error "Pre-check failed: implementation has structural issues"
        exit 1
    fi

    # ── Gate 4: Independent Review (fresh session) ──────────────────────
    _run_gate "REVIEW" _gate_review || {
        log "Review CHANGES_REQUIRED — implementation needs work"
        exit 1
    }

    # ── Gate 5: Independent Audit (fresh session) ───────────────────────
    _run_gate "AUDIT" _gate_audit || {
        log "Audit CHANGES_REQUIRED — security issues found"
        exit 1
    }

    # ── Phase 5: PR Creation (idempotent — check before create) ─────────
    log "Phase 5: PR CREATION"
    local existing_pr
    existing_pr=$(gh pr list --head "$BRANCH" --json number,url --jq '.[0].url // empty' 2>/dev/null || true)

    if [[ -n "$existing_pr" ]]; then
        pr_url="$existing_pr"
        log "Reusing existing PR: $pr_url"
        local pr_number
        pr_number=$(echo "$pr_url" | grep -oE '[0-9]+$')
        gh api "repos/{owner}/{repo}/pulls/$pr_number" -X PATCH \
            -f body="Autonomous spiral cycle (updated). Profile: $PIPELINE_PROFILE. See flight recorder." \
            --jq '.html_url' 2>/dev/null || true
        _record_action "PR_CREATION" "gh-cli" "reused_pr" "" "" "" 0 0 0 "$pr_url"
    else
        pr_url=$(gh pr create \
            --title "feat($CYCLE_ID): $(echo "$TASK" | head -c 60)" \
            --body "Autonomous spiral cycle. Profile: $PIPELINE_PROFILE. See flight recorder for evidence trail." \
            --draft 2>/dev/null || true)
        if [[ -n "$pr_url" ]]; then
            _record_action "PR_CREATION" "gh-cli" "create_pr" "" "" "" 0 0 0 "$pr_url"
            log "PR created: $pr_url"
        else
            log "WARNING: PR creation failed, continuing"
        fi
    fi

    # ── Gate 6: Bridgebuilder (advisory, not blocking) ──────────────────
    _gate_bridgebuilder "$pr_url"

    # ── Cost sidecar (cycle-072: cross-cycle reconciliation) ────────────
    local total_cost
    total_cost=$(_get_cumulative_cost)
    local cost_sidecar="$CYCLE_DIR/cycle-cost.json"
    local cost_tmp="${cost_sidecar}.tmp"
    jq -n --argjson cost "$total_cost" --arg profile "$PIPELINE_PROFILE" \
        '{cycle_cost_usd: $cost, profile: $profile, source: "flight_recorder"}' \
        > "$cost_tmp" && mv "$cost_tmp" "$cost_sidecar"

    # ── Finalize ────────────────────────────────────────────────────────
    _finalize_flight_recorder "$CYCLE_DIR"

    log "Harness complete: cycle=$CYCLE_ID profile=$PIPELINE_PROFILE cost=\$${total_cost}"
    log "Flight recorder: $CYCLE_DIR/flight-recorder.jsonl"
    log "Evidence: $EVIDENCE_DIR/"
    [[ -n "$pr_url" ]] && log "PR: $pr_url"

    echo "$pr_url"
}

main
