#!/usr/bin/env bash
# =============================================================================
# compliance-lib.sh — Shared library for compliance gate extraction and profiles
# =============================================================================
# Part of: Shared Library Extraction (cycle-047, Sprint 3 T3.2/T3.5)
#
# Extracts SDD sections by keyword matching and loads compliance gate profiles.
# Separates extraction (returning raw text) from evaluation (model prompt
# interpretation). Sourceable with no side effects.
#
# Architecture:
#   EXTRACTION: extract_sections_by_keywords() → raw SDD sections as text
#   PROFILES:   load_compliance_profile() → {keywords, prompt_template}
#   EVALUATION:  get_evaluation_context() → prompt preamble for model invocation
#
# Prompt Templates:
#   Template names map to prompt construction patterns used by the model
#   invocation step. Currently only "security-comparison" exists (default).
#   To add new templates:
#     1. Add profile under red_team.compliance_gates.<name> in .loa.config.yaml
#     2. Set prompt_template: "<template-name>"
#     3. Add case in get_evaluation_context() for the new template
#
# Consumers:
#   - red-team-code-vs-design.sh (primary — security compliance)
#   - pipeline-self-review.sh (future — pipeline compliance)
#
# Usage:
#   source .claude/scripts/lib/compliance-lib.sh
# =============================================================================

# Guard against double-sourcing
[[ -n "${_COMPLIANCE_LIB_LOADED:-}" ]] && return 0
_COMPLIANCE_LIB_LOADED=1

# =============================================================================
# SDD Section Extraction
# =============================================================================

# Extract sections from a document matching header keywords.
# Parameterized for reuse across compliance gate profiles (cycle-046 FR-4).
#
# Args:
#   $1 - file path
#   $2 - max chars (default 20000)
#   $3 - pipe-separated keyword regex (default: security keywords)
#
# Returns:
#   0 - sections found, output on stdout
#   1 - file not found
#   3 - no matching sections found
extract_sections_by_keywords() {
    local file_path="$1"
    local max_chars="${2:-20000}"  # ~5K tokens
    local keywords="${3:-Security|Authentication|Authorization|Validation|Error.Handling|Access.Control|Secrets|Encryption|Input.Sanitiz}"

    if [[ ! -f "$file_path" ]]; then
        echo "[compliance-lib] ERROR: File not found: $file_path" >&2
        return 1
    fi

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

            # Check if this header matches the keyword pattern
            if printf '%s\n' "$line" | grep -iqE "($keywords)"; then
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
    done < "$file_path"

    if [[ -z "$output" ]]; then
        return 3  # No matching sections found
    fi

    echo "$output"
}

# =============================================================================
# Compliance Profile Loading
# =============================================================================

# Load keywords for a compliance gate from config.
# Falls back to hardcoded security defaults if config is unavailable.
#
# Args:
#   $1 - profile name (default: "security")
#   $2 - config file path (default: PROJECT_ROOT/.loa.config.yaml)
#
# Returns:
#   Pipe-separated keyword string on stdout
load_compliance_keywords() {
    local profile="${1:-security}"
    local config_file="${2:-${PROJECT_ROOT:-.}/.loa.config.yaml}"
    local default_keywords="Security|Authentication|Authorization|Validation|Error.Handling|Access.Control|Secrets|Encryption|Input.Sanitiz"

    if command -v yq &>/dev/null && [[ -f "$config_file" ]]; then
        local config_keywords
        config_keywords=$(yq ".red_team.compliance_gates.${profile}.keywords // [] | join(\"|\")" "$config_file" 2>/dev/null || echo "")
        if [[ -n "$config_keywords" ]]; then
            echo "$config_keywords"
            return
        fi
    fi

    echo "$default_keywords"
}

# Load full compliance profile: keywords + prompt_template.
#
# Args:
#   $1 - profile name (default: "security")
#   $2 - config file path (default: PROJECT_ROOT/.loa.config.yaml)
#
# Returns:
#   JSON object on stdout: {"keywords": "...", "prompt_template": "..."}
load_compliance_profile() {
    local profile="${1:-security}"
    local config_file="${2:-${PROJECT_ROOT:-.}/.loa.config.yaml}"

    local keywords
    keywords=$(load_compliance_keywords "$profile" "$config_file")

    local template="security-comparison"
    if command -v yq &>/dev/null && [[ -f "$config_file" ]]; then
        local config_template
        config_template=$(yq ".red_team.compliance_gates.${profile}.prompt_template // \"\"" "$config_file" 2>/dev/null || echo "")
        if [[ -n "$config_template" && "$config_template" != "null" ]]; then
            template="$config_template"
        fi
    fi

    jq -n --arg keywords "$keywords" --arg template "$template" \
        '{keywords: $keywords, prompt_template: $template}'
}

# Load only the prompt template name for a compliance gate.
#
# Args:
#   $1 - profile name (default: "security")
#   $2 - config file path (default: PROJECT_ROOT/.loa.config.yaml)
#
# Returns:
#   Template name on stdout (e.g., "security-comparison")
load_prompt_template() {
    local profile="${1:-security}"
    local config_file="${2:-${PROJECT_ROOT:-.}/.loa.config.yaml}"

    if command -v yq &>/dev/null && [[ -f "$config_file" ]]; then
        local config_template
        config_template=$(yq ".red_team.compliance_gates.${profile}.prompt_template // \"\"" "$config_file" 2>/dev/null || echo "")
        if [[ -n "$config_template" && "$config_template" != "null" ]]; then
            echo "$config_template"
            return
        fi
    fi

    echo "security-comparison"
}

# =============================================================================
# Evaluation Context (T3.5 — extraction/evaluation separation)
# =============================================================================

# Return a structured prompt preamble based on the compliance gate profile's
# prompt_template. This separates WHAT to extract (keywords) from HOW to
# evaluate (prompt construction).
#
# Args:
#   $1 - template name (e.g., "security-comparison")
#
# Returns:
#   Prompt preamble text on stdout
get_evaluation_context() {
    local template="${1:-security-comparison}"

    case "$template" in
        security-comparison)
            cat <<'PREAMBLE'
You are a security compliance reviewer. Compare the SDD security design sections
against the actual code changes (diff). For each security concern in the SDD,
determine whether the implementation FULLY_IMPLEMENTS, PARTIALLY_IMPLEMENTS, or
shows CONFIRMED_DIVERGENCE from the design intent.

Focus on: authentication flows, authorization checks, input validation, secrets
handling, error exposure, and access control boundaries.
PREAMBLE
            ;;
        # Future templates:
        # api_contract)
        #     cat <<'PREAMBLE'
        # You are an API contract reviewer. Compare the SDD API specifications...
        # PREAMBLE
        #     ;;
        # economic_invariant)
        #     cat <<'PREAMBLE'
        # You are an economic invariant reviewer. Compare the SDD economic...
        # PREAMBLE
        #     ;;
        *)
            echo "Unknown template: $template — using security-comparison defaults" >&2
            get_evaluation_context "security-comparison"
            ;;
    esac
}
