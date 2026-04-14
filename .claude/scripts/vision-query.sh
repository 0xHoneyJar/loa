#!/usr/bin/env bash
# =============================================================================
# vision-query.sh — Vision Registry Query CLI
# =============================================================================
# Version: 1.0.0
# Part of: Vision Registry Graduation (cycle-069, #486)
#
# Query and filter visions from entry files. Rebuild index from entries.
# Sources vision-lib.sh for shared functions.
#
# Usage:
#   vision-query.sh [--tags t1,t2] [--status s1,s2] [--source pat]
#                   [--since date] [--before date] [--min-refs n]
#                   [--format json|table|ids] [--count] [--limit n]
#                   [--strict] [--rebuild-index [--dry-run]]
#
# Exit codes:
#   0 - Success (results found, or rebuild complete)
#   1 - No results matching filters
#   2 - Invalid arguments
#   3 - Parse error (quarantined entries)
#   4 - I/O error
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/bootstrap.sh"
source "$SCRIPT_DIR/vision-lib.sh"

# =============================================================================
# Configuration
# =============================================================================

VISIONS_DIR="${PROJECT_ROOT}/grimoires/loa/visions"
ENTRIES_DIR="${VISIONS_DIR}/entries"
INDEX_FILE="${VISIONS_DIR}/index.md"
DEFAULT_LIMIT=50

# Valid statuses for validation
VALID_STATUSES="Captured Exploring Proposed Implemented Deferred Archived Rejected"

# =============================================================================
# Argument Parsing
# =============================================================================

FILTER_TAGS=""
FILTER_STATUS=""
FILTER_SOURCE=""
FILTER_SINCE=""
FILTER_BEFORE=""
FILTER_MIN_REFS=0
OUTPUT_FORMAT="json"
OUTPUT_COUNT=false
OUTPUT_LIMIT="$DEFAULT_LIMIT"
STRICT_MODE=false
DO_REBUILD=false
DRY_RUN=false

_usage() {
  echo "Usage: vision-query.sh [OPTIONS]" >&2
  echo "" >&2
  echo "Options:" >&2
  echo "  --tags t1,t2       Filter by tags (ANY match)" >&2
  echo "  --status s1,s2     Filter by status (comma-list)" >&2
  echo "  --source pattern   Filter by source (fixed-string match)" >&2
  echo "  --since date       Visions on or after ISO date" >&2
  echo "  --before date      Visions before ISO date" >&2
  echo "  --min-refs n       Visions with >= n references" >&2
  echo "  --format f         Output: json (default), table, ids" >&2
  echo "  --count            Show count instead of listing" >&2
  echo "  --limit n          Max results (default: $DEFAULT_LIMIT)" >&2
  echo "  --strict           Fail on parse errors (exit 3)" >&2
  echo "  --rebuild-index    Regenerate index.md from entries" >&2
  echo "  --dry-run          With --rebuild-index: show diff only" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tags)
      [[ -z "${2:-}" ]] && { echo "ERROR: --tags requires a value" >&2; exit 2; }
      FILTER_TAGS="$2"; shift 2 ;;
    --status)
      [[ -z "${2:-}" ]] && { echo "ERROR: --status requires a value" >&2; exit 2; }
      FILTER_STATUS="$2"; shift 2 ;;
    --source)
      [[ -z "${2:-}" ]] && { echo "ERROR: --source requires a value" >&2; exit 2; }
      FILTER_SOURCE="$2"; shift 2 ;;
    --since)
      [[ -z "${2:-}" ]] && { echo "ERROR: --since requires a value" >&2; exit 2; }
      if [[ ! "$2" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2} ]]; then
        echo "ERROR: --since must be ISO-8601 date (YYYY-MM-DD)" >&2; exit 2
      fi
      FILTER_SINCE="$2"; shift 2 ;;
    --before)
      [[ -z "${2:-}" ]] && { echo "ERROR: --before requires a value" >&2; exit 2; }
      if [[ ! "$2" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2} ]]; then
        echo "ERROR: --before must be ISO-8601 date (YYYY-MM-DD)" >&2; exit 2
      fi
      FILTER_BEFORE="$2"; shift 2 ;;
    --min-refs)
      [[ -z "${2:-}" ]] && { echo "ERROR: --min-refs requires a value" >&2; exit 2; }
      if [[ ! "$2" =~ ^[0-9]+$ ]]; then
        echo "ERROR: --min-refs must be a non-negative integer" >&2; exit 2
      fi
      FILTER_MIN_REFS="$2"; shift 2 ;;
    --format)
      [[ -z "${2:-}" ]] && { echo "ERROR: --format requires a value" >&2; exit 2; }
      case "$2" in
        json|table|ids) OUTPUT_FORMAT="$2" ;;
        *) echo "ERROR: --format must be json, table, or ids" >&2; exit 2 ;;
      esac
      shift 2 ;;
    --count) OUTPUT_COUNT=true; shift ;;
    --limit)
      [[ -z "${2:-}" ]] && { echo "ERROR: --limit requires a value" >&2; exit 2; }
      if [[ ! "$2" =~ ^[0-9]+$ ]]; then
        echo "ERROR: --limit must be a positive integer" >&2; exit 2
      fi
      OUTPUT_LIMIT="$2"; shift 2 ;;
    --strict) STRICT_MODE=true; shift ;;
    --rebuild-index) DO_REBUILD=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --help|-h) _usage ;;
    *)
      echo "ERROR: Unknown option: $1" >&2; exit 2 ;;
  esac
