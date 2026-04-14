#!/usr/bin/env bash
# =============================================================================
# spiral-evidence.sh — Evidence verification + Flight Recorder for Spiral Harness
# =============================================================================
# Version: 1.1.0
# Part of: Spiral Harness Architecture (cycle-071, cost optimization cycle-072)
#
# Provides:
#   - Append-only flight recorder (JSONL)
#   - Artifact verification (checksum, size, structure)
#   - Flatline output validation
#   - Review/audit verdict parsing
#   - Cumulative cost tracking
#
# Usage:
#   source spiral-evidence.sh
#   _init_flight_recorder "/path/to/cycle-dir"
#   _record_action "PHASE" "actor" "action" ...
#   _verify_artifact "PHASE" "/path/to/file" 500
# =============================================================================

# Prevent double-sourcing
if [[ "${_SPIRAL_EVIDENCE_LOADED:-}" == "true" ]]; then
    return 0 2>/dev/null || exit 0
fi
_SPIRAL_EVIDENCE_LOADED=true

# =============================================================================
# Flight Recorder State
# =============================================================================

_FLIGHT_RECORDER=""
_FLIGHT_RECORDER_SEQ=0

# =============================================================================
# Flight Recorder — Append-Only JSONL
# =============================================================================

# Initialize flight recorder for a cycle
# Input: $1=cycle_dir
_init_flight_recorder() {
    local cycle_dir="$1"
    _FLIGHT_RECORDER="$cycle_dir/flight-recorder.jsonl"
    _FLIGHT_RECORDER_SEQ=0

    (umask 077 && touch "$_FLIGHT_RECORDER")
    chmod 600 "$_FLIGHT_RECORDER"
}

# Append an action entry to the flight recorder
# All values passed via jq --arg (safe, no shell expansion)
_record_action() {
    local phase="$1"
    local actor="$2"
    local action="$3"
    local input_checksum="${4:-}"
    local output_checksum="${5:-}"
    local output_path="${6:-}"
    local output_bytes="${7:-0}"
    local duration_ms="${8:-0}"
    local cost_usd="${9:-0}"
    local verdict="${10:-}"

    [[ -z "$_FLIGHT_RECORDER" ]] && return 1

    _FLIGHT_RECORDER_SEQ=$((_FLIGHT_RECORDER_SEQ + 1))

    # Validate numeric fields (prevent jq errors)
    [[ "$output_bytes" =~ ^[0-9]+$ ]] || output_bytes=0
    [[ "$duration_ms" =~ ^[0-9]+$ ]] || duration_ms=0
    # cost_usd can be decimal
    echo "$cost_usd" | grep -qE '^[0-9]+\.?[0-9]*$' || cost_usd=0

    jq -n -c \
        --argjson seq "$_FLIGHT_RECORDER_SEQ" \
        --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg phase "$phase" \
        --arg actor "$actor" \
        --arg action "$action" \
        --arg in_ck "$input_checksum" \
        --arg out_ck "$output_checksum" \
        --arg out_path "$output_path" \
        --argjson out_bytes "$output_bytes" \
        --argjson duration_ms "$duration_ms" \
        --argjson cost_usd "$cost_usd" \
        --arg verdict "$verdict" \
        '{
            seq: $seq,
            ts: $ts,
            phase: $phase,
            actor: $actor,
            action: $action,
            input_checksum: (if $in_ck == "" then null else $in_ck end),
            output_checksum: (if $out_ck == "" then null else $out_ck end),
            output_path: (if $out_path == "" then null else $out_path end),
            output_bytes: $out_bytes,
            duration_ms: $duration_ms,
            cost_usd: $cost_usd,
            verdict: (if $verdict == "" then null else $verdict end)
        }' >> "$_FLIGHT_RECORDER"
}

# Record a gate failure
_record_failure() {
    local phase="$1"
    local reason="$2"
    local detail="${3:-}"

    _record_action "$phase" "evidence-gate" "FAILED" "" "" "" 0 0 0 "FAIL:${reason}:${detail}"
}

# =============================================================================
# Artifact Verification
# =============================================================================

# Verify an artifact file exists, meets minimum size, and compute checksum
# Input: $1=phase, $2=artifact_path, $3=min_bytes (default 500)
# Output: sha256 checksum to stdout
# Returns: 0 if valid, 1 if not
_verify_artifact() {
    local phase="$1"
    local artifact="$2"
    local min_bytes="${3:-500}"

    if [[ ! -f "$artifact" ]]; then
        _record_failure "$phase" "MISSING_ARTIFACT" "$artifact"
        echo "ERROR: Artifact not found: $artifact" >&2
        return 1
    fi

    local bytes
    bytes=$(wc -c < "$artifact")
    if [[ "$bytes" -lt "$min_bytes" ]]; then
        _record_failure "$phase" "ARTIFACT_TOO_SMALL" "${bytes} < ${min_bytes}"
        echo "ERROR: Artifact too small: $artifact ($bytes bytes < $min_bytes min)" >&2
        return 1
    fi

    local checksum
    checksum=$(sha256sum "$artifact" | awk '{print $1}')

    # Record successful verification
    _record_action "$phase" "evidence-gate" "verified" "" "$checksum" "$artifact" "$bytes" 0 0 "OK"

    echo "$checksum"
}

