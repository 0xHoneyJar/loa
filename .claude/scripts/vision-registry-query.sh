#!/usr/bin/env bash
# vision-registry-query.sh — Query vision registry for planning integration
# Version: 1.0.0
#
# Queries the vision registry for visions relevant to current work context.
# Scores visions by tag overlap, reference count, and recency.
#
# Usage:
#   vision-registry-query.sh \
#     --tags "architecture,multi-model" \
#     --status "Captured,Exploring" \
#     --min-overlap 2 \
#     --max-results 3 \
#     --json
#
#   # Auto-derive tags from sprint context:
#   vision-registry-query.sh --tags auto --json
#
#   # Shadow mode (logs but doesn't present):
#   vision-registry-query.sh --tags "architecture" --shadow --json
#
# Exit Codes:
#   0 - Success (even if no results)
#   1 - Error
#   2 - Missing arguments or dependencies

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source shared vision library (error exit if missing)
if [[ ! -f "$SCRIPT_DIR/vision-lib.sh" ]]; then
  echo "ERROR: vision-lib.sh not found at $SCRIPT_DIR/vision-lib.sh" >&2
  exit 2
fi
source "$SCRIPT_DIR/vision-lib.sh"

# Dependency check (IMP-003)
for cmd in jq yq; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "ERROR: $cmd is required but not installed" >&2
    echo "  Install: brew install $cmd (macOS) or apt-get install $cmd (Linux)" >&2
    exit 2
  fi
done

# =============================================================================
# Arguments
# =============================================================================

TAGS=""
STATUS_FILTER="Captured,Exploring"
MIN_OVERLAP=2
MIN_OVERLAP_EXPLICIT=false
MAX_RESULTS=3
VISIONS_DIR="${PROJECT_ROOT}/grimoires/loa/visions"
JSON_OUTPUT=false
INCLUDE_TEXT=false
SHADOW_MODE=false
SHADOW_CYCLE=""
SHADOW_PHASE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tags)
      TAGS="${2:-}"
      shift 2
      ;;
    --status)
      STATUS_FILTER="${2:-}"
      shift 2
      ;;
    --min-overlap)
      MIN_OVERLAP="${2:-2}"
      MIN_OVERLAP_EXPLICIT=true
      shift 2
      ;;
    --max-results)
      MAX_RESULTS="${2:-3}"
      shift 2
      ;;
    --visions-dir)
      VISIONS_DIR="${2:-}"
      shift 2
      ;;
    --json)
      JSON_OUTPUT=true
      shift
      ;;
    --include-text)
      INCLUDE_TEXT=true
      shift
      ;;
    --shadow)
      SHADOW_MODE=true
      shift
      ;;
    --shadow-cycle)
      SHADOW_CYCLE="${2:-}"
      shift 2
      ;;
    --shadow-phase)
      SHADOW_PHASE="${2:-}"
      shift 2
      ;;
    --help)
      echo "Usage: vision-registry-query.sh --tags <tags> [--status <statuses>] [--min-overlap N] [--max-results N] [--json] [--include-text] [--shadow]"
      echo "  --shadow: Shadow mode auto-lowers --min-overlap to 1 (override with explicit --min-overlap)"
      exit 0
      ;;
    *)
      echo "ERROR: Unknown option: $1" >&2
      exit 2
      ;;
  esac
done

# Shadow mode auto-lowers min_overlap to 1 for broader observation
# (unless user explicitly set --min-overlap)
if [[ "$SHADOW_MODE" == "true" && "$MIN_OVERLAP_EXPLICIT" == "false" ]]; then
  MIN_OVERLAP=1
fi

if [[ -z "$TAGS" ]]; then
  echo "ERROR: --tags is required" >&2
  exit 2
fi

# Validate tags format (SKP-005)
if [[ "$TAGS" != "auto" ]]; then
  IFS=',' read -ra tag_arr <<< "$TAGS"
  for tag in "${tag_arr[@]}"; do
    tag=$(echo "$tag" | xargs)
    if [[ -n "$tag" && ! "$tag" =~ ^[a-z][a-z0-9_,-]*$ ]]; then
      echo "ERROR: Invalid tag format: $tag (expected ^[a-z][a-z0-9_-]*$)" >&2
      exit 2
    fi
  done
fi

# Validate visions-dir exists and is under project root (SKP-005)
if [[ -d "$VISIONS_DIR" ]]; then
  _vision_validate_dir "$VISIONS_DIR" || exit 2
fi

# Validate status values
IFS=',' read -ra status_arr <<< "$STATUS_FILTER"
for s in "${status_arr[@]}"; do
  s=$(echo "$s" | xargs)
  case "$s" in
    Captured|Exploring|Proposed|Implemented|Deferred) ;;
    *) echo "ERROR: Invalid status value: $s" >&2; exit 2 ;;
  esac
done

# =============================================================================
# Auto-tag derivation (IMP-002)
# =============================================================================

