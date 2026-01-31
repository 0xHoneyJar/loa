#!/usr/bin/env bash
# feedback-classifier.sh - Classify feedback context to determine target repository
#
# Usage:
#   feedback-classifier.sh --context <file>
#   feedback-classifier.sh --context - < context.txt
#   echo "context" | feedback-classifier.sh --context -
#
# Output: JSON with classification, confidence, signals_matched, recommended_repo

set -euo pipefail

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Default configuration
DEFAULT_REPOS=(
    "loa_framework:0xHoneyJar/loa"
    "loa_constructs:0xHoneyJar/loa-constructs"
    "forge:0xHoneyJar/forge"
    "project:project-specific"
)

# Signal patterns and weights
# Format: category:pattern:weight
SIGNAL_PATTERNS=(
    # loa_framework signals
    "loa_framework:\.claude/:2"
    "loa_framework:grimoires/:2"
    "loa_framework:skill:2"
    "loa_framework:command:2"
    "loa_framework:protocol:2"
    "loa_framework:PRD:1"
    "loa_framework:SDD:1"
    "loa_framework:sprint:1"
    "loa_framework:prd\.md:2"
    "loa_framework:sdd\.md:2"
    "loa_framework:CLAUDE\.md:2"

    # loa_constructs signals
    "loa_constructs:registry:2"
    "loa_constructs:API:2"
    "loa_constructs:endpoint:2"
    "loa_constructs:install:2"
    "loa_constructs:load:1"
    "loa_constructs:pack:2"
    "loa_constructs:license:1"
    "loa_constructs:authentication:1"
    "loa_constructs:api.key:1"
    "loa_constructs:constructs:2"

    # forge signals
    "forge:experimental:2"
    "forge:sandbox:2"
    "forge:WIP:1"
    "forge:draft:1"
    "forge:construct.dev:1"

    # project_specific signals
    "project:application:2"
    "project:app:1"
    "project:deployment:2"
    "project:infra:2"
)

usage() {
    cat << 'EOF'
feedback-classifier.sh - Classify feedback context for routing

USAGE:
    feedback-classifier.sh --context <file>
    feedback-classifier.sh --context -
    echo "context" | feedback-classifier.sh --context -

OPTIONS:
    --context <file>    File containing context to classify (use - for stdin)
    --config <file>     Configuration file (default: .loa.config.yaml)
    --help              Show this help message

OUTPUT:
    JSON object with:
    - classification: Category name (loa_framework, loa_constructs, forge, project)
    - confidence: Score between 0.0 and 1.0
    - signals_matched: Array of matched signal descriptions
    - recommended_repo: Full repository path (owner/repo)

EXAMPLES:
    # Classify from file
    feedback-classifier.sh --context /tmp/context.txt

    # Classify from stdin
    echo "Error in .claude/skills/foo.md" | feedback-classifier.sh --context -

    # Classify conversation context
    feedback-classifier.sh --context grimoires/loa/context/feedback.txt
EOF
}

# Parse arguments
CONTEXT_FILE=""
CONFIG_FILE=".loa.config.yaml"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --context)
            CONTEXT_FILE="$2"
            shift 2
            ;;
        --config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}" >&2
            usage >&2
            exit 1
            ;;
    esac
done

# Validate arguments
if [[ -z "$CONTEXT_FILE" ]]; then
    echo -e "${RED}Error: --context is required${NC}" >&2
    usage >&2
    exit 1
fi

# Read context
if [[ "$CONTEXT_FILE" == "-" ]]; then
    CONTEXT=$(cat)
elif [[ -f "$CONTEXT_FILE" ]]; then
    CONTEXT=$(cat "$CONTEXT_FILE")
else
    echo -e "${RED}Error: Context file not found: $CONTEXT_FILE${NC}" >&2
    exit 1
fi

# Initialize scores
declare -A SCORES
SCORES[loa_framework]=0
SCORES[loa_constructs]=0
SCORES[forge]=0
SCORES[project]=0

