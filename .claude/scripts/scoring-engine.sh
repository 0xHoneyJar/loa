#!/usr/bin/env bash
# =============================================================================
# scoring-engine.sh - Consensus calculation for Flatline Protocol
# =============================================================================
# Version: 1.0.0
# Part of: Flatline Protocol v1.17.0
#
# Usage:
#   scoring-engine.sh --gpt-scores <file> --opus-scores <file> [options]
#
# Options:
#   --gpt-scores <file>     GPT cross-scores JSON file (required)
#   --opus-scores <file>    Opus cross-scores JSON file (required)
#   --thresholds <file>     Custom thresholds JSON file
#   --include-blockers      Include skeptic concerns in analysis
#   --skeptic-gpt <file>    GPT skeptic concerns JSON file
#   --skeptic-opus <file>   Opus skeptic concerns JSON file
#   --json                  Output as JSON (default)
#
# Thresholds (defaults from .loa.config.yaml or built-in):
#   high_consensus: 700     Both models score >700 = auto-integrate
#   dispute_delta: 300      Score difference >300 = disputed
#   low_value: 400          Both models score <400 = discard
#   blocker: 700            Skeptic concern >700 = blocker
#
# Exit codes:
#   0 - Success
#   1 - Missing input files
#   2 - Invalid input format
#   3 - No items to score
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_FILE="$PROJECT_ROOT/.loa.config.yaml"
SCHEMA_FILE="$PROJECT_ROOT/.claude/schemas/flatline-result.schema.json"

# Default thresholds
DEFAULT_HIGH_CONSENSUS=700
DEFAULT_DISPUTE_DELTA=300
DEFAULT_LOW_VALUE=400
DEFAULT_BLOCKER=700

# =============================================================================
# Logging
# =============================================================================

log() {
    echo "[scoring-engine] $*" >&2
}

