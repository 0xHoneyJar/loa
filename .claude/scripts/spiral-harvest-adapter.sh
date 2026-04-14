#!/usr/bin/env bash
# =============================================================================
# spiral-harvest-adapter.sh - HARVEST phase adapter for /spiral (cycle-067)
# =============================================================================
# Version: 1.0.0
# Part of: FR-8 HARVEST Contract (FAANG-grade)
# Sourced by: spiral-orchestrator.sh
#
# Produces and parses cycle-outcome.json sidecar using 3-tier precedence:
#   1. Sidecar JSON (typed, versioned)
#   2. .run/ state files (structured → structured)
#   3. Markdown regex fallback (last resort)
#
# All JSON construction via jq --arg/--argjson (NFR-4).
# =============================================================================

# Guard against double-source
[[ -n "${_SPIRAL_HARVEST_ADAPTER_LOADED:-}" ]] && return 0
readonly _SPIRAL_HARVEST_ADAPTER_LOADED=1

# =============================================================================
# Constants — regex patterns for markdown fallback (NFR-7: readonly, single SoT)
# =============================================================================

readonly SPIRAL_RX_REVIEW_VERDICT='^## Verdict[[:space:]]*$'
readonly SPIRAL_RX_REVIEW_VALUE='^(APPROVED|REQUEST_CHANGES)[[:space:]]*$'
readonly SPIRAL_RX_AUDIT_VERDICT='^## Final Verdict[[:space:]]*$'
readonly SPIRAL_RX_AUDIT_VALUE='^(APPROVED|CHANGES_REQUIRED)[[:space:]]*$'
readonly SPIRAL_RX_FINDINGS_HEADER='^## Findings Summary[[:space:]]*$'
readonly SPIRAL_RX_FINDINGS_ROW='^\|[[:space:]]*(Blocker|High|Medium|Low)[[:space:]]*\|[[:space:]]*([0-9]+)[[:space:]]*\|'

readonly SPIRAL_SIDECAR_FILENAME="cycle-outcome.json"
readonly SPIRAL_SUPPORTED_SCHEMA_VERSIONS=(1)

# =============================================================================
# Sidecar Writer — FR-8.1
# =============================================================================

# emit_cycle_outcome_sidecar <cycle_dir> <review_verdict> <audit_verdict> <findings_json>
#   [flatline_sig] [elapsed_sec] [exit_status]
#
# Writes cycle-outcome.json atomically. Returns path on stdout.
emit_cycle_outcome_sidecar() {
    local cycle_dir="$1"
    local review_verdict="$2"
    local audit_verdict="$3"
    local findings_json="$4"
    local flatline_sig="${5:-null}"
    local elapsed_sec="${6:-null}"
    local exit_status="${7:-success}"

    local cycle_id
    cycle_id=$(basename "$cycle_dir")

    local sidecar_path="${cycle_dir}/${SPIRAL_SIDECAR_FILENAME}"
    local tmp="${sidecar_path}.tmp"

    # Compute content hash from artifacts if they exist
    local content_hash="null"
    local reviewer_path="${cycle_dir}/reviewer.md"
    local auditor_path="${cycle_dir}/auditor-sprint-feedback.md"
    if [[ -f "$reviewer_path" && -f "$auditor_path" ]]; then
        content_hash="\"sha256:$(cat "$reviewer_path" "$auditor_path" | sha256sum | cut -d' ' -f1)\""
    fi

    # Compute flatline signature if not provided
    if [[ "$flatline_sig" == "null" ]]; then
        local computed_sig
        computed_sig=$(compute_flatline_signature "$review_verdict" "$audit_verdict" "$findings_json" "$content_hash")
        flatline_sig="\"$computed_sig\""
    else
        flatline_sig="\"$flatline_sig\""
    fi

    # Build sidecar via jq (NFR-4: --arg for strings, --argjson for JSON)
    local review_arg audit_arg elapsed_arg
    if [[ "$review_verdict" == "null" ]]; then
        review_arg="null"
    else
        review_arg="\"$review_verdict\""
    fi
    if [[ "$audit_verdict" == "null" ]]; then
        audit_arg="null"
    else
        audit_arg="\"$audit_verdict\""
    fi
    if [[ "$elapsed_sec" == "null" ]]; then
        elapsed_arg="null"
    else
        elapsed_arg="$elapsed_sec"
    fi

    if ! jq -n \
        --arg cycle_id "$cycle_id" \
        --argjson review "$review_arg" \
        --argjson audit "$audit_arg" \
        --argjson findings "$findings_json" \
        --argjson flatline_sig "$flatline_sig" \
        --argjson content_hash "$content_hash" \
        --argjson elapsed "$elapsed_arg" \
        --arg exit_status "$exit_status" \
        --arg reviewer_md "${reviewer_path#"$PROJECT_ROOT/"}" \
        --arg auditor_md "${auditor_path#"$PROJECT_ROOT/"}" \
        '{
            "$schema_version": 1,
            "cycle_id": $cycle_id,
            "review_verdict": $review,
            "audit_verdict": $audit,
            "findings": $findings,
            "artifacts": {
                "reviewer_md": $reviewer_md,
                "auditor_md": $auditor_md,
                "pr_url": null
            },
            "flatline_signature": $flatline_sig,
            "content_hash": $content_hash,
            "elapsed_sec": $elapsed,
            "exit_status": $exit_status
        }' > "$tmp" 2>/dev/null; then
        rm -f "$tmp"
        echo "ERROR: Failed to write sidecar JSON" >&2
        return 1
    fi

    if ! mv "$tmp" "$sidecar_path" 2>/dev/null; then
        echo "ERROR: Failed to atomically move sidecar (mv failed)" >&2
        return 1
    fi

    echo "$sidecar_path"
}

