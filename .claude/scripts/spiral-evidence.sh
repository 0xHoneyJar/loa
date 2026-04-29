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
#   - Deterministic pre-checks (cycle-072: fail fast at $0)
#   - Secret scanning chain (cycle-072: gitleaks → trufflehog → regex)
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

_init_flight_recorder() {
    local cycle_dir="$1"
    _FLIGHT_RECORDER="$cycle_dir/flight-recorder.jsonl"
    _FLIGHT_RECORDER_SEQ=0

    (umask 077 && touch "$_FLIGHT_RECORDER")
    chmod 600 "$_FLIGHT_RECORDER"
}

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

    [[ "$output_bytes" =~ ^[0-9]+$ ]] || output_bytes=0
    [[ "$duration_ms" =~ ^[0-9]+$ ]] || duration_ms=0
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

_record_failure() {
    local phase="$1"
    local reason="$2"
    local detail="${3:-}"

    _record_action "$phase" "evidence-gate" "FAILED" "" "" "" 0 0 0 "FAIL:${reason}:${detail}"
}

# =============================================================================
# Artifact Verification
# =============================================================================

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

    _record_action "$phase" "evidence-gate" "verified" "" "$checksum" "$artifact" "$bytes" 0 0 "OK"

    echo "$checksum"
}

# =============================================================================
# Flatline Output Verification
# =============================================================================

_verify_flatline_output() {
    local phase="$1"
    local output="$2"

    if [[ ! -f "$output" ]]; then
        _record_failure "$phase" "NO_FLATLINE_OUTPUT" "$output"
        echo "ERROR: Flatline output not found: $output" >&2
        return 1
    fi

    if ! jq empty "$output" 2>/dev/null; then
        _record_failure "$phase" "INVALID_JSON" "$output"
        echo "ERROR: Invalid JSON in Flatline output: $output" >&2
        return 1
    fi

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

_get_cumulative_cost() {
    [[ -z "$_FLIGHT_RECORDER" || ! -f "$_FLIGHT_RECORDER" ]] && { echo "0"; return; }

    jq -s '[.[].cost_usd // 0] | add // 0' "$_FLIGHT_RECORDER" 2>/dev/null || echo "0"
}

_check_budget() {
    local max_budget="$1"
    local spent
    spent=$(_get_cumulative_cost)

    if jq -n --argjson spent "$spent" --argjson max "$max_budget" '$spent > $max' 2>/dev/null | grep -q true; then
        _record_failure "BUDGET" "EXCEEDED" "spent=$spent max=$max_budget"
        echo "ERROR: Budget exceeded: \$${spent} > \$${max_budget}" >&2
        return 1
    fi
    return 0
}

# =============================================================================
# Flatline Findings Summarization
# =============================================================================

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
# Deterministic Pre-Checks (cycle-072)
# Fail fast at $0 before spending $2-4 on LLM review/audit sessions.
# =============================================================================

# Validate planning artifacts exist before implementation phase
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

    # 2. Git diff is non-empty
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

    # 4. Secret scanning (gitleaks → trufflehog → regex fallback → allowlist)
    local secret_found=false
    if command -v gitleaks &>/dev/null; then
        if git diff "main...${branch}" 2>/dev/null | gitleaks detect --no-git --pipe 2>/dev/null; then
            secret_found=true
        fi
    elif command -v trufflehog &>/dev/null; then
        if trufflehog git "file://." --since-commit "$(git merge-base main "${branch}" 2>/dev/null)" \
            --only-verified --json 2>/dev/null | jq -e '.' >/dev/null 2>&1; then
            secret_found=true
        fi
    else
        # Regex fallback — only scan added lines (^+, excluding +++ headers)
        if git diff "main...${branch}" 2>/dev/null | \
            grep -E '^\+([^+]|$)' | \
            grep -qiE '(password|secret|api_key|private_key|aws_access_key_id)\s*[:=]\s*["'"'"'][^"'"'"']{8,}'; then
            secret_found=true
        fi
    fi

    # Check allowlist if secret found
    if [[ "$secret_found" == "true" ]]; then
        local allowlist="${PROJECT_ROOT:-.}/.claude/data/secret-scan-allowlist.yaml"
        if [[ -f "$allowlist" ]]; then
            # Check if all findings match allowlist patterns (simplified: if allowlist exists, downgrade to warning)
            local expired_count
            expired_count=$(yq eval '[.[] | select(.expires != null and .expires < now)] | length' "$allowlist" 2>/dev/null || echo "0")
            if [[ "$expired_count" -gt 0 ]]; then
                echo "PRE-CHECK WARN: $expired_count expired allowlist entries" >&2
            fi
            echo "PRE-CHECK WARN: potential secret detected but allowlist present — manual review recommended" >&2
        else
            echo "PRE-CHECK FAIL: possible secret detected in diff (no allowlist at $allowlist)" >&2
            issues=$((issues + 1))
        fi
    fi

    [[ -n "$_FLIGHT_RECORDER" ]] && \
        _record_action "PRE_CHECK" "evidence-gate" "review_ready" "" "" "" 0 0 0 \
            "$([ "$issues" -eq 0 ] && echo 'PASS' || echo "FAIL:${issues}_issues")"

    [[ "$issues" -eq 0 ]]
}



