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
# Status Transition Mode (v1.39.0 — Vision Lifecycle)
# =============================================================================

# Update vision status in index.md
# Usage: update_vision_status <vision_id> <new_status> <output_dir>
# Valid transitions: Captured→Exploring, Exploring→Proposed, Proposed→Implemented/Deferred
update_vision_status() {
  local vid="$1"
  local new_status="$2"
  local visions_dir="$3"
  local index_file="$visions_dir/index.md"

  if [[ ! -f "$index_file" ]]; then
    echo "ERROR: Vision index not found: $index_file" >&2
    return 1
  fi

  case "$new_status" in
    Captured|Exploring|Proposed|Implemented|Deferred) ;;
    *) echo "ERROR: Invalid status: $new_status" >&2; return 1 ;;
  esac

  local safe_vid safe_status
  safe_vid=$(printf '%s' "$vid" | sed 's/[\\/&]/\\\\&/g')
  safe_status=$(printf '%s' "$new_status" | sed 's/[\\/&]/\\\\&/g')

  if grep -q "^| $vid " "$index_file" 2>/dev/null; then
    # Match columns by counting pipes: | ID | Title | Source | STATUS | Tags |
    # Use [^|]* to stay within column boundaries (non-greedy per-column)
    sed "s/^\(| $safe_vid [^|]*|[^|]*|[^|]*| \)[A-Za-z]* \(|.*\)/\1$safe_status \2/" "$index_file" > "$index_file.tmp" && mv "$index_file.tmp" "$index_file"
    echo "Updated $vid status to $new_status"
  else
    echo "WARNING: Vision $vid not found in index" >&2
    return 1
  fi

  local entry_file="$visions_dir/entries/${vid}.md"
  if [[ -f "$entry_file" ]]; then
    sed "s/^\*\*Status\*\*: .*/\*\*Status\*\*: $safe_status/" "$entry_file" > "$entry_file.tmp" && mv "$entry_file.tmp" "$entry_file"
  fi
}

# =============================================================================
# Reference Recording Mode (v1.39.0 — Vision Revisitation Tracking)
# =============================================================================

# Record a reference to a vision from a bridge review.
# Increments the Refs counter in the Active Visions table.
# Usage: bridge-vision-capture.sh --record-reference <vision-id> <bridge-id> [visions-dir]
record_reference() {
  local vid="$1"
  local bridge_id="$2"
  local visions_dir="${3:-${PROJECT_ROOT}/grimoires/loa/visions}"
  local index_file="$visions_dir/index.md"
  local ref_threshold="${VISION_REF_THRESHOLD:-3}"

  if [[ ! -f "$index_file" ]]; then
    echo "ERROR: Vision index not found: $index_file" >&2
    return 1
  fi

  if ! grep -q "^| $vid " "$index_file" 2>/dev/null; then
    echo "WARNING: Vision $vid not found in index" >&2
    return 1
  fi

  # Ensure the Refs column exists in the header
  if ! grep -q "| Refs |" "$index_file" 2>/dev/null; then
    # Add Refs column to header row and separator row
    sed 's/| Tags |$/| Tags | Refs |/' "$index_file" > "$index_file.tmp" && mv "$index_file.tmp" "$index_file"
    sed 's/|------|\s*$/|------|------|/' "$index_file" > "$index_file.tmp" && mv "$index_file.tmp" "$index_file"
    # Add initial ref count (0) to existing vision rows
    sed '/^| vision-/s/ |$/| 0 |/' "$index_file" > "$index_file.tmp" && mv "$index_file.tmp" "$index_file"
  fi

  # Extract current ref count for this vision
  local current_refs
  current_refs=$(grep "^| $vid " "$index_file" | sed 's/.*| \([0-9]*\) |$/\1/' || echo "0")
  if [[ -z "$current_refs" || ! "$current_refs" =~ ^[0-9]+$ ]]; then
    current_refs=0
  fi

  local new_refs=$((current_refs + 1))

  # Update ref count — match the trailing "| N |" at end of the vision row
  local safe_vid
  safe_vid=$(printf '%s' "$vid" | sed 's/[\\/&]/\\\\&/g')
  sed "s/^\(| $safe_vid .*| \)[0-9]* |$/\1$new_refs |/" "$index_file" > "$index_file.tmp" && mv "$index_file.tmp" "$index_file"

  echo "Recorded reference: $vid now has $new_refs references (bridge: $bridge_id)"

  # Check threshold for lore elevation suggestion
  if [[ "$new_refs" -gt "$ref_threshold" ]]; then
    echo "$vid referenced $new_refs times — consider elevating to lore"
  fi
}