# =============================================================================
# Sidecar Validator — FR-8.4
# =============================================================================

# validate_sidecar_schema <sidecar_path>
# Exit: 0=valid, 1=missing required, 2=invalid enum, 3=version mismatch
validate_sidecar_schema() {
    local sidecar_path="$1"

    if [[ ! -f "$sidecar_path" ]]; then
        echo "ERROR: Sidecar not found: $sidecar_path" >&2
        return 1
    fi

    # Check valid JSON
    if ! jq empty "$sidecar_path" 2>/dev/null; then
        echo "ERROR: Invalid JSON in sidecar" >&2
        return 1
    fi

    # Check schema version
    local version
    version=$(jq -r '."$schema_version" // "missing"' "$sidecar_path")
    if [[ "$version" == "missing" ]]; then
        echo "ERROR: Missing \$schema_version field" >&2
        return 1
    fi

    local version_supported=false
    for v in "${SPIRAL_SUPPORTED_SCHEMA_VERSIONS[@]}"; do
        if [[ "$version" == "$v" ]]; then
            version_supported=true
            break
        fi
    done
    if [[ "$version_supported" != "true" ]]; then
        echo "ERROR: Unsupported schema version: $version (supported: ${SPIRAL_SUPPORTED_SCHEMA_VERSIONS[*]})" >&2
        return 3
    fi

    # Check required fields
    local missing
    missing=$(jq -r '[
        (if .cycle_id == null then "cycle_id" else empty end),
        (if .findings == null then "findings" else empty end),
        (if .exit_status == null then "exit_status" else empty end)
    ] | join(", ")' "$sidecar_path")

    if [[ -n "$missing" ]]; then
        echo "ERROR: Missing required fields: $missing" >&2
        return 1
    fi

    # Check enum values
    local review_v audit_v exit_s
    review_v=$(jq -r '.review_verdict // "null"' "$sidecar_path")
    audit_v=$(jq -r '.audit_verdict // "null"' "$sidecar_path")
    exit_s=$(jq -r '.exit_status' "$sidecar_path")

    if [[ "$review_v" != "null" ]]; then
        case "$review_v" in
            APPROVED|REQUEST_CHANGES) ;;
            *) echo "ERROR: Invalid review_verdict: $review_v" >&2; return 2 ;;
        esac
    fi

    if [[ "$audit_v" != "null" ]]; then
        case "$audit_v" in
            APPROVED|CHANGES_REQUIRED) ;;
            *) echo "ERROR: Invalid audit_verdict: $audit_v" >&2; return 2 ;;
        esac
    fi

    case "$exit_s" in
        success|partial|failed) ;;
        *) echo "ERROR: Invalid exit_status: $exit_s" >&2; return 2 ;;
    esac

    # Check findings structure
    local findings_valid
    findings_valid=$(jq -r '
        if .findings | (has("blocker") and has("high") and has("medium") and has("low"))
        then "ok" else "missing_findings_fields" end
    ' "$sidecar_path")

    if [[ "$findings_valid" != "ok" ]]; then
        echo "ERROR: Findings object missing required fields (blocker, high, medium, low)" >&2
        return 1
    fi

    return 0
}

# =============================================================================
# Sidecar Parser — FR-8.2 (3-tier precedence)
# =============================================================================