# =============================================================================
# Flatline Output Verification
# =============================================================================

# Verify Flatline output is valid JSON with expected consensus structure
# Input: $1=phase, $2=flatline_output_path
# Output: "high=N blockers=M" to stdout
# Returns: 0 if valid, 1 if not
_verify_flatline_output() {
    local phase="$1"
    local output="$2"

    if [[ ! -f "$output" ]]; then
        _record_failure "$phase" "NO_FLATLINE_OUTPUT" "$output"
        echo "ERROR: Flatline output not found: $output" >&2
        return 1
    fi

    # Must be valid JSON
    if ! jq empty "$output" 2>/dev/null; then
        _record_failure "$phase" "INVALID_JSON" "$output"
        echo "ERROR: Invalid JSON in Flatline output: $output" >&2
        return 1
    fi

    # Must have consensus_summary
    if ! jq -e '.consensus_summary' "$output" >/dev/null 2>&1; then
        _record_failure "$phase" "NO_CONSENSUS" "$output"
        echo "ERROR: No consensus_summary in Flatline output" >&2
        return 1
    fi

    local high blockers
    high=$(jq '.consensus_summary.high_consensus_count // 0' "$output")
    blockers=$(jq '.consensus_summary.blocker_count // 0' "$output")

    local checksum
    checksum=$(sha256sum "$output" | awk '{print $1}')
    _record_action "GATE_${phase}" "flatline-orchestrator" "multi_model_review" \
        "" "$checksum" "$output" "$(wc -c < "$output")" 0 0 "high=${high} blockers=${blockers}"

    echo "high=$high blockers=$blockers"
}

# =============================================================================
# Review/Audit Verdict Verification
# =============================================================================

# Verify a review or audit feedback file contains a verdict
# Input: $1=phase_name ("REVIEW" or "AUDIT"), $2=feedback_file_path
# Returns: 0 if APPROVED, 1 if CHANGES_REQUIRED or missing
_verify_review_verdict() {
    local phase="$1"
    local feedback="$2"

    if [[ ! -f "$feedback" ]]; then
        _record_failure "$phase" "NO_FEEDBACK" "$feedback"
        echo "ERROR: Feedback file not found: $feedback" >&2
        return 1
    fi

    if grep -qi "All good\|APPROVED" "$feedback"; then
        local checksum
        checksum=$(sha256sum "$feedback" | awk '{print $1}')
        _record_action "GATE_${phase}" "claude-opus" "verdict" "" "$checksum" "$feedback" \
            "$(wc -c < "$feedback")" 0 0 "APPROVED"
        return 0
    elif grep -qi "CHANGES_REQUIRED\|Changes required" "$feedback"; then
        _record_action "GATE_${phase}" "claude-opus" "verdict" "" "" "$feedback" \
            "$(wc -c < "$feedback")" 0 0 "CHANGES_REQUIRED"
        return 1
    else
        _record_failure "$phase" "NO_VERDICT" "$feedback"
        echo "ERROR: No verdict found in: $feedback" >&2
        return 1
    fi
}

# =============================================================================
# Cost Tracking
# =============================================================================

# Get cumulative cost from all flight recorder entries
# Output: total cost as decimal to stdout
_get_cumulative_cost() {
    [[ -z "$_FLIGHT_RECORDER" || ! -f "$_FLIGHT_RECORDER" ]] && { echo "0"; return; }

    jq -s '[.[].cost_usd // 0] | add // 0' "$_FLIGHT_RECORDER" 2>/dev/null || echo "0"
}

# Check if cumulative cost exceeds budget
# Input: $1=max_budget_usd
# Returns: 0 if within budget, 1 if exceeded
_check_budget() {
    local max_budget="$1"
    local spent
    spent=$(_get_cumulative_cost)

    if jq -n --argjson spent "$spent" --argjson max "$max_budget" '$spent >= $max' 2>/dev/null | grep -q true; then
        _record_failure "BUDGET" "EXCEEDED" "spent=$spent max=$max_budget"
        echo "ERROR: Budget exceeded: \$${spent} >= \$${max_budget}" >&2
        return 1
    fi
    return 0
}

# =============================================================================
# Flatline Findings Summarization
# =============================================================================

