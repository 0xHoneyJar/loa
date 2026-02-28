#!/usr/bin/env bash
# =============================================================================
# red-team-code-vs-design.sh — Compare SDD security design to implemented code
# =============================================================================
# Version: 1.0.0
# Part of: Review Pipeline Hardening (cycle-045, FR-3)
#
# Compares SDD security sections to actual code changes, producing findings
# categorized as CONFIRMED_DIVERGENCE, PARTIAL_IMPLEMENTATION, or FULLY_IMPLEMENTED.
#
# Usage:
#   red-team-code-vs-design.sh --sdd <path> --diff <file> --output <path> --sprint <id>
#
# Options:
#   --sdd <path>           SDD document path (required)
#   --diff <file>          Code diff file path (or - for stdin)
#   --output <path>        Output findings JSON path (required)
#   --sprint <id>          Sprint ID for context (required)
#   --prior-findings <path> Prior review/audit findings to inform analysis (repeatable)
#   --token-budget <n>     Max tokens for model invocation (default from config)
#   --severity-threshold <n> Min severity to report (default from config)
#   --dry-run              Validate inputs without calling model
#
# Exit codes:
#   0 - Success (findings produced)
#   1 - Error (missing inputs, model failure)
#   2 - Invalid input
#   3 - No SDD security sections found
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_FILE="$PROJECT_ROOT/.loa.config.yaml"
MODEL_ADAPTER="$SCRIPT_DIR/model-adapter.sh"

# =============================================================================
# Logging
# =============================================================================

log() {
    echo "[red-team-code] $*" >&2
}