done

# Validate --status values
if [[ -n "$FILTER_STATUS" ]]; then
  IFS=',' read -ra status_arr <<< "$FILTER_STATUS"
  for s in "${status_arr[@]}"; do
    s=$(echo "$s" | xargs)  # trim
    local_match=false
    for valid in $VALID_STATUSES; do
      if [[ "${s,,}" == "${valid,,}" ]]; then
        local_match=true
        break
      fi
    done
    if [[ "$local_match" == "false" ]]; then
      echo "ERROR: Invalid status '$s'. Valid: $VALID_STATUSES" >&2
      exit 2
    fi
  done
fi

# Validate --tags format
if [[ -n "$FILTER_TAGS" ]]; then
  IFS=',' read -ra tag_arr <<< "$FILTER_TAGS"
  for t in "${tag_arr[@]}"; do
    t=$(echo "$t" | xargs)
    if [[ -n "$t" ]] && ! _vision_validate_tag "$t" 2>/dev/null; then
      echo "ERROR: Invalid tag format: $t (expected lowercase alphanumeric with hyphens)" >&2
      exit 2
    fi
  done
fi

# =============================================================================
# Entry Parser
# =============================================================================

_parse_entry() {
  local entry_file="$1"
  local had_error=false

  if [[ ! -f "$entry_file" ]]; then
    return 1
  fi

  # Extract title from H1 header
  local title
  title=$(grep '^# Vision:' "$entry_file" 2>/dev/null | head -1 | sed 's/^# Vision: *//' || true)

  # Extract frontmatter fields
  local id source pr date status tags_raw
  id=$(grep '^\*\*ID\*\*:' "$entry_file" 2>/dev/null | head -1 | sed 's/\*\*ID\*\*: *//' || true)
  source=$(grep '^\*\*Source\*\*:' "$entry_file" 2>/dev/null | head -1 | sed 's/\*\*Source\*\*: *//' || true)
  pr=$(grep '^\*\*PR\*\*:' "$entry_file" 2>/dev/null | head -1 | sed 's/\*\*PR\*\*: *//' || true)
  date=$(grep '^\*\*Date\*\*:' "$entry_file" 2>/dev/null | head -1 | sed 's/\*\*Date\*\*: *//' || true)
  status=$(grep '^\*\*Status\*\*:' "$entry_file" 2>/dev/null | head -1 | sed 's/\*\*Status\*\*: *//' || true)
  tags_raw=$(grep '^\*\*Tags\*\*:' "$entry_file" 2>/dev/null | head -1 | sed 's/\*\*Tags\*\*: *//' || true)

  # Validate required fields
  if [[ -z "$id" || -z "$status" ]]; then
    echo "WARNING: Malformed entry (missing ID or Status): $entry_file" >&2
    if [[ "$STRICT_MODE" == "true" ]]; then
      had_error=true
    fi
    # Emit quarantined entry for json format
    jq -n --arg file "$entry_file" '{parse_error: true, file: $file, reason: "missing ID or Status"}'
    if [[ "$had_error" == "true" ]]; then
      return 3
    fi
    return 0
  fi

  # Validate status
  local status_valid=false
  for valid in $VALID_STATUSES; do
    if [[ "$status" == "$valid" ]]; then
      status_valid=true
      break
    fi
  done
  if [[ "$status_valid" == "false" ]]; then
    echo "WARNING: Invalid status '$status' in: $entry_file" >&2
    jq -n --arg file "$entry_file" --arg status "$status" '{parse_error: true, file: $file, reason: ("invalid status: " + $status)}'
    if [[ "$STRICT_MODE" == "true" ]]; then
      return 3
    fi
    return 0
  fi

  # Parse tags
  local tags_json
  tags_json=$(echo "$tags_raw" | tr -d '[]' | tr ',' '\n' | \
    sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | \
    grep -v '^$' | \
    jq -R . | jq -s '.' 2>/dev/null || echo '[]')

  # Extract insight excerpt (first 200 chars of ## Insight section)
  local insight_excerpt
  insight_excerpt=$(vision_sanitize_text "$entry_file" 200 2>/dev/null || true)

  # Get ref count from index (best-effort)
  local refs=0
  if [[ -f "$INDEX_FILE" ]]; then
    refs=$(grep "^| $id " "$INDEX_FILE" 2>/dev/null | awk -F'|' '{print $NF}' | xargs 2>/dev/null || echo "0")
    if [[ -z "$refs" || ! "$refs" =~ ^[0-9]+$ ]]; then
      refs=0
    fi
  fi

  # Extract optional reason fields
  local archived_reason rejected_reason
  archived_reason=$(grep '^\*\*Archived-Reason\*\*:' "$entry_file" 2>/dev/null | head -1 | sed 's/\*\*Archived-Reason\*\*: *//' || true)
  rejected_reason=$(grep '^\*\*Rejected-Reason\*\*:' "$entry_file" 2>/dev/null | head -1 | sed 's/\*\*Rejected-Reason\*\*: *//' || true)

  # Build JSON output via jq --arg (safe, no shell expansion)
  local json_args=(
    --arg id "$id"
    --arg title "$title"
    --arg source "$source"
    --arg pr "$pr"
    --arg date "$date"
    --arg status "$status"
    --argjson tags "$tags_json"
    --arg insight_excerpt "$insight_excerpt"
    --argjson refs "$refs"
    --arg file "$entry_file"
  )

  local jq_expr='{id:$id, title:$title, source:$source, date:$date, status:$status, tags:$tags, insight_excerpt:$insight_excerpt, refs:$refs, file:$file}'

  # Add optional fields
  if [[ -n "$pr" ]]; then
    jq_expr='{id:$id, title:$title, source:$source, pr:$pr, date:$date, status:$status, tags:$tags, insight_excerpt:$insight_excerpt, refs:$refs, file:$file}'
  fi

  jq -n "${json_args[@]}" "$jq_expr"
}

