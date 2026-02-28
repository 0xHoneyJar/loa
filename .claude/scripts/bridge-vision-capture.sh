#!/usr/bin/env bash
# bridge-vision-capture.sh - Extract VISION-type findings into vision registry
# Version: 1.1.0
#
# Filters findings JSON for VISION entries and creates vision registry entries.
# Shared functions provided by vision-lib.sh (v1.42.0 refactor).
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

# Source shared vision library (IMP-009: error exit if missing, no silent fallback)
if [[ ! -f "$SCRIPT_DIR/vision-lib.sh" ]]; then
  echo "ERROR: vision-lib.sh not found at $SCRIPT_DIR/vision-lib.sh — run /update-loa to restore" >&2
  exit 2
fi
source "$SCRIPT_DIR/vision-lib.sh"

# =============================================================================
# Entry Points — delegates to vision-lib.sh functions
# =============================================================================

# Early exit for vision relevance check mode
if [[ "${1:-}" == "--check-relevant" ]]; then
  shift
  cr_diff="${1:-}"
  cr_dir="${2:-${PROJECT_ROOT}/grimoires/loa/visions}"
  cr_min="${3:-2}"
  if [[ -z "$cr_diff" ]]; then
    echo "Usage: bridge-vision-capture.sh --check-relevant <diff-file> [visions-dir] [min-overlap]" >&2
    exit 2
  fi
  # Use legacy check_relevant_visions for backward compat with diff-file input
  _capture_check_relevant() {
    local diff_file="$1"
    local visions_dir="$2"
    local min_tag_overlap="$3"
    local index_file="${visions_dir}/index.md"

    [[ -f "$index_file" ]] || return 0

    local pr_tags_str
    pr_tags_str=$(_capture_extract_pr_tags "$diff_file" 2>/dev/null || true)
    [[ -z "$pr_tags_str" ]] && return 0

    local -a pr_tags
    mapfile -t pr_tags <<< "$pr_tags_str"

    while IFS= read -r line; do
      local vid status tags_raw
      vid=$(echo "$line" | awk -F'|' '{print $2}' | xargs)
      status=$(echo "$line" | awk -F'|' '{print $5}' | xargs)
      tags_raw=$(echo "$line" | awk -F'|' '{print $6}' | xargs)

      [[ "$status" == "Captured" || "$status" == "Exploring" ]] || continue

      local vision_tags
      vision_tags=$(echo "$tags_raw" | tr -d '[]' | tr ',' '\n' | xargs -I{} echo {} | xargs)

      local overlap=0
      for vtag in $vision_tags; do
        for ptag in "${pr_tags[@]}"; do
          if [[ "$vtag" == "$ptag" ]]; then
            overlap=$((overlap + 1))
          fi
        done
      done

      if [[ $overlap -ge $min_tag_overlap ]]; then
        echo "$vid"
      fi
    done < <(grep '^| vision-' "$index_file" 2>/dev/null || true)
  }

  # Extract PR tags from diff file (legacy entry point)
  _capture_extract_pr_tags() {
    local diff_file="$1"
    [[ -f "$diff_file" || "$diff_file" == "-" ]] || return 0

    local content
    content=$(cat "$diff_file" 2>/dev/null || true)

    echo "$content" | grep -oP '(?:^diff --git a/|^\+\+\+ b/)(.+)' 2>/dev/null | \
      sed 's|diff --git a/||;s|+++ b/||' | sort -u | \
      vision_extract_tags -
  }

  _capture_check_relevant "$cr_diff" "$cr_dir" "$cr_min"
  exit $?
fi

# Early exit for reference recording mode
if [[ "${1:-}" == "--record-reference" ]]; then
  shift
  rr_vid="${1:-}"
  rr_bridge="${2:-}"
  rr_dir="${3:-${PROJECT_ROOT}/grimoires/loa/visions}"
  if [[ -z "$rr_vid" || -z "$rr_bridge" ]]; then
    echo "Usage: bridge-vision-capture.sh --record-reference <vision-id> <bridge-id> [visions-dir]" >&2
    exit 2
  fi
  vision_record_ref "$rr_vid" "$rr_bridge" "$rr_dir"
  exit $?
fi

