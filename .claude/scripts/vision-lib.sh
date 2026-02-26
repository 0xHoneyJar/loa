#!/usr/bin/env bash
# vision-lib.sh — Shared vision registry functions
# Version: 1.0.0
#
# Provides shared functions for both write side (bridge-vision-capture.sh)
# and read side (vision-registry-query.sh) of the Vision Registry.
#
# Functions:
#   vision_load_index()          — Parse index.md into JSON array
#   vision_match_tags()          — Tag overlap matching with scoring
#   vision_record_ref()          — Atomic reference counting (flock + tmp+mv)
#   vision_validate_entry()      — Schema validation for vision entries
#   vision_sanitize_text()       — Allowlist extraction for safe context injection
#   vision_update_status()       — Lifecycle status transitions (flock + tmp+mv)
#   vision_extract_tags()        — File-path-to-tag mapping
#   vision_atomic_write()        — Flock-guarded file mutation wrapper
#   vision_check_lore_elevation() — Check if vision refs exceed lore threshold
#   vision_generate_lore_entry() — Generate lore-compatible YAML for a vision
#   vision_append_lore_entry()   — Idempotent append of elevated vision to lore
#
# Usage:
#   source "$SCRIPT_DIR/vision-lib.sh"

# Prevent double-sourcing
if [[ "${_VISION_LIB_LOADED:-}" == "true" ]]; then
  return 0 2>/dev/null || exit 0
fi
_VISION_LIB_LOADED=true

set -euo pipefail

# =============================================================================
# Dependencies
# =============================================================================

_VISION_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source bootstrap for PROJECT_ROOT
if [[ -z "${PROJECT_ROOT:-}" ]]; then
  source "$_VISION_LIB_DIR/bootstrap.sh"
fi

# Source compat-lib for cross-platform utilities
if [[ -f "$_VISION_LIB_DIR/compat-lib.sh" ]]; then
  source "$_VISION_LIB_DIR/compat-lib.sh"
fi

# Dependency check: jq required at source time
if ! command -v jq &>/dev/null; then
  echo "ERROR: vision-lib.sh requires jq but it is not installed" >&2
  echo "  Install: brew install jq (macOS) or apt-get install jq (Linux)" >&2
  return 2 2>/dev/null || exit 2
fi

# =============================================================================
# Flock Availability
# =============================================================================

# Check and ensure flock is available (same pattern as event-bus.sh)
_vision_require_flock() {
  if command -v flock &>/dev/null; then
    return 0
  fi

  # macOS: check Homebrew keg-only paths
  if [[ "$(uname -s)" == "Darwin" ]]; then
    local keg_paths=(
      "/opt/homebrew/opt/util-linux/bin"
      "/usr/local/opt/util-linux/bin"
    )
    for keg_path in "${keg_paths[@]}"; do
      if [[ -x "${keg_path}/flock" ]]; then
        export PATH="${keg_path}:${PATH}"
        return 0
      fi
    done

    echo "ERROR: vision-lib.sh requires flock for atomic writes." >&2
    echo "  Install on macOS: brew install util-linux" >&2
    echo "  (flock will be found automatically at Homebrew's keg-only path)" >&2
    return 3
  fi

  echo "ERROR: vision-lib.sh requires flock for atomic writes." >&2
  echo "  Install: apt-get install util-linux" >&2
  return 3
}

# =============================================================================
# Input Validation (SKP-005)
# =============================================================================

# Validate vision ID format: vision-NNN
_vision_validate_id() {
  local vid="$1"
  if [[ ! "$vid" =~ ^vision-[0-9]{3}$ ]]; then
    echo "ERROR: Invalid vision ID format: $vid (expected vision-NNN)" >&2
    return 1
  fi
  return 0
}

# Validate tag value: lowercase alphanumeric with hyphens/underscores
_vision_validate_tag() {
  local tag="$1"
  if [[ ! "$tag" =~ ^[a-z][a-z0-9_-]*$ ]]; then
    echo "ERROR: Invalid tag format: $tag (expected ^[a-z][a-z0-9_-]*$)" >&2
    return 1
  fi
  return 0
}