# =============================================================================
# SEED Pre-Check (#575 item 3)
# =============================================================================
#
# Validates environment invariants BEFORE the discovery phase dispatches,
# mirroring _pre_check_implementation / _pre_check_review which validate
# post-conditions for later phases. Catches classes of failure that are
# visible pre-dispatch but currently only surface as confusing mid-cycle
# errors.
#
# Empirical justification: cycle-084 CWD-mismatch (reviewer subprocess
# running in .loa/ submodule CWD vs main repo) was catchable pre-dispatch
# but currently surfaces as "grimoires/loa/prd.md not found" after discovery
# runs and writes to the wrong location.
#
# Checks (in order):
#   1. CWD is a git repository AND has grimoires/loa/ directory (hard-fail —
#      this is the cycle-084 class of defect)
#   2. Cycle dir is writable or creatable (hard-fail)
#   3. SEED_CONTEXT file exists when path provided (warn, not block — the
#      operator may have intended a standalone run)
#
# Returns 0 on pass (possibly with warnings), 1 on hard-fail.
#
# Usage:
#   _pre_check_seed <cycle_dir>
#
# Env:
#   SPIRAL_PRE_CHECK_SEED_STRICT=true — promote warnings to errors
_pre_check_seed() {
    local cycle_dir="${1:-}"
    local issues=0
    local warnings=0
    local strict="${SPIRAL_PRE_CHECK_SEED_STRICT:-false}"

    # 1. CWD must be a git repository root with grimoires/loa/ present.
    #    This is the cycle-084 failure: CWD was .loa/ (a submodule) not the
    #    main repo, so any grimoires/loa/prd.md write went to the wrong path.
    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "PRE-CHECK-SEED FAIL: CWD $(pwd) is not inside a git work tree" >&2
        issues=$((issues + 1))
    fi

    if [[ ! -d "grimoires/loa" ]]; then
        echo "PRE-CHECK-SEED FAIL: grimoires/loa/ not found from CWD $(pwd) — likely wrong CWD (cycle-084 class)" >&2
        issues=$((issues + 1))
    fi

    # 2. Cycle dir must exist or be creatable (check parent writable).
    if [[ -n "$cycle_dir" ]]; then
        if [[ ! -d "$cycle_dir" ]]; then
            local parent
            parent="$(dirname "$cycle_dir")"
            if [[ ! -d "$parent" ]]; then
                # Try to create it; if that fails, hard-fail
                if ! mkdir -p "$parent" 2>/dev/null; then
                    echo "PRE-CHECK-SEED FAIL: cannot create cycle parent: $parent" >&2
                    issues=$((issues + 1))
                fi
            elif [[ ! -w "$parent" ]]; then
                echo "PRE-CHECK-SEED FAIL: cycle parent not writable: $parent" >&2
                issues=$((issues + 1))
            fi
        elif [[ ! -w "$cycle_dir" ]]; then
            echo "PRE-CHECK-SEED FAIL: cycle dir not writable: $cycle_dir" >&2
            issues=$((issues + 1))
        fi
    fi

    # 3. SEED_CONTEXT file existence — warn if operator specified a path that's missing
    if [[ -n "${SEED_CONTEXT:-}" ]]; then
        if [[ ! -f "$SEED_CONTEXT" ]]; then
            echo "PRE-CHECK-SEED WARN: SEED_CONTEXT path does not resolve: $SEED_CONTEXT" >&2
            warnings=$((warnings + 1))
        elif [[ ! -r "$SEED_CONTEXT" ]]; then
            echo "PRE-CHECK-SEED WARN: SEED_CONTEXT file not readable: $SEED_CONTEXT" >&2
            warnings=$((warnings + 1))
        elif [[ ! -s "$SEED_CONTEXT" ]]; then
            echo "PRE-CHECK-SEED WARN: SEED_CONTEXT file is empty: $SEED_CONTEXT" >&2
            warnings=$((warnings + 1))
        fi
    fi

    # Strict mode: promote warnings to errors
    if [[ "$strict" == "true" ]]; then
        issues=$((issues + warnings))
    fi

    # Record trajectory (if flight recorder is active)
    [[ -n "${_FLIGHT_RECORDER:-}" ]] && \
        _record_action "PRE_CHECK_SEED" "evidence-gate" "seed_ready" "" "" "" 0 0 0 \
            "$([ "$issues" -eq 0 ] && echo "PASS:warnings=$warnings" || echo "FAIL:${issues}_issues_warnings=${warnings}")"

    [[ "$issues" -eq 0 ]]
}

# =============================================================================
# Phase-Current State File (cycle-092, Sprint 1 — #598/#599)
# =============================================================================
#
# `.phase-current` is a single-line tab-separated state file at
# $CYCLE_DIR/.phase-current indicating which harness phase is in-flight right
# now. Monitors (Sprint 4 heartbeat, Sprint 3 dashboard, external operator
# scripts) read it as the single truth source for "what phase now?" queries,
# avoiding the brittle dispatch.log grep pattern that stranded cycle-092's
# reference monitor at '⚙️ preparing' for 5 pulses.
#
# Format (see grimoires/loa/proposals/dispatch-log-grammar.md §.phase-current):
#   <phase_label>\t<start_ts>\t<attempt_num>\t<fix_iter>
#
# Lifecycle:
#   - _phase_current_write at phase START (overwrite semantics)
#   - _phase_current_touch when attempt/iter sub-state changes within a phase
#   - _phase_current_clear at phase EXIT and from EXIT trap on crash
#
# All helpers are fail-safe: missing cycle_dir, unwritable paths, or IO errors
# return non-zero without raising under `set -euo pipefail`. Follows the
# _pre_check_seed pattern (spiral-evidence.sh:387).

_phase_current_file() {
    local cycle_dir="${1:-}"
    [[ -z "$cycle_dir" ]] && return 1
    echo "$cycle_dir/.phase-current"
}

