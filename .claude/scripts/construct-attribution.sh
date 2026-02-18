#!/usr/bin/env bash
# =============================================================================
# construct-attribution.sh - Attribute feedback to installed constructs
# =============================================================================
# Version: 1.0.0
# Cycle: cycle-025 (Cross-Codebase Feedback Routing)
# Source: grimoires/loa/sdd.md §2.1
#
# Maps feedback text to installed constructs using weighted signal scoring.
#
# Usage:
#   construct-attribution.sh --context <file_or_->
#   echo "context" | construct-attribution.sh --context -
#
# Exit codes:
#   0 - Attribution successful (attributed=true or attributed=false)
#   1 - Invalid input (missing --context, unreadable file)
#   2 - Corrupt .constructs-meta.json (invalid JSON)
#
# Output JSON schema (stdout):
#   {
#     "attributed": boolean,
#     "construct": "vendor/pack" | null,
#     "construct_type": "pack" | "skill" | null,
#     "source_repo": "owner/repo" | null,
#     "confidence": 0.0-1.0,
#     "signals": ["signal_type:detail", ...],
#     "trust_warning": "string" | null,
#     "version": "semver" | null,
#     "ambiguous": boolean,
#     "candidates": [{"construct": "...", "confidence": 0.0}] | null
#   }
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Require bash 4.0+ (associative arrays)
# shellcheck source=bash-version-guard.sh
source "$SCRIPT_DIR/bash-version-guard.sh"

# Source shared library for registry functions
# shellcheck source=constructs-lib.sh
source "$SCRIPT_DIR/constructs-lib.sh"

# --- Argument parsing ---

CONTEXT_FILE=""