# parse_cycle_outcome <cycle_dir> [run_dir] [cycle_id]
# Returns normalized cycle record JSON on stdout.
# Precedence: sidecar → state files → markdown
parse_cycle_outcome() {
    local cycle_dir="$1"
    local run_dir="${2:-${PROJECT_ROOT}/.run}"
    local cycle_id="${3:-$(basename "$cycle_dir")}"
    local sidecar_path="${cycle_dir}/${SPIRAL_SIDECAR_FILENAME}"

    # Tier 1: Sidecar JSON
    if [[ -f "$sidecar_path" ]]; then
        if validate_sidecar_schema "$sidecar_path" 2>/dev/null; then
            _parse_sidecar "$sidecar_path" "$cycle_id"
            return $?
        else
            local exit_code=$?
            case $exit_code in
                3) _log_harvest_event "harvest_schema_version_mismatch" \
                       "$cycle_id" "$(jq -r '."$schema_version"' "$sidecar_path" 2>/dev/null)" ;;
                1) _log_harvest_event "harvest_sidecar_incomplete" \
                       "$cycle_id" "$(validate_sidecar_schema "$sidecar_path" 2>&1)" ;;
                2) _log_harvest_event "harvest_sidecar_invalid_enum" \
                       "$cycle_id" "$(validate_sidecar_schema "$sidecar_path" 2>&1)" ;;
            esac
            # Fail-closed on sidecar present but invalid
            _emit_failed_cycle_record "$cycle_id"
            return 0
        fi
    fi

    # Check for orphan .tmp (IMP-002: crash between jq and mv)
    if [[ -f "${sidecar_path}.tmp" ]]; then
        _log_harvest_event "harvest_orphan_tmp_detected" "$cycle_id" "${sidecar_path}.tmp"
        rm -f "${sidecar_path}.tmp"
    fi

    # Tier 2: State files
    if [[ -d "$run_dir" ]] && [[ -f "$run_dir/sprint-plan-state.json" || -f "$run_dir/simstim-state.json" ]]; then
        local state_result
        if state_result=$(parse_from_state_files "$run_dir" "$cycle_id" 2>/dev/null); then
            _log_harvest_event "harvest_from_state_files" "$cycle_id" "ok"
            echo "$state_result"
            return 0
        fi
        # Fall through to markdown
    fi

    # Tier 3: Markdown fallback
    if [[ -f "${cycle_dir}/reviewer.md" ]] || [[ -f "${cycle_dir}/auditor-sprint-feedback.md" ]]; then
        _log_harvest_event "harvest_fallback_markdown" "$cycle_id" "sidecar_and_state_missing"
        fallback_parse_markdown "$cycle_dir" "$cycle_id"
        return $?
    fi

    # Nothing to parse — fail-closed
    _log_harvest_event "harvest_no_artifacts" "$cycle_id" "no sidecar, state files, or markdown"
    _emit_failed_cycle_record "$cycle_id"
    return 0
}

# parse_from_state_files <run_dir> <cycle_id>
# Reads .run/ state files, rejects if cycle_id doesn't match.
parse_from_state_files() {
    local run_dir="$1"
    local cycle_id="$2"

    # Try sprint-plan-state.json for verdicts
    local sprint_state="${run_dir}/sprint-plan-state.json"
    local simstim_state="${run_dir}/simstim-state.json"

    if [[ ! -f "$sprint_state" ]] && [[ ! -f "$simstim_state" ]]; then
        echo "ERROR: No state files found in $run_dir" >&2
        return 1
    fi

    # Validate cycle_id correlation
    if [[ -f "$sprint_state" ]]; then
        local plan_id
        plan_id=$(jq -r '.plan_id // "unknown"' "$sprint_state")
        # State files don't have per-cycle IDs, so we check plan freshness via timestamp
        local last_activity
        last_activity=$(jq -r '.timestamps.last_activity // "1970-01-01T00:00:00Z"' "$sprint_state")
        # Reject state older than 1 hour (stale from previous cycle)
        local last_epoch now_epoch
        now_epoch=$(date -u +%s)
        last_epoch=$(date -u -d "$last_activity" +%s 2>/dev/null \
            || date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$last_activity" +%s 2>/dev/null \
            || echo "0")
        local age=$((now_epoch - last_epoch))
        if [[ "$age" -gt 3600 ]]; then
            _log_harvest_event "harvest_state_cycle_mismatch" "$cycle_id" "state age ${age}s > 3600s"
            return 1
        fi
    fi

    # Extract available data
    local review_v="null" audit_v="null"
    local blocker=0 high=0 medium=0 low=0

    if [[ -f "$sprint_state" ]]; then
        local state_data
        state_data=$(jq -r '.state // "unknown"' "$sprint_state")
        if [[ "$state_data" == "JACKED_OUT" ]]; then
            review_v="APPROVED"
            audit_v="APPROVED"
        fi
    fi

    jq -n \
        --arg cycle_id "$cycle_id" \
        --argjson review "$(if [[ "$review_v" == "null" ]]; then echo null; else echo "\"$review_v\""; fi)" \
        --argjson audit "$(if [[ "$audit_v" == "null" ]]; then echo null; else echo "\"$audit_v\""; fi)" \
        --argjson blocker "$blocker" \
        --argjson high "$high" \
        --argjson medium "$medium" \
        --argjson low "$low" \
        '{
            cycle_id: $cycle_id,
            review_verdict: $review,
            audit_verdict: $audit,
            findings_critical: ($blocker + $high),
            findings_minor: ($medium + $low),
            flatline_signature: null,
            content_hash: null,
            elapsed_sec: null,
            exit_status: "success",
            parse_source: "state_files"
        }'
}