# _phase_current_write <cycle_dir> <phase_label> [attempt_num] [fix_iter]
#
# Overwrite .phase-current with a fresh phase record. start_ts is captured at
# call time (UTC ISO-8601). attempt_num and fix_iter default to "-" (hyphen)
# when unspecified, matching the grammar spec's "default when N/A" rule.
# Atomic via .tmp + mv.
_phase_current_write() {
    local cycle_dir="${1:-}"
    local phase_label="${2:-}"
    local attempt_num="${3:-}"
    local fix_iter="${4:-}"
    [[ -z "$cycle_dir" || -z "$phase_label" ]] && return 1
    # cycle-092 Sprint 1 review F-3: reject phase_label containing tab or
    # newline — the file format is tab-separated single-line, and corrupting
    # either would silently break downstream IFS=$'\t' read parsers in the
    # heartbeat (#598) and dashboard (#599) consumers.
    [[ "$phase_label" == *$'\t'* || "$phase_label" == *$'\n'* ]] && return 1
    [[ ! -d "$cycle_dir" ]] && return 1
    [[ -w "$cycle_dir" ]] || return 1

    local ts
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    [[ -z "$attempt_num" ]] && attempt_num="-"
    [[ -z "$fix_iter" ]] && fix_iter="-"

    local file tmp
    file="$(_phase_current_file "$cycle_dir")"
    tmp="$file.tmp"
    printf '%s\t%s\t%s\t%s\n' "$phase_label" "$ts" "$attempt_num" "$fix_iter" \
        > "$tmp" 2>/dev/null || return 1
    mv "$tmp" "$file" 2>/dev/null || return 1
    return 0
}

# _phase_current_touch <cycle_dir> [attempt_num] [fix_iter]
#
# Update attempt_num and/or fix_iter on an existing .phase-current record
# without disturbing phase_label or start_ts. Empty args preserve the existing
# value for that field. Returns 1 if .phase-current does not exist (no phase
# currently in-flight).
_phase_current_touch() {
    local cycle_dir="${1:-}"
    local new_attempt="${2:-}"
    local new_fix_iter="${3:-}"
    [[ -z "$cycle_dir" ]] && return 1

    local file
    file="$(_phase_current_file "$cycle_dir")"
    [[ -f "$file" && -w "$file" ]] || return 1

    local phase_label start_ts old_attempt old_fix_iter
    IFS=$'\t' read -r phase_label start_ts old_attempt old_fix_iter < "$file" 2>/dev/null || return 1
    # cycle-092 Sprint 1 review F-3: if the file already contains a corrupted
    # phase_label (tab/newline injected by a bypass of _phase_current_write's
    # validation), refuse to re-write — fail loud instead of propagating.
    [[ "$phase_label" == *$'\t'* || "$phase_label" == *$'\n'* ]] && return 1

    local attempt_out="${new_attempt:-$old_attempt}"
    local fix_out="${new_fix_iter:-$old_fix_iter}"

    local tmp="$file.tmp"
    printf '%s\t%s\t%s\t%s\n' "$phase_label" "$start_ts" "$attempt_out" "$fix_out" \
        > "$tmp" 2>/dev/null || return 1
    mv "$tmp" "$file" 2>/dev/null || return 1
    return 0
}

# _phase_current_clear <cycle_dir>
#
# Remove .phase-current. Called at phase-EXIT and from the EXIT trap in
# spiral-harness.sh main() so abnormal exits don't leave a stale in-flight
# signal for monitors. Idempotent — returns 0 even when the file is absent.
_phase_current_clear() {
    local cycle_dir="${1:-}"
    [[ -z "$cycle_dir" ]] && return 1
    local file
    file="$(_phase_current_file "$cycle_dir")"
    rm -f "$file" 2>/dev/null
    return 0
}

# _phase_current_read <cycle_dir> [field]
#
# Read .phase-current. Without a field arg, outputs the raw tab-separated
# line. With field (phase_label | start_ts | attempt_num | fix_iter), outputs
# the specific field's value. Returns 1 if .phase-current is missing.
_phase_current_read() {
    local cycle_dir="${1:-}"
    local field="${2:-}"
    [[ -z "$cycle_dir" ]] && return 1

    local file
    file="$(_phase_current_file "$cycle_dir")"
    [[ -f "$file" ]] || return 1

    if [[ -z "$field" ]]; then
        cat "$file" 2>/dev/null || return 1
        return 0
    fi

    local phase_label start_ts attempt_num fix_iter
    IFS=$'\t' read -r phase_label start_ts attempt_num fix_iter < "$file" 2>/dev/null || return 1

    case "$field" in
        phase_label) echo "$phase_label" ;;
        start_ts)    echo "$start_ts" ;;
        attempt_num) echo "$attempt_num" ;;
        fix_iter)    echo "$fix_iter" ;;
        *) return 1 ;;
    esac
    return 0
}

# =============================================================================
# Pre-Review Artifact-Coverage Evidence Gate (cycle-092 Sprint 2 — #600)
# =============================================================================
#
# Catches the cycle-091 defect class: IMPL subprocess commits "all N sprints
# complete" but silently omits SEED-enumerated visible-surface artefacts
# (Svelte scenes, Page components). Runs AFTER _phase_implement but BEFORE
# _pre_check_review so a targeted fix-loop can re-dispatch IMPL with a
# narrower "produce these N paths" prompt — cheaper and more deterministic
# than surfacing the gap via a 3-attempt semantic REVIEW that burns $60.
#
# Deterministic checks only: filesystem test -s. LLM input costs $0.

