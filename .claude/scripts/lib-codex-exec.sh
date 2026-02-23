#!/usr/bin/env bash
# =============================================================================
# lib-codex-exec.sh — Codex CLI adapter with capability detection
# =============================================================================
# Version: 1.0.0
# Cycle: cycle-033 (Codex CLI Integration for GPT Review)
#
# Provides execution backend for OpenAI Codex CLI (`codex exec`).
# Handles capability probing, single invocation, output normalization,
# and workspace management.
#
# Used by:
#   - gpt-review-api.sh (codex execution path via route_review)
#   - lib-multipass.sh (multi-pass orchestration, Sprint 2)
#
# Functions:
#   codex_is_available           → 0 if codex on PATH + version OK
#   detect_capabilities          → probe flags, write cache
#   codex_has_capability <flag>  → 0 if flag supported
#   codex_exec_single <prompt> <model> <output_file> [workspace] [timeout]
#   parse_codex_output <raw>     → normalized JSON to stdout
#   setup_review_workspace <content_file> → workspace path to stdout
#   cleanup_workspace <path>     → remove temp workspace
#
# Design decisions:
#   - Version-pinned minimum (Flatline IMP-003): CODEX_MIN_VERSION
#   - Version-scoped capability cache (SDD IMP-003): /tmp/loa-codex-caps-<hash>.json
#   - Diff-only default (SDD SKP-002): no --cd to repo root
#   - timeout(1) wrapping (Flatline IMP-004): configurable per invocation
#   - Probe with stderr parsing (SDD SKP-001): version-pinned expectations
#
# IMPORTANT: This file must NOT call any function at the top level.
# It is designed to be sourced by other scripts.

# Guard against double-sourcing
if [[ "${_LIB_CODEX_EXEC_LOADED:-}" == "true" ]]; then
  return 0 2>/dev/null || true
fi
_LIB_CODEX_EXEC_LOADED="true"

# =============================================================================
# Dependencies
# =============================================================================

if [[ "${_LIB_SECURITY_LOADED:-}" != "true" ]]; then
  _lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # shellcheck source=lib-security.sh
  source "$_lib_dir/lib-security.sh"
  unset _lib_dir
fi

# =============================================================================
# Constants
# =============================================================================

# Minimum supported Codex CLI version (Flatline IMP-003)
CODEX_MIN_VERSION="${CODEX_MIN_VERSION:-0.1.0}"

# Default timeout for codex exec (seconds)
CODEX_DEFAULT_TIMEOUT="${CODEX_DEFAULT_TIMEOUT:-120}"

# Capability cache directory
_CODEX_CACHE_DIR="${TMPDIR:-/tmp}"

# Flags to probe during capability detection
_CODEX_PROBE_FLAGS=(
  "--sandbox"
  "--ephemeral"
  "--output-last-message"
  "--cd"
  "--skip-git-repo-check"
  "--model"
  "--json"
)

# =============================================================================
# Version Utilities
# =============================================================================

# Compare two semantic versions. Returns 0 if $1 >= $2, 1 otherwise.
_version_gte() {
  local v1="$1" v2="$2"
  # Use sort -V for version comparison
  local lower
  lower=$(printf '%s\n%s\n' "$v1" "$v2" | sort -V | head -1)
  [[ "$lower" == "$v2" ]]
}

# =============================================================================
# Availability & Capability Detection
# =============================================================================

# Check if codex CLI is available and meets minimum version.
# Returns: 0 if available, 1 if not found, 2 if version too old
codex_is_available() {
  if ! command -v codex &>/dev/null; then
    return 1
  fi

  # Get version
  local version_output
  version_output=$(codex --version 2>/dev/null) || return 1

  # Extract version number (e.g., "codex 0.1.2" -> "0.1.2")
  local version
  version=$(echo "$version_output" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1) || version=""

  if [[ -z "$version" ]]; then
    echo "[codex-exec] WARNING: Could not parse codex version from: $version_output" >&2
    # Proceed anyway if we can't parse version
    return 0
  fi

  if ! _version_gte "$version" "$CODEX_MIN_VERSION"; then
    echo "[codex-exec] ERROR: codex version $version < required $CODEX_MIN_VERSION" >&2
    echo "[codex-exec] Please upgrade: npm install -g @openai/codex" >&2
    return 2
  fi

  return 0
}