# Track matched signals
MATCHED_SIGNALS=()

# Score context against patterns
for pattern_spec in "${SIGNAL_PATTERNS[@]}"; do
    IFS=':' read -r category pattern weight <<< "$pattern_spec"

    # Case-insensitive grep (SECURITY: use printf and -- to prevent injection)
    if printf '%s' "$CONTEXT" | grep -qiE -- "$pattern"; then
        SCORES[$category]=$((SCORES[$category] + weight))
        MATCHED_SIGNALS+=("$pattern ($category +$weight)")
    fi
done

# Check for negative signals (absence of loa-related content = project)
# SECURITY: use printf and -- to prevent injection
if ! printf '%s' "$CONTEXT" | grep -qiE -- "(loa|claude|skill|grimoire)"; then
    SCORES[project]=$((SCORES[project] + 1))
    MATCHED_SIGNALS+=("no loa keywords (project +1)")
fi

# Find highest scoring category
HIGHEST_CATEGORY="project"
HIGHEST_SCORE=0
TOTAL_SCORE=0

for category in "${!SCORES[@]}"; do
    score=${SCORES[$category]}
    TOTAL_SCORE=$((TOTAL_SCORE + score))

    if [[ $score -gt $HIGHEST_SCORE ]]; then
        HIGHEST_SCORE=$score
        HIGHEST_CATEGORY=$category
    fi
done

# Calculate confidence (highest score / total possible)
if [[ $TOTAL_SCORE -gt 0 ]]; then
    # Scale confidence: max is 1.0 when one category dominates
    CONFIDENCE=$(echo "scale=2; $HIGHEST_SCORE / ($TOTAL_SCORE + 1)" | bc)
    # Boost confidence if score is high
    if [[ $HIGHEST_SCORE -ge 5 ]]; then
        CONFIDENCE=$(echo "scale=2; if ($CONFIDENCE + 0.2 > 1.0) 1.0 else $CONFIDENCE + 0.2" | bc)
    fi
else
    CONFIDENCE="0.50"
    HIGHEST_CATEGORY="project"
fi

# SECURITY: Validate confidence is a valid number (0.0-1.0)
if ! [[ "$CONFIDENCE" =~ ^[0-9]*\.?[0-9]+$ ]] || \
   (( $(echo "$CONFIDENCE > 1.0" | bc -l) )) || \
   (( $(echo "$CONFIDENCE < 0.0" | bc -l) )); then
    CONFIDENCE="0.50"
fi

# Map category to repo
case "$HIGHEST_CATEGORY" in
    loa_framework)
        RECOMMENDED_REPO="0xHoneyJar/loa"
        ;;
    loa_constructs)
        RECOMMENDED_REPO="0xHoneyJar/loa-constructs"
        ;;
    forge)
        RECOMMENDED_REPO="0xHoneyJar/forge"
        ;;
    project|*)
        RECOMMENDED_REPO="project-specific"
        ;;
esac

# Build signals JSON array
SIGNALS_JSON="["
first=true
for signal in "${MATCHED_SIGNALS[@]}"; do
    if [[ "$first" == "true" ]]; then
        first=false
    else
        SIGNALS_JSON+=","
    fi
    # Escape backslashes and quotes for JSON
    escaped_signal=$(echo "$signal" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g')
    SIGNALS_JSON+="\"$escaped_signal\""
done
SIGNALS_JSON+="]"

# Output JSON result
cat << EOF
{
  "classification": "$HIGHEST_CATEGORY",
  "confidence": $CONFIDENCE,
  "signals_matched": $SIGNALS_JSON,
  "recommended_repo": "$RECOMMENDED_REPO",
  "scores": {
    "loa_framework": ${SCORES[loa_framework]},
    "loa_constructs": ${SCORES[loa_constructs]},
    "forge": ${SCORES[forge]},
    "project": ${SCORES[project]}
  }
}
EOF