error() {
    echo "[red-team-code] ERROR: $*" >&2
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

# =============================================================================
# SDD Section Extraction
# =============================================================================

# Extract security-related sections from SDD using header regex
# Matches headers containing security-related keywords
extract_security_sections() {
    local sdd_path="$1"
    local max_chars="${2:-20000}"  # ~5K tokens

    if [[ ! -f "$sdd_path" ]]; then
        error "SDD not found: $sdd_path"
        return 1
    fi

    # Extract sections with security-related headers
    # Pattern: any markdown header (1-3 #) containing security keywords
    local in_section=false
    local section_level=0
    local output=""
    local char_count=0

    while IFS= read -r line; do
        # Check if this is a header line
        if [[ "$line" =~ ^(#{1,3})[[:space:]] ]]; then
            local level=${#BASH_REMATCH[1]}

            # If we're in a section and hit same-or-higher level header, exit section
            if [[ "$in_section" == true && $level -le $section_level ]]; then
                in_section=false
            fi

            # Check if this header matches security keywords
            if printf '%s\n' "$line" | grep -iqE '(Security|Authentication|Authorization|Validation|Error.Handling|Access.Control|Secrets|Encryption|Input.Sanitiz)'; then
                in_section=true
                section_level=$level
            fi
        fi

        # Collect content when in a matching section
        if [[ "$in_section" == true ]]; then
            output+="$line"$'\n'
            char_count=$((char_count + ${#line} + 1))

            # Truncate if over budget
            if [[ $char_count -ge $max_chars ]]; then
                output+=$'\n[... truncated to token budget ...]\n'
                break
            fi
        fi
    done < "$sdd_path"

    if [[ -z "$output" ]]; then
        return 3  # No security sections found
    fi

    echo "$output"
}

# =============================================================================
# Prior Findings Extraction (Deliberative Council pattern — cycle-046 FR-2)
# =============================================================================

# Extract actionable findings from prior review/audit feedback files.
# Looks for ## Findings, ## Issues, ## Changes Required, ## Security sections.
# Returns truncated content or empty string for missing/empty files.
extract_prior_findings() {
    local path="$1"
    local max_chars="${2:-20000}"

    if [[ ! -f "$path" ]]; then
        return 0
    fi

    local content=""
    local in_section=false
    local char_count=0

    while IFS= read -r line; do
        # Match relevant findings sections
        if [[ "$line" =~ ^##[[:space:]] ]]; then
            if printf '%s\n' "$line" | grep -iqE '(Findings|Issues|Changes.Required|Security|Concerns|Recommendations)'; then
                in_section=true
            elif [[ "$in_section" == true ]]; then
                # Hit a different ## section — stop collecting
                in_section=false
            fi
        fi

        if [[ "$in_section" == true ]]; then
            content+="$line"$'\n'
            char_count=$((char_count + ${#line} + 1))
            if [[ $char_count -ge $max_chars ]]; then
                content+=$'\n[... prior findings truncated to token budget ...]\n'
                break
            fi
        fi
    done < "$path"

    echo "$content"
}

# =============================================================================
# Main
# =============================================================================

main() {
    local sdd_path=""
    local diff_path=""
    local output_path=""
    local sprint_id=""
    local token_budget=""
    local severity_threshold=""
    local dry_run=false
    local prior_findings_paths=()

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --sdd)           sdd_path="$2"; shift 2 ;;
            --diff)          diff_path="$2"; shift 2 ;;
            --output)        output_path="$2"; shift 2 ;;
            --sprint)        sprint_id="$2"; shift 2 ;;
            --prior-findings) prior_findings_paths+=("$2"); shift 2 ;;
            --token-budget)  token_budget="$2"; shift 2 ;;
            --severity-threshold) severity_threshold="$2"; shift 2 ;;
            --dry-run)       dry_run=true; shift ;;
            -h|--help)
                echo "Usage: red-team-code-vs-design.sh --sdd <path> --diff <file> --output <path> --sprint <id>"
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                exit 2
                ;;
        esac
    done

    # Read config defaults
    [[ -z "$token_budget" ]] && token_budget=$(read_config '.red_team.code_vs_design.token_budget' '150000')
    [[ -z "$severity_threshold" ]] && severity_threshold=$(read_config '.red_team.code_vs_design.severity_threshold' '700')

    # Validate required arguments
    if [[ -z "$sdd_path" ]]; then
        error "SDD path required (--sdd)"
        exit 2
    fi
    if [[ -z "$output_path" ]]; then
        error "Output path required (--output)"
        exit 2
    fi
    if [[ -z "$sprint_id" ]]; then
        error "Sprint ID required (--sprint)"
        exit 2
    fi

    # Check SDD exists
    local skip_if_no_sdd
    skip_if_no_sdd=$(read_config '.red_team.code_vs_design.skip_if_no_sdd' 'true')
    if [[ ! -f "$sdd_path" ]]; then
        if [[ "$skip_if_no_sdd" == "true" ]]; then
            log "SDD not found, skipping (skip_if_no_sdd: true)"
            # Write empty findings
            jq -n '{findings: [], summary: {total: 0, confirmed_divergence: 0, partial_implementation: 0, fully_implemented: 0}, skipped: true, reason: "sdd_not_found"}' > "$output_path"
            exit 0
        else
            error "SDD not found: $sdd_path"
            exit 1
        fi
    fi

    # Extract security sections
    # Token budget controls input truncation (~4 chars/token)
    # With prior findings: 3-way split (1/3 each). Without: 2-way split (1/2 each).
    local input_channels=2
    if [[ ${#prior_findings_paths[@]} -gt 0 ]]; then
        input_channels=3
        log "Prior findings provided (${#prior_findings_paths[@]} files) — 3-way token budget"
    fi
    local max_section_chars=$(( token_budget * 4 / input_channels ))
    [[ $max_section_chars -gt 100000 ]] && max_section_chars=100000  # cap at 100K chars
    [[ $max_section_chars -lt 4000 ]] && max_section_chars=4000      # floor at 4K chars
    log "Extracting SDD security sections from: $sdd_path (max $max_section_chars chars)"
    local security_sections
    local extract_exit=0
    security_sections=$(extract_security_sections "$sdd_path" "$max_section_chars") || extract_exit=$?
    if [[ $extract_exit -ne 0 ]]; then
        if [[ $extract_exit -eq 3 ]]; then
            log "No security sections found in SDD, skipping"
            jq -n '{findings: [], summary: {total: 0, confirmed_divergence: 0, partial_implementation: 0, fully_implemented: 0}, skipped: true, reason: "no_security_sections"}' > "$output_path"
            exit 0
        fi
        error "Failed to extract security sections"
        exit 1
    fi

    local section_chars=${#security_sections}
    log "Extracted $section_chars characters of security content"

    # Get code diff
    local code_diff=""
    if [[ -n "$diff_path" && "$diff_path" != "-" ]]; then
        # Explicit path provided — fail if it doesn't exist (no silent fallthrough)
        if [[ ! -f "$diff_path" ]]; then
            error "Diff file not found: $diff_path"
            exit 2
        fi
        code_diff=$(cat "$diff_path")
    elif [[ "$diff_path" == "-" ]]; then
        code_diff=$(cat)
    else
        # No --diff specified — generate from git
        code_diff=$(git diff main...HEAD 2>/dev/null || git diff HEAD~1 2>/dev/null || echo "")
    fi

    if [[ -z "$code_diff" ]]; then
        log "No code diff available, skipping"
        jq -n '{findings: [], summary: {total: 0, confirmed_divergence: 0, partial_implementation: 0, fully_implemented: 0}, skipped: true, reason: "no_code_diff"}' > "$output_path"
        exit 0
    fi

    local diff_chars=${#code_diff}
    # Truncate diff to remaining token budget (same budget split as sections)
    if [[ $diff_chars -gt $max_section_chars ]]; then
        code_diff="${code_diff:0:$max_section_chars}"$'\n[... diff truncated to token budget ...]'
        log "Code diff: $diff_chars characters (truncated to $max_section_chars)"
    else
        log "Code diff: $diff_chars characters"
    fi

    # Dry run
    if [[ "$dry_run" == true ]]; then
        log "Dry run — validation passed"
        jq -n \
            --arg sdd "$sdd_path" \
            --arg sprint "$sprint_id" \
            --argjson section_chars "$section_chars" \
            --argjson diff_chars "$diff_chars" \
            --argjson token_budget "$token_budget" \
            '{status: "dry_run", sdd: $sdd, sprint: $sprint, section_chars: $section_chars, diff_chars: $diff_chars, token_budget: $token_budget}'
        exit 0
    fi

    # Build comparison prompt
    local prompt_file stderr_tmp
    prompt_file=$(mktemp)
    stderr_tmp=$(mktemp)
    trap 'rm -f "$prompt_file" "$stderr_tmp"' EXIT
    cat > "$prompt_file" << 'PROMPT'
You are a security design verification agent. Compare the SDD security design specifications below to the actual code changes.

For each security design requirement found in the SDD sections, classify the implementation status as:

- **CONFIRMED_DIVERGENCE**: The code explicitly contradicts or omits a security requirement from the SDD. Severity 700-1000.
- **PARTIAL_IMPLEMENTATION**: The code partially implements a security requirement but has gaps. Severity 400-699.
- **FULLY_IMPLEMENTED**: The code correctly implements the security requirement. Severity 0 (informational).

Output ONLY valid JSON in this format:
```json
{
  "findings": [
    {
      "id": "RTC-001",
      "sdd_section": "section header from SDD",
      "sdd_requirement": "the specific requirement",
      "code_evidence": "file:line — description of what the code does",
      "classification": "CONFIRMED_DIVERGENCE|PARTIAL_IMPLEMENTATION|FULLY_IMPLEMENTED",
      "severity": 750,
      "recommendation": "what should change"
    }
  ]
}
```

Focus on actionable findings. Do not invent requirements not present in the SDD.
PROMPT

    # Append SDD sections
    echo "" >> "$prompt_file"
    echo "## SDD Security Sections" >> "$prompt_file"
    echo "" >> "$prompt_file"
    echo "$security_sections" >> "$prompt_file"

    # Append prior findings if provided (Deliberative Council pattern)
    if [[ ${#prior_findings_paths[@]} -gt 0 ]]; then
        local prior_content=""
        for pf_path in "${prior_findings_paths[@]}"; do
            local pf_extracted
            pf_extracted=$(extract_prior_findings "$pf_path" "$max_section_chars")
            if [[ -n "$pf_extracted" ]]; then
                local pf_name
                pf_name=$(basename "$pf_path")
                prior_content+="### From $pf_name"$'\n\n'"$pf_extracted"$'\n\n'
            fi
        done
        if [[ -n "$prior_content" ]]; then
            local prior_chars=${#prior_content}
            if [[ $prior_chars -gt $max_section_chars ]]; then
                prior_content="${prior_content:0:$max_section_chars}"$'\n[... prior findings truncated to token budget ...]\n'
                log "Prior findings: $prior_chars chars (truncated to $max_section_chars)"
            else
                log "Prior findings: $prior_chars chars from ${#prior_findings_paths[@]} files"
            fi
            echo "" >> "$prompt_file"
            echo "## Prior Review Findings" >> "$prompt_file"
            echo "" >> "$prompt_file"
            echo "The following findings were identified by earlier review stages." >> "$prompt_file"
            echo "Use these to focus your design compliance analysis on areas already flagged." >> "$prompt_file"
            echo "" >> "$prompt_file"
            echo "$prior_content" >> "$prompt_file"
        fi
    fi

    # Append code diff
    echo "" >> "$prompt_file"
    echo "## Code Changes (git diff)" >> "$prompt_file"
    echo "" >> "$prompt_file"
    echo "$code_diff" >> "$prompt_file"

    # Invoke model
    log "Invoking model for code-vs-design comparison (budget: $token_budget tokens)"
    local model_output exit_code=0
    model_output=$("$MODEL_ADAPTER" \
        --model opus \
        --mode dissent \
        --input "$prompt_file" \
        --timeout 120 \
        --json 2>"$stderr_tmp") || exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        local stderr_tail
        stderr_tail=$(tail -5 "$stderr_tmp" 2>/dev/null || echo "(no stderr)")
        error "Model invocation failed (exit $exit_code): $stderr_tail"
        exit 1
    fi

    # Parse findings from model output
    local findings_json
    findings_json=$(echo "$model_output" | jq -r '.content // ""' 2>/dev/null)

    # Strip markdown code fences if present (two-pass: awk range for multi-line, sed fallback)
    if echo "$findings_json" | head -1 | grep -qE '^\s*```'; then
        findings_json=$(echo "$findings_json" | awk '/^[[:space:]]*```/{if(f){exit}else{f=1;next}} f')
    fi

    # Validate JSON
    if ! echo "$findings_json" | jq '.' > /dev/null 2>&1; then
        error "Model output is not valid JSON"
        # Write error findings
        jq -n '{findings: [], summary: {total: 0, confirmed_divergence: 0, partial_implementation: 0, fully_implemented: 0}, error: "invalid_model_output"}' > "$output_path"
        exit 1
    fi

    # Compute summary
    local final_output
    final_output=$(echo "$findings_json" | jq --argjson threshold "$severity_threshold" '{
        findings: .findings,
        summary: {
            total: (.findings | length),
            confirmed_divergence: ([.findings[] | select(.classification == "CONFIRMED_DIVERGENCE")] | length),
            partial_implementation: ([.findings[] | select(.classification == "PARTIAL_IMPLEMENTATION")] | length),
            fully_implemented: ([.findings[] | select(.classification == "FULLY_IMPLEMENTED")] | length),
            actionable: ([.findings[] | select(.classification == "CONFIRMED_DIVERGENCE" and .severity >= $threshold)] | length)
        }
    }')

    # Write output
    mkdir -p "$(dirname "$output_path")"
    echo "$final_output" | jq . > "$output_path"
    chmod 600 "$output_path"

    local total divergences
    total=$(echo "$final_output" | jq '.summary.total')
    divergences=$(echo "$final_output" | jq '.summary.confirmed_divergence')
    local actionable
    actionable=$(echo "$final_output" | jq '.summary.actionable')

    log "Findings: $total total, $divergences divergences ($actionable actionable above threshold $severity_threshold)"
    log "Output: $output_path"
}

main "$@"