usage() {
    cat << 'USAGE_EOF'
construct-attribution.sh - Attribute feedback to installed constructs

USAGE:
    construct-attribution.sh --context <file>
    construct-attribution.sh --context -
    echo "context" | construct-attribution.sh --context -

OPTIONS:
    --context <file>    File containing context to attribute (use - for stdin)
    --help              Show this help message

EXIT CODES:
    0 - Success (attributed=true or attributed=false)
    1 - Invalid input
    2 - Corrupt metadata
USAGE_EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --context)
            if [[ $# -lt 2 ]]; then
                echo "Error: --context requires a value" >&2
                exit 1
            fi
            CONTEXT_FILE="$2"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "Error: Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

# Validate required argument
if [[ -z "$CONTEXT_FILE" ]]; then
    echo "Error: --context is required" >&2
    usage >&2
    exit 1
fi

# Read context
CONTEXT=""
if [[ "$CONTEXT_FILE" == "-" ]]; then
    CONTEXT=$(cat)
elif [[ -f "$CONTEXT_FILE" ]]; then
    CONTEXT=$(cat "$CONTEXT_FILE")
else
    echo "Error: Context file not found: $CONTEXT_FILE" >&2
    exit 1
fi

if [[ -z "$CONTEXT" ]]; then
    echo "Error: Context is empty" >&2
    exit 1
fi

# --- No-construct fast path ---

META_PATH=$(get_registry_meta_path)

if [[ ! -f "$META_PATH" ]]; then
    cat << 'FAST_EOF'
{"attributed": false, "construct": null, "construct_type": null, "source_repo": null, "confidence": 0.0, "signals": [], "trust_warning": null, "version": null, "ambiguous": false, "candidates": null}
FAST_EOF
    exit 0
fi

# Validate JSON integrity
if ! jq empty "$META_PATH" 2>/dev/null; then
    echo "Error: Corrupt .constructs-meta.json (invalid JSON)" >&2
    exit 2
fi

# Check for installed skills and packs
INSTALLED_SKILLS=$(jq -r '.installed_skills // {} | keys[]' "$META_PATH" 2>/dev/null || true)
INSTALLED_PACKS=$(jq -r '.installed_packs // {} | keys[]' "$META_PATH" 2>/dev/null || true)

if [[ -z "$INSTALLED_SKILLS" ]] && [[ -z "$INSTALLED_PACKS" ]]; then
    cat << 'FAST_EOF'
{"attributed": false, "construct": null, "construct_type": null, "source_repo": null, "confidence": 0.0, "signals": [], "trust_warning": null, "version": null, "ambiguous": false, "candidates": null}
FAST_EOF
    exit 0
fi

# --- Build lookup tables ---

declare -A CONSTRUCT_SCORES
declare -A CONSTRUCT_SIGNALS
declare -A CONSTRUCT_TYPES
declare -A CONSTRUCT_VERSIONS

SKILLS_DIR=$(get_registry_skills_dir)
PACKS_DIR=$(get_registry_packs_dir)

# --- Portable word-boundary matching (BB-101) ---
# grep -P (Perl regex \b) is not available on macOS/BSD. Detect and fall back.
HAS_GREP_P=false
if printf 'test' | grep -qP '\btest\b' 2>/dev/null; then
    HAS_GREP_P=true
fi

# Match a word with word-boundary semantics, case-insensitive
# Uses grep -P \b when available, falls back to grep -wi (whole-word)
grep_word_boundary() {
    local word="$1"
    if [[ "$HAS_GREP_P" == "true" ]]; then
        grep -qiP -- "\\b${word}\\b" 2>/dev/null
    else
        grep -qwi -- "$word" 2>/dev/null
    fi
}

# --- Scoring function ---
# Signal weights: path_match=1.0, skill_name=0.6, vendor_name=0.4, explicit_mention=1.0
# Max possible = 3.0

add_score() {
    local construct="$1"
    local weight="$2"
    local signal="$3"

    local current="${CONSTRUCT_SCORES[$construct]:-0}"
    # Use awk for float addition
    CONSTRUCT_SCORES[$construct]=$(awk "BEGIN{printf \"%.2f\", $current + $weight}")

    local existing="${CONSTRUCT_SIGNALS[$construct]:-}"
    if [[ -n "$existing" ]]; then
        CONSTRUCT_SIGNALS[$construct]="${existing}|${signal}"
    else
        CONSTRUCT_SIGNALS[$construct]="$signal"
    fi
}

# --- Unified construct scoring function (BB-103: DRY) ---
# Scores a single construct against all 4 signal types.
# Args: $1=construct_key $2=construct_type $3=meta_section $4=primary_path $5=alt_path_base
score_construct() {
    local c_key="$1"
    local c_type="$2"
    local meta_section="$3"
    local primary_path="$4"
    local alt_path="$5"

    local c_vendor c_name
    c_vendor=$(echo "$c_key" | cut -d'/' -f1)
    c_name=$(echo "$c_key" | cut -d'/' -f2)

    CONSTRUCT_TYPES[$c_key]="$c_type"

    # Get version from metadata
    local c_version
    c_version=$(jq -r ".${meta_section}[\"$c_key\"].version // \"unknown\"" "$META_PATH" 2>/dev/null || echo "unknown")
    CONSTRUCT_VERSIONS[$c_key]="$c_version"

    # Signal 1: Path match (weight 1.0)
    if printf '%s' "$CONTEXT" | grep -qF -- "$primary_path" 2>/dev/null || \
       printf '%s' "$CONTEXT" | grep -qF -- "$alt_path" 2>/dev/null; then
        add_score "$c_key" "1.0" "path_match:${alt_path}"
    fi

    # Signal 2: Name match (weight 0.6, word-boundary, min 4 chars)
    if [[ ${#c_name} -ge 4 ]]; then
        if printf '%s' "$CONTEXT" | grep_word_boundary "$c_name"; then
            add_score "$c_key" "0.6" "${c_type}_name:${c_name}"
        fi
    fi

    # Signal 3: Vendor name match (weight 0.4, word-boundary, min 4 chars)
    if [[ ${#c_vendor} -ge 4 ]]; then
        if printf '%s' "$CONTEXT" | grep_word_boundary "$c_vendor"; then
            add_score "$c_key" "0.4" "vendor_name:${c_vendor}"
        fi
    fi

    # Signal 4: Explicit mention (weight 1.0)
    if printf '%s' "$CONTEXT" | grep -qiE -- "(construct|${c_type}):${c_name}" 2>/dev/null; then
        add_score "$c_key" "1.0" "explicit_mention:${c_name}"
    fi
}

# --- Score installed packs ---

while IFS= read -r pack_key; do
    [[ -z "$pack_key" ]] && continue
    local_name=$(echo "$pack_key" | cut -d'/' -f2)
    score_construct "$pack_key" "pack" "installed_packs" \
        "${PACKS_DIR}/${local_name}/" \
        ".claude/constructs/packs/${local_name}/"
done <<< "$INSTALLED_PACKS"

# --- Score installed skills ---

while IFS= read -r skill_key; do
    [[ -z "$skill_key" ]] && continue
    local_vendor=$(echo "$skill_key" | cut -d'/' -f1)
    local_name=$(echo "$skill_key" | cut -d'/' -f2)
    score_construct "$skill_key" "skill" "installed_skills" \
        "${SKILLS_DIR}/${local_vendor}/${local_name}/" \
        ".claude/constructs/skills/${local_vendor}/${local_name}/"
done <<< "$INSTALLED_SKILLS"

# --- Find best match with disambiguation ---

BEST_CONSTRUCT=""
BEST_SCORE="0.00"
SECOND_BEST_SCORE="0.00"
ALL_MATCHES=()

for construct in "${!CONSTRUCT_SCORES[@]}"; do
    score="${CONSTRUCT_SCORES[$construct]}"

    # Skip zero scores
    if awk "BEGIN{exit !($score > 0)}" 2>/dev/null; then
        ALL_MATCHES+=("$construct")

        if awk "BEGIN{exit !($score > $BEST_SCORE)}" 2>/dev/null; then
            SECOND_BEST_SCORE="$BEST_SCORE"
            BEST_SCORE="$score"
            BEST_CONSTRUCT="$construct"
        elif awk "BEGIN{exit !($score > $SECOND_BEST_SCORE)}" 2>/dev/null; then
            SECOND_BEST_SCORE="$score"
        fi
    fi
done

# No match found
if [[ -z "$BEST_CONSTRUCT" ]]; then
    cat << 'NOMATCH_EOF'
{"attributed": false, "construct": null, "construct_type": null, "source_repo": null, "confidence": 0.0, "signals": [], "trust_warning": null, "version": null, "ambiguous": false, "candidates": null}
NOMATCH_EOF
    exit 0
fi

# Normalize confidence: score / 3.0, capped at 1.0
MAX_POSSIBLE="3.0"
CONFIDENCE=$(awk "BEGIN{c = $BEST_SCORE / $MAX_POSSIBLE; if(c > 1.0) c = 1.0; printf \"%.2f\", c}")

# Check ambiguity: top two within 0.1
IS_AMBIGUOUS="false"
SCORE_DIFF=$(awk "BEGIN{printf \"%.2f\", $BEST_SCORE - $SECOND_BEST_SCORE}")
if [[ ${#ALL_MATCHES[@]} -gt 1 ]] && awk "BEGIN{exit !($SCORE_DIFF <= 0.10)}" 2>/dev/null; then
    IS_AMBIGUOUS="true"
fi

# --- Resolve source_repo from manifest ---

CONSTRUCT_TYPE="${CONSTRUCT_TYPES[$BEST_CONSTRUCT]}"
CONSTRUCT_VERSION="${CONSTRUCT_VERSIONS[$BEST_CONSTRUCT]:-unknown}"

local_vendor=$(echo "$BEST_CONSTRUCT" | cut -d'/' -f1)
local_name=$(echo "$BEST_CONSTRUCT" | cut -d'/' -f2)

SOURCE_REPO=""
TRUST_WARNING=""

# Find manifest
MANIFEST_PATH=""
if [[ "$CONSTRUCT_TYPE" == "pack" ]]; then
    if [[ -f "${PACKS_DIR}/${local_name}/manifest.yaml" ]]; then
        MANIFEST_PATH="${PACKS_DIR}/${local_name}/manifest.yaml"
    elif [[ -f "${PACKS_DIR}/${local_name}/manifest.json" ]]; then
        MANIFEST_PATH="${PACKS_DIR}/${local_name}/manifest.json"
    fi
elif [[ "$CONSTRUCT_TYPE" == "skill" ]]; then
    if [[ -f "${SKILLS_DIR}/${local_vendor}/${local_name}/manifest.yaml" ]]; then
        MANIFEST_PATH="${SKILLS_DIR}/${local_vendor}/${local_name}/manifest.yaml"
    elif [[ -f "${SKILLS_DIR}/${local_vendor}/${local_name}/manifest.json" ]]; then
        MANIFEST_PATH="${SKILLS_DIR}/${local_vendor}/${local_name}/manifest.json"
    fi
fi

if [[ -n "$MANIFEST_PATH" ]]; then
    if [[ "$MANIFEST_PATH" == *.yaml ]]; then
        if command -v yq &>/dev/null; then
            SOURCE_REPO=$(yq -r '.source_repo // ""' "$MANIFEST_PATH" 2>/dev/null || echo "")
        fi
    else
        SOURCE_REPO=$(jq -r '.source_repo // ""' "$MANIFEST_PATH" 2>/dev/null || echo "")
    fi
fi

# --- Trust validation (3-level) ---

if [[ -n "$SOURCE_REPO" ]]; then
    # Level 1: Format validation (owner/repo pattern)
    if ! echo "$SOURCE_REPO" | grep -qE '^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$'; then
        TRUST_WARNING="source_repo format invalid: must be owner/repo"
        SOURCE_REPO=""  # Block routing on format failure
    else
        # Level 2: Org match check
        repo_org=$(echo "$SOURCE_REPO" | cut -d'/' -f1)
        if [[ "$repo_org" != "$local_vendor" ]]; then
            TRUST_WARNING="source_repo org '${repo_org}' does not match vendor '${local_vendor}'"
        fi

        # Level 3: Repo existence check (non-blocking, only if gh available)
        if command -v gh &>/dev/null && [[ -n "$SOURCE_REPO" ]]; then
            if ! gh repo view "$SOURCE_REPO" --json name >/dev/null 2>&1; then
                if [[ -n "$TRUST_WARNING" ]]; then
                    TRUST_WARNING="${TRUST_WARNING}; source_repo '${SOURCE_REPO}' does not exist or is not accessible"
                else
                    TRUST_WARNING="source_repo '${SOURCE_REPO}' does not exist or is not accessible"
                fi
            fi
        fi
    fi
fi

# --- Build signals JSON ---

SIGNALS_JSON="["
FIRST_SIGNAL=true
IFS='|' read -ra SIGNAL_ARRAY <<< "${CONSTRUCT_SIGNALS[$BEST_CONSTRUCT]:-}"
for signal in "${SIGNAL_ARRAY[@]}"; do
    [[ -z "$signal" ]] && continue
    if [[ "$FIRST_SIGNAL" == "true" ]]; then
        FIRST_SIGNAL=false
    else
        SIGNALS_JSON+=","
    fi
    escaped_signal=$(printf '%s' "$signal" | sed 's/\\/\\\\/g; s/"/\\"/g')
    SIGNALS_JSON+="\"$escaped_signal\""
done
SIGNALS_JSON+="]"

# --- Build candidates JSON (if ambiguous) ---

CANDIDATES_JSON="null"
if [[ "$IS_AMBIGUOUS" == "true" ]]; then
    CANDIDATES_JSON="["
    FIRST_CANDIDATE=true
    for match in "${ALL_MATCHES[@]}"; do
        match_score="${CONSTRUCT_SCORES[$match]}"
        match_conf=$(awk "BEGIN{c = $match_score / $MAX_POSSIBLE; if(c > 1.0) c = 1.0; printf \"%.2f\", c}")
        if [[ "$FIRST_CANDIDATE" == "true" ]]; then
            FIRST_CANDIDATE=false
        else
            CANDIDATES_JSON+=","
        fi
        CANDIDATES_JSON+="{\"construct\":\"$match\",\"confidence\":$match_conf}"
    done
    CANDIDATES_JSON+="]"
fi

# --- Output JSON (BB-106: use jq for safe JSON construction) ---

# Build base JSON with jq to prevent shell expansion issues
jq --null-input \
    --arg construct "$BEST_CONSTRUCT" \
    --arg construct_type "$CONSTRUCT_TYPE" \
    --arg source_repo "$SOURCE_REPO" \
    --argjson confidence "$CONFIDENCE" \
    --argjson signals "$SIGNALS_JSON" \
    --arg trust_warning "$TRUST_WARNING" \
    --arg version "$CONSTRUCT_VERSION" \
    --argjson ambiguous "$IS_AMBIGUOUS" \
    --argjson candidates "$CANDIDATES_JSON" \
    '{
        attributed: true,
        construct: $construct,
        construct_type: $construct_type,
        source_repo: (if $source_repo == "" then null else $source_repo end),
        confidence: $confidence,
        signals: $signals,
        trust_warning: (if $trust_warning == "" then null else $trust_warning end),
        version: (if $version == "" or $version == "unknown" then null else $version end),
        ambiguous: $ambiguous,
        candidates: $candidates
    }'