# Validate visions directory path (no traversal)
_vision_validate_dir() {
  local dir="$1"
  local project_root="${PROJECT_ROOT:-$(pwd)}"

  # Resolve to canonical path
  local canon_dir
  canon_dir=$(cd "$dir" 2>/dev/null && pwd) || {
    echo "ERROR: Visions directory does not exist: $dir" >&2
    return 1
  }

  local canon_root
  canon_root=$(cd "$project_root" 2>/dev/null && pwd)

  # Ensure dir is under project root (exact prefix with trailing slash to prevent
  # /home/user/project-evil matching /home/user/project)
  if [[ "$canon_dir" != "$canon_root" && "$canon_dir" != "$canon_root"/* ]]; then
    echo "ERROR: Visions directory must be under project root: $dir" >&2
    return 1
  fi
  return 0
}

# =============================================================================
# vision_atomic_write() — Flock-guarded file mutation
# =============================================================================
#
# Wraps a file mutation function with flock for mutual exclusion.
# The callback receives the target file path as its first argument.
#
# Usage:
#   vision_atomic_write "/path/to/file.md" my_mutation_func arg1 arg2
#
vision_atomic_write() {
  local target_file="$1"
  shift

  _vision_require_flock || return $?

  local lock_file="${target_file}.lock"

  (
    flock -w 5 200 || {
      echo "ERROR: Could not acquire lock on $lock_file after 5s" >&2
      exit 1  # exit, not return — inside flock subshell (PR #215 convention)
    }
    "$@"
  ) 200>"$lock_file"
}

# =============================================================================
# vision_load_index() — Parse index.md into JSON array
# =============================================================================
#
# Reads the vision registry index.md table and outputs a JSON array.
# Returns [] for empty or missing registry (no error).
# Malformed entries are logged and skipped, not fatal.
#
# Input: $1=visions_dir
# Output: JSON array to stdout
#
vision_load_index() {
  local visions_dir="${1:?Usage: vision_load_index <visions_dir>}"
  local index_file="$visions_dir/index.md"

  if [[ ! -f "$index_file" ]]; then
    echo "[]"
    return 0
  fi

  local json_entries=()
  while IFS= read -r line; do
    local id title source status tags_raw refs

    # Parse pipe-delimited table columns
    id=$(echo "$line" | awk -F'|' '{print $2}' | xargs)
    title=$(echo "$line" | awk -F'|' '{print $3}' | xargs)
    source=$(echo "$line" | awk -F'|' '{print $4}' | xargs)
    status=$(echo "$line" | awk -F'|' '{print $5}' | xargs)
    tags_raw=$(echo "$line" | awk -F'|' '{print $6}' | xargs)
    refs=$(echo "$line" | awk -F'|' '{print $7}' | xargs 2>/dev/null || echo "0")

    # Validate required fields — skip malformed (IMP-003)
    if [[ -z "$id" || -z "$status" ]]; then
      echo "WARNING: Skipping malformed vision entry (missing ID or Status)" >&2
      continue
    fi

    # Validate ID format
    if [[ ! "$id" =~ ^vision-[0-9]{3}$ ]]; then
      echo "WARNING: Skipping entry with invalid ID format: $id" >&2
      continue
    fi

    # Validate status value
    case "$status" in
      Captured|Exploring|Proposed|Implemented|Deferred) ;;
      *)
        echo "WARNING: Skipping entry with invalid status: $id ($status)" >&2
        continue
        ;;
    esac

    # Parse tags: strip brackets, split by comma, trim
    local tags_json
    tags_json=$(echo "$tags_raw" | tr -d '[]' | tr ',' '\n' | \
      sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | \
      grep -v '^$' | \
      jq -R . | jq -s '.')

    # Sanitize refs to integer
    if [[ -z "$refs" || ! "$refs" =~ ^[0-9]+$ ]]; then
      refs=0
    fi

    local entry
    entry=$(jq -n \
      --arg id "$id" \
      --arg title "$title" \
      --arg source "$source" \
      --arg status "$status" \
      --argjson tags "$tags_json" \
      --argjson refs "$refs" \
      '{id:$id, title:$title, source:$source, status:$status, tags:$tags, refs:$refs}')

    json_entries+=("$entry")
  done < <(grep '^| vision-' "$index_file" 2>/dev/null || true)

  # Combine entries into JSON array
  if [[ ${#json_entries[@]} -eq 0 ]]; then
    echo "[]"
  else
    printf '%s\n' "${json_entries[@]}" | jq -s '.'
  fi
}

# =============================================================================
# vision_match_tags() — Tag overlap scoring
# =============================================================================
#
# Count how many work context tags overlap with a vision's tags.
#
# Input: $1=work_tags (comma-separated), $2=vision_tags_json (JSON array string)
# Output: overlap count to stdout
#
vision_match_tags() {
  local work_tags="$1"
  local vision_tags_json="$2"

  local overlap=0
  local IFS=','
  for wtag in $work_tags; do
    # Trim whitespace
    wtag=$(echo "$wtag" | xargs)
    [[ -z "$wtag" ]] && continue

    if echo "$vision_tags_json" | jq -e --arg t "$wtag" 'index($t) != null' >/dev/null 2>&1; then
      overlap=$((overlap + 1))
    fi
  done
  echo "$overlap"
}

# =============================================================================
# vision_extract_tags() — File-path-to-tag mapping
# =============================================================================
#
# Maps file paths to vision tags using established patterns.
# Extracted from bridge-vision-capture.sh:extract_pr_tags().
#
# Input: stdin (one file path per line) OR $1=file containing paths
# Output: deduplicated tags to stdout (one per line)
#
vision_extract_tags() {
  local input="${1:--}"

  local paths
  if [[ "$input" == "-" ]]; then
    paths=$(cat)
  elif [[ -f "$input" ]]; then
    paths=$(cat "$input")
  else
    paths="$input"
  fi

  echo "$paths" | while IFS= read -r filepath; do
    [[ -z "$filepath" ]] && continue
    case "$filepath" in
      *orchestrator*|*architect*|*bridge*)  echo "architecture" ;;
      *security*|*redact*|*secret*|*audit*) echo "security" ;;
      *constraint*|*permission*|*guard*)    echo "constraints" ;;
      *flatline*|*multi-model*|*hounfour*)  echo "multi-model" ;;
      *test*|*spec*)                        echo "testing" ;;
      *lore*|*vision*|*memory*)             echo "philosophy" ;;
      *construct*|*pack*)                   echo "orchestration" ;;
      *config*|*yaml*|*setting*)            echo "configuration" ;;
      *hook*|*event*|*bus*)                 echo "eventing" ;;
    esac
  done | sort -u
}

# =============================================================================
# vision_sanitize_text() — Allowlist extraction for context injection
# =============================================================================
#
# Sanitizes vision text for safe inclusion in planning context.
# Uses strict allowlist extraction: only text between ## Insight and next heading.
# Secondary defense: strips instruction patterns, truncates.
#
# Input: $1=entry_file_path OR text via stdin
# Output: sanitized text to stdout
#
vision_sanitize_text() {
  local input="$1"
  local max_chars="${2:-500}"

  local text=""

  if [[ -f "$input" ]]; then
    # Primary defense: extract ONLY text between ## Insight and next ## heading
    text=$(awk '/^## Insight/{found=1; next} /^## /{found=0} found{print}' "$input")
  else
    # If passed raw text, use it directly
    text="$input"
  fi

  # Normalize: decode HTML entities, strip zero-width chars
  text=$(echo "$text" | sed -E '
    s/&lt;/</g
    s/&gt;/>/g
    s/&amp;/\&/g
    s/&quot;/"/g
    s/\xE2\x80\x8B//g
    s/\xE2\x80\x8C//g
    s/\xE2\x80\x8D//g
    s/\xEF\xBB\xBF//g
  ')

  # Secondary defense: strip instruction-like patterns (case-insensitive)
  text=$(echo "$text" | sed -E '
    s/<[sS][yY][sS][tT][eE][mM][^>]*>[^<]*<\/[sS][yY][sS][tT][eE][mM][^>]*>//g
    s/<[pP][rR][oO][mM][pP][tT][^>]*>[^<]*<\/[pP][rR][oO][mM][pP][tT][^>]*>//g
    s/<[iI][nN][sS][tT][rR][uU][cC][tT][iI][oO][nN][sS][^>]*>[^<]*<\/[iI][nN][sS][tT][rR][uU][cC][tT][iI][oO][nN][sS][^>]*>//g
    s/```[^`]*```//g
  ')

  # Strip any remaining angle-bracket tags that look like XML directives
  text=$(echo "$text" | sed -E 's/<\/?(system|prompt|instructions|context|role|user|assistant)[^>]*>//gI')

  # Strip lines that look like indirect instructions (case-insensitive)
  text=$(echo "$text" | grep -viE '(ignore previous|forget all|you are now|act as|pretend to be|disregard|override|ignore all|ignore the above|do not follow|new instructions|reset context)' || true)

  # Normalize whitespace
  text=$(echo "$text" | tr '\n' ' ' | sed 's/  */ /g' | xargs)

  # Truncate to max chars
  if [[ ${#text} -gt $max_chars ]]; then
    text="${text:0:$max_chars}"
    # Strip trailing partial word
    text=$(echo "$text" | sed 's/ [^ ]*$//')
    text="${text}..."
  fi

  echo "$text"
}

# =============================================================================
# vision_validate_entry() — Schema validation for vision entries
# =============================================================================
#
# Validates a vision entry file against the required schema.
# Returns 0 for valid entries, 1 for invalid with error details on stderr.
#
# Input: $1=entry_file_path
# Output: "VALID" or "INVALID: ..." to stdout, errors on stderr
#
vision_validate_entry() {
  local entry_file="$1"
  local errors=()

  if [[ ! -f "$entry_file" ]]; then
    echo "SKIP: file not found"
    return 1
  fi

  grep -q '^\*\*ID\*\*:' "$entry_file" || errors+=("missing ID field")
  grep -q '^\*\*Source\*\*:' "$entry_file" || errors+=("missing Source field")
  grep -q '^\*\*Status\*\*:' "$entry_file" || errors+=("missing Status field")
  grep -q '^\*\*Tags\*\*:' "$entry_file" || errors+=("missing Tags field")
  grep -q '^## Insight' "$entry_file" || errors+=("missing Insight section")

  if [[ ${#errors[@]} -gt 0 ]]; then
    echo "INVALID: ${errors[*]}" >&2
    echo "INVALID: ${errors[*]}"
    return 1
  fi

  # Additional validations
  local status
  status=$(grep '^\*\*Status\*\*:' "$entry_file" | sed 's/\*\*Status\*\*: *//')
  case "$status" in
    Captured|Exploring|Proposed|Implemented|Deferred) ;;
    *)
      echo "INVALID: unknown status '$status'" >&2
      echo "INVALID: unknown status '$status'"
      return 1
      ;;
  esac

  echo "VALID"
  return 0
}

# =============================================================================
# vision_update_status() — Lifecycle status transitions
# =============================================================================
#
# Update vision status in both index.md and entry file.
# Valid transitions: Captured→Exploring, Exploring→Proposed,
#                    Proposed→Implemented/Deferred
# Uses flock for concurrency safety.
#
# Input: $1=vision_id, $2=new_status, $3=visions_dir
#
vision_update_status() {
  local vid="$1"
  local new_status="$2"
  local visions_dir="$3"

  # Validate inputs (SKP-005)
  _vision_validate_id "$vid" || return 1

  case "$new_status" in
    Captured|Exploring|Proposed|Implemented|Deferred) ;;
    *) echo "ERROR: Invalid status: $new_status" >&2; return 1 ;;
  esac

  local index_file="$visions_dir/index.md"

  if [[ ! -f "$index_file" ]]; then
    echo "ERROR: Vision index not found: $index_file" >&2
    return 1
  fi

  # Flock-guarded status update
  _do_update_status() {
    local safe_vid safe_status
    safe_vid=$(printf '%s' "$vid" | sed 's/[\\/&]/\\\\&/g')
    safe_status=$(printf '%s' "$new_status" | sed 's/[\\/&]/\\\\&/g')

    if grep -q "^| $vid " "$index_file" 2>/dev/null; then
      sed "s/^\(| $safe_vid [^|]*|[^|]*|[^|]*| \)[A-Za-z]* \(|.*\)/\1$safe_status \2/" "$index_file" > "$index_file.tmp" && mv "$index_file.tmp" "$index_file"
      echo "Updated $vid status to $new_status"
    else
      echo "WARNING: Vision $vid not found in index" >&2
      return 1
    fi

    # Update entry file too
    local entry_file="$visions_dir/entries/${vid}.md"
    if [[ -f "$entry_file" ]]; then
      sed "s/^\*\*Status\*\*: .*/\*\*Status\*\*: $safe_status/" "$entry_file" > "$entry_file.tmp" && mv "$entry_file.tmp" "$entry_file"
    fi
  }

  vision_atomic_write "$index_file" _do_update_status

  # Regenerate statistics after status change
  vision_regenerate_index_stats "$index_file" 2>/dev/null || true
}

# =============================================================================
# vision_record_ref() — Atomic reference counting
# =============================================================================
#
# Record a reference to a vision and increment its ref counter.
# Uses flock for concurrency safety.
#
# Input: $1=vision_id, $2=bridge_id, $3=visions_dir (optional)
#
vision_record_ref() {
  local vid="$1"
  local bridge_id="$2"
  local visions_dir="${3:-${PROJECT_ROOT}/grimoires/loa/visions}"

  # Validate inputs (SKP-005)
  _vision_validate_id "$vid" || return 1

  local index_file="$visions_dir/index.md"
  local ref_threshold="${VISION_REF_THRESHOLD:-3}"

  if [[ ! -f "$index_file" ]]; then
    echo "ERROR: Vision index not found: $index_file" >&2
    return 1
  fi

  _do_record_ref() {
    if ! grep -q "^| $vid " "$index_file" 2>/dev/null; then
      echo "WARNING: Vision $vid not found in index" >&2
      return 1
    fi

    # Ensure the Refs column exists in the header
    if ! grep -q "| Refs |" "$index_file" 2>/dev/null; then
      sed 's/| Tags |$/| Tags | Refs |/' "$index_file" > "$index_file.tmp" && mv "$index_file.tmp" "$index_file"
      sed 's/|------|\s*$/|------|------|/' "$index_file" > "$index_file.tmp" && mv "$index_file.tmp" "$index_file"
      sed '/^| vision-/s/ |$/| 0 |/' "$index_file" > "$index_file.tmp" && mv "$index_file.tmp" "$index_file"
    fi

    # Extract current ref count
    local current_refs
    current_refs=$(grep "^| $vid " "$index_file" | sed 's/.*| \([0-9]*\) |$/\1/' || echo "0")
    if [[ -z "$current_refs" || ! "$current_refs" =~ ^[0-9]+$ ]]; then
      current_refs=0
    fi

    local new_refs=$((current_refs + 1))

    # Update ref count atomically (tmp+mv)
    local safe_vid
    safe_vid=$(printf '%s' "$vid" | sed 's/[\\/&]/\\\\&/g')
    sed "s/^\(| $safe_vid .*| \)[0-9]* |$/\1$new_refs |/" "$index_file" > "$index_file.tmp" && mv "$index_file.tmp" "$index_file"

    echo "Recorded reference: $vid now has $new_refs references (bridge: $bridge_id)"

    # Check threshold for lore elevation suggestion
    if [[ "$new_refs" -gt "$ref_threshold" ]]; then
      echo "$vid referenced $new_refs times — consider elevating to lore"
    fi
  }

  vision_atomic_write "$index_file" _do_record_ref
}

# =============================================================================
# vision_check_lore_elevation() — Lore elevation check
# =============================================================================
#
# Check if a vision has enough references to warrant lore elevation.
#
# Input: $1=vision_id, $2=visions_dir (optional)
# Output: "ELEVATE" or "NO" to stdout
#
vision_check_lore_elevation() {
  local vid="$1"
  local visions_dir="${2:-${PROJECT_ROOT}/grimoires/loa/visions}"
  local index_file="$visions_dir/index.md"
  local ref_threshold="${VISION_REF_THRESHOLD:-3}"

  if [[ ! -f "$index_file" ]]; then
    echo "NO"
    return 0
  fi

  local refs
  refs=$(grep "^| $vid " "$index_file" 2>/dev/null | sed 's/.*| \([0-9]*\) |$/\1/' || echo "0")
  if [[ -z "$refs" || ! "$refs" =~ ^[0-9]+$ ]]; then
    refs=0
  fi

  if [[ "$refs" -gt "$ref_threshold" ]]; then
    echo "ELEVATE"
  else
    echo "NO"
  fi
}

# =============================================================================
# vision_generate_lore_entry() — Generate lore YAML for elevated visions
# =============================================================================
#
# When a vision has been referenced enough to warrant lore elevation,
# generate a YAML entry compatible with lore-discover.sh format.
#
# Input: $1=vision_id, $2=visions_dir (optional)
# Output: YAML entry to stdout (compatible with discovered/visions.yaml)
# Returns: 0 if entry generated, 1 if vision not found or not eligible
#
vision_generate_lore_entry() {
  local vid="$1"
  local visions_dir="${2:-${PROJECT_ROOT}/grimoires/loa/visions}"

  _vision_validate_id "$vid" || return 1

  local entry_file="$visions_dir/entries/${vid}.md"
  if [[ ! -f "$entry_file" ]]; then
    echo "ERROR: Vision entry file not found: $entry_file" >&2
    return 1
  fi

  # Extract fields from entry file
  local title source tags_raw insight potential
  title=$(grep '^\*\*ID\*\*:' "$entry_file" | head -1 | sed 's/.*# Vision: //' || true)
  # Title is in the H1 header
  title=$(grep '^# Vision:' "$entry_file" | head -1 | sed 's/^# Vision: *//' || true)
  if [[ -z "$title" ]]; then
    title=$(grep "^| $vid " "$visions_dir/index.md" 2>/dev/null | awk -F'|' '{print $3}' | xargs || echo "$vid")
  fi

  source=$(grep '^\*\*Source\*\*:' "$entry_file" | head -1 | sed 's/\*\*Source\*\*: *//')
  tags_raw=$(grep '^\*\*Tags\*\*:' "$entry_file" | head -1 | sed 's/\*\*Tags\*\*: *//' | tr -d '[]')

  # Extract insight (sanitized)
  insight=$(vision_sanitize_text "$entry_file" 300)

  # Extract potential section
  potential=$(awk '/^## Potential/{found=1; next} /^## /{found=0} found{print}' "$entry_file" | head -5 | tr '\n' ' ' | xargs)

  # Generate lore ID from vision ID
  local lore_id="vision-elevated-${vid}"

  # Build tags array from raw tags + fixed prefix tags
  local tags_csv
  tags_csv=$(printf '%s' "$tags_raw" | sed 's/ *, */,/g')

  # Use jq for safe YAML-like output (no shell expansion of user data)
  local context_text
  context_text="${potential} Elevated from Vision Registry entry ${vid} after crossing reference threshold."

  # Emit YAML using printf with pre-sanitized values (no heredoc expansion)
  # All values passed through jq --arg for safe escaping
  jq -n \
    --arg id "$lore_id" \
    --arg term "$title" \
    --arg short "$insight" \
    --arg context "$context_text" \
    --arg source "$source" \
    --arg tags_csv "$tags_csv" \
    --arg vid "$vid" \
    '{id: $id, term: $term, short: $short, context: $context, source: $source, tags_csv: $tags_csv, vision_id: $vid}' | \
  jq -r '"  - id: \(.id)\n    term: \"\(.term)\"\n    short: \"\(.short)\"\n    context: |\n      \(.context)\n    source: \"\(.source)\"\n    tags: [discovered, vision-elevated, \(.tags_csv | split(",") | join(", "))]\n    vision_id: \"\(.vision_id)\""'
}

# =============================================================================
# vision_append_lore_entry() — Append elevated vision to visions.yaml
# =============================================================================
#
# Appends a lore entry to discovered/visions.yaml if not already present.
# Idempotent — checks for existing entry by vision_id.
#
# Input: $1=vision_id, $2=visions_dir (optional)
# Returns: 0 if appended (or already exists), 1 on error
#
vision_append_lore_entry() {
  local vid="$1"
  local visions_dir="${2:-${PROJECT_ROOT}/grimoires/loa/visions}"
  local lore_file="${PROJECT_ROOT}/.claude/data/lore/discovered/visions.yaml"

  _vision_validate_id "$vid" || return 1

  # Check if lore file exists
  if [[ ! -f "$lore_file" ]]; then
    echo "WARNING: Lore file not found: $lore_file" >&2
    return 1
  fi

  # Idempotency: check if vision already elevated
  if grep -q "vision_id: \"$vid\"" "$lore_file" 2>/dev/null; then
    echo "Already elevated: $vid"
    return 0
  fi

  # Generate and append
  local entry
  entry=$(vision_generate_lore_entry "$vid" "$visions_dir") || return 1

  echo "" >> "$lore_file"
  echo "$entry" >> "$lore_file"
  echo "Elevated $vid to lore: $lore_file"
}

# =============================================================================
# vision_regenerate_index_stats() — Dynamic statistics from table
# =============================================================================
#
# Recomputes the ## Statistics section in index.md from the actual table rows.
# Eliminates manually-maintained counts that drift from reality.
#
# Input: $1=index_file (optional, defaults to PROJECT_ROOT/grimoires/loa/visions/index.md)
# Returns: 0 on success, 1 if index not found
#
vision_regenerate_index_stats() {
  local index_file="${1:-${PROJECT_ROOT}/grimoires/loa/visions/index.md}"

  if [[ ! -f "$index_file" ]]; then
    echo "ERROR: Vision index not found: $index_file" >&2
    return 1
  fi

  # Count statuses from the table (grep for status column values)
  local captured exploring proposed implemented deferred
  captured=$(grep -c '| Captured |' "$index_file" 2>/dev/null || echo 0)
  exploring=$(grep -c '| Exploring |' "$index_file" 2>/dev/null || echo 0)
  proposed=$(grep -c '| Proposed |' "$index_file" 2>/dev/null || echo 0)
  implemented=$(grep -c '| Implemented |' "$index_file" 2>/dev/null || echo 0)
  deferred=$(grep -c '| Deferred |' "$index_file" 2>/dev/null || echo 0)

  # Rewrite statistics section using awk (safe, no shell expansion issues)
  # Note: avoid awk variable names that clash with builtins (exp, log, etc.)
  local tmp_file="${index_file}.stats.tmp"
  awk -v n_cap="$captured" -v n_expl="$exploring" -v n_prop="$proposed" \
      -v n_impl="$implemented" -v n_def="$deferred" '
    BEGIN { in_stats=0; stats_written=0 }
    /^## Statistics/ {
      in_stats=1
      print
      print ""
      print "- Total captured: " n_cap
      print "- Total exploring: " n_expl
      print "- Total proposed: " n_prop
      print "- Total implemented: " n_impl
      print "- Total deferred: " n_def
      stats_written=1
      next
    }
    in_stats && /^## / { in_stats=0; print; next }
    in_stats && /^$/ && stats_written { next }
    in_stats && /^- Total / { next }
    !in_stats { print }
  ' "$index_file" > "$tmp_file" && mv "$tmp_file" "$index_file"
}
