#!/usr/bin/env bash
# grounding-check.sh - Calculate grounding ratio from trajectory log
#
# Part of Loa Framework v0.9.0 Lossless Ledger Protocol
#
# Usage:
#   ./grounding-check.sh [agent] [threshold] [date]
#
# Arguments:
#   agent     - Agent name (default: implementing-tasks)
#   threshold - Minimum grounding ratio (default: 0.95)
#   date      - Date to check (default: today, format: YYYY-MM-DD)
#
# Exit Codes:
#   0 - Grounding ratio meets or exceeds threshold
#   1 - Grounding ratio below threshold
#   2 - Error (missing dependencies, invalid input)
#
# Output:
#   Structured key=value pairs for parsing

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/bootstrap.sh"

AGENT="${1:-implementing-tasks}"
THRESHOLD="${2:-0.95}"
DATE="${3:-$(date +%Y-%m-%d)}"

TRAJECTORY_DIR=$(get_trajectory_dir)
TRAJECTORY="${TRAJECTORY_DIR}/${AGENT}-${DATE}.jsonl"

# Validate threshold is a valid number
if ! echo "$THRESHOLD" | grep -qE '^[0-9]+\.?[0-9]*$'; then
    echo "error=invalid_threshold"
    echo "message=Threshold must be a number between 0 and 1"
    exit 2
fi

# Check for bc dependency (needed for decimal math)
if ! command -v bc &>/dev/null; then
    echo "error=missing_dependency"
    echo "message=bc is required for grounding ratio calculation"
    echo "install=apt install bc  # or: brew install bc"
    exit 2
fi

# Check if trajectory file exists
if [[ ! -f "$TRAJECTORY" ]]; then
    # No trajectory = no claims = passes (zero-claim session)
    echo "total_claims=0"
    echo "grounded_claims=0"
    echo "assumptions=0"
    echo "grounding_ratio=1.00"
    echo "status=pass"
    echo "message=No trajectory log for ${DATE} (zero-claim session)"
    exit 0
fi

# Count claims by type
# Look for citation phase entries in trajectory
total_claims=$(grep -c '"phase":"cite"' "$TRAJECTORY" 2>/dev/null || echo "0")

# Count grounded claims (citation or code_reference)
grounded_citations=$(grep -c '"grounding":"citation"' "$TRAJECTORY" 2>/dev/null || echo "0")
grounded_references=$(grep -c '"grounding":"code_reference"' "$TRAJECTORY" 2>/dev/null || echo "0")
grounded_user_input=$(grep -c '"grounding":"user_input"' "$TRAJECTORY" 2>/dev/null || echo "0")
grounded_claims=$((grounded_citations + grounded_references + grounded_user_input))

# Count assumptions (ungrounded claims)
assumptions=$(grep -c '"grounding":"assumption"' "$TRAJECTORY" 2>/dev/null || echo "0")

# Handle zero-claim sessions
if [[ "$total_claims" -eq 0 ]]; then
    echo "total_claims=0"
    echo "grounded_claims=0"
    echo "assumptions=0"
    echo "grounding_ratio=1.00"
    echo "status=pass"
    echo "message=Zero-claim session (passes by default)"
    exit 0
fi

# Calculate grounding ratio
ratio=$(echo "scale=4; $grounded_claims / $total_claims" | bc)
# Format to 2 decimal places for display
ratio_display=$(printf "%.2f" "$ratio")

# Output metrics
echo "total_claims=$total_claims"
echo "grounded_claims=$grounded_claims"
echo "grounded_citations=$grounded_citations"
echo "grounded_references=$grounded_references"
echo "grounded_user_input=$grounded_user_input"
echo "assumptions=$assumptions"
echo "grounding_ratio=$ratio_display"
echo "threshold=$THRESHOLD"

# Check threshold
if (( $(echo "$ratio < $THRESHOLD" | bc -l) )); then
    echo "status=fail"
    echo "message=Grounding ratio $ratio_display below threshold $THRESHOLD"

    # List ungrounded claims if any
    if [[ "$assumptions" -gt 0 ]]; then
        echo ""
        echo "ungrounded_claims:"
        grep '"grounding":"assumption"' "$TRAJECTORY" 2>/dev/null | \
            jq -r '.claim // .decision // "Unknown claim"' 2>/dev/null | \
            head -10 | \
            while read -r claim; do
                echo "  - $claim"
            done
    fi

    exit 1
else
    echo "status=pass"
    echo "message=Grounding ratio $ratio_display meets threshold $THRESHOLD"
    exit 0
fi
