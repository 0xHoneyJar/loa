#!/usr/bin/env bash
# bridge-findings-parser.sh — Eval fixture stub
# Parses Bridgebuilder review output and extracts structured findings JSON.
#
# Marker extraction: looks for <!-- bridge-findings-start --> and
# <!-- bridge-findings-end --> delimiters in review files.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse findings from a review file
parse_findings() {
    local review_file="$1"
    if [[ ! -f "$review_file" ]]; then
        echo '{"findings":[]}'
        return
    fi

    # Extract JSON between bridge-findings-start and bridge-findings-end markers
    sed -n '/<!-- bridge-findings-start -->/,/<!-- bridge-findings-end -->/p' "$review_file" | \
        grep -v '<!-- bridge-findings' || echo '{"findings":[]}'
}

# Main
if [[ $# -gt 0 ]]; then
    parse_findings "$1"
fi