# Early exit for status update mode
if [[ "${1:-}" == "--update-status" ]]; then
  shift
  us_vid="${1:-}"
  us_status="${2:-}"
  us_dir="${3:-${PROJECT_ROOT}/grimoires/loa/visions}"
  if [[ -z "$us_vid" || -z "$us_status" ]]; then
    echo "Usage: bridge-vision-capture.sh --update-status <vision-id> <new-status> [visions-dir]" >&2
    exit 2
  fi
  vision_update_status "$us_vid" "$us_status" "$us_dir"
  exit $?
fi

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
# Extract Vision Findings
# =============================================================================

vision_count=$(jq '[.findings[] | select(.severity == "VISION" or .severity == "SPECULATION")] | length' "$FINDINGS_FILE")

if [[ "$vision_count" -eq 0 ]]; then
  echo "0"
  exit 0
fi

# Determine next vision number
entries_dir="$OUTPUT_DIR/entries"
mkdir -p "$entries_dir"

next_number=1
if ls "$entries_dir"/vision-*.md 1>/dev/null 2>&1; then
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

  # Create vision entry file — safe template via jq (no shell expansion, vision-002 fix)
  jq -n \
    --arg title "$title" \
    --arg vid "$vision_id" \
    --arg source "Bridge iteration ${ITERATION} of ${BRIDGE_ID}" \
    --arg pr "${PR_NUMBER:-unknown}" \
    --arg date "$now" \
    --arg desc "$description" \
    --arg pot "$potential" \
    --arg fid "$finding_id" \
    --arg bid "$BRIDGE_ID" \
    --arg iter "$ITERATION" \
    -r '"# Vision: " + $title + "\n\n" +
      "**ID**: " + $vid + "\n" +
      "**Source**: " + $source + "\n" +
      "**PR**: #" + $pr + "\n" +
      "**Date**: " + $date + "\n" +
      "**Status**: Captured\n" +
      "**Tags**: [architecture]\n\n" +
      "## Insight\n\n" + $desc + "\n\n" +
      "## Potential\n\n" + $pot + "\n\n" +
      "## Connection Points\n\n" +
      "- Bridgebuilder finding: " + $fid + "\n" +
      "- Bridge: " + $bid + ", iteration " + $iter' \
    > "$entries_dir/${vision_id}.md"

  captured=$((captured + 1))
done < <(jq -c '.findings[] | select(.severity == "VISION" or .severity == "SPECULATION")' "$FINDINGS_FILE")

# Update index.md
if [[ -f "$OUTPUT_DIR/index.md" ]]; then
  local_num=$next_number
  while IFS= read -r vision; do
    vision_id=$(printf "vision-%03d" "$local_num")
    title=$(echo "$vision" | jq -r '.title // "Untitled Vision"')

    if grep -q "^| $vision_id " "$OUTPUT_DIR/index.md" 2>/dev/null; then
      : # Already exists, skip
    else
      safe_vid=$(printf '%s' "$vision_id" | sed 's/[\\/&]/\\\\&/g')
      safe_title=$(printf '%s' "$title" | sed 's/[\\/&]/\\\\&/g')
      safe_iteration=$(printf '%s' "$ITERATION" | sed 's/[\\/&]/\\\\&/g')
      safe_bridge_id=$(printf '%s' "$BRIDGE_ID" | sed 's/[\\/&]/\\\\&/g')
      safe_pr=$(printf '%s' "${PR_NUMBER:-?}" | sed 's/[\\/&]/\\\\&/g')
      sed "/^## Statistics/i | $safe_vid | $safe_title | Bridge iter $safe_iteration, PR #$safe_pr | Captured | [architecture] | 0 |" "$OUTPUT_DIR/index.md" > "$OUTPUT_DIR/index.md.tmp" && mv "$OUTPUT_DIR/index.md.tmp" "$OUTPUT_DIR/index.md"
    fi

    local_num=$((local_num + 1))
  done < <(jq -c '.findings[] | select(.severity == "VISION" or .severity == "SPECULATION")' "$FINDINGS_FILE")

  # Regenerate statistics dynamically from table rows
  vision_regenerate_index_stats "$OUTPUT_DIR/index.md" 2>/dev/null || true
fi

echo "$vision_count"