# Summarize Flatline findings for cascading to next phase prompt
# Input: $1=flatline_json_path
# Output: human-readable summary to stdout
_summarize_flatline() {
    local flatline_json="$1"
    [[ -f "$flatline_json" ]] || { echo ""; return; }

    jq -r '
        "Flatline Review Findings:\n\n" +
        "AUTO-INTEGRATED (HIGH_CONSENSUS):\n" +
        (if (.high_consensus // []) | length > 0 then
            ([.high_consensus[] | "- " + (.description // "No description")] | join("\n"))
        else "- None" end) +
        "\n\nBLOCKERS/REJECTED:\n" +
        (if ((.arbiter_rejected // .blockers // []) | length) > 0 then
            ([(.arbiter_rejected // .blockers // [])[] | "- " + (.concern // .description // "No description")] | join("\n"))
        else "- None" end)
    ' "$flatline_json" 2>/dev/null || echo ""
}

# =============================================================================
# Deterministic Pre-Checks (cycle-072 cost optimization)
# Fail fast at $0 cost before spending $2-4 on LLM review/audit sessions.
# =============================================================================

# Validate planning artifacts exist before implementation phase
# Returns: 0 if ready, 1 if missing required artifacts
_pre_check_implementation() {
    local ok=0

    if [[ ! -f "grimoires/loa/prd.md" ]]; then
        echo "PRE-CHECK FAIL: grimoires/loa/prd.md not found" >&2
        ok=1
    fi
    if [[ ! -f "grimoires/loa/sdd.md" ]]; then
        echo "PRE-CHECK FAIL: grimoires/loa/sdd.md not found" >&2
        ok=1
    fi
    if [[ ! -f "grimoires/loa/sprint.md" ]]; then
        echo "PRE-CHECK FAIL: grimoires/loa/sprint.md not found" >&2
        ok=1
    fi

    # Sprint plan must have acceptance criteria (checkboxes)
    if [[ -f "grimoires/loa/sprint.md" ]]; then
        if ! grep -qE '^\- \[' "grimoires/loa/sprint.md" 2>/dev/null; then
            echo "PRE-CHECK WARN: sprint.md has no acceptance criteria checkboxes" >&2
        fi
    fi

    [[ -n "$_FLIGHT_RECORDER" ]] && \
        _record_action "PRE_CHECK" "evidence-gate" "implementation_ready" "" "" "" 0 0 0 \
            "$([ "$ok" -eq 0 ] && echo 'PASS' || echo 'FAIL')"

    return "$ok"
}

# Validate implementation output before spending $2-4 on LLM review/audit
# Checks: branch has commits, diff is non-empty, tests exist, no obvious secrets
# Returns: 0 if ready for review, 1 if structural issues detected
_pre_check_review() {
    local branch="${BRANCH:-HEAD}"
    local issues=0

    # 1. Branch has commits ahead of main
    local ahead
    ahead=$(git rev-list --count "main..${branch}" 2>/dev/null || echo "0")
    if [[ "$ahead" -eq 0 ]]; then
        echo "PRE-CHECK FAIL: no commits ahead of main on $branch" >&2
        issues=$((issues + 1))
    fi

    # 2. Git diff is non-empty (actual code changes exist)
    local diff_lines
    diff_lines=$(git diff "main...${branch}" --stat 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$diff_lines" -eq 0 ]]; then
        echo "PRE-CHECK FAIL: no diff between main and $branch" >&2
        issues=$((issues + 1))
    fi

    # 3. Tests exist in the diff (warn, not block)
    if ! git diff "main...${branch}" --name-only 2>/dev/null | grep -qiE 'test|spec|\.bats'; then
        echo "PRE-CHECK WARN: no test files in diff (expected for most tasks)" >&2
    fi

    # 4. No obvious secrets in diff (block on match)
    if git diff "main...${branch}" 2>/dev/null | \
        grep -qiE '(password|secret|api_key|private_key)\s*[:=]\s*["\x27][^"\x27]{8,}'; then
        echo "PRE-CHECK FAIL: possible secret detected in diff" >&2
        issues=$((issues + 1))
    fi

    [[ -n "$_FLIGHT_RECORDER" ]] && \
        _record_action "PRE_CHECK" "evidence-gate" "review_ready" "" "" "" 0 0 0 \
            "$([ "$issues" -eq 0 ] && echo 'PASS' || echo "FAIL:${issues}_issues")"

    [[ "$issues" -eq 0 ]]
}

# =============================================================================
# Finalization
# =============================================================================

# Finalize flight recorder with summary entry
_finalize_flight_recorder() {
    local cycle_dir="$1"

    local total_cost
    total_cost=$(_get_cumulative_cost)

    local total_actions
    total_actions=$(wc -l < "$_FLIGHT_RECORDER" 2>/dev/null | tr -d ' ' || echo "0")

    local failures
    failures=$(grep -c '"FAILED"' "$_FLIGHT_RECORDER" 2>/dev/null | tr -d ' ' || echo "0")

    _record_action "SUMMARY" "spiral-harness" "finalize" "" "" "" 0 0 "$total_cost" \
        "actions=${total_actions} failures=${failures} cost=${total_cost}"
}
