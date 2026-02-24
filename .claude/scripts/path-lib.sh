#!/usr/bin/env bash
# path-lib.sh - Configurable path resolution for grimoires and state
# Version: 2.0.0
#
# Provides centralized path resolution with config support and validation.
# Sourced by bootstrap.sh, which should be sourced by all Loa scripts.
#
# Requirements:
#   - yq v4+ for YAML parsing (optional if using defaults)
#   - realpath for path canonicalization
#
# Environment Variables:
#   PROJECT_ROOT      - Workspace root (set by bootstrap.sh)
#   CONFIG_FILE       - Path to .loa.config.yaml (set by bootstrap.sh)
#   LOA_USE_LEGACY_PATHS - Set to "1" to bypass config and use hardcoded paths
#   LOA_STRICT_CONFIG - Set to "1" to fail on missing yq or config errors
#   LOA_GRIMOIRE_DIR  - Override grimoire directory (inheritance from parent)
#   LOA_BEADS_DIR     - Override beads directory
#   LOA_SOUL_SOURCE   - Override soul source path
#   LOA_SOUL_OUTPUT   - Override soul output path
#   LOA_STATE_DIR     - Override state directory
#   LOA_ALLOW_ABSOLUTE_STATE - Set to "1" to permit absolute LOA_STATE_DIR paths
# path-lib: exempt

# =============================================================================
# Constants
# =============================================================================

_PATH_LIB_VERSION="2.0.0"

# Defaults (match current hardcoded behavior for backward compatibility)
_DEFAULT_GRIMOIRE="grimoires/loa"
_DEFAULT_BEADS=".beads"
_DEFAULT_SOUL_SOURCE="grimoires/loa/BEAUVOIR.md"
_DEFAULT_SOUL_OUTPUT="grimoires/loa/SOUL.md"
_DEFAULT_STATE_DIR=".loa-state"

# =============================================================================
# Internal State
# =============================================================================

# NOTE: Initialization is process-local.
# The _path_lib_initialized flag is per-process, not shared across processes.
# Concurrent shell processes each run initialization independently.
# This is intentional - no locking is needed for typical shell script usage.
_path_lib_initialized=false

# =============================================================================
# Initialization
# =============================================================================

_init_path_lib() {
  # Skip if already initialized
  if [[ "$_path_lib_initialized" == "true" ]]; then
    return 0
  fi

  # Check for legacy mode (rollback during migration)
  if [[ "${LOA_USE_LEGACY_PATHS:-}" == "1" ]]; then
    _use_legacy_paths
    _path_lib_initialized=true
    return 0
  fi

  # Inherit from environment if already set (parent script passed values)
  if [[ -n "${LOA_GRIMOIRE_DIR:-}" ]]; then
    # Resolve state dir from env or use default
    if [[ -n "${LOA_STATE_DIR:-}" ]]; then
      if ! _resolve_state_dir_from_env; then
        return 1
      fi
    else
      export LOA_STATE_DIR="${PROJECT_ROOT}/${_DEFAULT_STATE_DIR}"
    fi
    # Validate inherited paths
    if ! _validate_paths; then
      return 1
    fi
    _path_lib_initialized=true
    return 0
  fi

  # Read from config if available
  if [[ -f "${CONFIG_FILE:-}" ]]; then
    if ! _read_config_paths; then
      return 1
    fi
  else
    if ! _use_defaults; then
      return 1
    fi
  fi

  # Validate all paths
  if ! _validate_paths; then
    return 1
  fi

  _path_lib_initialized=true
  return 0
}

_use_defaults() {
  export LOA_GRIMOIRE_DIR="${PROJECT_ROOT}/${_DEFAULT_GRIMOIRE}"
  export LOA_BEADS_DIR="${PROJECT_ROOT}/${_DEFAULT_BEADS}"
  export LOA_SOUL_SOURCE="${PROJECT_ROOT}/${_DEFAULT_SOUL_SOURCE}"
  export LOA_SOUL_OUTPUT="${PROJECT_ROOT}/${_DEFAULT_SOUL_OUTPUT}"
  # State dir: env var takes precedence over default
  if [[ -n "${LOA_STATE_DIR:-}" ]]; then
    if ! _resolve_state_dir_from_env; then
      return 1
    fi
  else
    export LOA_STATE_DIR="${PROJECT_ROOT}/${_DEFAULT_STATE_DIR}"
  fi
}