# Detect which flags the installed codex version supports.
# Probes by running codex with each flag and checking stderr for errors.
# Results cached to /tmp/loa-codex-caps-<version_hash>.json (version-scoped).
# Returns: 0 on success, writes cache file path to stdout
detect_capabilities() {
  local version_output
  version_output=$(codex --version 2>/dev/null) || version_output="unknown"

  # Hash version for cache key
  local version_hash
  version_hash=$(echo "$version_output" | md5sum | cut -c1-8)
  local cache_file="${_CODEX_CACHE_DIR}/loa-codex-caps-${version_hash}.json"

  # Return cached if exists
  if [[ -f "$cache_file" ]]; then
    echo "$cache_file"
    return 0
  fi

  local capabilities="{}"

  # Hoist help text above loop — single subprocess call instead of N (cycle-034, Task 3.1)
  local help_text
  help_text=$(codex exec --help 2>&1) || help_text=""

  for flag in "${_CODEX_PROBE_FLAGS[@]}"; do
    local supported="true"

    if echo "$help_text" | grep -qiE "(unknown option|unrecognized|invalid).*${flag}"; then
      supported="false"
    elif ! echo "$help_text" | grep -q -- "$flag"; then
      # Flag not mentioned in help — mark as unknown (assume supported)
      supported="true"
    fi

    capabilities=$(echo "$capabilities" | jq --arg f "$flag" --arg s "$supported" '. + {($f): ($s == "true")}')
  done

  # Add metadata
  capabilities=$(echo "$capabilities" | jq \
    --arg v "$version_output" \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg pid "$$" \
    '. + {"_version": $v, "_probed_at": $ts, "_pid": ($pid | tonumber)}')

  # Write cache (0600 for security)
  echo "$capabilities" > "$cache_file"
  chmod 600 "$cache_file"

  echo "$cache_file"
  return 0
}

# Check if a specific flag is supported.
# Args: flag (e.g., "--sandbox")
# Returns: 0 if supported, 1 if not
codex_has_capability() {
  local flag="$1"

  local cache_file
  cache_file=$(detect_capabilities) || return 1

  local supported
  supported=$(jq -r --arg f "$flag" '.[$f] // false' "$cache_file" 2>/dev/null) || supported="false"

  [[ "$supported" == "true" ]]
}

# =============================================================================
# Execution
# =============================================================================

# Execute a single codex exec invocation.
# Uses --sandbox read-only, --ephemeral, --skip-git-repo-check, --output-last-message.
# Wrapped with timeout(1) command (Flatline IMP-004).
#
# Args:
#   prompt       - The review prompt text
#   model        - Model to use (e.g., gpt-5.2-codex)
#   output_file  - Path to write output
#   workspace    - Working directory (default: temp dir, NOT repo root)
#   timeout_secs - Timeout in seconds (default: CODEX_DEFAULT_TIMEOUT)
#
# Returns: 0 on success, 1 on failure, 124 on timeout
codex_exec_single() {
  local prompt="$1"
  local model="$2"
  local output_file="$3"
  local workspace="${4:-}"
  local timeout_secs="${5:-$CODEX_DEFAULT_TIMEOUT}"

  # Auth check
  if ! ensure_codex_auth; then
    echo "[codex-exec] ERROR: OPENAI_API_KEY not set" >&2
    return 4
  fi

  # Set up workspace if not provided
  local cleanup_workspace_flag="false"
  if [[ -z "$workspace" ]]; then
    workspace=$(mktemp -d "${_CODEX_CACHE_DIR}/loa-codex-ws-$$.XXXXXX")
    cleanup_workspace_flag="true"
  fi

  # Build command
  local cmd=(codex exec)

  # Add flags based on detected capabilities
  if codex_has_capability "--sandbox"; then
    cmd+=(--sandbox read-only)
  fi
  if codex_has_capability "--ephemeral"; then
    cmd+=(--ephemeral)
  fi
  if codex_has_capability "--skip-git-repo-check"; then
    cmd+=(--skip-git-repo-check)
  fi
  if codex_has_capability "--output-last-message"; then
    cmd+=(--output-last-message "$output_file")
  fi
  if codex_has_capability "--model"; then
    cmd+=(--model "$model")
  fi
  if codex_has_capability "--cd"; then
    cmd+=(--cd "$workspace")
  fi

  # Write prompt to temp file
  local prompt_file
  prompt_file=$(mktemp "${_CODEX_CACHE_DIR}/loa-codex-prompt-$$.XXXXXX")
  chmod 600 "$prompt_file"
  printf '%s' "$prompt" > "$prompt_file"

  # Execute with timeout wrapping (Flatline IMP-004)
  # stdout suppressed — output is captured via --output-last-message file
  local exit_code=0
  timeout "$timeout_secs" "${cmd[@]}" < "$prompt_file" >/dev/null 2>/dev/null || exit_code=$?

  rm -f "$prompt_file"

  # Clean up workspace if we created it
  if [[ "$cleanup_workspace_flag" == "true" && -d "$workspace" ]]; then
    rm -rf "$workspace"
  fi

  # timeout returns 124 on timeout
  if [[ $exit_code -eq 124 ]]; then
    echo "[codex-exec] ERROR: codex exec timed out after ${timeout_secs}s" >&2
    return 124
  fi

  return $exit_code
}

# =============================================================================
# Output Normalization
# =============================================================================

