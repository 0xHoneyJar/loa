#!/usr/bin/env bash
# =============================================================================
# upstream-score-calculator.sh - Calculate Upstream Eligibility Score
# =============================================================================
# Sprint 1, Task T1.2: Weighted score aggregation for upstream proposal eligibility
# Goal Contribution: G-4 (Define learning proposal schema), G-5 (Silent detection)
#
# Calculates a weighted score from 4 components:
#   - Quality Gates (25%): From quality-gates.sh
#   - Effectiveness (30%): From calculate-effectiveness.sh
#   - Novelty (25%): Via jaccard-similarity.sh against framework learnings
#   - Generality (20%): Domain-agnostic extraction scoring
#
# Usage:
#   ./upstream-score-calculator.sh --learning <ID>
#   ./upstream-score-calculator.sh --learning <ID> --format json
#   ./upstream-score-calculator.sh --learning <ID> --check-eligibility
#
# Options:
#   --learning ID       Learning ID to evaluate (required)
#   --format FORMAT     Output format: json (default), summary
#   --check-eligibility Only check if eligible (exits 0/1)
#   --verbose           Show detailed breakdown
#   --help              Show this help
#
# Eligibility Thresholds (configurable via .loa.config.yaml):
#   - upstream_score >= 70
#   - applications >= 3
#   - success_rate >= 80%
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_FILE="$PROJECT_ROOT/.loa.config.yaml"

# Paths to dependency scripts
QUALITY_GATES_SCRIPT="$SCRIPT_DIR/quality-gates.sh"
EFFECTIVENESS_SCRIPT="$SCRIPT_DIR/calculate-effectiveness.sh"
JACCARD_SCRIPT="$SCRIPT_DIR/jaccard-similarity.sh"

# Learnings paths
FRAMEWORK_LEARNINGS_DIR="$PROJECT_ROOT/.claude/loa/learnings"
PROJECT_LEARNINGS_FILE="$PROJECT_ROOT/grimoires/loa/a2a/compound/learnings.json"

# Component weights (from PRD)
QUALITY_WEIGHT=25
EFFECTIVENESS_WEIGHT=30
NOVELTY_WEIGHT=25
GENERALITY_WEIGHT=20

# Default thresholds
MIN_SCORE=70
MIN_APPLICATIONS=3
MIN_SUCCESS_RATE=80

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# Parameters
LEARNING_ID=""
OUTPUT_FORMAT="json"
CHECK_ELIGIBILITY=false
VERBOSE=false

usage() {
    sed -n '/^# Usage:/,/^# =====/p' "$0" | grep -v "^# =====" | sed 's/^# //'
    exit 0
}

# Read config value with yq, fallback to default
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