if [[ "$TAGS" == "auto" ]]; then
  derived_tags=""

  # Source 1: Sprint plan file paths
  if [[ -f "${PROJECT_ROOT}/grimoires/loa/sprint.md" ]]; then
    sprint_paths=$(grep -oE '\*\*File\*\*: `([^`]+)`' "${PROJECT_ROOT}/grimoires/loa/sprint.md" | \
      sed 's/\*\*File\*\*: `//;s/`//' || true)
    if [[ -n "$sprint_paths" ]]; then
      sprint_tags=$(echo "$sprint_paths" | vision_extract_tags - | tr '\n' ',' | sed 's/,$//')
      derived_tags="${derived_tags:+$derived_tags,}$sprint_tags"
    fi
  fi

  # Source 2: PRD keywords
  if [[ -f "${PROJECT_ROOT}/grimoires/loa/prd.md" ]]; then
    prd_content=$(cat "${PROJECT_ROOT}/grimoires/loa/prd.md" 2>/dev/null || true)
    # Match section headers against controlled vocabulary
    for keyword in architecture security constraints multi-model testing philosophy orchestration configuration eventing; do
      if echo "$prd_content" | grep -qi "$keyword" 2>/dev/null; then
        derived_tags="${derived_tags:+$derived_tags,}$keyword"
      fi
    done
  fi

  # Deduplicate
  if [[ -n "$derived_tags" ]]; then
    TAGS=$(echo "$derived_tags" | tr ',' '\n' | sort -u | tr '\n' ',' | sed 's/,$//')
  else
    # No tags derivable — return empty results
    if [[ "$JSON_OUTPUT" == "true" ]]; then
      echo "[]"
    else
      echo "No visions found (could not derive work context tags)"
    fi
    exit 0
  fi
fi

# =============================================================================
# Query
# =============================================================================

# Load index
index_json=$(vision_load_index "$VISIONS_DIR")

if [[ "$index_json" == "[]" ]]; then
  if [[ "$JSON_OUTPUT" == "true" ]]; then
    echo "[]"
  else
    echo "No visions found (empty registry)"
  fi
  exit 0
fi