# Parse and normalize codex exec output.
# Tries: direct JSON → markdown-fenced JSON → greedy JSON extraction → error.
# Args: raw_output (string)
# Outputs: normalized JSON to stdout
# Returns: 0 on success, 5 on invalid format (SDD IMP-007)
parse_codex_output() {
  local raw="$1"

  # 1. Try direct JSON parse
  if echo "$raw" | jq empty 2>/dev/null; then
    echo "$raw" | jq '.'
    return 0
  fi

  # 2. Try extracting from markdown code fences
  local fenced
  fenced=$(echo "$raw" | sed -n '/^```json/,/^```$/p' | sed '1d;$d') || fenced=""
  if [[ -n "$fenced" ]] && echo "$fenced" | jq empty 2>/dev/null; then
    echo "$fenced" | jq '.'
    return 0
  fi

  # Also try without language specifier
  fenced=$(echo "$raw" | sed -n '/^```/,/^```$/p' | sed '1d;$d') || fenced=""
  if [[ -n "$fenced" ]] && echo "$fenced" | jq empty 2>/dev/null; then
    echo "$fenced" | jq '.'
    return 0
  fi

  # 3. Greedy JSON extraction: extract JSON object substring (supports 2 levels of nesting)
  local greedy
  greedy=$(echo "$raw" | grep -oP '\{(?:[^{}]|\{(?:[^{}]|\{[^{}]*\})*\})*\}' 2>/dev/null | head -1) || greedy=""
  if [[ -n "$greedy" ]] && echo "$greedy" | jq empty 2>/dev/null; then
    echo "$greedy" | jq '.'
    return 0
  fi

  # 3.5. Python3 raw_decode fallback for arbitrary nesting (cycle-034, Task 3.2)
  if command -v python3 &>/dev/null; then
    local py_extracted
    py_extracted=$(python3 -c '
import json, sys
raw = sys.stdin.read()
idx = raw.find("{")
if idx == -1:
    sys.exit(1)
try:
    obj, end = json.JSONDecoder().raw_decode(raw, idx)
    print(json.dumps(obj))
except (json.JSONDecodeError, ValueError):
    sys.exit(1)
' <<< "$raw" 2>/dev/null) || py_extracted=""
    if [[ -n "$py_extracted" ]] && echo "$py_extracted" | jq empty 2>/dev/null; then
      echo "$py_extracted" | jq '.'
      return 0
    fi
  fi

  # 4. All extraction methods failed
  echo "[codex-exec] ERROR: Could not extract valid JSON from codex output" >&2
  echo "[codex-exec] Raw output (first 500 chars): ${raw:0:500}" >&2
  return 5
}

# =============================================================================
# Workspace Management
# =============================================================================

# Set up a review workspace with content file.
# Default mode (diff-only): content passed as file in temp workspace.
# Tool-access mode: copies allowed files to temp workspace (Flatline SKP-006).
#
# Args: content_file [tool_access]
#   content_file - path to the content to review
#   tool_access  - "true" to enable repo-root file access (default: false)
#
# Outputs: workspace path to stdout
setup_review_workspace() {
  local content_file="$1"
  local tool_access="${2:-false}"
  local project_root="${PROJECT_ROOT:-.}"

  local workspace
  workspace=$(mktemp -d "${_CODEX_CACHE_DIR}/loa-codex-review-$$.XXXXXX")

  if [[ "$tool_access" == "true" ]]; then
    # Tool-access mode: copy allowed files to workspace (allow-list approach)
    # Flatline SKP-006: deny list becomes allow list
    _copy_allowed_files "$project_root" "$workspace"
  fi

  # Always copy the content file
  if [[ -f "$content_file" ]]; then
    cp "$content_file" "$workspace/review-content.txt"
  fi

  echo "$workspace"
}

# Internal: Copy allowed files to workspace (allow-list for tool-access mode)
_copy_allowed_files() {
  local src="$1"
  local dst="$2"

  # Only copy source code and config (NOT secrets)
  local allowed_patterns=(
    "*.sh" "*.bash"
    "*.py" "*.js" "*.ts" "*.tsx" "*.jsx"
    "*.go" "*.rs" "*.java" "*.rb"
    "*.yaml" "*.yml" "*.toml" "*.json"
    "*.md" "*.txt"
    "Makefile" "Dockerfile"
  )

  for pattern in "${allowed_patterns[@]}"; do
    # Use find to locate files, filter through is_sensitive_file
    while IFS= read -r -d '' file; do
      if ! is_sensitive_file "$file"; then
        local rel_path="${file#$src/}"
        local dest_dir
        dest_dir=$(dirname "$dst/$rel_path")
        mkdir -p "$dest_dir"
        cp "$file" "$dst/$rel_path"
      fi
    done < <(find "$src" -maxdepth 4 -name "$pattern" -type f -print0 2>/dev/null) || true
  done
}

# Remove a review workspace.
# Args: workspace_path
cleanup_workspace() {
  local workspace="$1"

  if [[ -n "$workspace" && -d "$workspace" && "$workspace" == "${_CODEX_CACHE_DIR}/loa-codex"* ]]; then
    rm -rf "$workspace"
  fi
}