# _parse_sprint_paths <sprint_md> [sprint_id]
#
# Extract deliverable paths from a sprint.md file.
#
# Handles the two formats observed in cycles 082/091/092:
#   1. Backtick-wrapped paths containing at least one `/` (excludes bare
#      filename references like `\`spiral-harness.sh\`` which are prose):
#      `- [ ] \`src/lib/scenes/Reliquary.svelte\` — scene component`
#   2. Bare paths rooted at well-known repo prefixes (src/, tests/, etc.).
#
# If sprint_id is supplied (e.g. "sprint-2"), path extraction is scoped to
# the matching `## Sprint N:` section — prevents false-positives where a
# sprint.md enumerates deliverables for multiple sprints. Without sprint_id,
# the whole file is parsed (spiral-harness default, matches cycle-091 scope).
#
# Returns deduped paths via stdout, one per line. Missing or unreadable
# sprint_md returns 1 with no output.
_parse_sprint_paths() {
    local sprint_md="${1:-grimoires/loa/sprint.md}"
    local sprint_id="${2:-}"
    [[ -f "$sprint_md" && -r "$sprint_md" ]] || return 1

    # Scope content to a specific sprint section if sprint_id provided.
    # Matches `## Sprint N:` header; extraction runs until the next
    # `## Sprint` header or `---` separator or EOF. When a `### Deliverables`
    # subsection exists within that sprint, narrow further — prose references
    # (Technical Tasks, Risks, etc.) elsewhere in the section often mention
    # example paths that aren't actual deliverables.
    local content
    if [[ -n "$sprint_id" ]]; then
        local sprint_num="${sprint_id#sprint-}"
        local sprint_section
        sprint_section=$(awk -v n="$sprint_num" '
            $0 ~ "^## Sprint " n ":" { in_section=1; next }
            in_section && /^## Sprint [0-9]/ { in_section=0 }
            in_section && /^---$/ { in_section=0 }
            in_section { print }
        ' "$sprint_md" 2>/dev/null)
        [[ -z "$sprint_section" ]] && return 1

        # Look for a `### Deliverables` subsection and scope to it. If absent,
        # use the whole sprint section as a fallback (older sprint.md formats).
        local deliverables_section
        deliverables_section=$(echo "$sprint_section" | awk '
            /^### Deliverables[[:space:]]*$/ { in_deliv=1; next }
            in_deliv && /^### / { in_deliv=0 }
            in_deliv { print }
        ' 2>/dev/null)
        if [[ -n "$deliverables_section" ]]; then
            content="$deliverables_section"
        else
            content="$sprint_section"
        fi
    else
        content=$(cat "$sprint_md" 2>/dev/null) || return 1
    fi

    # Known source file extensions worth gating on. Markdown/yaml/json are
    # included so doc/config deliverables (e.g. grammar spec) are covered.
    local ext_re='(svelte|ts|tsx|js|jsx|vue|py|rs|go|sh|bats|md|yaml|yml|json)'

    {
        # Pattern 1: backtick-wrapped paths with at least one `/` before the
        # extension. The `/` requirement excludes bare filename prose like
        # `\`spiral-harness.sh\`` (which is a reference, not a deliverable
        # declaration). Accepts `.claude/scripts/...`, `src/...`, etc.
        echo "$content" | grep -oE "\`[^\`]*/[^\`]+\.${ext_re}\`" 2>/dev/null | \
            sed 's/^`//; s/`$//'
        # Pattern 2: bare paths rooted at well-known *top-level* repo prefixes.
        # Anchored to start-of-line or whitespace/non-path-char to prevent
        # substring matches within longer paths — without the anchor,
        # `src/lib/scenes/tests/foo.ts` would match both as `src/...` (full)
        # AND `tests/foo.ts` (substring). Leading boundary char is stripped.
        # Trailing charclass includes `/` (path separator), `.` (multi-dot
        # filenames like foo.test.ts), `+` (SvelteKit route convention like
        # +page.svelte), `()` (SvelteKit route groups like `(rooms)`).
        # Trailing `-` sits last in the class so it's literal, not a range.
        echo "$content" | grep -oE "(^|[^a-zA-Z0-9_/.-])(src|tests|\.claude/scripts|\.claude/hooks|grimoires)/[a-zA-Z0-9_/.+()-]+\.${ext_re}" \
            2>/dev/null | \
            sed -E 's/^[^a-zA-Z.]//'
    } | sort -u
}

# _pre_check_implementation_evidence [sprint_md]
#
# Validate that every sprint.md-enumerated deliverable path exists and is
# non-empty on disk AFTER the implementation phase committed. Emits a
# grammar-shaped `IMPL_EVIDENCE_MISSING` log line on failure with the
# missing-path list; advisory `IMPL_EVIDENCE_TRIVIAL` on paths present but
# suspiciously small. Records flight-recorder action for Sprint 4 heartbeat
# consumption.
#
# Returns:
#   0 — all enumerated paths present and non-trivial
#   0 with advisory — paths present, some flagged as trivial (advisory-only)
#   1 — at least one enumerated path is missing or empty
_pre_check_implementation_evidence() {
    local sprint_md="${1:-grimoires/loa/sprint.md}"
    local sprint_id="${2:-}"
    local missing=()
    local trivial=()

    # Parse sprint.md paths. If parsing fails (missing sprint.md or empty
    # sprint section), record and pass — absence of enumerated paths is an
    # upstream concern, not an evidence gap. BUT emit a distinct visible
    # signal so monitors can distinguish "gate ran, no input to check" from
    # "gate ran, all good" (Iter-7 BB F-007-opus fix: fail-open is fine,
    # fail-silent is not — Borgmon "no signal vs all-good signal" rule).
    local paths_raw
    paths_raw="$(_parse_sprint_paths "$sprint_md" "$sprint_id" 2>/dev/null || true)"
    if [[ -z "$paths_raw" ]]; then
        # Distinguish missing sprint.md from present-but-empty-deliverables.
        # Match the [harness]-prefix convention of MISSING/TRIVIAL signals
        # below — same emit pattern (echo to stderr) for monitor consistency.
        local reason
        if [[ ! -f "$sprint_md" ]]; then
            reason="sprint_md_not_found"
            echo "[harness] IMPL_EVIDENCE_NO_SPRINT_PLAN — sprint.md not found at $sprint_md (gate cannot enumerate deliverables; advisory only)" >&2
        else
            reason="no_enumerated_paths"
            echo "[harness] IMPL_EVIDENCE_NO_DELIVERABLES — sprint.md found but no deliverable paths enumerated (gate satisfied vacuously; advisory only)" >&2
        fi
        [[ -n "${_FLIGHT_RECORDER:-}" ]] && \
            _record_action "PRE_CHECK_IMPL_EVIDENCE" "evidence-gate" "artifact_coverage" "" "" "" 0 0 0 \
                "PASS:$reason"
        return 0
    fi

    # Classify each path: missing (not present or zero bytes) vs trivial
    # (present but <20 lines, or matches known-stub regex).
    local path line_count
    while IFS= read -r path; do
        [[ -z "$path" ]] && continue
        if [[ ! -s "$path" ]]; then
            missing+=("$path")
            continue
        fi
        # wc -l on stdin redirected from a file emits just the count (no
        # filename suffix). Use pure-bash whitespace strip to avoid depending
        # on `tr` being in PATH (some shell init contexts — notably zsh
        # sourced-in-function-scope — can mask it).
        line_count=$(wc -l < "$path" 2>/dev/null)
        line_count="${line_count// /}"
        line_count="${line_count:-0}"
        if [[ "$line_count" -lt 20 ]] || \
           grep -qE '^[[:space:]]*<script>[[:space:]]*</script>' "$path" 2>/dev/null || \
           grep -qE '^[[:space:]]*TODO[[:space:]]*$' "$path" 2>/dev/null; then
            trivial+=("$path")
        fi
    done <<< "$paths_raw"

    # Join arrays for log emission. Use IFS=, in a subshell so outer IFS stays
    # unchanged (set -u safe).
    local joined_missing="" joined_trivial=""
    if [[ ${#missing[@]} -gt 0 ]]; then
        joined_missing="$(IFS=,; echo "${missing[*]}")"
    fi
    if [[ ${#trivial[@]} -gt 0 ]]; then
        joined_trivial="$(IFS=,; echo "${trivial[*]}")"
    fi

    # Blocking: missing paths
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "[harness] IMPL_EVIDENCE_MISSING — ${#missing[@]} sprint-plan paths not produced: $joined_missing" >&2
        [[ -n "${_FLIGHT_RECORDER:-}" ]] && \
            _record_action "PRE_CHECK_IMPL_EVIDENCE" "evidence-gate" "artifact_coverage" "" "" "" 0 0 0 \
                "FAIL:${#missing[@]}_missing:${joined_missing}"
        return 1
    fi

    # Advisory: trivial paths present. Non-blocking; pass with annotation.
    if [[ ${#trivial[@]} -gt 0 ]]; then
        echo "[harness] IMPL_EVIDENCE_TRIVIAL — ${#trivial[@]} paths below content threshold: $joined_trivial" >&2
        [[ -n "${_FLIGHT_RECORDER:-}" ]] && \
            _record_action "PRE_CHECK_IMPL_EVIDENCE" "evidence-gate" "artifact_coverage" "" "" "" 0 0 0 \
                "PASS:${#trivial[@]}_trivial:${joined_trivial}"
        return 0
    fi

    # Happy path
    [[ -n "${_FLIGHT_RECORDER:-}" ]] && \
        _record_action "PRE_CHECK_IMPL_EVIDENCE" "evidence-gate" "artifact_coverage" "" "" "" 0 0 0 "PASS"
    return 0
}

# =============================================================================
# Finalization
# =============================================================================

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

    # Final dashboard snapshot so external consumers see the complete picture
    # without needing a live harness process.
    _emit_dashboard_snapshot "FINALIZED" "PHASE_EXIT" "$cycle_dir"
}

# =============================================================================
# Prior Cycle Failure Summary (#575 item 2)
# =============================================================================
#
# When a new spiral cycle starts, the previous cycle's flight-recorder.jsonl
# contains load-bearing failure events (circuit breakers, stuck findings,
# auto-escalations, exhausted fix-loops) that currently no downstream phase
# reads. The operator would have to hand-curate these into the SEED. These
# helpers extract and summarize them so the discovery phase can learn from
# prior failure modes automatically.
#
# Feature flag: spiral.seed.include_flight_recorder (default false — safe
# rollout; operators who want learning-across-cycles enable it explicitly).

# _find_prior_cycle — locate the most recent cycle directory that ran before
# the current one. Looks under .run/cycles/ and returns the lexicographically
# previous entry. Returns empty if no prior cycle exists or the layout is
# unexpected.
_find_prior_cycle() {
    local current_cycle_dir="$1"
    local cycles_root
    cycles_root="$(dirname "$current_cycle_dir")"

    [[ ! -d "$cycles_root" ]] && { echo ""; return 0; }

    local current_name
    current_name="$(basename "$current_cycle_dir")"

    # List sibling cycle dirs, sort lexicographically, pick the one before.
    # Guard against directories that aren't actual cycles (no flight-recorder).
    local prior=""
    local prior_candidate
    while IFS= read -r candidate; do
        [[ -z "$candidate" ]] && continue
        local cand_name
        cand_name="$(basename "$candidate")"

        # Skip the current cycle itself
        [[ "$cand_name" == "$current_name" ]] && continue

        # Only consider directories that have a flight-recorder (real cycles)
        [[ ! -f "$candidate/flight-recorder.jsonl" ]] && continue

        # Must sort before current_name (we want the predecessor)
        [[ "$cand_name" < "$current_name" ]] || continue

        prior_candidate="$candidate"
        # Keep iterating — the last `prior_candidate` that's < current wins
        # (dirs sorted ascending, so the last one before current is the
        # immediate predecessor).
        prior="$prior_candidate"
    done < <(find "$cycles_root" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort)

    echo "$prior"
}

# _summarize_prior_cycle_failures — scan a prior cycle's flight-recorder for
# load-bearing failure events and emit a markdown summary suitable for
# injection into discovery phase prompts.
#
# Events surfaced (load-bearing per #575):
#   - CIRCUIT_BREAKER: gate tripped after MAX_RETRIES
#   - BB_FINDING_STUCK: Bridgebuilder finding that can't be fixed
#   - AUTO_ESCALATION: profile escalated mid-cycle (signals coverage gap)
#   - REVIEW_FIX_LOOP_EXHAUSTED: fix-loop ran out of iterations
#   - BUDGET (FAILED): budget exceeded
#   - Any phase with verdict starting with "FAIL"
#
# Usage:
#   _summarize_prior_cycle_failures <prior_cycle_dir>
#
# Emits markdown to stdout, or empty string if the prior cycle ran cleanly
# (no load-bearing events found). Truncates output at ~2000 chars to avoid
# inflating the discovery prompt.
_summarize_prior_cycle_failures() {
    local prior_cycle_dir="$1"

    [[ -z "$prior_cycle_dir" || ! -d "$prior_cycle_dir" ]] && { echo ""; return 0; }

    local fr="$prior_cycle_dir/flight-recorder.jsonl"
    [[ ! -f "$fr" ]] && { echo ""; return 0; }

    # Extract load-bearing events with verdict/action filtering.
    # Using jq -s for streaming + array ops.
    local events
    events=$(jq -s -r '
        def is_load_bearing:
            (.phase // "") as $p
            | (.action // "") as $a
            | (.verdict // "") as $v
            | ($p == "CIRCUIT_BREAKER")
              or ($p | tostring | startswith("BB_FINDING_STUCK"))
              or ($p | tostring | startswith("AUTO_ESCALATION"))
              or ($p == "REVIEW_FIX_LOOP_EXHAUSTED")
              or ($a == "CIRCUIT_BREAKER")
              or ($p == "BUDGET" and ($v | tostring | startswith("FAIL")))
              or (($v | tostring | startswith("FAIL")) and ($p != "BUDGET"));

        [.[] | select(is_load_bearing)]
        | if length == 0 then empty
          else
            "**Load-bearing events from prior cycle:**",
            "",
            (.[] | "- [\(.phase // "?")] \(.action // "?")\(if .verdict and (.verdict | tostring | length > 0) then " → \(.verdict)" else "" end)")
          end
    ' "$fr" 2>/dev/null || echo "")

    # Truncate to avoid bloating discovery prompts
    if [[ -n "$events" ]]; then
        echo "$events" | head -c 2000
    fi
}

# _build_seed_failure_prelude — if the feature is enabled and a prior cycle
# exists, emits a full prelude block suitable for prepending to the SEED
# context. Returns empty string when disabled or no prior data.
#
# Usage:
#   _build_seed_failure_prelude <current_cycle_dir>
_build_seed_failure_prelude() {
    local current_cycle_dir="$1"

    [[ -z "$current_cycle_dir" ]] && { echo ""; return 0; }

    # Feature gate — default off for safe rollout. _read_harness_config is
    # defined in spiral-harness.sh; check availability so spiral-evidence.sh
    # can be sourced standalone (for tests) without a command-not-found error.
    local include_fr
    if declare -f _read_harness_config >/dev/null 2>&1; then
        include_fr=$(_read_harness_config "spiral.seed.include_flight_recorder" "false" 2>/dev/null || echo "false")
    else
        include_fr="${SPIRAL_SEED_INCLUDE_FLIGHT_RECORDER:-false}"
    fi
    [[ "$include_fr" != "true" ]] && { echo ""; return 0; }

    local prior_cycle
    prior_cycle=$(_find_prior_cycle "$current_cycle_dir")
    [[ -z "$prior_cycle" ]] && { echo ""; return 0; }

    local summary
    summary=$(_summarize_prior_cycle_failures "$prior_cycle")
    [[ -z "$summary" ]] && { echo ""; return 0; }

    # Wrap in a labeled block so the model knows what it's looking at
    cat <<EOF
---
Prior cycle observability (from $(basename "$prior_cycle")):
$summary
---
EOF
}

# =============================================================================
# Observability Dashboard (#569)
# =============================================================================
#
# Aggregates the raw flight-recorder.jsonl event stream into an operator-
# friendly dashboard snapshot. Appends one JSON line per call to
# dashboard.jsonl (append-only audit trail of observations) and overwrites
# dashboard-latest.json (cheap read for /spiral --status consumers).
#
# Usage:
#   _emit_dashboard_snapshot <current_phase> [event_type] [cycle_dir]
#
# - current_phase is a string like "IMPLEMENT" or "FLATLINE_PRD". Appears in
#   the snapshot so readers know what was active when the snapshot was taken.
# - event_type (cycle-092 Sprint 3, #599): PHASE_START | PHASE_HEARTBEAT |
#   PHASE_EXIT. Additive JSON field, defaults to PHASE_START. Lets consumers
#   distinguish mid-phase heartbeats from phase-entry/phase-exit writes.
# - cycle_dir defaults to the dirname of $_FLIGHT_RECORDER.
#
# Backward compatibility: existing 2-arg callers `_emit_dashboard_snapshot
# <phase> <cycle_dir>` must be migrated to 3-arg form. A legacy-detection
# fallback treats arg 2 as cycle_dir if it contains `/` (path-like).
#
# Environment:
#   SPIRAL_TOTAL_BUDGET — if exported by the caller (spiral-harness main()
#     exports this), the snapshot includes budget_cap_usd and remaining budget.
#
# Fail-safe: any jq/shell error is swallowed so instrumentation cannot
# break the pipeline. Dashboard is best-effort observability.

_emit_dashboard_snapshot() {
    local current_phase="${1:-}"
    local event_type="${2:-PHASE_START}"
    local cycle_dir="${3:-}"

    # Legacy 2-arg form: `_emit_dashboard_snapshot <phase> <cycle_dir>`.
    # Iter-7 BB 2195dfb4-gemini fix: previous discriminator was `*/*|*.*`
    # which would misroute future event_type values containing `.`
    # (e.g. PHASE_START.V1) as paths. The new test: an event_type is
    # whatever isn't a real directory on disk. Backward compat preserved
    # for legacy callers passing a real path; future-proof against
    # event_type names containing `/` or `.`.
    case "$event_type" in
        PHASE_START|PHASE_HEARTBEAT|PHASE_EXIT) ;;
        *)
            # If arg 2 is a real directory, the caller is using the
            # legacy 2-arg form (event_type defaults; cycle_dir was passed
            # in arg 2's slot). Otherwise treat as a future event_type
            # name we don't yet recognize and let downstream proceed —
            # event_type values are emitted as-is to consumers.
            if [[ -d "$event_type" ]]; then
                cycle_dir="$event_type"
                event_type="PHASE_START"
            fi
            ;;
    esac

    [[ -z "$_FLIGHT_RECORDER" || ! -f "$_FLIGHT_RECORDER" ]] && return 0

    if [[ -z "$cycle_dir" ]]; then
        cycle_dir="$(dirname "$_FLIGHT_RECORDER")"
    fi

    [[ ! -d "$cycle_dir" ]] && return 0

    local dashboard_jsonl="$cycle_dir/dashboard.jsonl"
    local dashboard_latest="$cycle_dir/dashboard-latest.json"

    # Budget cap from env (set by spiral-harness main()). Fall back to 0 if unset.
    local budget_cap="${SPIRAL_TOTAL_BUDGET:-0}"
    # Guard against non-numeric values
    [[ "$budget_cap" =~ ^[0-9]+(\.[0-9]+)?$ ]] || budget_cap=0

    # Compute snapshot from flight-recorder. All numeric aggregation happens
    # inside jq so we don't round-trip floats through shell arithmetic.
    # -c emits compact JSON (one line per snapshot for dashboard.jsonl).
    local snapshot
    snapshot=$(jq -s -c \
        --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg current_phase "$current_phase" \
        --arg event_type "$event_type" \
        --argjson budget_cap "$budget_cap" \
        '
        def safe_sum(path): [.[] | path // 0] | add // 0;
        def safe_num(v): if (v | type) == "number" then v else 0 end;

        . as $all
        | (
            # Per-phase rollup — group by .phase, sum metrics
            group_by(.phase) | map({
                phase: .[0].phase,
                actions: length,
                duration_ms: (map(safe_num(.duration_ms)) | add // 0),
                bytes: (map(safe_num(.output_bytes)) | add // 0),
                cost_usd: (map(safe_num(.cost_usd)) | add // 0),
                failures: (map(select(.verdict | tostring | startswith("FAIL"))) | length),
                first_ts: ([.[] | .ts] | min),
                last_ts: ([.[] | .ts] | max)
            })
          ) as $per_phase
        | (safe_sum(.cost_usd)) as $total_cost
        | (safe_sum(.duration_ms)) as $total_duration_ms
        | ($all | length) as $total_actions
        | ([$all[] | select(.verdict | tostring | startswith("FAIL"))] | length) as $total_failures
        | (if $budget_cap > 0 then ($budget_cap - $total_cost) else null end) as $remaining
        | ([$all[] | select(.action == "REVIEW_FIX_DISPATCH" or .phase == "REVIEW_FIX_LOOP_EXHAUSTED")] | length) as $fix_loop_events
        | ([$all[] | select(.phase | tostring | startswith("BB_FIX_CYCLE"))] | length) as $bb_fix_cycles
        | ([$all[] | select(.action == "CIRCUIT_BREAKER")] | length) as $circuit_breaks
        | ([$all[0].ts]) as $start_ts
        | ([$all | last | .ts]) as $last_ts
        | {
            schema: "spiral.dashboard.v1",
            ts: $ts,
            current_phase: (if $current_phase == "" then null else $current_phase end),
            event_type: $event_type,
            totals: {
                actions: $total_actions,
                failures: $total_failures,
                cost_usd: $total_cost,
                duration_ms: $total_duration_ms,
                budget_cap_usd: (if $budget_cap > 0 then $budget_cap else null end),
                budget_remaining_usd: $remaining,
                fix_loop_events: $fix_loop_events,
                bb_fix_cycles: $bb_fix_cycles,
                circuit_breaks: $circuit_breaks,
                first_action_ts: ($start_ts[0] // null),
                last_action_ts: ($last_ts[0] // null)
            },
            per_phase: $per_phase
          }
        ' "$_FLIGHT_RECORDER" 2>/dev/null) || snapshot=""

    [[ -z "$snapshot" ]] && return 0

    # Append to rolling journal + overwrite latest pointer. Both writes are
    # atomic per call (jq produces complete JSON; >> and > are atomic for
    # small writes on POSIX).
    echo "$snapshot" >> "$dashboard_jsonl" 2>/dev/null || true
    echo "$snapshot" > "${dashboard_latest}.tmp" 2>/dev/null && \
        mv "${dashboard_latest}.tmp" "$dashboard_latest" 2>/dev/null || true

    return 0
}

# =============================================================================
# Dashboard Mid-Phase Heartbeat Daemon (cycle-092 Sprint 3 — #599)
# =============================================================================
#
# Spawns a background process that emits PHASE_HEARTBEAT dashboard snapshots
# on a configurable interval while the harness is running. Reads
# $cycle_dir/.phase-current (Sprint 1 state file) as the truth source for
# "what phase now?". Daemon dies on SIGTERM/SIGINT (EXIT trap in harness
# main() sends SIGTERM at pipeline exit).
#
# Fixes the cycle-091 observed regression: dashboard-latest.json froze at
# PRE_CHECK's $15 during the 36-min IMPL phase because phase-EXIT was the
# only write site.
#
# Usage:
#   daemon_pid=$(_spawn_dashboard_heartbeat_daemon "$cycle_dir" [interval_sec])
#
# Env overrides:
#   SPIRAL_DASHBOARD_HEARTBEAT_SEC  [60]   — default interval, clamped [30,300]
#   SPIRAL_DASHBOARD_STALE_SEC      [1800] — if .phase-current mtime older
#                                             than this, daemon skips the
#                                             emit (suspected-stuck phase)

# Clamp a raw interval-seconds input to the heartbeat valid range.
# Echoes the effective interval. Behavioral contract — tests call this
# directly with boundary inputs and assert on stdout (Iter-4/5 BB F2 +
# non_behavioral_clamp_test fix: replace source-grep with execute-and-observe).
#   $1 = raw interval string (may be empty / non-numeric)
# Echoes the clamped integer to stdout.
_clamp_heartbeat_interval() {
    local raw="${1:-}"
    local v="$raw"
    if ! [[ "$v" =~ ^[0-9]+$ ]]; then
        v=60
    fi
    if (( v < 30 )); then
        v=30
    elif (( v > 300 )); then
        v=300
    fi
    printf '%s\n' "$v"
}

_spawn_dashboard_heartbeat_daemon() {
    local cycle_dir="${1:-}"
    local interval_sec="${2:-${SPIRAL_DASHBOARD_HEARTBEAT_SEC:-60}}"
    local stale_sec="${SPIRAL_DASHBOARD_STALE_SEC:-1800}"

    [[ -z "$cycle_dir" ]] && return 1
    [[ ! -d "$cycle_dir" ]] && return 1

    # Clamp interval to [30, 300]. Non-numeric falls back to 60.
    # TEST-ONLY: $LOA_TEST_HEARTBEAT_INTERVAL bypasses the clamp so daemon
    # self-termination tests can observe file-absence detection in <2s
    # instead of waiting 30s. Honored only when set; otherwise standard
    # production clamp applies. This satisfies iter-5 BB MEDIUM 993540fc:
    # daemon self-termination must be tested via PID-wait on file-absence,
    # not via SIGTERM (which proves "killable", not "self-exits cleanly").
    if [[ -n "${LOA_TEST_HEARTBEAT_INTERVAL:-}" ]] && \
       [[ "$LOA_TEST_HEARTBEAT_INTERVAL" =~ ^[0-9]+$ ]]; then
        interval_sec="$LOA_TEST_HEARTBEAT_INTERVAL"
    else
        interval_sec=$(_clamp_heartbeat_interval "$interval_sec")
    fi

    # Backgrounded while-loop. Inherits _FLIGHT_RECORDER and function defs
    # from parent shell. Sleep-first so PHASE_START (emitted by main() before
    # spawn completes) isn't immediately clobbered.
    # Signal responsiveness: `sleep & wait` pattern so SIGTERM interrupts
    # the sleep immediately instead of waiting up to interval_sec for the
    # next loop iteration.
    (
        trap 'kill $SLEEP_PID 2>/dev/null; exit 0' TERM INT
        SLEEP_PID=""
        while true; do
            sleep "$interval_sec" &
            SLEEP_PID=$!
            wait "$SLEEP_PID" 2>/dev/null || true
            SLEEP_PID=""
            # Read .phase-current — if absent, harness is idle or exited.
            # Exit cleanly (daemon has no work to do).
            if [[ ! -f "$cycle_dir/.phase-current" ]]; then
                exit 0
            fi
            # mtime staleness check — if .phase-current hasn't been touched
            # in stale_sec, phase is suspected stuck. Skip emit (the Sprint 4
            # heartbeat surface handles "stuck" signaling separately).
            local mtime now age
            mtime=$(stat -c %Y "$cycle_dir/.phase-current" 2>/dev/null || \
                    stat -f %m "$cycle_dir/.phase-current" 2>/dev/null || echo 0)
            now=$(date +%s)
            age=$((now - mtime))
            if (( age > stale_sec )); then
                continue
            fi
            # Extract phase_label (first tab-separated field) and emit.
            local phase_label
            phase_label=$(awk -F'\t' '{print $1; exit}' \
                          "$cycle_dir/.phase-current" 2>/dev/null)
            if [[ -n "$phase_label" ]]; then
                _emit_dashboard_snapshot "$phase_label" "PHASE_HEARTBEAT" \
                    "$cycle_dir" 2>/dev/null || true
            fi
        done
    ) </dev/null >/dev/null 2>&1 &
    # Note: stdin/stdout/stderr all redirected so `$(_spawn_...)` command
    # substitution in callers returns immediately rather than waiting for
    # the backgrounded subshell to finish. Return daemon PID via this echo.
    echo "$!"
}