error() {
    echo "ERROR: $*" >&2
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

get_threshold() {
    local name="$1"
    local default="$2"
    read_config ".flatline_protocol.thresholds.$name" "$default"
}

# =============================================================================
# Scoring Logic
# =============================================================================

# Merge scores from both models and calculate consensus
calculate_consensus() {
    local gpt_scores_file="$1"
    local opus_scores_file="$2"
    local high_threshold="$3"
    local dispute_delta="$4"
    local low_threshold="$5"
    local blocker_threshold="$6"
    local skeptic_gpt_file="${7:-}"
    local skeptic_opus_file="${8:-}"

    # Parse input files
    local gpt_scores opus_scores
    gpt_scores=$(cat "$gpt_scores_file")
    opus_scores=$(cat "$opus_scores_file")

    # Merge and calculate consensus using jq
    jq -n \
        --argjson gpt "$gpt_scores" \
        --argjson opus "$opus_scores" \
        --argjson high "$high_threshold" \
        --argjson delta "$dispute_delta" \
        --argjson low "$low_threshold" \
        --argjson blocker "$blocker_threshold" \
        --slurpfile skeptic_gpt <(if [[ -n "$skeptic_gpt_file" && -f "$skeptic_gpt_file" ]]; then cat "$skeptic_gpt_file"; else echo '{"concerns":[]}'; fi) \
        --slurpfile skeptic_opus <(if [[ -n "$skeptic_opus_file" && -f "$skeptic_opus_file" ]]; then cat "$skeptic_opus_file"; else echo '{"concerns":[]}'; fi) '
# Build lookup maps from scores
def build_score_map:
    reduce .scores[] as $item ({}; . + {($item.id): $item.score});

# Merge items from both models
($gpt | build_score_map) as $gpt_map |
($opus | build_score_map) as $opus_map |

# Get all unique item IDs
([$gpt.scores[].id, $opus.scores[].id] | unique) as $all_ids |

# Classify each item
(reduce $all_ids[] as $id (
    {
        high_consensus: [],
        disputed: [],
        low_value: [],
        medium_value: []
    };

    ($gpt_map[$id] // 0) as $g |
    ($opus_map[$id] // 0) as $o |
    (($g - $o) | if . < 0 then -. else . end) as $d |
    (($g + $o) / 2) as $avg |

    # Find original item details from GPT or Opus
    (($gpt.scores[] | select(.id == $id)) // ($opus.scores[] | select(.id == $id)) // {id: $id}) as $item |

    {
        id: $id,
        description: ($item.description // $item.evaluation // ""),
        gpt_score: $g,
        opus_score: $o,
        delta: $d,
        average_score: $avg,
        would_integrate: (($item.would_integrate // false) or ($g > $high and $o > $high))
    } as $scored_item |

    if ($g > $high and $o > $high) then
        .high_consensus += [$scored_item + {agreement: "HIGH"}]
    elif $d > $delta then
        .disputed += [$scored_item + {agreement: "DISPUTED"}]
    elif ($g < $low and $o < $low) then
        .low_value += [$scored_item + {agreement: "LOW"}]
    else
        .medium_value += [$scored_item + {agreement: "MEDIUM"}]
    end
)) as $classified |

# Process skeptic concerns for blockers
(
    [
        ($skeptic_gpt[0].concerns // [])[] | . + {source: "gpt_skeptic"},
        ($skeptic_opus[0].concerns // [])[] | . + {source: "opus_skeptic"}
    ] | map(select(.severity_score > $blocker))
) as $blockers |

# Calculate model agreement percentage
($all_ids | length) as $total |
(($classified.high_consensus | length) + ($classified.medium_value | length)) as $agreed |
(if $total > 0 then ($agreed / $total * 100 | floor) else 0 end) as $agreement_pct |

# Build final output
{
    consensus_summary: {
        high_consensus_count: ($classified.high_consensus | length),
        disputed_count: ($classified.disputed | length),
        low_value_count: ($classified.low_value | length),
        blocker_count: ($blockers | length),
        model_agreement_percent: $agreement_pct
    },
    high_consensus: $classified.high_consensus,
    disputed: $classified.disputed,
    low_value: $classified.low_value,
    blockers: $blockers
}
'
}

# =============================================================================
# Main
# =============================================================================

usage() {
    cat <<EOF
Usage: scoring-engine.sh --gpt-scores <file> --opus-scores <file> [options]

Required:
  --gpt-scores <file>     GPT cross-scores JSON file
  --opus-scores <file>    Opus cross-scores JSON file

Options:
  --thresholds <file>     Custom thresholds JSON file
  --include-blockers      Include skeptic concerns in analysis
  --skeptic-gpt <file>    GPT skeptic concerns JSON file
  --skeptic-opus <file>   Opus skeptic concerns JSON file
  --json                  Output as JSON (default)
  -h, --help              Show this help

Thresholds (from config or defaults):
  high_consensus: 700     Both >700 = auto-integrate
  dispute_delta: 300      Delta >300 = disputed
  low_value: 400          Both <400 = discard
  blocker: 700            Skeptic >700 = blocker

Input Format (scores file):
{
  "scores": [
    {"id": "IMP-001", "score": 850, "evaluation": "...", "would_integrate": true},
    {"id": "IMP-002", "score": 420, "evaluation": "...", "would_integrate": false}
  ]
}

Output Format:
{
  "consensus_summary": {
    "high_consensus_count": N,
    "disputed_count": N,
    "low_value_count": N,
    "blocker_count": N,
    "model_agreement_percent": N
  },
  "high_consensus": [...],
  "disputed": [...],
  "low_value": [...],
  "blockers": [...]
}
EOF
}

main() {
    local gpt_scores_file=""
    local opus_scores_file=""
    local thresholds_file=""
    local include_blockers=false
    local skeptic_gpt_file=""
    local skeptic_opus_file=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --gpt-scores)
                gpt_scores_file="$2"
                shift 2
                ;;
            --opus-scores)
                opus_scores_file="$2"
                shift 2
                ;;
            --thresholds)
                thresholds_file="$2"
                shift 2
                ;;
            --include-blockers)
                include_blockers=true
                shift
                ;;
            --skeptic-gpt)
                skeptic_gpt_file="$2"
                shift 2
                ;;
            --skeptic-opus)
                skeptic_opus_file="$2"
                shift 2
                ;;
            --json)
                # Default behavior
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    # Validate required files
    if [[ -z "$gpt_scores_file" ]]; then
        error "GPT scores file required (--gpt-scores)"
        exit 1
    fi

    if [[ ! -f "$gpt_scores_file" ]]; then
        error "GPT scores file not found: $gpt_scores_file"
        exit 1
    fi

    if [[ -z "$opus_scores_file" ]]; then
        error "Opus scores file required (--opus-scores)"
        exit 1
    fi

    if [[ ! -f "$opus_scores_file" ]]; then
        error "Opus scores file not found: $opus_scores_file"
        exit 1
    fi

    # Validate JSON format
    if ! jq empty "$gpt_scores_file" 2>/dev/null; then
        error "Invalid JSON in GPT scores file: $gpt_scores_file"
        exit 2
    fi

    if ! jq empty "$opus_scores_file" 2>/dev/null; then
        error "Invalid JSON in Opus scores file: $opus_scores_file"
        exit 2
    fi

    # Check for scores array
    local gpt_count opus_count
    gpt_count=$(jq '.scores | length' "$gpt_scores_file" 2>/dev/null || echo "0")
    opus_count=$(jq '.scores | length' "$opus_scores_file" 2>/dev/null || echo "0")

    if [[ "$gpt_count" == "0" && "$opus_count" == "0" ]]; then
        error "No items to score in either file"
        exit 3
    fi

    log "GPT scores: $gpt_count items"
    log "Opus scores: $opus_count items"

    # Load thresholds
    local high_threshold dispute_delta low_threshold blocker_threshold

    if [[ -n "$thresholds_file" && -f "$thresholds_file" ]]; then
        high_threshold=$(jq -r '.high_consensus // 700' "$thresholds_file")
        dispute_delta=$(jq -r '.dispute_delta // 300' "$thresholds_file")
        low_threshold=$(jq -r '.low_value // 400' "$thresholds_file")
        blocker_threshold=$(jq -r '.blocker // 700' "$thresholds_file")
    else
        high_threshold=$(get_threshold "high_consensus" "$DEFAULT_HIGH_CONSENSUS")
        dispute_delta=$(get_threshold "dispute_delta" "$DEFAULT_DISPUTE_DELTA")
        low_threshold=$(get_threshold "low_value" "$DEFAULT_LOW_VALUE")
        blocker_threshold=$(get_threshold "blocker" "$DEFAULT_BLOCKER")
    fi

    log "Thresholds: high=$high_threshold, delta=$dispute_delta, low=$low_threshold, blocker=$blocker_threshold"

    # Calculate consensus
    local result
    if [[ "$include_blockers" == "true" ]]; then
        result=$(calculate_consensus \
            "$gpt_scores_file" \
            "$opus_scores_file" \
            "$high_threshold" \
            "$dispute_delta" \
            "$low_threshold" \
            "$blocker_threshold" \
            "$skeptic_gpt_file" \
            "$skeptic_opus_file")
    else
        result=$(calculate_consensus \
            "$gpt_scores_file" \
            "$opus_scores_file" \
            "$high_threshold" \
            "$dispute_delta" \
            "$low_threshold" \
            "$blocker_threshold")
    fi

    # Output result
    echo "$result" | jq .

    # Log summary
    local high_count disputed_count low_count blocker_count agreement
    high_count=$(echo "$result" | jq '.consensus_summary.high_consensus_count')
    disputed_count=$(echo "$result" | jq '.consensus_summary.disputed_count')
    low_count=$(echo "$result" | jq '.consensus_summary.low_value_count')
    blocker_count=$(echo "$result" | jq '.consensus_summary.blocker_count')
    agreement=$(echo "$result" | jq '.consensus_summary.model_agreement_percent')

    log "Consensus: HIGH=$high_count DISPUTED=$disputed_count LOW=$low_count BLOCKERS=$blocker_count (${agreement}% agreement)"
}

main "$@"