_resolve_state_dir_from_env() {
  # Validate and resolve LOA_STATE_DIR from environment variable
  if [[ "$LOA_STATE_DIR" == /* ]]; then
    # Absolute path — requires opt-in
    if [[ "${LOA_ALLOW_ABSOLUTE_STATE:-}" != "1" ]]; then
      echo "ERROR: LOA_STATE_DIR is absolute but LOA_ALLOW_ABSOLUTE_STATE is not set: $LOA_STATE_DIR" >&2
      return 1
    fi
    if [[ ! -d "$LOA_STATE_DIR" ]]; then
      echo "ERROR: LOA_STATE_DIR does not exist: $LOA_STATE_DIR" >&2
      return 1
    fi
    if [[ ! -w "$LOA_STATE_DIR" ]]; then
      echo "ERROR: LOA_STATE_DIR is not writable: $LOA_STATE_DIR" >&2
      return 1
    fi
  else
    # Relative path — prepend PROJECT_ROOT
    export LOA_STATE_DIR="${PROJECT_ROOT}/${LOA_STATE_DIR}"
  fi
  return 0
}

_use_legacy_paths() {
  # Hardcoded paths for rollback during migration
  # These match the original behavior before configurable paths
  export LOA_GRIMOIRE_DIR="${PROJECT_ROOT}/grimoires/loa"
  export LOA_BEADS_DIR="${PROJECT_ROOT}/.beads"
  export LOA_SOUL_SOURCE="${PROJECT_ROOT}/grimoires/loa/BEAUVOIR.md"
  export LOA_SOUL_OUTPUT="${PROJECT_ROOT}/grimoires/loa/SOUL.md"
}

_read_config_paths() {
  # Verify yq is available
  if ! command -v yq &>/dev/null; then
    if [[ "${LOA_STRICT_CONFIG:-}" == "1" ]]; then
      echo "ERROR: yq is required but not found." >&2
      echo "  Install with: brew install yq (macOS) or apt install yq (Linux)" >&2
      return 1
    fi
    echo "WARNING: yq not found, using default paths. Set LOA_STRICT_CONFIG=1 to make this an error." >&2
    _use_defaults
    return 0
  fi

  # Verify yq version (v4+ required)
  local yq_version yq_major
  yq_version=$(yq --version 2>&1 | grep -oE '[0-9]+\.[0-9]+' | head -1) || true

  if [[ -n "$yq_version" ]]; then
    yq_major="${yq_version%%.*}"
    if [[ "$yq_major" -lt 4 ]]; then
      echo "ERROR: yq v4+ required, found v${yq_version}." >&2
      echo "  Upgrade with: brew upgrade yq (macOS) or update via package manager" >&2
      return 1
    fi
  else
    # Could be Python yq or unknown variant
    # Try a simple test to see if it's mikefarah/yq
    if ! yq -e '.' "$CONFIG_FILE" &>/dev/null; then
      echo "ERROR: Incompatible yq version. Please install mikefarah/yq v4+." >&2
      echo "  See: https://github.com/mikefarah/yq" >&2
      return 1
    fi
  fi

  # Read grimoire path with proper error handling
  local grimoire_raw yq_stderr yq_exit
  yq_stderr=$(mktemp)
  grimoire_raw=$(yq -e '.paths.grimoire // ""' "$CONFIG_FILE" 2>"$yq_stderr") || yq_exit=$?

  if [[ "${yq_exit:-0}" -ne 0 && -s "$yq_stderr" ]]; then
    echo "ERROR: Failed to parse paths.grimoire from $CONFIG_FILE:" >&2
    cat "$yq_stderr" >&2
    rm -f "$yq_stderr"
    return 1
  fi
  rm -f "$yq_stderr"

  if [[ -n "$grimoire_raw" && "$grimoire_raw" != "null" ]]; then
    # Reject absolute paths
    if [[ "$grimoire_raw" == /* ]]; then
      echo "ERROR: paths.grimoire must be relative, got: $grimoire_raw" >&2
      return 1
    fi
    export LOA_GRIMOIRE_DIR="${PROJECT_ROOT}/${grimoire_raw}"
  else
    export LOA_GRIMOIRE_DIR="${PROJECT_ROOT}/${_DEFAULT_GRIMOIRE}"
  fi

  # Read beads path
  local beads_raw
  beads_raw=$(yq -e '.paths.beads // ""' "$CONFIG_FILE" 2>/dev/null) || true

  if [[ -n "$beads_raw" && "$beads_raw" != "null" ]]; then
    if [[ "$beads_raw" == /* ]]; then
      echo "ERROR: paths.beads must be relative, got: $beads_raw" >&2
      return 1
    fi
    export LOA_BEADS_DIR="${PROJECT_ROOT}/${beads_raw}"
  else
    export LOA_BEADS_DIR="${PROJECT_ROOT}/${_DEFAULT_BEADS}"
  fi

  # Read soul source path
  local soul_source_raw
  soul_source_raw=$(yq -e '.paths.soul.source // ""' "$CONFIG_FILE" 2>/dev/null) || true

  if [[ -n "$soul_source_raw" && "$soul_source_raw" != "null" ]]; then
    if [[ "$soul_source_raw" == /* ]]; then
      echo "ERROR: paths.soul.source must be relative, got: $soul_source_raw" >&2
      return 1
    fi
    export LOA_SOUL_SOURCE="${PROJECT_ROOT}/${soul_source_raw}"
  else
    export LOA_SOUL_SOURCE="${PROJECT_ROOT}/${_DEFAULT_SOUL_SOURCE}"
  fi

  # Read soul output path
  local soul_output_raw
  soul_output_raw=$(yq -e '.paths.soul.output // ""' "$CONFIG_FILE" 2>/dev/null) || true

  if [[ -n "$soul_output_raw" && "$soul_output_raw" != "null" ]]; then
    if [[ "$soul_output_raw" == /* ]]; then
      echo "ERROR: paths.soul.output must be relative, got: $soul_output_raw" >&2
      return 1
    fi
    export LOA_SOUL_OUTPUT="${PROJECT_ROOT}/${soul_output_raw}"
  else
    export LOA_SOUL_OUTPUT="${PROJECT_ROOT}/${_DEFAULT_SOUL_OUTPUT}"
  fi

  # Read state directory path
  # Priority: LOA_STATE_DIR env var > config paths.state_dir > default
  if [[ -n "${LOA_STATE_DIR:-}" ]]; then
    # Env var already set — delegate validation to shared helper
    if ! _resolve_state_dir_from_env; then
      return 1
    fi
  else
    local state_dir_raw
    state_dir_raw=$(yq -e '.paths.state_dir // ""' "$CONFIG_FILE" 2>/dev/null) || true

    if [[ -n "$state_dir_raw" && "$state_dir_raw" != "null" ]]; then
      if [[ "$state_dir_raw" == /* ]]; then
        echo "ERROR: paths.state_dir must be relative, got: $state_dir_raw" >&2
        return 1
      fi
      export LOA_STATE_DIR="${PROJECT_ROOT}/${state_dir_raw}"
    else
      export LOA_STATE_DIR="${PROJECT_ROOT}/${_DEFAULT_STATE_DIR}"
    fi
  fi

  return 0
}

_validate_paths() {
  local errors=0

  # Validate grimoire path doesn't escape workspace
  local canonical_grimoire
  canonical_grimoire=$(realpath -m "$LOA_GRIMOIRE_DIR" 2>/dev/null) || true

  if [[ -n "$canonical_grimoire" && ! "$canonical_grimoire" == "$PROJECT_ROOT"* ]]; then
    echo "ERROR: Grimoire path escapes workspace: $LOA_GRIMOIRE_DIR" >&2
    echo "  Resolved to: $canonical_grimoire" >&2
    echo "  Workspace:   $PROJECT_ROOT" >&2
    ((errors++)) || true
  fi

  # If path contains symlinks, re-validate after physical resolution
  if [[ -L "$LOA_GRIMOIRE_DIR" ]] || [[ -e "$LOA_GRIMOIRE_DIR" && "$(realpath "$LOA_GRIMOIRE_DIR" 2>/dev/null)" != "$LOA_GRIMOIRE_DIR" ]]; then
    local physical_path
    physical_path=$(realpath -P -m "$LOA_GRIMOIRE_DIR" 2>/dev/null) || true
    if [[ -n "$physical_path" && ! "$physical_path" == "$PROJECT_ROOT"* ]]; then
      echo "ERROR: Symlink resolves outside workspace: $LOA_GRIMOIRE_DIR -> $physical_path" >&2
      ((errors++)) || true
    fi
  fi

  # Validate state dir doesn't escape workspace (Sprint 1 audit MEDIUM fix)
  # Only for relative paths resolved to absolute — skip for explicit absolute paths
  # with LOA_ALLOW_ABSOLUTE_STATE opt-in (those are intentionally outside workspace)
  if [[ "${LOA_ALLOW_ABSOLUTE_STATE:-}" != "1" ]]; then
    local canonical_state
    canonical_state=$(realpath -m "$LOA_STATE_DIR" 2>/dev/null) || true
    if [[ -n "$canonical_state" && ! "$canonical_state" == "$PROJECT_ROOT"* ]]; then
      echo "ERROR: State dir escapes workspace: $LOA_STATE_DIR" >&2
      echo "  Resolved to: $canonical_state" >&2
      echo "  Workspace:   $PROJECT_ROOT" >&2
      ((errors++)) || true
    fi
  fi

  # Validate soul source != output (prevent circular reference)
  local canonical_source canonical_output
  canonical_source=$(realpath -m "$LOA_SOUL_SOURCE" 2>/dev/null) || true
  canonical_output=$(realpath -m "$LOA_SOUL_OUTPUT" 2>/dev/null) || true

  if [[ -n "$canonical_source" && -n "$canonical_output" && "$canonical_source" == "$canonical_output" ]]; then
    echo "ERROR: Soul source and output cannot be the same file" >&2
    echo "  Source: $LOA_SOUL_SOURCE" >&2
    echo "  Output: $LOA_SOUL_OUTPUT" >&2
    ((errors++)) || true
  fi

  [[ $errors -eq 0 ]]
}

# =============================================================================
# Public API - Core Getters
# =============================================================================

get_grimoire_dir() {
  _init_path_lib || return 1
  echo "$LOA_GRIMOIRE_DIR"
}

get_beads_dir() {
  _init_path_lib || return 1
  echo "$LOA_BEADS_DIR"
}

# =============================================================================
# Public API - Derived Getters
# =============================================================================

get_ledger_path() {
  _init_path_lib || return 1
  echo "${LOA_GRIMOIRE_DIR}/ledger.json"
}

get_notes_path() {
  _init_path_lib || return 1
  echo "${LOA_GRIMOIRE_DIR}/NOTES.md"
}

get_trajectory_dir() {
  _init_path_lib || return 1
  echo "${LOA_GRIMOIRE_DIR}/a2a/trajectory"
}

get_compound_dir() {
  _init_path_lib || return 1
  echo "${LOA_GRIMOIRE_DIR}/a2a/compound"
}

get_flatline_dir() {
  _init_path_lib || return 1
  echo "${LOA_GRIMOIRE_DIR}/a2a/flatline"
}

get_archive_dir() {
  _init_path_lib || return 1
  echo "${LOA_GRIMOIRE_DIR}/archive"
}

get_analytics_dir() {
  _init_path_lib || return 1
  echo "${LOA_GRIMOIRE_DIR}/analytics"
}

get_context_dir() {
  _init_path_lib || return 1
  echo "${LOA_GRIMOIRE_DIR}/context"
}

get_skills_dir() {
  _init_path_lib || return 1
  echo "${LOA_GRIMOIRE_DIR}/skills"
}

get_skills_pending_dir() {
  _init_path_lib || return 1
  echo "${LOA_GRIMOIRE_DIR}/skills-pending"
}

get_decisions_path() {
  _init_path_lib || return 1
  echo "${LOA_GRIMOIRE_DIR}/decisions.yaml"
}

get_urls_path() {
  _init_path_lib || return 1
  echo "${LOA_GRIMOIRE_DIR}/urls.yaml"
}

# =============================================================================
# Public API - Soul/Beauvoir Paths
# =============================================================================

get_beauvoir_path() {
  _init_path_lib || return 1
  echo "$LOA_SOUL_SOURCE"
}

get_soul_output_path() {
  _init_path_lib || return 1
  echo "$LOA_SOUL_OUTPUT"
}

# =============================================================================
# Public API - State Directory Getters
# =============================================================================

get_state_dir() {
  _init_path_lib || return 1
  echo "${LOA_STATE_DIR}"
}

get_state_beads_dir() {
  _init_path_lib || return 1
  echo "${LOA_STATE_DIR}/beads"
}

get_state_ck_dir() {
  _init_path_lib || return 1
  echo "${LOA_STATE_DIR}/ck"
}

get_state_run_dir() {
  _init_path_lib || return 1
  echo "${LOA_STATE_DIR}/run"
}

get_state_memory_dir() {
  _init_path_lib || return 1
  echo "${LOA_STATE_DIR}/memory"
}

get_state_trajectory_dir() {
  _init_path_lib || return 1
  echo "${LOA_STATE_DIR}/trajectory"
}

# =============================================================================
# Public API - State Layout Detection
# =============================================================================

detect_state_layout() {
  local version_file="${PROJECT_ROOT}/.loa-version.json"
  if [[ -f "$version_file" ]]; then
    local ver
    ver=$(jq -r '.state_layout_version // 0' "$version_file" 2>/dev/null) || true
    if [[ "$ver" =~ ^[0-9]+$ ]]; then
      echo "$ver"
    else
      echo "0"
    fi
  else
    echo "0"
  fi
}

init_version_file() {
  local version_file="${PROJECT_ROOT}/.loa-version.json"
  if [[ -f "$version_file" ]]; then
    return 0  # Already exists
  fi

  local layout_version=2
  # Detect legacy: if old scattered dirs exist, this is layout v1
  if [[ -d "${PROJECT_ROOT}/.beads" || -d "${PROJECT_ROOT}/.run" || -d "${PROJECT_ROOT}/.ck" ]]; then
    layout_version=1
  fi

  local tmp_file="${version_file}.tmp.$$"
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  cat > "$tmp_file" <<EOF
{
  "state_layout_version": ${layout_version},
  "created": "${timestamp}",
  "last_migration": null
}
EOF
  mv "$tmp_file" "$version_file"
}

# =============================================================================
# Public API - State Structure Management
# =============================================================================

ensure_state_structure() {
  _init_path_lib || return 1
  local sd
  sd=$(get_state_dir) || return 1
  mkdir -p "${sd}/beads" "${sd}/ck" "${sd}/run/bridge-reviews" "${sd}/run/mesh-cache"
  mkdir -p "${sd}/memory/archive" "${sd}/memory/sessions"
  mkdir -p "${sd}/trajectory/current" "${sd}/trajectory/archive"
  # Initialize version file
  init_version_file
}

# =============================================================================
# Public API - Atomic JSONL Append
# =============================================================================

append_jsonl() {
  local file="$1" entry="$2"
  if [[ -z "$file" || -z "$entry" ]]; then
    echo "ERROR: append_jsonl requires file and entry arguments" >&2
    return 1
  fi
  local lockfile="${file}.lock"
  (
    if ! flock -w 5 200; then
      echo "WARN: Could not acquire lock for $file after 5s" >&2
      return 1
    fi
    printf '%s\n' "$entry" >> "$file"
  ) 200>"$lockfile"
}

# =============================================================================
# Public API - Structure Management
# =============================================================================

validate_grimoire_structure() {
  _init_path_lib || return 1

  local grimoire_dir="$LOA_GRIMOIRE_DIR"
  local missing=()

  # Check required subdirectories
  local required_dirs=(
    "a2a/trajectory"
    "a2a/compound"
    "archive"
    "context"
  )

  for subdir in "${required_dirs[@]}"; do
    if [[ ! -d "${grimoire_dir}/${subdir}" ]]; then
      missing+=("$subdir")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "WARNING: Missing grimoire subdirectories: ${missing[*]}" >&2
    return 1
  fi

  return 0
}

ensure_grimoire_structure() {
  _init_path_lib || return 1

  local grimoire_dir="$LOA_GRIMOIRE_DIR"

  # Create required directories
  mkdir -p "${grimoire_dir}/a2a/trajectory"
  mkdir -p "${grimoire_dir}/a2a/compound"
  mkdir -p "${grimoire_dir}/a2a/flatline"
  mkdir -p "${grimoire_dir}/archive"
  mkdir -p "${grimoire_dir}/analytics"
  mkdir -p "${grimoire_dir}/context"
  mkdir -p "${grimoire_dir}/skills"
  mkdir -p "${grimoire_dir}/skills-pending"
}

# =============================================================================
# Public API - Version
# =============================================================================

get_path_lib_version() {
  echo "$_PATH_LIB_VERSION"
}