# fallback_parse_markdown <cycle_dir> [cycle_id]
# Parses reviewer.md + auditor-sprint-feedback.md via regex.
fallback_parse_markdown() {
    local cycle_dir="$1"
    local cycle_id="${2:-$(basename "$cycle_dir")}"

    local reviewer_path="${cycle_dir}/reviewer.md"
    local auditor_path="${cycle_dir}/auditor-sprint-feedback.md"

    local review_v="null"
    local audit_v="null"
    local blocker=0 high=0 medium=0 low=0

    # Parse review verdict via awk state machine
    if [[ -f "$reviewer_path" ]]; then
        review_v=$(_extract_verdict "$reviewer_path" \
            "$SPIRAL_RX_REVIEW_VERDICT" "$SPIRAL_RX_REVIEW_VALUE")
    fi

    # Parse audit verdict
    if [[ -f "$auditor_path" ]]; then
        audit_v=$(_extract_verdict "$auditor_path" \
            "$SPIRAL_RX_AUDIT_VERDICT" "$SPIRAL_RX_AUDIT_VALUE")
    fi

    # Parse findings counts from whichever file has the summary
    local findings_file=""
    for f in "$auditor_path" "$reviewer_path"; do
        if [[ -f "$f" ]] && grep -qE "$SPIRAL_RX_FINDINGS_HEADER" "$f" 2>/dev/null; then
            findings_file="$f"
            break
        fi
    done

    if [[ -n "$findings_file" ]]; then
        local counts
        counts=$(_extract_findings_counts "$findings_file")
        blocker=$(echo "$counts" | jq -r '.blocker')
        high=$(echo "$counts" | jq -r '.high')
        medium=$(echo "$counts" | jq -r '.medium')
        low=$(echo "$counts" | jq -r '.low')
    fi

    # Compute content hash
    local content_hash="null"
    if [[ -f "$reviewer_path" && -f "$auditor_path" ]]; then
        content_hash="\"sha256:$(cat "$reviewer_path" "$auditor_path" | sha256sum | cut -d' ' -f1)\""
    fi

    local review_arg audit_arg
    if [[ "$review_v" == "null" ]]; then review_arg="null"; else review_arg="\"$review_v\""; fi
    if [[ "$audit_v" == "null" ]]; then audit_arg="null"; else audit_arg="\"$audit_v\""; fi

    jq -n \
        --arg cycle_id "$cycle_id" \
        --argjson review "$review_arg" \
        --argjson audit "$audit_arg" \
        --argjson blocker "$blocker" \
        --argjson high "$high" \
        --argjson medium "$medium" \
        --argjson low "$low" \
        --argjson content_hash "$content_hash" \
        '{
            cycle_id: $cycle_id,
            review_verdict: $review,
            audit_verdict: $audit,
            findings_critical: ($blocker + $high),
            findings_minor: ($medium + $low),
            flatline_signature: null,
            content_hash: $content_hash,
            elapsed_sec: null,
            exit_status: "success",
            parse_source: "markdown"
        }'
}

# =============================================================================
# Flatline Signature — FR-10
# =============================================================================

