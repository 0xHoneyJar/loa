#!/usr/bin/env bash
# bridge-vision-capture.sh - Extract VISION-type findings into vision registry
# Version: 1.0.0
#
# Filters findings JSON for VISION entries and creates vision registry entries.
#
# Usage:
#   bridge-vision-capture.sh \
#     --findings findings.json \
#     --bridge-id bridge-20260212-abc \
#     --iteration 2 \
#     --pr 295 \
#     --output-dir grimoires/loa/visions/
#
# Exit Codes:
#   0 - Success
#   1 - Error
#   2 - Missing arguments

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/bootstrap.sh"

# =============================================================================
# Arguments
# =============================================================================

FINDINGS_FILE=""
BRIDGE_ID=""
ITERATION=""
PR_NUMBER=""
OUTPUT_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --findings)
      if [[ -z "${2:-}" ]]; then
        echo "ERROR: --findings requires a value" >&2
        exit 2
      fi
      FINDINGS_FILE="$2"
      shift 2
      ;;
    --bridge-id)
      if [[ -z "${2:-}" ]]; then
        echo "ERROR: --bridge-id requires a value" >&2
        exit 2
      fi
      BRIDGE_ID="$2"
      shift 2
      ;;
    --iteration)
      if [[ -z "${2:-}" ]]; then
        echo "ERROR: --iteration requires a value" >&2
        exit 2
      fi
      ITERATION="$2"
      shift 2
      ;;
    --pr)
      if [[ -z "${2:-}" ]]; then
        echo "ERROR: --pr requires a value" >&2
        exit 2
      fi
      PR_NUMBER="$2"
      shift 2
      ;;
    --output-dir)
      if [[ -z "${2:-}" ]]; then
        echo "ERROR: --output-dir requires a value" >&2
        exit 2
      fi
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --help)
      echo "Usage: bridge-vision-capture.sh --findings <json> --bridge-id <id> --iteration <n> --pr <n> --output-dir <dir>"
      exit 0
      ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [[ -z "$FINDINGS_FILE" ]] || [[ -z "$BRIDGE_ID" ]] || [[ -z "$ITERATION" ]] || [[ -z "$OUTPUT_DIR" ]]; then
  echo "ERROR: --findings, --bridge-id, --iteration, and --output-dir are required" >&2
  exit 2
fi

if [[ ! -f "$FINDINGS_FILE" ]]; then
  echo "ERROR: Findings file not found: $FINDINGS_FILE" >&2
  exit 2
fi

# =============================================================================
# Check dependencies
# =============================================================================

if ! command -v jq &>/dev/null; then
  echo "ERROR: jq is required" >&2
  exit 2
fi

# =============================================================================
# Extract Vision Findings
# =============================================================================

vision_count=$(jq '[.findings[] | select(.severity == "VISION")] | length' "$FINDINGS_FILE")

if [[ "$vision_count" -eq 0 ]]; then
  echo "0"
  exit 0
fi

# Determine next vision number
entries_dir="$OUTPUT_DIR/entries"
mkdir -p "$entries_dir"

next_number=1
if ls "$entries_dir"/vision-*.md 1>/dev/null 2>&1; then
  # Find highest existing vision number
  local_max=$(ls "$entries_dir"/vision-*.md 2>/dev/null | \
    sed 's/.*vision-\([0-9]*\)\.md/\1/' | \
    sort -n | tail -1)
  next_number=$((local_max + 1))
fi

# Create vision entries
captured=0
now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

while IFS= read -r vision; do
  local_num=$((next_number + captured))
  vision_id=$(printf "vision-%03d" "$local_num")

  title=$(echo "$vision" | jq -r '.title // "Untitled Vision"')
  description=$(echo "$vision" | jq -r '.description // "No description"')
  potential=$(echo "$vision" | jq -r '.potential // "To be explored"')
  finding_id=$(echo "$vision" | jq -r '.id // "unknown"')

  # Create vision entry file
  cat > "$entries_dir/${vision_id}.md" <<EOF
# Vision: ${title}

**ID**: ${vision_id}
**Source**: Bridge iteration ${ITERATION} of ${BRIDGE_ID}
**PR**: #${PR_NUMBER:-unknown}
**Date**: ${now}
**Status**: Captured
**Tags**: [architecture]

## Insight

${description}

## Potential

${potential}

## Connection Points

- Bridgebuilder finding: ${finding_id}
- Bridge: ${BRIDGE_ID}, iteration ${ITERATION}
EOF

  captured=$((captured + 1))
done < <(jq -c '.findings[] | select(.severity == "VISION")' "$FINDINGS_FILE")

# Update index.md
if [[ -f "$OUTPUT_DIR/index.md" ]]; then
  # Read current index and append new entries to the table
  local_num=$next_number
  while IFS= read -r vision; do
    vision_id=$(printf "vision-%03d" "$local_num")
    title=$(echo "$vision" | jq -r '.title // "Untitled Vision"')

    # Insert row before the empty line after the table header
    # Find the table and append
    if grep -q "^| $vision_id " "$OUTPUT_DIR/index.md" 2>/dev/null; then
      : # Already exists, skip
    else
      # Sanitize all sed-interpolated variables for metacharacters
      safe_vid=$(printf '%s' "$vision_id" | sed 's/[\\/&]/\\\\&/g')
      safe_title=$(printf '%s' "$title" | sed 's/[\\/&]/\\\\&/g')
      safe_iteration=$(printf '%s' "$ITERATION" | sed 's/[\\/&]/\\\\&/g')
      safe_bridge_id=$(printf '%s' "$BRIDGE_ID" | sed 's/[\\/&]/\\\\&/g')
      safe_pr=$(printf '%s' "${PR_NUMBER:-?}" | sed 's/[\\/&]/\\\\&/g')
      # Append to table (before Statistics section) — portable sed (no -i)
      sed "/^## Statistics/i | $safe_vid | $safe_title | Bridge iter $safe_iteration, PR #$safe_pr | Captured | [architecture] |" "$OUTPUT_DIR/index.md" > "$OUTPUT_DIR/index.md.tmp" && mv "$OUTPUT_DIR/index.md.tmp" "$OUTPUT_DIR/index.md"
    fi

    local_num=$((local_num + 1))
  done < <(jq -c '.findings[] | select(.severity == "VISION")' "$FINDINGS_FILE")

  # Update statistics — portable sed (no -i)
  total_captured=$(ls "$entries_dir"/vision-*.md 2>/dev/null | wc -l)
  safe_total=$(printf '%s' "$total_captured" | sed 's/[\\/&]/\\\\&/g')
  sed "s/^- Total captured: .*/- Total captured: $safe_total/" "$OUTPUT_DIR/index.md" > "$OUTPUT_DIR/index.md.tmp" && mv "$OUTPUT_DIR/index.md.tmp" "$OUTPUT_DIR/index.md"
fi

echo "$vision_count"