# =============================================================================
# Filter Matching
# =============================================================================

_match_filters() {
  local entry_json="$1"

  # Skip quarantined entries
  if echo "$entry_json" | jq -e '.parse_error // false' >/dev/null 2>&1; then
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
      echo "$entry_json"
    fi
    return 0
  fi

  # Status filter (comma-list, case-insensitive)
  if [[ -n "$FILTER_STATUS" ]]; then
    local entry_status
    entry_status=$(echo "$entry_json" | jq -r '.status')
    local matched=false
    IFS=',' read -ra status_arr <<< "$FILTER_STATUS"
    for s in "${status_arr[@]}"; do
      s=$(echo "$s" | xargs)
      if [[ "${entry_status,,}" == "${s,,}" ]]; then
        matched=true
        break
      fi
    done
    if [[ "$matched" == "false" ]]; then
      return 1
    fi
  fi

  # Tags filter (ANY match)
  if [[ -n "$FILTER_TAGS" ]]; then
    local tag_matched=false
    IFS=',' read -ra tag_arr <<< "$FILTER_TAGS"
    for t in "${tag_arr[@]}"; do
      t=$(echo "$t" | xargs)
      if echo "$entry_json" | jq -e --arg t "$t" '.tags | index($t) != null' >/dev/null 2>&1; then
        tag_matched=true
        break
      fi
    done
    if [[ "$tag_matched" == "false" ]]; then
      return 1
    fi
  fi

  # Source filter (fixed-string, case-insensitive — Flatline SKP-004)
  if [[ -n "$FILTER_SOURCE" ]]; then
    local entry_source
    entry_source=$(echo "$entry_json" | jq -r '.source')
    if ! echo "$entry_source" | grep -qFi -- "$FILTER_SOURCE"; then
      return 1
    fi
  fi

  # Date filters (lexicographic comparison — UTC ISO-8601)
  if [[ -n "$FILTER_SINCE" ]]; then
    local entry_date
    entry_date=$(echo "$entry_json" | jq -r '.date')
    if [[ "$entry_date" < "$FILTER_SINCE" ]]; then
      return 1
    fi
  fi

  if [[ -n "$FILTER_BEFORE" ]]; then
    local entry_date
    entry_date=$(echo "$entry_json" | jq -r '.date')
    if [[ ! "$entry_date" < "$FILTER_BEFORE" ]]; then
      return 1
    fi
  fi

  # Min-refs filter
  if [[ "$FILTER_MIN_REFS" -gt 0 ]]; then
    local entry_refs
    entry_refs=$(echo "$entry_json" | jq -r '.refs')
    if [[ "$entry_refs" -lt "$FILTER_MIN_REFS" ]]; then
      return 1
    fi
  fi

  echo "$entry_json"
  return 0
}