# =============================================================================
# Vision Relevance Check (FR-3 — Vision Registry Activation)
# =============================================================================

# Extract PR-relevant tags from a diff file by mapping file paths to categories.
# Output: space-separated tag list
extract_pr_tags() {
  local diff_file="$1"

  if [[ ! -f "$diff_file" && "$diff_file" != "-" ]]; then
    return
  fi

  local tags=()
  local content
  content=$(cat "$diff_file" 2>/dev/null || true)

  # Map file path patterns to tags
  echo "$content" | grep -oP '(?:^diff --git a/|^\+\+\+ b/)(.+)' 2>/dev/null | sed 's|diff --git a/||;s|+++ b/||' | sort -u | while read -r filepath; do
    case "$filepath" in
      *orchestrator*|*architect*|*bridge*)  echo "architecture" ;;
      *security*|*redact*|*secret*|*audit*) echo "security" ;;
      *constraint*|*permission*|*guard*)    echo "constraints" ;;
      *flatline*|*multi-model*|*hounfour*)  echo "multi-model" ;;
      *test*|*spec*)                        echo "testing" ;;
      *lore*|*vision*|*memory*)             echo "philosophy" ;;
      *construct*|*pack*)                   echo "orchestration" ;;
    esac
  done | sort -u
}

# Check visions for relevance to current PR changes.
# Returns list of relevant vision IDs (one per line).
# Args: $1=diff_file, $2=visions_dir (optional), $3=min_tag_overlap (optional)
check_relevant_visions() {
  local diff_file="$1"
  local visions_dir="${2:-${PROJECT_ROOT}/grimoires/loa/visions}"
  local min_tag_overlap="${3:-2}"
  local index_file="${visions_dir}/index.md"

  [[ -f "$index_file" ]] || return 0

  # Extract PR tags from diff
  local pr_tags_str
  pr_tags_str=$(extract_pr_tags "$diff_file" 2>/dev/null || true)

  if [[ -z "$pr_tags_str" ]]; then
    return 0
  fi

  # Convert to array
  local -a pr_tags
  mapfile -t pr_tags <<< "$pr_tags_str"

  # Parse index.md for Captured/Exploring visions
  while IFS= read -r line; do
    # Parse table row: | ID | Title | Source | Status | Tags | Refs |
    local vid status tags_raw

    vid=$(echo "$line" | awk -F'|' '{print $2}' | xargs)
    status=$(echo "$line" | awk -F'|' '{print $5}' | xargs)
    tags_raw=$(echo "$line" | awk -F'|' '{print $6}' | xargs)

    # Only consider Captured or Exploring visions
    [[ "$status" == "Captured" || "$status" == "Exploring" ]] || continue

    # Parse vision tags (format: [tag1, tag2] or tag1, tag2)
    local vision_tags
    vision_tags=$(echo "$tags_raw" | tr -d '[]' | tr ',' '\n' | xargs -I{} echo {} | xargs)

    # Count tag overlap
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
  check_relevant_visions "$cr_diff" "$cr_dir" "$cr_min"
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
  record_reference "$rr_vid" "$rr_bridge" "$rr_dir"
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
  update_vision_status "$us_vid" "$us_status" "$us_dir"
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