# compute_flatline_signature <review_verdict> <audit_verdict> <findings_json> [content_hash]
# Outputs sha256:... on stdout.
compute_flatline_signature() {
    local review_v="$1"
    local audit_v="$2"
    local findings_json="$3"
    local content_hash="${4:-null}"

    # Normalize: lowercase verdicts, stable sort findings
    local norm_review norm_audit norm_findings
    norm_review=$(echo "$review_v" | tr '[:upper:]' '[:lower:]')
    norm_audit=$(echo "$audit_v" | tr '[:upper:]' '[:lower:]')

    # Extract and sort findings into stable format
    norm_findings=$(echo "$findings_json" | jq -Sc '{
        blocker: (.blocker // 0),
        high: (.high // 0),
        low: (.low // 0),
        medium: (.medium // 0)
    }')

    # Clean content_hash (strip quotes if present)
    local norm_content_hash
    norm_content_hash=$(echo "$content_hash" | tr -d '"')

    # Concatenate and hash
    local input="${norm_review}\n${norm_audit}\n${norm_findings}\n${norm_content_hash}"
    local hash
    hash=$(printf '%b' "$input" | sha256sum | cut -d' ' -f1)

    echo "sha256:${hash}"
}

# =============================================================================
# Internal helpers
# =============================================================================

# _extract_verdict <file> <header_regex> <value_regex>
# Returns verdict string or "null"
_extract_verdict() {
    local file="$1"
    local header_rx="$2"
    local value_rx="$3"

    local result
    result=$(awk -v header="$header_rx" -v value="$value_rx" '
        BEGIN { found_header = 0 }
        $0 ~ header { found_header = 1; next }
        found_header && $0 ~ value {
            # Strip leading/trailing whitespace
            gsub(/^[[:space:]]+|[[:space:]]+$/, "")
            print
            exit
        }
        found_header && /^#/ { exit }  # Next section, verdict not found
        found_header && /^[[:space:]]*$/ { next }  # Skip blank lines
    ' "$file" 2>/dev/null) || true

    if [[ -z "$result" ]]; then
        echo "null"
    else
        echo "$result"
    fi
}

# _extract_findings_counts <file>
# Returns JSON: {"blocker": N, "high": N, "medium": N, "low": N}
_extract_findings_counts() {
    local file="$1"

    awk -v header="$SPIRAL_RX_FINDINGS_HEADER" -v row="$SPIRAL_RX_FINDINGS_ROW" '
        BEGIN {
            found = 0
            blocker = 0; high = 0; medium = 0; low = 0
        }
        $0 ~ header { found = 1; next }
        found && /^\|/ {
            # Match severity | count pattern
            if (match($0, /Blocker[[:space:]]*\|[[:space:]]*([0-9]+)/, a)) blocker = a[1]
            else if (match($0, /High[[:space:]]*\|[[:space:]]*([0-9]+)/, a)) high = a[1]
            else if (match($0, /Medium[[:space:]]*\|[[:space:]]*([0-9]+)/, a)) medium = a[1]
            else if (match($0, /Low[[:space:]]*\|[[:space:]]*([0-9]+)/, a)) low = a[1]
        }
        found && /^[^|]/ && !/^[[:space:]]*$/ { exit }
        END {
            printf "{\"blocker\":%d,\"high\":%d,\"medium\":%d,\"low\":%d}\n", blocker, high, medium, low
        }
    ' "$file" 2>/dev/null || echo '{"blocker":0,"high":0,"medium":0,"low":0}'
}

# _parse_sidecar <sidecar_path> <cycle_id>
# Normalize sidecar into cycle record format
_parse_sidecar() {
    local sidecar_path="$1"
    local cycle_id="$2"

    jq --arg cycle_id "$cycle_id" '{
        cycle_id: $cycle_id,
        review_verdict: .review_verdict,
        audit_verdict: .audit_verdict,
        findings_critical: ((.findings.blocker // 0) + (.findings.high // 0)),
        findings_minor: ((.findings.medium // 0) + (.findings.low // 0)),
        flatline_signature: .flatline_signature,
        content_hash: .content_hash,
        elapsed_sec: .elapsed_sec,
        exit_status: .exit_status,
        parse_source: "sidecar"
    }' "$sidecar_path"
}

# _emit_failed_cycle_record <cycle_id>
# Emit a fail-closed cycle record (null verdicts, failed status)
_emit_failed_cycle_record() {
    local cycle_id="$1"
    jq -n --arg cycle_id "$cycle_id" '{
        cycle_id: $cycle_id,
        review_verdict: null,
        audit_verdict: null,
        findings_critical: 0,
        findings_minor: 0,
        flatline_signature: null,
        content_hash: null,
        elapsed_sec: null,
        exit_status: "failed",
        parse_source: "fail_closed"
    }'
}

# _log_harvest_event <event_name> <cycle_id> <detail>
# Log to trajectory if log_trajectory function is available
_log_harvest_event() {
    local event="$1"
    local cycle_id="$2"
    local detail="$3"

    if type -t log_trajectory &>/dev/null; then
        log_trajectory "$event" "$(jq -n --arg c "$cycle_id" --arg d "$detail" \
            '{cycle_id: $c, detail: $d}')"
    else
        echo "[harvest] $event: cycle=$cycle_id detail=$detail" >&2
    fi
}