# =============================================================================
# Index Rebuild
# =============================================================================

_rebuild_index() {
  if [[ ! -d "$ENTRIES_DIR" ]]; then
    echo "ERROR: Entries directory not found: $ENTRIES_DIR" >&2
    exit 4
  fi

  local new_index=""
  local parse_errors=0
  local total=0

  # Header
  new_index="<!-- schema_version: 1 -->
# Vision Registry

## Active Visions

| ID | Title | Source | Status | Tags | Refs |
|----|-------|--------|--------|------|------|"

  # Scan and parse all entries
  local entry_files=()
  while IFS= read -r f; do
    entry_files+=("$f")
  done < <(ls "$ENTRIES_DIR"/vision-*.md 2>/dev/null | sort)

  for entry_file in ${entry_files[@]+"${entry_files[@]}"}; do
    local entry_json
    entry_json=$(_parse_entry "$entry_file" 2>/dev/null) || true

    if [[ -z "$entry_json" ]]; then
      parse_errors=$((parse_errors + 1))
      continue
    fi

    # Skip quarantined entries
    if echo "$entry_json" | jq -e '.parse_error // false' >/dev/null 2>&1; then
      echo "WARNING: Skipping quarantined entry: $entry_file" >&2
      parse_errors=$((parse_errors + 1))
      continue
    fi

    local id title source status tags_display refs
    id=$(echo "$entry_json" | jq -r '.id')
    # Review fix #5: escape pipes in title/source to prevent markdown table breakage
    title=$(echo "$entry_json" | jq -r '.title | gsub("\\|"; "-")')
    source=$(echo "$entry_json" | jq -r '.source | gsub("\\|"; "-")')
    status=$(echo "$entry_json" | jq -r '.status')
    tags_display=$(echo "$entry_json" | jq -r '.tags | join(", ")')
    refs=$(echo "$entry_json" | jq -r '.refs')

    new_index="${new_index}
| ${id} | ${title} | ${source} | ${status} | ${tags_display} | ${refs} |"
    total=$((total + 1))
  done

  # Count statuses for statistics
  local captured=0 exploring=0 proposed=0 implemented=0 deferred=0 archived=0 rejected=0
  while IFS= read -r line; do
    case "$(echo "$line" | awk -F'|' '{print $5}' | xargs)" in
      Captured) captured=$((captured + 1)) ;;
      Exploring) exploring=$((exploring + 1)) ;;
      Proposed) proposed=$((proposed + 1)) ;;
      Implemented) implemented=$((implemented + 1)) ;;
      Deferred) deferred=$((deferred + 1)) ;;
      Archived) archived=$((archived + 1)) ;;
      Rejected) rejected=$((rejected + 1)) ;;
    esac
  done <<< "$(echo "$new_index" | grep '^| vision-')"

  new_index="${new_index}