# Filter by status and score
results=$(echo "$index_json" | jq -c --arg statuses "$STATUS_FILTER" '
  ($statuses | split(",") | map(gsub("^\\s+|\\s+$"; ""))) as $valid_statuses |
  [.[] | select(.status as $s | $valid_statuses | index($s) != null)]
')

if [[ "$results" == "[]" ]]; then
  if [[ "$JSON_OUTPUT" == "true" ]]; then
    echo "[]"
  else
    echo "No visions found matching status filter: $STATUS_FILTER"
  fi
  exit 0
fi

# Score each vision
scored_results="[]"
while IFS= read -r vision; do
  vid=$(echo "$vision" | jq -r '.id')
  vtags=$(echo "$vision" | jq -c '.tags')
  vrefs=$(echo "$vision" | jq -r '.refs // 0')
  vsource=$(echo "$vision" | jq -r '.source // ""')

  # Tag overlap score
  overlap=$(vision_match_tags "$TAGS" "$vtags")

  # Skip below minimum overlap
  if [[ "$overlap" -lt "$MIN_OVERLAP" ]]; then
    continue
  fi

  # Find matched tags
  matched_tags="[]"
  IFS=',' read -ra work_tag_arr <<< "$TAGS"
  for wtag in "${work_tag_arr[@]}"; do
    wtag=$(echo "$wtag" | xargs)
    [[ -z "$wtag" ]] && continue
    if echo "$vtags" | jq -e --arg t "$wtag" 'index($t) != null' >/dev/null 2>&1; then
      matched_tags=$(echo "$matched_tags" | jq --arg t "$wtag" '. + [$t]')
    fi
  done

  # Recency bonus: check if entry file has Date within 30 days
  recency_bonus=0
  entry_file="$VISIONS_DIR/entries/${vid}.md"
  if [[ -f "$entry_file" ]]; then
    date_str=$(grep '^\*\*Date\*\*:' "$entry_file" 2>/dev/null | sed 's/\*\*Date\*\*: *//' || true)
    if [[ -n "$date_str" ]]; then
      entry_epoch=$(date -d "$date_str" +%s 2>/dev/null || echo "0")
      now_epoch=$(date +%s)
      days_ago=$(( (now_epoch - entry_epoch) / 86400 ))
      if [[ "$days_ago" -le 30 ]]; then
        recency_bonus=1
      fi
    fi
  fi

  # Score formula: (tag_overlap * 3) + (refs * 2) + recency_bonus
  score=$(( (overlap * 3) + (vrefs * 2) + recency_bonus ))

  # Optionally include sanitized text
  insight_text=""
  if [[ "$INCLUDE_TEXT" == "true" && -f "$entry_file" ]]; then
    insight_text=$(vision_sanitize_text "$entry_file" 500)
  fi

  # Build result entry
  entry=$(jq -n \
    --arg id "$vid" \
    --arg title "$(echo "$vision" | jq -r '.title')" \
    --arg status "$(echo "$vision" | jq -r '.status')" \
    --argjson tags "$vtags" \
    --argjson refs "$vrefs" \
    --argjson score "$score" \
    --argjson matched_tags "$matched_tags" \
    --argjson overlap "$overlap" \
    --arg insight "$insight_text" \
    '{id:$id, title:$title, status:$status, tags:$tags, refs:$refs, score:$score, matched_tags:$matched_tags, overlap:$overlap, insight:$insight}')

  scored_results=$(echo "$scored_results" | jq --argjson e "$entry" '. + [$e]')
done < <(echo "$results" | jq -c '.[]')

# Sort by score descending, tie-break by vision ID
sorted_results=$(echo "$scored_results" | jq 'sort_by(-.score, .id)')

# Apply max-results cap
final_results=$(echo "$sorted_results" | jq --argjson max "$MAX_RESULTS" '.[0:$max]')

# Remove insight field if not requested
if [[ "$INCLUDE_TEXT" != "true" ]]; then
  final_results=$(echo "$final_results" | jq 'map(del(.insight))')
fi

# =============================================================================
# Shadow Mode Logging
# =============================================================================

if [[ "$SHADOW_MODE" == "true" ]]; then
  shadow_dir="${PROJECT_ROOT}/grimoires/loa/a2a/trajectory"
  mkdir -p "$shadow_dir"

  shadow_log="${shadow_dir}/vision-shadow-$(date -u +%Y-%m-%d).jsonl"
  shadow_state_file="$VISIONS_DIR/.shadow-state.json"

  # Read or initialize shadow state
  if [[ -f "$shadow_state_file" ]]; then
    shadow_cycles=$(jq -r '.shadow_cycles_completed // 0' "$shadow_state_file")
    shadow_matches=$(jq -r '.matches_during_shadow // 0' "$shadow_state_file")
  else
    shadow_cycles=0
    shadow_matches=0
  fi

  shadow_cycles=$((shadow_cycles + 1))
  match_count=$(echo "$final_results" | jq 'length')
  shadow_matches=$((shadow_matches + match_count))

  # Build shadow log entry (compact for JSONL — one line per entry)
  shadow_entry=$(jq -cn \
    --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg cycle "${SHADOW_CYCLE:-unknown}" \
    --arg phase "${SHADOW_PHASE:-plan-and-analyze}" \
    --arg work_tags "$TAGS" \
    --argjson matches "$final_results" \
    --argjson shadow_cycle_number "$shadow_cycles" \
    --argjson total_shadow_cycles "$shadow_cycles" \
    '{timestamp:$timestamp, cycle:$cycle, phase:$phase, work_tags:($work_tags | split(",")), matches:$matches, shadow_cycle_number:$shadow_cycle_number, total_shadow_cycles:$total_shadow_cycles}')

  echo "$shadow_entry" >> "$shadow_log"

  # Update shadow state atomically
  _do_update_shadow_state() {
    jq -n \
      --argjson cycles "$shadow_cycles" \
      --arg last_run "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --argjson matches "$shadow_matches" \
      '{shadow_cycles_completed:$cycles, last_shadow_run:$last_run, matches_during_shadow:$matches}' \
      > "$shadow_state_file.tmp" && mv "$shadow_state_file.tmp" "$shadow_state_file"
  }

  if command -v flock &>/dev/null; then
    vision_atomic_write "$shadow_state_file" _do_update_shadow_state
  else
    _do_update_shadow_state
  fi

  # Check graduation threshold
  config_threshold=$(yq eval '.vision_registry.shadow_cycles_before_prompt // 2' "${PROJECT_ROOT}/.loa.config.yaml" 2>/dev/null || echo "2")
  if [[ "$shadow_cycles" -ge "$config_threshold" && "$shadow_matches" -gt 0 ]]; then
    # Output graduation flag for the calling skill to detect
    if [[ "$JSON_OUTPUT" == "true" ]]; then
      final_results=$(echo "$final_results" | jq --argjson sc "$shadow_cycles" --argjson sm "$shadow_matches" \
        '{results: ., graduation: {ready: true, shadow_cycles: $sc, total_matches: $sm}}')
      echo "$final_results"
      exit 0
    else
      echo "GRADUATION_READY: Over $shadow_cycles cycles, $shadow_matches visions matched your work."
    fi
  fi
fi

# =============================================================================
# Output
# =============================================================================

if [[ "$JSON_OUTPUT" == "true" ]]; then
  echo "$final_results"
else
  count=$(echo "$final_results" | jq 'length')
  if [[ "$count" -eq 0 ]]; then
    echo "No matching visions found"
  else
    echo "Found $count relevant visions:"
    echo ""
    echo "$final_results" | jq -r '.[] | "  [\(.id)] \(.title) (score: \(.score), tags: \(.matched_tags | join(", ")))"'
  fi
fi