# Load thresholds from config
load_config() {
    MIN_SCORE=$(read_config '.upstream_detection.min_upstream_score' '70')
    MIN_APPLICATIONS=$(read_config '.upstream_detection.min_occurrences' '3')
    MIN_SUCCESS_RATE=$(read_config '.upstream_detection.min_success_rate' '0.8')
    # Convert success rate to percentage if it's a decimal
    if [[ "$MIN_SUCCESS_RATE" == "0."* ]]; then
        MIN_SUCCESS_RATE=$(echo "$MIN_SUCCESS_RATE * 100" | bc | cut -d'.' -f1)
    fi
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --learning)
                LEARNING_ID="$2"
                shift 2
                ;;
            --format)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            --check-eligibility)
                CHECK_ELIGIBILITY=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --help|-h)
                usage
                ;;
            *)
                echo "[ERROR] Unknown option: $1" >&2
                exit 1
                ;;
        esac
    done

    if [[ -z "$LEARNING_ID" ]]; then
        echo "[ERROR] --learning ID is required" >&2
        exit 1
    fi

    # MEDIUM-001 FIX: Validate learning ID format (alphanumeric, hyphens, underscores)
    if [[ ! "$LEARNING_ID" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "[ERROR] Invalid learning ID format: must be alphanumeric with hyphens/underscores only" >&2
        exit 1
    fi
}

# Get learning from project learnings file
get_learning() {
    local id="$1"

    if [[ ! -f "$PROJECT_LEARNINGS_FILE" ]]; then
        echo ""
        return 1
    fi

    jq --arg id "$id" '.learnings[] | select(.id == $id)' "$PROJECT_LEARNINGS_FILE" 2>/dev/null || echo ""
}

# Calculate quality score (0-100) from quality gates
# Uses quality-gates.sh if learning has pattern structure, otherwise estimates from fields
calculate_quality_score() {
    local learning="$1"

    # Check if quality_gates are already present
    local existing_gates
    existing_gates=$(echo "$learning" | jq -r '.quality_gates // empty')

    if [[ -n "$existing_gates" && "$existing_gates" != "null" ]]; then
        # Use existing quality gates
        local dd rd tc vr
        dd=$(echo "$learning" | jq -r '.quality_gates.discovery_depth // 5')
        rd=$(echo "$learning" | jq -r '.quality_gates.reusability // 5')
        tc=$(echo "$learning" | jq -r '.quality_gates.trigger_clarity // 5')
        vr=$(echo "$learning" | jq -r '.quality_gates.verification // 5')

        # Average and scale to 0-100
        local avg
        avg=$(echo "scale=2; ($dd + $rd + $tc + $vr) / 4 * 10" | bc)
        printf "%.0f" "$avg"
        return
    fi

    # Estimate quality from available fields
    local score=50  # Base score

    # Check trigger field (adds clarity)
    local trigger
    trigger=$(echo "$learning" | jq -r '.trigger // ""')
    if [[ -n "$trigger" && ${#trigger} -gt 20 ]]; then
        score=$((score + 15))
    fi

    # Check solution field
    local solution
    solution=$(echo "$learning" | jq -r '.solution // ""')
    if [[ -n "$solution" && ${#solution} -gt 50 ]]; then
        score=$((score + 15))
    fi

    # Check verified flag
    local verified
    verified=$(echo "$learning" | jq -r '.verified // false')
    if [[ "$verified" == "true" ]]; then
        score=$((score + 20))
    fi

    # Clamp to 0-100
    [[ $score -gt 100 ]] && score=100
    [[ $score -lt 0 ]] && score=0

    echo "$score"
}

# Calculate effectiveness score (0-100)
calculate_effectiveness_score() {
    local learning="$1"

    # Check for existing effectiveness_score
    local existing_score
    existing_score=$(echo "$learning" | jq -r '.effectiveness_score // "null"')

    if [[ "$existing_score" != "null" && -n "$existing_score" ]]; then
        echo "$existing_score"
        return
    fi

    # Calculate from applications
    local applications
    applications=$(echo "$learning" | jq -r '.applications // []')
    local app_count
    app_count=$(echo "$applications" | jq 'length')

    if [[ "$app_count" -eq 0 ]]; then
        echo "50"  # Default for no applications
        return
    fi

    # Count successful applications
    local successes
    successes=$(echo "$applications" | jq '[.[] | select(.outcome == "success")] | length')

    # Calculate success rate as percentage
    local success_rate
    success_rate=$(echo "scale=2; $successes / $app_count * 100" | bc | cut -d'.' -f1)

    # Weight by application count (more applications = more confidence)
    local confidence_bonus=0
    if [[ "$app_count" -ge 5 ]]; then
        confidence_bonus=10
    elif [[ "$app_count" -ge 3 ]]; then
        confidence_bonus=5
    fi

    local score=$((success_rate + confidence_bonus))
    [[ $score -gt 100 ]] && score=100

    echo "$score"
}

# Calculate novelty score (0-100) by comparing against framework learnings
calculate_novelty_score() {
    local learning="$1"

    # Extract keywords from learning
    local title trigger solution
    title=$(echo "$learning" | jq -r '.title // ""')
    trigger=$(echo "$learning" | jq -r '.trigger // ""')
    solution=$(echo "$learning" | jq -r '.solution // ""')

    local learning_text="$title $trigger $solution"

    # Compare against each framework learning
    local max_similarity=0

    # HIGH-002 FIX: Use null-safe iteration to handle filenames with special characters
    if [[ -d "$FRAMEWORK_LEARNINGS_DIR" ]]; then
        while IFS= read -r -d '' file; do
            # Skip index.json
            [[ "$(basename "$file")" == "index.json" ]] && continue

            # Extract all framework learning texts
            local fw_learnings
            fw_learnings=$(jq -r '.learnings[]? | "\(.title // "") \(.trigger // "") \(.solution // "")"' "$file" 2>/dev/null || true)

            while IFS= read -r fw_text; do
                [[ -z "$fw_text" ]] && continue

                # Calculate similarity if jaccard script exists
                if [[ -x "$JACCARD_SCRIPT" ]]; then
                    local sim
                    sim=$("$JACCARD_SCRIPT" --text-a "$learning_text" --text-b "$fw_text" 2>/dev/null || echo "0")

                    # Convert to integer for comparison
                    local sim_int
                    sim_int=$(echo "$sim * 100" | bc | cut -d'.' -f1)
                    [[ -z "$sim_int" ]] && sim_int=0

                    if [[ "$sim_int" -gt "$max_similarity" ]]; then
                        max_similarity=$sim_int
                    fi
                fi
            done <<< "$fw_learnings"
        done < <(find "$FRAMEWORK_LEARNINGS_DIR" -maxdepth 1 -name "*.json" -type f -print0)
    fi

    # Novelty = 100 - max_similarity (more similar = less novel)
    local novelty=$((100 - max_similarity))
    [[ $novelty -lt 0 ]] && novelty=0

    echo "$novelty"
}

# Calculate generality score (0-100) based on domain-agnostic characteristics
calculate_generality_score() {
    local learning="$1"

    local score=50  # Base score

    # Check tags for broad applicability
    local tags
    tags=$(echo "$learning" | jq -r '.tags // [] | .[]' 2>/dev/null || true)

    # Domain-agnostic tags increase score
    local agnostic_tags=("architecture" "pattern" "performance" "security" "testing" "debugging" "workflow" "organization")
    for tag in $tags; do
        for agnostic in "${agnostic_tags[@]}"; do
            if [[ "$tag" == "$agnostic" ]]; then
                score=$((score + 5))
            fi
        done
    done

    # Domain-specific tags decrease score
    local specific_tags=("react" "angular" "vue" "python" "golang" "rust" "aws" "gcp" "azure")
    for tag in $tags; do
        for specific in "${specific_tags[@]}"; do
            if [[ "$tag" == "$specific" ]]; then
                score=$((score - 5))
            fi
        done
    done

    # Check solution for domain-specific terms
    local solution
    solution=$(echo "$learning" | jq -r '.solution // ""')

    # General terms increase score
    if echo "$solution" | grep -qiE 'always|never|consider|ensure|verify|validate|pattern|approach'; then
        score=$((score + 10))
    fi

    # Technology-specific paths decrease score
    if echo "$solution" | grep -qE '/node_modules/|\.py$|\.go$|\.rs$|package\.json|requirements\.txt'; then
        score=$((score - 10))
    fi

    # Clamp to 0-100
    [[ $score -gt 100 ]] && score=100
    [[ $score -lt 0 ]] && score=0

    echo "$score"
}

# Calculate weighted upstream score
calculate_upstream_score() {
    local quality="$1"
    local effectiveness="$2"
    local novelty="$3"
    local generality="$4"

    local weighted_score
    weighted_score=$(echo "scale=2; ($quality * $QUALITY_WEIGHT + $effectiveness * $EFFECTIVENESS_WEIGHT + $novelty * $NOVELTY_WEIGHT + $generality * $GENERALITY_WEIGHT) / 100" | bc)

    printf "%.0f" "$weighted_score"
}

# Check eligibility based on thresholds
check_eligibility() {
    local learning="$1"
    local upstream_score="$2"

    # Check score threshold
    if [[ "$upstream_score" -lt "$MIN_SCORE" ]]; then
        echo "false"
        return
    fi

    # Check application count
    local app_count
    app_count=$(echo "$learning" | jq '[.applications // [] | .[]] | length')
    if [[ "$app_count" -lt "$MIN_APPLICATIONS" ]]; then
        echo "false"
        return
    fi

    # Check success rate
    local successes
    successes=$(echo "$learning" | jq '[.applications // [] | .[] | select(.outcome == "success")] | length')

    if [[ "$app_count" -gt 0 ]]; then
        local success_rate
        success_rate=$(echo "scale=2; $successes / $app_count * 100" | bc | cut -d'.' -f1)
        if [[ "$success_rate" -lt "$MIN_SUCCESS_RATE" ]]; then
            echo "false"
            return
        fi
    else
        echo "false"
        return
    fi

    echo "true"
}

# Get reason for ineligibility
get_ineligibility_reason() {
    local learning="$1"
    local upstream_score="$2"
    local reasons=()

    if [[ "$upstream_score" -lt "$MIN_SCORE" ]]; then
        reasons+=("score $upstream_score < $MIN_SCORE")
    fi

    local app_count
    app_count=$(echo "$learning" | jq '[.applications // [] | .[]] | length')
    if [[ "$app_count" -lt "$MIN_APPLICATIONS" ]]; then
        reasons+=("applications $app_count < $MIN_APPLICATIONS")
    fi

    if [[ "$app_count" -gt 0 ]]; then
        local successes
        successes=$(echo "$learning" | jq '[.applications // [] | .[] | select(.outcome == "success")] | length')
        local success_rate
        success_rate=$(echo "scale=2; $successes / $app_count * 100" | bc | cut -d'.' -f1)
        if [[ "$success_rate" -lt "$MIN_SUCCESS_RATE" ]]; then
            reasons+=("success_rate ${success_rate}% < ${MIN_SUCCESS_RATE}%")
        fi
    fi

    if [[ ${#reasons[@]} -eq 0 ]]; then
        echo "none"
    else
        printf '%s\n' "${reasons[@]}" | paste -sd ',' -
    fi
}

main() {
    parse_args "$@"
    load_config

    # Get the learning
    local learning
    learning=$(get_learning "$LEARNING_ID")

    if [[ -z "$learning" || "$learning" == "null" ]]; then
        if [[ "$OUTPUT_FORMAT" == "json" ]]; then
            echo '{"id":"'"$LEARNING_ID"'","error":"not_found"}'
        else
            echo -e "${RED}Learning not found: $LEARNING_ID${NC}" >&2
        fi
        exit 1
    fi

    # Calculate component scores
    local quality_score effectiveness_score novelty_score generality_score
    quality_score=$(calculate_quality_score "$learning")
    effectiveness_score=$(calculate_effectiveness_score "$learning")
    novelty_score=$(calculate_novelty_score "$learning")
    generality_score=$(calculate_generality_score "$learning")

    # Calculate weighted score
    local upstream_score
    upstream_score=$(calculate_upstream_score "$quality_score" "$effectiveness_score" "$novelty_score" "$generality_score")

    # Check eligibility
    local eligible
    eligible=$(check_eligibility "$learning" "$upstream_score")

    local ineligibility_reason=""
    if [[ "$eligible" == "false" ]]; then
        ineligibility_reason=$(get_ineligibility_reason "$learning" "$upstream_score")
    fi

    # Output results
    if [[ "$CHECK_ELIGIBILITY" == "true" ]]; then
        if [[ "$eligible" == "true" ]]; then
            exit 0
        else
            exit 1
        fi
    fi

    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        local app_count successes success_rate
        app_count=$(echo "$learning" | jq '[.applications // [] | .[]] | length')
        successes=$(echo "$learning" | jq '[.applications // [] | .[] | select(.outcome == "success")] | length')
        if [[ "$app_count" -gt 0 ]]; then
            success_rate=$(echo "scale=2; $successes / $app_count * 100" | bc)
        else
            success_rate="0"
        fi

        jq -n \
            --arg id "$LEARNING_ID" \
            --argjson score "$upstream_score" \
            --argjson quality "$quality_score" \
            --argjson effectiveness "$effectiveness_score" \
            --argjson novelty "$novelty_score" \
            --argjson generality "$generality_score" \
            --argjson eligible "$([ "$eligible" == "true" ] && echo true || echo false)" \
            --arg reason "$ineligibility_reason" \
            --argjson applications "$app_count" \
            --arg success_rate "$success_rate" \
            --argjson min_score "$MIN_SCORE" \
            --argjson min_applications "$MIN_APPLICATIONS" \
            --argjson min_success_rate "$MIN_SUCCESS_RATE" \
            '{
                id: $id,
                upstream_score: $score,
                components: {
                    quality: { score: $quality, weight: 25 },
                    effectiveness: { score: $effectiveness, weight: 30 },
                    novelty: { score: $novelty, weight: 25 },
                    generality: { score: $generality, weight: 20 }
                },
                eligibility: {
                    eligible: $eligible,
                    reason: (if $eligible then null else $reason end),
                    applications: $applications,
                    success_rate: ($success_rate | tonumber),
                    thresholds: {
                        min_score: $min_score,
                        min_applications: $min_applications,
                        min_success_rate: $min_success_rate
                    }
                }
            }'
    else
        # Summary format
        local title
        title=$(echo "$learning" | jq -r '.title // "Untitled"')

        echo -e "${BOLD}${CYAN}Upstream Score Calculator${NC}"
        echo "─────────────────────────────────────────"
        echo ""
        echo -e "  Learning: ${BLUE}$LEARNING_ID${NC}"
        echo -e "  Title: $title"
        echo ""
        echo "  Component Scores:"
        echo -e "    Quality (25%):       ${GREEN}$quality_score${NC}/100"
        echo -e "    Effectiveness (30%): ${GREEN}$effectiveness_score${NC}/100"
        echo -e "    Novelty (25%):       ${GREEN}$novelty_score${NC}/100"
        echo -e "    Generality (20%):    ${GREEN}$generality_score${NC}/100"
        echo ""
        echo "─────────────────────────────────────────"
        echo -e "  ${BOLD}Upstream Score:${NC} ${GREEN}$upstream_score${NC}/100"
        echo ""

        if [[ "$eligible" == "true" ]]; then
            echo -e "  ${GREEN}✓ ELIGIBLE${NC} for upstream proposal"
        else
            echo -e "  ${RED}✗ NOT ELIGIBLE${NC} for upstream proposal"
            echo -e "  Reason: ${YELLOW}$ineligibility_reason${NC}"
        fi
        echo ""
    fi
}

main "$@"