## Statistics

- Total captured: ${captured}
- Total exploring: ${exploring}
- Total proposed: ${proposed}
- Total implemented: ${implemented}
- Total deferred: ${deferred}
- Total archived: ${archived}
- Total rejected: ${rejected}
"

  if [[ "$DRY_RUN" == "true" ]]; then
    # Show diff without writing
    local tmp_new
    tmp_new=$(mktemp)
    echo "$new_index" > "$tmp_new"
    echo "=== Index Rebuild Dry Run ===" >&2
    echo "Entries parsed: $total" >&2
    echo "Parse errors: $parse_errors" >&2
    if [[ -f "$INDEX_FILE" ]]; then
      diff -u "$INDEX_FILE" "$tmp_new" || true
    else
      echo "(No existing index — would create new)" >&2
      cat "$tmp_new"
    fi
    rm -f "$tmp_new"
  else
    # Atomic write — use printf to write content (no subshell function needed)
    _do_rebuild_write() {
      printf '%s\n' "$new_index" > "$INDEX_FILE"
    }
    vision_atomic_write "$INDEX_FILE" _do_rebuild_write
    echo "Index rebuilt: $total entries ($parse_errors quarantined)" >&2
  fi

  if [[ "$parse_errors" -gt 0 && "$STRICT_MODE" == "true" ]]; then
    exit 3
  fi
}

# =============================================================================
# Output Formatting
# =============================================================================

_format_output() {
  local results_json="$1"
  local count
  count=$(echo "$results_json" | jq 'length')

  if [[ "$OUTPUT_COUNT" == "true" ]]; then
    echo "$count"
    return
  fi

  case "$OUTPUT_FORMAT" in
    json)
      echo "$results_json" | jq '.'
      ;;
    table)
      echo "| ID | Title | Source | Status | Tags | Refs |"
      echo "|----|-------|--------|--------|------|------|"
      echo "$results_json" | jq -r '.[] | select(.parse_error != true) | "| \(.id) | \(.title) | \(.source) | \(.status) | \(.tags | join(", ")) | \(.refs) |"'
      ;;
    ids)
      echo "$results_json" | jq -r '.[] | select(.parse_error != true) | .id'
      ;;
  esac
}

# =============================================================================
# Main
# =============================================================================

# Handle rebuild
if [[ "$DO_REBUILD" == "true" ]]; then
  _rebuild_index
  exit 0
fi

# Check entries directory
if [[ ! -d "$ENTRIES_DIR" ]]; then
  echo "ERROR: Entries directory not found: $ENTRIES_DIR" >&2
  exit 4
fi

# Scan and filter entries
results=()
parse_error_count=0

for entry_file in "$ENTRIES_DIR"/vision-*.md; do
  [[ -f "$entry_file" ]] || continue

  entry_json=$(_parse_entry "$entry_file") || {
    parse_error_count=$((parse_error_count + 1))
    continue
  }

  if [[ -z "$entry_json" ]]; then
    continue
  fi

  # Apply filters
  matched=$(_match_filters "$entry_json") || continue
  if [[ -n "$matched" ]]; then
    results+=("$matched")
  fi
done

# Sort by date descending
if [[ ${#results[@]} -gt 0 ]]; then
  sorted_json=$(printf '%s\n' "${results[@]}" | jq -s 'sort_by(.date) | reverse')
else
  sorted_json="[]"
fi

# Apply limit
limited_json=$(echo "$sorted_json" | jq --argjson limit "$OUTPUT_LIMIT" '.[0:$limit]')

# Check result count
result_count=$(echo "$limited_json" | jq 'length')

# Output
_format_output "$limited_json"

# Exit code
if [[ "$result_count" -eq 0 ]]; then
  exit 1
fi

if [[ "$parse_error_count" -gt 0 && "$STRICT_MODE" == "true" ]]; then
  exit 3
fi

exit 0
