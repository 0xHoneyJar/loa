#!/usr/bin/env bash
# =============================================================================
# findings-lib.sh — Shared library for findings extraction and processing
# =============================================================================
# Part of: Shared Library Extraction (cycle-047, Sprint 3 T3.1)
#
# Extracts actionable findings from review/audit feedback files and strips
# code fences from model output. Sourceable with no side effects.
#
# Consumers:
#   - red-team-code-vs-design.sh (primary — Deliberative Council prior findings)
#   - pipeline-self-review.sh (future — findings aggregation)
#   - bridge-findings-parser.sh (future — output normalization)
#
# Usage:
#   source .claude/scripts/lib/findings-lib.sh
# =============================================================================

# Guard against double-sourcing
[[ -n "${_FINDINGS_LIB_LOADED:-}" ]] && return 0
_FINDINGS_LIB_LOADED=1

# =============================================================================
# Prior Findings Extraction (Deliberative Council pattern — cycle-046 FR-2)
# =============================================================================

# Extract actionable findings from prior review/audit feedback files.
# Looks for ## Findings, ## Issues, ## Changes Required, ## Security sections.
# Returns truncated content or empty string for missing/empty files.
#
# Args:
#   $1 - file path
#   $2 - max chars (default 20000)
#
# Returns:
#   0 - always (empty string for missing files)
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
            if printf '%s\n' "$line" | grep -iqE '(Findings|Issues|Changes.Required|Security|Concerns|Recommendations|SEC-[0-9]|Audit|Observations)'; then
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
# Code Fence Stripping (F-007 hardening — cycle-047 T1.4)
# =============================================================================

# Strip markdown code fences from model output.
# Handles both cases:
#   (a) first line is a code fence — extract content between fences
#   (b) preamble text before fence — skip to first fence, then extract
#
# Args:
#   $1 - input string (model output)
#
# Returns:
#   Stripped content on stdout
strip_code_fences() {
    local input="$1"

    if echo "$input" | grep -qE '^[[:space:]]*```'; then
        # Extract content between first pair of code fences (handles both
        # leading fence and preamble-before-fence cases identically)
        echo "$input" | awk '/^[[:space:]]*```/{if(f){exit}else{f=1;next}} f'
    else
        # No fences found — return as-is
        echo "$input"
    fi
}
