#!/usr/bin/env bash
# =============================================================================
# scoring-engine.sh - Consensus calculation for Flatline Protocol
# =============================================================================
# Version: 1.1.0
# Part of: Flatline Protocol v1.17.0, FR-3 3-Model Consensus v1.40.0
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
#   --skeptic-tertiary <file> Tertiary model skeptic concerns JSON file (optional)
#   --tertiary-scores-opus <file>  Tertiary model's scores of Opus improvements (3-model)
#   --tertiary-scores-gpt <file>   Tertiary model's scores of GPT improvements (3-model)
#   --gpt-scores-tertiary <file>   GPT's scores of Tertiary improvements (3-model)
#   --opus-scores-tertiary <file>  Opus's scores of Tertiary improvements (3-model)
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

# Merge scores from all models and calculate consensus
# Supports 2-model (GPT + Opus) and 3-model (GPT + Opus + Tertiary) modes.
# In 3-model mode, tertiary-authored items join the consensus pool, and
# tertiary cross-scores of existing items provide additional confirmation.
calculate_consensus() {
    local gpt_scores_file="$1"
    local opus_scores_file="$2"
    local high_threshold="$3"
    local dispute_delta="$4"
    local low_threshold="$5"
    local blocker_threshold="$6"
    local skeptic_gpt_file="${7:-}"
    local skeptic_opus_file="${8:-}"
    local skeptic_tertiary_file="${9:-}"
    # FR-3: Tertiary cross-scoring files (3-model mode)
    local tertiary_scores_opus_file="${10:-}"
    local tertiary_scores_gpt_file="${11:-}"
    local gpt_scores_tertiary_file="${12:-}"
    local opus_scores_tertiary_file="${13:-}"

    # Parse and validate input files (Task 1.2: JSON validation before --argjson)
    local gpt_scores opus_scores
    local gpt_degraded=false opus_degraded=false

    if ! gpt_scores=$(jq -c '.' "$gpt_scores_file" 2>/dev/null); then
        log "WARNING: GPT scores file contains invalid JSON: $gpt_scores_file"
        gpt_scores='{"scores":[]}'
        gpt_degraded=true
    elif ! jq -e '.scores | type == "array"' "$gpt_scores_file" >/dev/null 2>&1; then
        log "WARNING: GPT scores file missing .scores array: $gpt_scores_file"
        gpt_scores='{"scores":[]}'
        gpt_degraded=true
    fi

    if ! opus_scores=$(jq -c '.' "$opus_scores_file" 2>/dev/null); then
        log "WARNING: Opus scores file contains invalid JSON: $opus_scores_file"
        opus_scores='{"scores":[]}'
        opus_degraded=true
    elif ! jq -e '.scores | type == "array"' "$opus_scores_file" >/dev/null 2>&1; then
        log "WARNING: Opus scores file missing .scores array: $opus_scores_file"
        opus_scores='{"scores":[]}'
        opus_degraded=true
    fi

    if [[ "$gpt_degraded" == "true" && "$opus_degraded" == "true" ]]; then
        error "Both model score files are invalid — cannot calculate consensus"
        return 1
    fi

    # FR-3: Load tertiary cross-scoring files (graceful degradation if missing/empty)
    local has_tertiary=false
    local gpt_scores_tertiary='{"scores":[]}'
    local opus_scores_tertiary='{"scores":[]}'
    local tertiary_scores_opus='{"scores":[]}'
    local tertiary_scores_gpt='{"scores":[]}'

    if [[ -n "$gpt_scores_tertiary_file" && -f "$gpt_scores_tertiary_file" ]]; then
        if gpt_scores_tertiary=$(jq -c '.' "$gpt_scores_tertiary_file" 2>/dev/null); then
            has_tertiary=true
        else
            log "WARNING: GPT scores of tertiary items invalid JSON, skipping"
            gpt_scores_tertiary='{"scores":[]}'
        fi
    fi
    if [[ -n "$opus_scores_tertiary_file" && -f "$opus_scores_tertiary_file" ]]; then
        opus_scores_tertiary=$(jq -c '.' "$opus_scores_tertiary_file" 2>/dev/null) || opus_scores_tertiary='{"scores":[]}'
    fi
    if [[ -n "$tertiary_scores_opus_file" && -f "$tertiary_scores_opus_file" ]]; then
        tertiary_scores_opus=$(jq -c '.' "$tertiary_scores_opus_file" 2>/dev/null) || tertiary_scores_opus='{"scores":[]}'
    fi
    if [[ -n "$tertiary_scores_gpt_file" && -f "$tertiary_scores_gpt_file" ]]; then
        tertiary_scores_gpt=$(jq -c '.' "$tertiary_scores_gpt_file" 2>/dev/null) || tertiary_scores_gpt='{"scores":[]}'
    fi

    [[ "$has_tertiary" == "true" ]] && log "3-model consensus mode: including tertiary items and cross-scores"

    # Merge and calculate consensus using jq
    jq -n \
        --argjson gpt "$gpt_scores" \
        --argjson opus "$opus_scores" \
        --argjson g_tert "$gpt_scores_tertiary" \
        --argjson o_tert "$opus_scores_tertiary" \
        --argjson t_opus "$tertiary_scores_opus" \
        --argjson t_gpt "$tertiary_scores_gpt" \
        --argjson high "$high_threshold" \
        --argjson delta "$dispute_delta" \
        --argjson low "$low_threshold" \
        --argjson blocker "$blocker_threshold" \
        --argjson gpt_degraded "$gpt_degraded" \
        --argjson opus_degraded "$opus_degraded" \
        --argjson has_tertiary "$has_tertiary" \
        --slurpfile skeptic_gpt <(if [[ -n "$skeptic_gpt_file" && -f "$skeptic_gpt_file" ]]; then cat "$skeptic_gpt_file"; else echo '{"concerns":[]}'; fi) \
        --slurpfile skeptic_opus <(if [[ -n "$skeptic_opus_file" && -f "$skeptic_opus_file" ]]; then cat "$skeptic_opus_file"; else echo '{"concerns":[]}'; fi) \
        --slurpfile skeptic_tertiary <(if [[ -n "$skeptic_tertiary_file" && -f "$skeptic_tertiary_file" ]]; then cat "$skeptic_tertiary_file"; else echo '{"concerns":[]}'; fi) '
# Build lookup maps from scores
def build_score_map:
    reduce (.scores // [])[] as $item ({}; . + {($item.id): $item.score});

# Primary cross-score maps (2-model, always present)
($gpt | build_score_map) as $gpt_map |
($opus | build_score_map) as $opus_map |

# FR-3: Tertiary cross-score maps (3-model, may be empty)
($g_tert | build_score_map) as $g_tert_map |
($o_tert | build_score_map) as $o_tert_map |
($t_opus | build_score_map) as $t_opus_map |
($t_gpt | build_score_map) as $t_gpt_map |

# Get all unique item IDs (including tertiary-authored items)
([$gpt.scores[].id, $opus.scores[].id,
  ($g_tert.scores // [])[].id, ($o_tert.scores // [])[].id] | unique) as $all_ids |

# Classify each item
(reduce $all_ids[] as $id (
    {
        high_consensus: [],
        disputed: [],
        low_value: [],
        medium_value: []
    };

    # Primary pair: GPT and Opus cross-scores (existing 2-model behavior)
    ($gpt_map[$id] // 0) as $g_primary |
    ($opus_map[$id] // 0) as $o_primary |

    # Tertiary cross-scores of this item (additional signal)
    ($t_opus_map[$id] // 0) as $t_on_opus |
    ($t_gpt_map[$id] // 0) as $t_on_gpt |

    # GPT/Opus scores of tertiary items (for tertiary-authored items)
    ($g_tert_map[$id] // 0) as $g_on_tert |
    ($o_tert_map[$id] // 0) as $o_on_tert |

    # Resolve effective score pair:
    # - For existing items (in gpt_map or opus_map): use primary pair
    # - For tertiary-authored items (in g_tert_map or o_tert_map only): use GPT+Opus scores
    (if ($g_primary > 0 or $o_primary > 0) then $g_primary
     elif $g_on_tert > 0 then $g_on_tert
     else 0 end) as $g |
    (if ($g_primary > 0 or $o_primary > 0) then $o_primary
     elif $o_on_tert > 0 then $o_on_tert
     else 0 end) as $o |

    # Tertiary confirmation: max of tertiary cross-scores for this item
    ([$t_on_opus, $t_on_gpt] | map(select(. > 0)) | if length > 0 then max else null end) as $tertiary_confirm |

    (($g - $o) | if . < 0 then -. else . end) as $d |
    (if ($g > 0 and $o > 0) then (($g + $o) / 2)
     elif ($g > 0) then $g
     elif ($o > 0) then $o
     else 0 end) as $avg |

    # Find original item details from any source
    (($gpt.scores[] | select(.id == $id)) //
     ($opus.scores[] | select(.id == $id)) //
     ($g_tert.scores[] | select(.id == $id)) //
     ($o_tert.scores[] | select(.id == $id)) //
     {id: $id}) as $item |

    # Determine item source
    (if ($gpt_map[$id] != null) then "gpt_scored"
     elif ($opus_map[$id] != null) then "opus_scored"
     elif ($g_tert_map[$id] != null or $o_tert_map[$id] != null) then "tertiary_authored"
     else "unknown" end) as $source |

    {
        id: $id,
        description: ($item.description // $item.evaluation // ""),
        gpt_score: $g,
        opus_score: $o,
        tertiary_score: $tertiary_confirm,
        delta: $d,
        average_score: $avg,
        source: $source,
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

# Process skeptic concerns for blockers (2 or 3 sources)
# Deduplicate by exact .concern text match (BB-F3/BB-F8b).
# Exact match is sufficient because models reviewing the same document typically
# echo each others phrasing. If the Hounfour scales to 3+ diverse models with
# varied prompting, consider fuzzy dedup (e.g., cosine similarity on concern text
# or a canonical concern ID assigned upstream in the skeptic prompt).
(
    [
        ($skeptic_gpt[0].concerns // [])[] | . + {source: "gpt_skeptic"},
        ($skeptic_opus[0].concerns // [])[] | . + {source: "opus_skeptic"},
        ($skeptic_tertiary[0].concerns // [])[] | . + {source: "tertiary_skeptic"}
    ] | group_by(.concern) | map(.[0]) | map(select(.severity_score > $blocker))
) as $blockers |

# Calculate model agreement percentage
($all_ids | length) as $total |
(($classified.high_consensus | length) + ($classified.medium_value | length)) as $agreed |
(if $total > 0 then ($agreed / $total * 100 | floor) else 0 end) as $agreement_pct |

# Count tertiary-authored items
([$classified.high_consensus[], $classified.disputed[], $classified.low_value[], $classified.medium_value[]
  | select(.source == "tertiary_authored")] | length) as $tertiary_items |

# Build final output
{
    consensus_summary: {
        high_consensus_count: ($classified.high_consensus | length),
        disputed_count: ($classified.disputed | length),
        low_value_count: ($classified.low_value | length),
        blocker_count: ($blockers | length),
        model_agreement_percent: $agreement_pct,
        models: (if $has_tertiary then 3 else 2 end),
        tertiary_items: $tertiary_items,
        confidence: (
            if ($gpt_degraded or $opus_degraded) then "degraded"
            elif (($gpt.scores | length) == 0 or ($opus.scores | length) == 0) then "single_model"
            else "full"
            end
        )
    },
    high_consensus: $classified.high_consensus,
    disputed: $classified.disputed,
    low_value: $classified.low_value,
    blockers: $blockers,
    degraded: (if ($gpt_degraded or $opus_degraded) then true else false end),
    degraded_model: (if $gpt_degraded then "gpt" elif $opus_degraded then "opus" else null end),
    confidence: (
        if ($gpt_degraded or $opus_degraded) then "degraded"
        elif (($gpt.scores | length) == 0 or ($opus.scores | length) == 0) then "single_model"
        else "full"
        end
    )
}
'
}

# =============================================================================
# Attack Mode Classification (Red Team Extension)
# =============================================================================

# Get red team threshold from config with fallback to default
get_rt_threshold() {
    local name="$1"
    local default="$2"
    read_config ".red_team.thresholds.$name" "$default"
}

# Classify a single attack based on cross-validation scores
# Returns: CONFIRMED_ATTACK, THEORETICAL, CREATIVE_ONLY, or DEFENDED
classify_attack() {
    local gpt_score="$1"
    local opus_score="$2"
    local has_counter="${3:-false}"
    local is_quick_mode="${4:-false}"

    # Configurable thresholds (read from .loa.config.yaml with defaults)
    local confirmed_threshold
    confirmed_threshold=$(get_rt_threshold "confirmed_attack" "700")

    # Quick mode can never produce CONFIRMED_ATTACK
    if [[ "$is_quick_mode" == "true" ]]; then
        if (( gpt_score > confirmed_threshold )); then
            echo "THEORETICAL"
        else
            echo "CREATIVE_ONLY"
        fi
        return 0
    fi

    if [[ "$has_counter" == "true" ]] && (( gpt_score > confirmed_threshold && opus_score > confirmed_threshold )); then
        echo "DEFENDED"
    elif (( gpt_score > confirmed_threshold && opus_score > confirmed_threshold )); then
        echo "CONFIRMED_ATTACK"
    elif (( gpt_score > confirmed_threshold || opus_score > confirmed_threshold )); then
        echo "THEORETICAL"
    else
        echo "CREATIVE_ONLY"
    fi
}

# Calculate attack consensus for red team mode
# Input: Two attack score files with .attacks[] arrays
calculate_attack_consensus() {
    local gpt_scores_file="$1"
    local opus_scores_file="$2"
    local is_quick_mode="${3:-false}"

    # Read configurable threshold (same source as classify_attack)
    local confirmed_threshold
    confirmed_threshold=$(get_rt_threshold "confirmed_attack" "700")

    jq -n \
        --argjson gpt "$(cat "$gpt_scores_file")" \
        --argjson opus "$(cat "$opus_scores_file")" \
        --argjson quick "$(if [[ "$is_quick_mode" == "true" ]]; then echo "true"; else echo "false"; fi)" \
        --argjson threshold "$confirmed_threshold" '

# Build score lookup from attacks
def attack_score_map:
    reduce (.attacks // .scores // [])[] as $item ({}; . + {($item.id): $item});

($gpt | attack_score_map) as $gpt_map |
($opus | attack_score_map) as $opus_map |

# Get all unique attack IDs
([($gpt.attacks // $gpt.scores // [])[].id, ($opus.attacks // $opus.scores // [])[].id] | unique) as $all_ids |

# Classify each attack using configurable threshold
(reduce $all_ids[] as $id (
    {confirmed: [], theoretical: [], creative: [], defended: []};

    ($gpt_map[$id] // {}) as $g_item |
    ($opus_map[$id] // {}) as $o_item |
    (($g_item.severity_score // $g_item.score // 0) | tonumber) as $g_score |
    (($o_item.severity_score // $o_item.score // 0) | tonumber) as $o_score |
    ($g_item.counter_design != null) as $has_counter |

    # Merge attack data from both models (prefer GPT, fill from Opus)
    ($g_item + $o_item + $g_item + {
        gpt_score: $g_score,
        opus_score: $o_score
    }) as $merged |

    if $quick then
        if $g_score > 400 then
            .theoretical += [$merged + {consensus: "THEORETICAL", human_review: "not_required"}]
        else
            .creative += [$merged + {consensus: "CREATIVE_ONLY", human_review: "not_required"}]
        end
    elif ($has_counter and $g_score > $threshold and $o_score > $threshold) then
        .defended += [$merged + {consensus: "DEFENDED", human_review: "not_required"}]
    elif ($g_score > $threshold and $o_score > $threshold) then
        .confirmed += [$merged + {
            consensus: "CONFIRMED_ATTACK",
            human_review: (if $g_score > ($threshold + 100) or $o_score > ($threshold + 100) then "required" else "not_required" end)
        }]
    elif ($g_score > $threshold or $o_score > $threshold) then
        .theoretical += [$merged + {consensus: "THEORETICAL", human_review: "not_required"}]
    else
        .creative += [$merged + {consensus: "CREATIVE_ONLY", human_review: "not_required"}]
    end
)) as $classified |

{
    attack_summary: {
        confirmed_count: ($classified.confirmed | length),
        theoretical_count: ($classified.theoretical | length),
        creative_count: ($classified.creative | length),
        defended_count: ($classified.defended | length),
        total_attacks: ($all_ids | length),
        human_review_required: ([($classified.confirmed // [])[] | select(.human_review == "required")] | length)
    },
    attacks: $classified,
    validated: ($quick | not),
    execution_mode: (if $quick then "quick" else "standard" end)
}
'
}

# Self-test against golden set
run_attack_self_test() {
    local golden_set="$PROJECT_ROOT/.claude/data/red-team-golden-set.json"

    if [[ ! -f "$golden_set" ]]; then
        error "Golden set not found: $golden_set"
        return 1
    fi

    log "Running attack classification self-test against golden set..."

    local pass=0
    local fail=0
    local total

    total=$(jq '.attacks | length' "$golden_set")

    for i in $(seq 0 $((total - 1))); do
        local id name expected_category severity_score
        id=$(jq -r ".attacks[$i].id" "$golden_set")
        name=$(jq -r ".attacks[$i].name" "$golden_set")
        expected_category=$(jq -r ".attacks[$i].expected_category" "$golden_set")
        severity_score=$(jq -r ".attacks[$i].severity_score" "$golden_set")

        # Check for per-model scores (THEORETICAL entries have separate expected scores)
        local gpt_score opus_score
        local has_per_model
        has_per_model=$(jq -r ".attacks[$i].expected_gpt_score // \"\"" "$golden_set")

        if [[ -n "$has_per_model" ]]; then
            # Per-model scores: use expected_gpt_score and expected_opus_score
            gpt_score=$(jq -r ".attacks[$i].expected_gpt_score" "$golden_set")
            opus_score=$(jq -r ".attacks[$i].expected_opus_score" "$golden_set")
        else
            # Legacy: use severity_score as both model scores
            gpt_score="$severity_score"
            opus_score="$severity_score"
        fi

        # Check for DEFENDED entries (have counter-design with effectiveness score)
        local has_counter="false"
        local defended_by
        defended_by=$(jq -r ".attacks[$i].defended_by // \"\"" "$golden_set")
        if [[ -n "$defended_by" ]]; then
            has_counter="true"
        fi

        local result
        result=$(classify_attack "$gpt_score" "$opus_score" "$has_counter" "false")

        if [[ "$result" == "$expected_category" ]]; then
            log "  PASS: $id ($name) → $result [GPT=$gpt_score, Opus=$opus_score]"
            pass=$((pass + 1))
        else
            log "  FAIL: $id ($name) → $result (expected $expected_category) [GPT=$gpt_score, Opus=$opus_score]"
            fail=$((fail + 1))
        fi
    done

    local accuracy=0
    if [[ $total -gt 0 ]]; then
        accuracy=$(( pass * 100 / total ))
    fi

    log "Self-test: $pass/$total passed ($accuracy% accuracy)"

    if [[ $fail -gt 0 ]]; then
        return 1
    fi
    return 0
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
  --skeptic-tertiary <file> Tertiary model skeptic concerns (optional, 3-model mode)
  --tertiary-scores-opus <file>  Tertiary scores of Opus improvements (3-model mode)
  --tertiary-scores-gpt <file>   Tertiary scores of GPT improvements (3-model mode)
  --gpt-scores-tertiary <file>   GPT scores of Tertiary improvements (3-model mode)
  --opus-scores-tertiary <file>  Opus scores of Tertiary improvements (3-model mode)
  --attack-mode           Use red team attack classification (4 categories)
  --quick-mode            Quick mode (no CONFIRMED_ATTACK possible)
  --self-test             Run classification self-test against golden set
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
    local skeptic_tertiary_file=""
    local tertiary_scores_opus_file=""
    local tertiary_scores_gpt_file=""
    local gpt_scores_tertiary_file=""
    local opus_scores_tertiary_file=""
    local attack_mode=false
    local quick_mode=false
    local self_test=false

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
            --skeptic-tertiary)
                skeptic_tertiary_file="$2"
                shift 2
                ;;
            --tertiary-scores-opus)
                tertiary_scores_opus_file="$2"
                shift 2
                ;;
            --tertiary-scores-gpt)
                tertiary_scores_gpt_file="$2"
                shift 2
                ;;
            --gpt-scores-tertiary)
                gpt_scores_tertiary_file="$2"
                shift 2
                ;;
            --opus-scores-tertiary)
                opus_scores_tertiary_file="$2"
                shift 2
                ;;
            --attack-mode)
                attack_mode=true
                shift
                ;;
            --quick-mode)
                quick_mode=true
                shift
                ;;
            --self-test)
                self_test=true
                shift
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

    # Self-test mode
    if [[ "$self_test" == "true" ]]; then
        run_attack_self_test
        exit $?
    fi

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

    # Check for scores/attacks arrays (attack-mode uses .attacks, standard uses .scores)
    local gpt_count opus_count
    if [[ "$attack_mode" == "true" ]]; then
        gpt_count=$(jq '(.attacks // .scores // []) | length' "$gpt_scores_file" 2>/dev/null || echo "0")
        opus_count=$(jq '(.attacks // .scores // []) | length' "$opus_scores_file" 2>/dev/null || echo "0")
    else
        gpt_count=$(jq '.scores | length' "$gpt_scores_file" 2>/dev/null || echo "0")
        opus_count=$(jq '.scores | length' "$opus_scores_file" 2>/dev/null || echo "0")
    fi

    if [[ "$gpt_count" == "0" && "$opus_count" == "0" ]]; then
        error "No items to score in either file"
        exit 3
    fi

    local mode_display="standard"
    [[ "$attack_mode" == "true" ]] && mode_display="attack"
    log "Input items: GPT=$gpt_count, Opus=$opus_count (mode=$mode_display)"

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

    # Calculate consensus (dispatch based on mode)
    local result
    if [[ "$attack_mode" == "true" ]]; then
        log "Attack mode: classifying attacks with 4-category system"
        result=$(calculate_attack_consensus "$gpt_scores_file" "$opus_scores_file" "$quick_mode")
    elif [[ "$include_blockers" == "true" ]]; then
        result=$(calculate_consensus \
            "$gpt_scores_file" \
            "$opus_scores_file" \
            "$high_threshold" \
            "$dispute_delta" \
            "$low_threshold" \
            "$blocker_threshold" \
            "$skeptic_gpt_file" \
            "$skeptic_opus_file" \
            "$skeptic_tertiary_file" \
            "$tertiary_scores_opus_file" \
            "$tertiary_scores_gpt_file" \
            "$gpt_scores_tertiary_file" \
            "$opus_scores_tertiary_file")
    else
        result=$(calculate_consensus \
            "$gpt_scores_file" \
            "$opus_scores_file" \
            "$high_threshold" \
            "$dispute_delta" \
            "$low_threshold" \
            "$blocker_threshold" \
            "" "" "" \
            "$tertiary_scores_opus_file" \
            "$tertiary_scores_gpt_file" \
            "$gpt_scores_tertiary_file" \
            "$opus_scores_tertiary_file")
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
